#!/usr/bin/env python3
"""Compile the mounted lance preview into DST animation assets.

The preview generator produces a merged JSON bank so the browser can render
all of the source layers.  The game only needs the three new animations.  The
base game already supplies the other ``wilsonbeefalo`` clips, while the lance
image/build is shipped as the small official ``swap_spear_lance`` asset.
"""

from __future__ import annotations

import argparse
import copy
import json
import shutil
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PREVIEW_ANIM = ROOT / "temp/animation-lab/mounted-lance-prototype/anim.json"
DEFAULT_SPEAR_ZIP = (
    ROOT
    / "temp/official-dst/dontstarve_steam.app/Contents/data/anim/swap_spear_lance.zip"
)
DEFAULT_ANIM_OUTPUT = ROOT / "mod/bank/yf_mounted_lance.zip"
DEFAULT_SPEAR_OUTPUT = ROOT / "mod/anim/swap_spear_lance.zip"
ANIM_NAMES = (
    "yf_mounted_lancejab_idle_side",
    "yf_mounted_lancejab_pre_side",
    "yf_mounted_lancejab_side",
)
GAME_ANIM_NAMES = {
    "yf_mounted_lancejab_idle_side": "yf_mounted_lancejab_idle",
    "yf_mounted_lancejab_pre_side": "yf_mounted_lancejab_pre",
    "yf_mounted_lancejab_side": "yf_mounted_lancejab",
}


def compile_anim(preview_anim: Path, output_zip: Path) -> None:
    tools_path = ROOT / "temp/tools/DSTmodutils/pyscripts"
    sys.path.insert(0, str(tools_path))
    from compiler.anim_bank import AnimBank

    source = json.loads(preview_anim.read_text())
    source_bank = source.get("banks", {}).get("wilsonbeefalo")
    if not isinstance(source_bank, dict):
        raise ValueError("preview animation JSON has no wilsonbeefalo bank")

    missing = [name for name in ANIM_NAMES if name not in source_bank]
    if missing:
        raise ValueError(f"preview animation JSON is missing: {', '.join(missing)}")

    game_bank = {
        GAME_ANIM_NAMES[name]: copy.deepcopy(source_bank[name])
        for name in ANIM_NAMES
    }
    delta = {
        "type": "Anim",
        "version": int(source.get("version", 4)),
        "banks": {"wilsonbeefalo": game_bank},
    }
    bank = AnimBank(delta)
    bank.json_to_bin()

    output_zip.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output_zip, "w", compression=ZIP_DEFLATED) as archive:
        archive.writestr("anim.bin", bank.content)

    print(
        f"wrote {output_zip} ({len(bank.content)} bytes, "
        f"{len(ANIM_NAMES)} animations)"
    )


def build(preview_anim: Path, spear_zip: Path, anim_output: Path, spear_output: Path) -> None:
    if not preview_anim.exists():
        raise FileNotFoundError(
            f"preview animation JSON not found: {preview_anim}. "
            "Run build_mounted_lance_preview.py first."
        )
    if not spear_zip.exists():
        raise FileNotFoundError(f"official lance build not found: {spear_zip}")

    compile_anim(preview_anim, anim_output)
    spear_output.parent.mkdir(parents=True, exist_ok=True)
    if spear_zip.resolve() != spear_output.resolve():
        shutil.copy2(spear_zip, spear_output)
    print(f"copied {spear_output}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview-anim", type=Path, default=DEFAULT_PREVIEW_ANIM)
    parser.add_argument("--spear-zip", type=Path, default=DEFAULT_SPEAR_ZIP)
    parser.add_argument("--anim-output", type=Path, default=DEFAULT_ANIM_OUTPUT)
    parser.add_argument("--spear-output", type=Path, default=DEFAULT_SPEAR_OUTPUT)
    args = parser.parse_args()
    build(args.preview_anim, args.spear_zip, args.anim_output, args.spear_output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
