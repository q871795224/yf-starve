#!/usr/bin/env python3
"""Build a preview-only mounted lance jab from the official DST assets.

The cow's official ``atk_pre_side``/``atk_side`` clips remain the movement
base.  The rider is rotated around the pelvis in target space and the Steam
``swap_spear_lance`` build is attached to the moving hand.  This is a browser
preview; it is intentionally not a final ``anim.bin`` compiler.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import shutil
import struct
import sys
import tempfile
from pathlib import Path
from typing import Any
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ANIM = ROOT / "temp/animation-lab/official-mount/anim.json"
DEFAULT_BUILD = ROOT / "temp/animation-lab/official-mount/build.json"
DEFAULT_SPEAR_ZIP = ROOT / "temp/official-dst/dontstarve_steam.app/Contents/data/anim/swap_spear_lance.zip"
DEFAULT_OUTPUT = ROOT / "temp/animation-lab/mounted-lance-prototype"
MATRIX_KEYS = ("m_a", "m_b", "m_c", "m_d", "m_tx", "m_ty")
SPEAR_SYMBOL = "swap_spear_lance"
SPEAR_FRAME = 0
RIDER_Z = {1, 2, *range(10, 44), 45, 46}


def matrix(element: dict[str, Any]) -> list[float]:
    return [float(element[key]) for key in MATRIX_KEYS]


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


def around_point(x: float, y: float, degrees: float) -> list[float]:
    radians = math.radians(degrees)
    rotation = [
        math.cos(radians),
        math.sin(radians),
        -math.sin(radians),
        math.cos(radians),
        0.0,
        0.0,
    ]
    translate = [1.0, 0.0, 0.0, 1.0, x, y]
    return multiply(translate, multiply(rotation, inverse(translate)))


def transform_point(transform: list[float], point: tuple[float, float]) -> tuple[float, float]:
    return (
        transform[0] * point[0] + transform[2] * point[1] + transform[4],
        transform[1] * point[0] + transform[3] * point[1] + transform[5],
    )


def spear_matrix(degrees: float, width_scale: float = 1.05, length_scale: float = 1.42) -> list[float]:
    radians = math.radians(degrees)
    return [
        width_scale * math.cos(radians),
        width_scale * math.sin(radians),
        -length_scale * math.sin(radians),
        length_scale * math.cos(radians),
        0.0,
        0.0,
    ]


def find_element(frame: dict[str, Any], name: str, z_index: int) -> dict[str, Any]:
    for element in frame["elements"]:
        if element["name"] == name and element.get("z_index") == z_index:
            return element
    raise ValueError(f"{name!r} at z={z_index} is missing from a source frame")


def add_rider_lean(frame: dict[str, Any], degrees: float) -> tuple[float, float]:
    pelvis = find_element(frame, "torso_pelvis", 22)
    lean = around_point(float(pelvis["m_tx"]), float(pelvis["m_ty"]), degrees)
    old_weapon = find_element(frame, "swap_object", 44)
    old_weapon_point = transform_point(lean, (float(old_weapon["m_tx"]), float(old_weapon["m_ty"])))

    for element in frame["elements"]:
        if element.get("z_index") in RIDER_Z:
            element.update(dict(zip(MATRIX_KEYS, multiply(lean, matrix(element)))))
    return old_weapon_point


def replace_with_spear(
    frame: dict[str, Any],
    lean_point: tuple[float, float],
    thrust: float,
    angle: float,
    z_index: int = 2,
    width_scale: float = 1.05,
    length_scale: float = 1.42,
) -> None:
    elements = []
    for element in frame["elements"]:
        if element["name"] != "swap_object" or element.get("z_index") != 44:
            elements.append(element)
            continue

        spear = copy.deepcopy(element)
        spear["name"] = SPEAR_SYMBOL
        spear["frame"] = SPEAR_FRAME
        # z=2 is immediately in front of the Beefalo head layers (z=3..9)
        # during the thrust. The old official weapon is removed instead of
        # being drawn twice.
        spear["z_index"] = z_index
        spear.update(dict(zip(MATRIX_KEYS, spear_matrix(angle, width_scale, length_scale))))
        spear["m_tx"] = lean_point[0] + thrust
        spear["m_ty"] = lean_point[1]
        elements.append(spear)
    frame["elements"] = elements


def progress_values(count: int, values: list[float]) -> list[float]:
    if count != len(values):
        raise ValueError(f"profile has {len(values)} values, expected {count}")
    return values


def make_frames(
    bank: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    idle = [copy.deepcopy(frame) for frame in bank["idle_loop"]["frames"][:3]]
    transition = [copy.deepcopy(bank["atk_pre_side"]["frames"][0]) for _ in range(2)]
    pre = [copy.deepcopy(frame) for frame in bank["atk_pre_side"]["frames"]]
    attack = [copy.deepcopy(frame) for frame in bank["atk_side"]["frames"]]

    transition_progress = [0.0, 1.0]
    pre_lean = progress_values(len(pre), [0, 5, 10, 15, 20, 24])
    attack_lean = progress_values(len(attack), [26, 30, 30, 28, 24, 20, 16, 12, 8, 4, 0, 0, 0, 0, 0, 0, 0])
    attack_thrust = [0, 8, 18, 28, 38, 42, 38, 32, 25, 18, 12, 7, 3, 0, 0, 0, 0]

    for frame in idle:
        point = add_rider_lean(frame, 0)
        replace_with_spear(frame, point, thrust=0, angle=18, z_index=2, width_scale=1.0, length_scale=1.15)
    for frame, progress in zip(transition, transition_progress):
        point = add_rider_lean(frame, 0)
        replace_with_spear(
            frame,
            point,
            thrust=0,
            angle=18 + 10 * progress,
            z_index=2,
            width_scale=1.0 + 0.05 * progress,
            length_scale=1.15 + 0.20 * progress,
        )
    for frame, lean in zip(pre, pre_lean):
        point = add_rider_lean(frame, lean)
        replace_with_spear(frame, point, thrust=0, angle=38 + lean * 3)
    for frame, lean, thrust in zip(attack, attack_lean, attack_thrust):
        point = add_rider_lean(frame, lean)
        replace_with_spear(frame, point, thrust=thrust, angle=110 + min(12, thrust / 3.5))
    return idle, transition, pre, attack


def decode_tex_to_png(path: Path, dest: Path) -> None:
    path = Path(path)
    dest = Path(dest)
    try:
        import texture2ddecoder
        from PIL import Image
    except ImportError as exc:
        raise RuntimeError(
            "缺少 texture2ddecoder/Pillow；请用 PYTHONPATH=temp/pydeps 运行此脚本"
        ) from exc

    data = path.read_bytes()
    header = struct.unpack("<I", data[4:8])[0]
    compression = (header >> 4) & 0x1F
    mipmap_count = (header >> 13) & 0x1F
    offset = 8
    mipmaps = []
    for _ in range(mipmap_count):
        mipmaps.append(struct.unpack("<HHHI", data[offset : offset + 10]))
        offset += 10
    width, height, _pitch, size = mipmaps[0]
    raw = data[offset : offset + size]
    if compression == 2:
        raw = texture2ddecoder.decode_bc3(raw, width, height)
    elif compression == 0:
        raw = texture2ddecoder.decode_bc1(raw, width, height)
    else:
        raise RuntimeError(f"暂不支持 {path.name} 的 KTEX 压缩格式 {compression}")
    image = Image.frombytes("RGBA", (width, height), raw)
    image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    dest.parent.mkdir(parents=True, exist_ok=True)
    image.save(dest)


def extract_spear_build(spear_zip: Path, staging: Path) -> tuple[dict[str, Any], Path]:
    """Decode the Steam swap build using the same build parser as DSTmodutils."""
    pydeps = ROOT / "temp/pydeps"
    tools = ROOT / "temp/tools/DSTmodutils/pyscripts"
    if str(tools) not in sys.path:
        sys.path.insert(0, str(tools))

    # Prefer a complete Pillow installation belonging to the active Python.
    # The bundled temp/pydeps copy may contain a cpython-313 extension; that
    # copy cannot be imported by Homebrew Python 3.14 even though the package
    # directory itself is present.
    try:
        from PIL import Image  # noqa: F401
    except ModuleNotFoundError as exc:
        if exc.name != "PIL":
            raise RuntimeError("当前 Python 的 Pillow 依赖没有加载成功") from exc
        if str(pydeps) not in sys.path:
            sys.path.insert(0, str(pydeps))
        try:
            from PIL import Image  # noqa: F401
        except ImportError as inner:
            raise RuntimeError(
                "动画素材解码依赖没有加载成功。请确认 temp/pydeps/PIL/_imaging "
                "与当前 Python 版本匹配。"
            ) from inner
    except ImportError as exc:
        raise RuntimeError("当前 Python 的 Pillow 原生模块无法加载") from exc

    # texture2ddecoder is shipped in temp/pydeps as an abi3 extension.  Add
    # that directory after Pillow has been imported so it cannot shadow a
    # working system Pillow package.
    if str(pydeps) not in sys.path:
        sys.path.append(str(pydeps))
    try:
        import texture2ddecoder  # noqa: F401
    except ImportError as exc:
        raise RuntimeError(
            "动画素材解码依赖没有加载成功。请确认 temp/pydeps/texture2ddecoder "
            "存在，并且当前 Python 支持 abi3 扩展。"
        ) from exc
    try:
        import compiler.anim_build as anim_build
        from compiler.anim_build import AnimBuild
    except ModuleNotFoundError as exc:
        if exc.name != "compiler":
            raise RuntimeError("DSTmodutils 的 Python 依赖没有加载成功") from exc
        raise RuntimeError("找不到 temp/tools/DSTmodutils/pyscripts") from exc
    except ImportError as exc:
        raise RuntimeError("DSTmodutils 的 Python 依赖没有加载成功") from exc

    anim_build.tex_to_png = decode_tex_to_png
    with ZipFile(spear_zip) as archive:
        parsed = AnimBuild(archive.read("build.bin"), archive)
        parsed.bin_to_json()
        parsed.save_json(str(staging))
        build_name = parsed.data["name"]
    build_path = staging / build_name / "build.json"
    images_root = staging / build_name
    return json.loads(build_path.read_text()), images_root


def build(input_anim: Path, input_build: Path, spear_zip: Path, output: Path) -> None:
    if not input_anim.exists() or not input_build.exists() or not spear_zip.exists():
        raise FileNotFoundError("官方 anim/build 或 swap_spear_lance.zip 不存在")

    animation = json.loads(input_anim.read_text())
    build_data = json.loads(input_build.read_text())
    bank = animation["banks"]["wilsonbeefalo"]
    idle, transition, pre, attack = make_frames(bank)
    bank["yf_mounted_lancejab_idle_side"] = {"framerate": 30, "numframes": len(idle), "frames": idle}
    bank["yf_mounted_lancejab_transition_side"] = {"framerate": 30, "numframes": len(transition), "frames": transition}
    bank["yf_mounted_lancejab_pre_side"] = {"framerate": 30, "numframes": len(pre), "frames": pre}
    bank["yf_mounted_lancejab_side"] = {"framerate": 30, "numframes": len(attack), "frames": attack}

    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="yf-lance-") as tmp:
        spear_build, spear_images = extract_spear_build(spear_zip, Path(tmp))
        build_data["Symbol"][SPEAR_SYMBOL] = spear_build["Symbol"][SPEAR_SYMBOL]
        image_root = output / "images"
        shutil.copytree(input_build.parent / "images", image_root, dirs_exist_ok=True)
        shutil.copytree(spear_images / SPEAR_SYMBOL, image_root / SPEAR_SYMBOL, dirs_exist_ok=True)

    (output / "anim.json").write_text(json.dumps(animation, ensure_ascii=False, separators=(",", ":")))
    (output / "build.json").write_text(json.dumps(build_data, ensure_ascii=False, separators=(",", ":")))
    trigger_frames = len(transition) + len(pre) + len(attack)
    core_attack_frames = len(pre) + len(attack)
    print(
        f"wrote {output / 'anim.json'} "
        f"({len(idle) + trigger_frames} preview frames; trigger {trigger_frames} frames; "
        f"core attack {core_attack_frames} frames)"
    )
    print(f"wrote {output / 'build.json'} with Steam {SPEAR_SYMBOL} symbol")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--anim", type=Path, default=DEFAULT_ANIM)
    parser.add_argument("--build", type=Path, default=DEFAULT_BUILD)
    parser.add_argument("--spear-zip", type=Path, default=DEFAULT_SPEAR_ZIP)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    build(args.anim, args.build, args.spear_zip, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
