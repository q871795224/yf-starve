#!/usr/bin/env python3
"""Build a preview-only mounted attack from the official Beefalo bank.

The official cow attack is used as the complete scene and keeps the rider's
moving seated root, hands, and weapon anchors.  A small, target-space swing is
applied to the weapon arm around the official weapon hand.  This keeps the
weapon attached to the mounted pose instead of importing the incompatible
side-on coordinate system from ``player_atk_*``.

The result is an ``anim.json`` for the local animation lab.  It is not a
replacement for compiling a final ``anim.bin`` with the DST Mod Tools.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any


MATRIX_KEYS = ("m_a", "m_b", "m_c", "m_d", "m_tx", "m_ty")
PREPARATION_FRAMES = 6
WEAPON_HAND_Z = 39
SWING_ELEMENT_Z = (40, 41, 42, 43, 44)
SWING_AMPLITUDE_DEGREES = 20.0


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


def flatten_frames(bank: dict[str, Any], names: list[str]) -> list[dict[str, Any]]:
    return [frame for name in names for frame in bank[name]["frames"]]


def find_element_at_z(
    frame: dict[str, Any], name: str, z_index: int,
) -> dict[str, Any]:
    for element in frame["elements"]:
        if element["name"] == name and element.get("z_index") == z_index:
            return element
    raise ValueError(f"{name!r} at z={z_index} is missing from a source frame")


def rotation(degrees: float) -> list[float]:
    radians = math.radians(degrees)
    return [
        math.cos(radians),
        math.sin(radians),
        -math.sin(radians),
        math.cos(radians),
        0.0,
        0.0,
    ]


def make_clip_frames(cow_frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Add a bounded weapon-arm swing while retaining the official scene.

    The animation bank's rider and Beefalo layers already share the same
    target-space root. Rotating the arm chain around its existing weapon hand
    therefore changes the attack gesture without introducing the offset seen
    when ``player_atk_*`` is copied as an absolute pose.
    """
    attack_frames = len(cow_frames) - PREPARATION_FRAMES
    result = [copy.deepcopy(frame) for frame in cow_frames]
    for index, frame in enumerate(result[PREPARATION_FRAMES:]):
        progress = index / max(1, attack_frames - 1)
        angle = SWING_AMPLITUDE_DEGREES * math.sin(math.pi * progress)
        pivot = find_element_at_z(frame, "hand", WEAPON_HAND_Z)
        swing = multiply(
            matrix(pivot),
            multiply(rotation(angle), inverse(matrix(pivot))),
        )
        for element in frame["elements"]:
            if element.get("z_index") in SWING_ELEMENT_Z:
                element.update(
                    dict(zip(MATRIX_KEYS, multiply(swing, matrix(element))))
                )
    return result


def build(input_path: Path, output_path: Path) -> None:
    data = json.loads(input_path.read_text())
    bank = data["banks"]["wilsonbeefalo"]
    cow_frames = flatten_frames(bank, ["atk_pre_side", "atk_side"])
    frames = make_clip_frames(cow_frames)

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
