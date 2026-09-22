#!/usr/bin/env python3
"""Catalog animation clips across Klei animation bank fragments.

Unlike ``inspect_anim_bank.py``, this command accepts many zip/bin files and
merges duplicate entries from split bank archives.  It is intended for
shortlisting clips before opening a matching build in an animation previewer.
"""

from __future__ import annotations

import argparse
import glob
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

from inspect_anim_bank import load_input, read_anim


DEFAULT_GLOB = "temp/reference-mods/RideableGrassGator/bank/*.zip"


def expand_inputs(values: list[str]) -> list[Path]:
    paths: list[Path] = []
    for value in values or [DEFAULT_GLOB]:
        matches = sorted(glob.glob(value, recursive=True))
        paths.extend(Path(item) for item in (matches or [value]))
    # Preserve sorted output while avoiding the same file being read twice.
    return list(dict.fromkeys(paths))


def collect(paths: list[Path]) -> tuple[dict[tuple[str, str, int, int], set[str]], list[str]]:
    clips: dict[tuple[str, str, int, int], set[str]] = defaultdict(set)
    errors: list[str] = []
    for path in paths:
        try:
            data, _ = load_input(path)
            report = read_anim(data)
        except (OSError, ValueError, zipfile.BadZipFile) as exc:
            errors.append(f"{path}: {exc}")
            continue
        for item in report["animations"]:
            key = (
                item["bank"],
                item["name"],
                item["numframes"],
                item["framerate"],
            )
            clips[key].add(path.name)
    return clips, errors


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "inputs",
        nargs="*",
        help="anim.bin, zip, or shell-style glob; defaults to the reference bank directory",
    )
    parser.add_argument(
        "--contains",
        metavar="TEXT",
        action="append",
        help="only show clips whose bank or name contains TEXT; may be repeated",
    )
    parser.add_argument(
        "--bank",
        metavar="TEXT",
        help="only show banks whose name contains TEXT",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="show only the number of distinct clips in each bank",
    )
    args = parser.parse_args(argv)

    paths = expand_inputs(args.inputs)
    clips, errors = collect(paths)
    if not clips:
        parser.error("no readable animation files found")

    needles = [value.lower() for value in (args.contains or [])]
    bank_needle = args.bank.lower() if args.bank else None

    def selected(key: tuple[str, str, int, int]) -> bool:
        bank, name, _, _ = key
        haystack = f"{bank} {name}".lower()
        return (
            (not needles or any(needle in haystack for needle in needles))
            and (not bank_needle or bank_needle in bank.lower())
        )

    selected_clips = {key: sources for key, sources in clips.items() if selected(key)}
    if not selected_clips:
        print("no clips matched the filter")
        return 0

    if args.summary:
        by_bank: dict[str, int] = defaultdict(int)
        for bank, _, _, _ in selected_clips:
            by_bank[bank] += 1
        print(f"files scanned: {len(paths)}")
        print(f"distinct clips: {len(selected_clips)}")
        for bank in sorted(by_bank):
            print(f"{bank:<24} {by_bank[bank]:>3} clips")
    else:
        print(f"files scanned: {len(paths)}")
        print(f"distinct clips: {len(selected_clips)}")
        print(f"{'bank':<24} {'animation':<36} {'frames':>6} {'fps':>4}  source")
        for bank, name, frames, fps in sorted(selected_clips):
            sources = ",".join(sorted(selected_clips[(bank, name, frames, fps)]))
            print(f"{bank:<24} {name:<36} {frames:>6} {fps:>4}  {sources}")

    if errors:
        print("\nignored files:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
