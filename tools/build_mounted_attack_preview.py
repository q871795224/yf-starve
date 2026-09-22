#!/usr/bin/env python3
"""Build a preview-only mounted attack from the official Beefalo bank.

The official cow attack is used as the complete scene and keeps the rider's
moving seated root.  Only the rider's upper-body symbols are borrowed from
the player attack.  Those symbols are converted to torso-relative transforms
and then placed on the torso of each cow-attack frame, so the rider follows
the motion already present in ``atk_pre_side``/``atk_side``.

The result is an ``anim.json`` for the local animation lab.  It is not a
replacement for compiling a final ``anim.bin`` with the DST Mod Tools.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any


UPPER_BODY_SYMBOLS = {
    "hand",
    "arm_upper",
    "arm_upper_skin",
    "arm_lower_cuff",
    "arm_lower",
    "swap_object",
}
MATRIX_KEYS = ("m_a", "m_b", "m_c", "m_d", "m_tx", "m_ty")


def matrix(element: dict[str, Any]) -> list[float]:
    return [element[key] for key in MATRIX_KEYS]


def multiply(left: list[float], right: list[float]) -> list[float]:
    return [
        left[0] * right[0] + left[2] * right[1],
        left[1] * right[0] + left[3] * right[1],
        left[0] * right[2] + left[2] * right[3],
        left[1] * right[2] + left[3] * right[3],
        left[0] * right[4] + left[2] * right[5] + left[4],
        left[1] * right[4] + left[3] * right[5] + left[5],
    ]


def inverse(transform: list[float]) -> list[float]:
    a, b, c, d, tx, ty = transform
    determinant = a * d - b * c
    if abs(determinant) < 1e-7:
        raise ValueError("encountered a singular animation transform")
    return [
        d / determinant,
        -b / determinant,
        -c / determinant,
        a / determinant,
        (c * ty - d * tx) / determinant,
        (b * tx - a * ty) / determinant,
    ]


def transform_element(element: dict[str, Any], transform: list[float]) -> dict[str, Any]:
    result = copy.deepcopy(element)
    values = multiply(transform, matrix(element))
    result.update(dict(zip(MATRIX_KEYS, values)))
    return result


def flatten_frames(bank: dict[str, Any], names: list[str]) -> list[dict[str, Any]]:
    return [frame for name in names for frame in bank[name]["frames"]]


def find_element(frame: dict[str, Any], name: str) -> dict[str, Any]:
    for element in frame["elements"]:
        if element["name"] == name:
            return element
    raise ValueError(f"{name!r} is missing from a source frame")


def source_frame_indices(source_length: int, target_attack_frames: int) -> list[int]:
    # Keep the six preparation frames. Compress the source lag + attack into
    # the seventeen frames occupied by the Beefalo attack clip.
    indices = list(range(6))
    lag_and_attack = source_length - 6
    for frame in range(target_attack_frames):
        position = frame * (lag_and_attack - 1) / max(1, target_attack_frames - 1)
        indices.append(6 + int(round(position)))
    return indices


def make_clip_frames(
    cow_frames: list[dict[str, Any]], rider_frames: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    target_attack_frames = len(cow_frames) - 6
    indices = source_frame_indices(len(rider_frames), target_attack_frames)
    if len(indices) != len(cow_frames):
        raise ValueError("source and target timelines did not produce the same length")

    result = []
    for cow_frame, rider_index in zip(cow_frames, indices):
        rider_frame = rider_frames[rider_index]
        cow_torso = find_element(cow_frame, "torso")
        rider_torso = find_element(rider_frame, "torso")
        rider_to_cow_torso = multiply(matrix(cow_torso), inverse(matrix(rider_torso)))

        elements = [
            copy.deepcopy(element)
            for element in cow_frame["elements"]
            if element["name"] not in UPPER_BODY_SYMBOLS
        ]
        for element in rider_frame["elements"]:
            if element["name"] in UPPER_BODY_SYMBOLS:
                elements.append(transform_element(element, rider_to_cow_torso))

        frame = copy.deepcopy(cow_frame)
        frame["elements"] = elements
        result.append(frame)
    return result


def build(input_path: Path, output_path: Path) -> None:
    data = json.loads(input_path.read_text())
    bank = data["banks"]["wilsonbeefalo"]
    cow_frames = flatten_frames(bank, ["atk_pre_side", "atk_side"])
    rider_frames = flatten_frames(bank, ["player_atk_pre_side", "player_atk_lag_side", "player_atk_side"])
    frames = make_clip_frames(cow_frames, rider_frames)

    bank["yf_mounted_atk_pre_side"] = {
        "framerate": 30,
        "numframes": 6,
        "frames": frames[:6],
    }
    bank["yf_mounted_atk_side"] = {
        "framerate": 30,
        "numframes": len(frames) - 6,
        "frames": frames[6:],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
    print(f"wrote {output_path} ({len(frames)} frames)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        type=Path,
        default=Path("temp/animation-lab/official-mount/anim.json"),
        help="official animation JSON",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("temp/animation-lab/mounted-attack-prototype/anim.json"),
        help="preview animation JSON",
    )
    args = parser.parse_args()
    build(args.input, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
