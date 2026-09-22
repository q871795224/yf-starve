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


PRIMARY_HAND_Z = 39
SUPPORT_HAND_Z = 34
PRIMARY_ARM_Z = (39, 40, 41, 42, 43)
SUPPORT_ARM_Z = (34, 35, 36, 37, 38)
GRIP_HAND_FRONT_Z = 1


def spear_matrix(degrees: float, width_scale: float = 1.0, length_scale: float = 1.0) -> list[float]:
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


def element_point(element: dict[str, Any]) -> tuple[float, float]:
    return float(element["m_tx"]), float(element["m_ty"])


def tip_axis(degrees: float) -> tuple[float, float]:
    radians = math.radians(degrees)
    # The spear build is vertical in its local image: its tip is at -Y.
    return math.sin(radians), -math.cos(radians)


def angle_of(vector: tuple[float, float]) -> float:
    return math.degrees(math.atan2(vector[1], vector[0]))


def rotate_elements(frame: dict[str, Any], z_indices: tuple[int, ...], pivot: tuple[float, float], degrees: float) -> None:
    if abs(degrees) < 1e-5:
        return
    transform = around_point(pivot[0], pivot[1], degrees)
    for element in frame["elements"]:
        if element.get("z_index") in z_indices:
            element.update(dict(zip(MATRIX_KEYS, multiply(transform, matrix(element)))))


def add_rider_lean(frame: dict[str, Any], degrees: float) -> None:
    pelvis = find_element(frame, "torso_pelvis", 22)
    lean = around_point(float(pelvis["m_tx"]), float(pelvis["m_ty"]), degrees)

    for element in frame["elements"]:
        if element.get("z_index") in RIDER_Z:
            element.update(dict(zip(MATRIX_KEYS, multiply(lean, matrix(element)))))


def align_primary_grip(frame: dict[str, Any], angle: float) -> None:
    """Turn the weapon arm toward the lance while keeping its hand in place."""
    hand = find_element(frame, "hand", PRIMARY_HAND_Z)
    forearm = find_element(frame, "arm_lower", 43)
    hand_point = element_point(hand)
    current_axis = angle_of((hand_point[0] - float(forearm["m_tx"]), hand_point[1] - float(forearm["m_ty"])))
    desired_axis = angle - 90.0
    delta = max(-55.0, min(55.0, desired_axis - current_axis))
    rotate_elements(frame, PRIMARY_ARM_Z, hand_point, delta)


def align_support_grip(frame: dict[str, Any], anchor: tuple[float, float], angle: float) -> None:
    """Place the second hand on the same lance line without stretching the arm."""
    shoulder = find_element(frame, "arm_upper", 35)
    hand = find_element(frame, "hand", SUPPORT_HAND_Z)
    shoulder_point = element_point(shoulder)
    hand_point = element_point(hand)
    arm_vector = (hand_point[0] - shoulder_point[0], hand_point[1] - shoulder_point[1])
    arm_length = math.hypot(*arm_vector)
    if arm_length < 1e-5:
        return

    axis = tip_axis(angle)
    shoulder_to_anchor = (anchor[0] - shoulder_point[0], anchor[1] - shoulder_point[1])
    projection = shoulder_to_anchor[0] * axis[0] + shoulder_to_anchor[1] * axis[1]
    perpendicular_sq = (
        shoulder_to_anchor[0] ** 2 + shoulder_to_anchor[1] ** 2 - projection ** 2
    )
    discriminant = arm_length ** 2 - perpendicular_sq
    if discriminant < 0:
        return

    # The support hand sits behind the primary hand along the shaft.  Choose
    # the negative root so the arm does not cross past the forward hand.
    distance = -projection - math.sqrt(max(0.0, discriminant))
    target = (anchor[0] + distance * axis[0], anchor[1] + distance * axis[1])
    current_angle = angle_of(arm_vector)
    target_angle = angle_of((target[0] - shoulder_point[0], target[1] - shoulder_point[1]))
    rotate_elements(frame, SUPPORT_ARM_Z, shoulder_point, target_angle - current_angle)


def bring_grip_hands_forward(frame: dict[str, Any]) -> None:
    """Render the two grip hands above the weapon so the contact reads clearly."""
    for source_z in (SUPPORT_HAND_Z, PRIMARY_HAND_Z):
        source = find_element(frame, "hand", source_z)
        hand = copy.deepcopy(source)
        hand["z_index"] = GRIP_HAND_FRONT_Z
        frame["elements"].append(hand)


def replace_with_spear(
    frame: dict[str, Any],
    anchor: tuple[float, float],
    angle: float,
    z_index: int = 2,
    width_scale: float = 1.0,
    length_scale: float = 1.0,
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
        # Keep the local origin at the primary hand.  Translating the weapon
        # independently makes it visibly detach from both hands during the
        # attack; the upward thrust is expressed by the arm and angle instead.
        spear["m_tx"], spear["m_ty"] = anchor
        elements.append(spear)
    frame["elements"] = elements


def progress_values(count: int, values: list[float]) -> list[float]:
    if count != len(values):
        raise ValueError(f"profile has {len(values)} values, expected {count}")
    return values


def make_frames(
    bank: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    idle = [copy.deepcopy(frame) for frame in bank["idle_loop"]["frames"][:3]]
    pre = [copy.deepcopy(frame) for frame in bank["atk_pre_side"]["frames"]]
    attack = [copy.deepcopy(frame) for frame in bank["atk_side"]["frames"]]

    pre_lean = progress_values(len(pre), [0, 5, 10, 15, 20, 24])
    attack_lean = progress_values(len(attack), [26, 30, 30, 28, 24, 20, 16, 12, 8, 4, 0, 0, 0, 0, 0, 0, 0])
    pre_angles = [0, 4, 8, 12, 16, 20]
    attack_angles = [20, 17, 14, 11, 8, 5, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    for frame in idle:
        add_rider_lean(frame, 0)
        anchor = element_point(find_element(frame, "hand", PRIMARY_HAND_Z))
        align_primary_grip(frame, 0)
        align_support_grip(frame, anchor, 0)
        replace_with_spear(frame, anchor, angle=0, z_index=2)
        bring_grip_hands_forward(frame)
    for frame, lean, angle in zip(pre, pre_lean, pre_angles):
        add_rider_lean(frame, lean)
        anchor = element_point(find_element(frame, "hand", PRIMARY_HAND_Z))
        align_primary_grip(frame, angle)
        align_support_grip(frame, anchor, angle)
        replace_with_spear(frame, anchor, angle=angle, z_index=2)
        bring_grip_hands_forward(frame)
    for frame, lean, angle in zip(attack, attack_lean, attack_angles):
        add_rider_lean(frame, lean)
        anchor = element_point(find_element(frame, "hand", PRIMARY_HAND_Z))
        align_primary_grip(frame, angle)
        align_support_grip(frame, anchor, angle)
        replace_with_spear(frame, anchor, angle=angle, z_index=2)
        bring_grip_hands_forward(frame)
    return idle, pre, attack


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
    idle, pre, attack = make_frames(bank)
    bank["yf_mounted_lancejab_idle_side"] = {"framerate": 30, "numframes": len(idle), "frames": idle}
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
    trigger_frames = len(pre) + len(attack)
    core_attack_frames = trigger_frames
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
