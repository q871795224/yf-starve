#!/usr/bin/env python3
"""Inspect a Klei ``anim.bin`` or animation zip without starting DST.

This is an asset-level check.  It reports the bank and animation clips that
are present in the file; it does not prove that a mounted player will render
the clip in-game.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import zipfile
from pathlib import Path


# The format uses the four cardinal direction bits plus four diagonal bits.
# A side/upside/downside clip combines the corresponding diagonal bits.
FACING_SUFFIX = {
    1 << 0: "_right",
    1 << 1: "_up",
    1 << 2: "_left",
    1 << 3: "_down",
    (1 << 0) | (1 << 2): "_side",
    (1 << 4) | (1 << 5): "_upside",
    (1 << 6) | (1 << 7): "_downside",
    (1 << 5): "_upleft",
    (1 << 4): "_upright",
    (1 << 7): "_downleft",
    (1 << 6): "_downright",
    (1 << 4) | (1 << 5) | (1 << 6) | (1 << 7): "_45s",
    (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3): "_90s",
}


class Reader:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.offset = 0

    def read(self, size: int) -> bytes:
        end = self.offset + size
        if end > len(self.data):
            raise ValueError(
                f"unexpected end of file at 0x{self.offset:x} "
                f"(wanted {size} bytes)"
            )
        result = self.data[self.offset:end]
        self.offset = end
        return result

    def unpack(self, fmt: str):
        size = struct.calcsize(fmt)
        return struct.unpack(fmt, self.read(size))

    def u32(self) -> int:
        return self.unpack("<I")[0]

    def i32(self) -> int:
        return self.unpack("<i")[0]

    def f32(self) -> float:
        return self.unpack("<f")[0]

    def string(self) -> str:
        length = self.i32()
        if length < 0:
            raise ValueError(f"negative string length {length}")
        return self.read(length).decode("utf-8")


def read_anim(data: bytes) -> dict:
    reader = Reader(data)
    magic, version = reader.unpack("<4sI")
    if magic != b"ANIM":
        raise ValueError(f"not an ANIM file (magic={magic!r})")

    element_count, frame_count, event_count, animation_count = reader.unpack(
        "<IIII"
    )
    animations = []
    for _ in range(animation_count):
        base_name = reader.string()
        facing = reader.unpack("<B")[0]
        root_hash = reader.u32()
        framerate = reader.f32()
        frame_total = reader.u32()
        frames = []
        for frame_index in range(frame_total):
            bounds = reader.unpack("<ffff")
            events = reader.u32()
            reader.read(events * 4)
            elements = reader.u32()
            reader.read(elements * (12 + 28))
            frames.append(
                {
                    "index": frame_index,
                    "elements": elements,
                    "bounds": bounds,
                }
            )
        animations.append(
            {
                "base_name": base_name,
                "facing": facing,
                "root_hash": root_hash,
                "framerate": int(framerate),
                "numframes": frame_total,
                "frames": frames,
            }
        )

    hash_count = reader.u32()
    hashes = {}
    for _ in range(hash_count):
        hash_id = reader.u32()
        hashes[hash_id] = reader.string()

    for animation in animations:
        bank = hashes.get(animation["root_hash"], f"0x{animation['root_hash']:08x}")
        animation["bank"] = bank
        animation["name"] = animation["base_name"] + FACING_SUFFIX.get(
            animation["facing"], ""
        )

    return {
        "magic": magic.decode("ascii"),
        "version": version,
        "counts": {
            "elements": element_count,
            "frames": frame_count,
            "events": event_count,
            "animations": animation_count,
        },
        "animations": animations,
    }


def load_input(path: Path) -> tuple[bytes, str]:
    if path.suffix.lower() != ".zip":
        return path.read_bytes(), path.name
    with zipfile.ZipFile(path) as archive:
        try:
            return archive.read("anim.bin"), f"{path.name}:anim.bin"
        except KeyError as exc:
            raise ValueError(f"{path} does not contain anim.bin") from exc


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="anim.bin or a zip containing it")
    parser.add_argument(
        "--contains",
        metavar="TEXT",
        help="only print animations whose bank or name contains TEXT",
    )
    parser.add_argument(
        "--json", action="store_true", help="write the parsed report as JSON"
    )
    args = parser.parse_args(argv)

    try:
        data, label = load_input(args.input)
        report = read_anim(data)
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        parser.error(str(exc))

    animations = report["animations"]
    if args.contains:
        needle = args.contains.lower()
        animations = [
            item
            for item in animations
            if needle in item["bank"].lower() or needle in item["name"].lower()
        ]

    if args.json:
        output = dict(report)
        output["source"] = label
        output["animations"] = animations
        print(json.dumps(output, ensure_ascii=False, indent=2))
        return 0

    print(f"source: {label}")
    print(f"format: ANIM v{report['version']}")
    print(f"clips: {len(animations)}")
    for item in animations:
        print(
            f"{item['bank']:<24} {item['name']:<36} "
            f"{item['numframes']:>3} frames @ {item['framerate']:>2} FPS"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
