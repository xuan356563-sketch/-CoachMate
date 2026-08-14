#!/usr/bin/env python3
"""从 Flow V2 品牌标确定性生成 iOS、Android 与 Web 独立图标。"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (
    ROOT
    / "assets/branding/flow-v2-color-detail/exports/png/"
    "trainmate-flow-brandmark-1024.png"
)
SOURCE_SHA256 = "538bf13be1739eb25e04f6889148cc08a7d4e7725123079ee45133f5cb609d47"
IOS_SET = ROOT / "ios/Runner/Assets.xcassets/FlowV2Icon.appiconset"

BACKGROUND = "#FFF0E1"
ACCENTS = ("#FFD447", "#55B8FF", "#42D9C1", "#8B72FF")

IOS_SLOTS = (
    ("iphone", "20x20", "2x", 40),
    ("iphone", "20x20", "3x", 60),
    ("iphone", "29x29", "1x", 29),
    ("iphone", "29x29", "2x", 58),
    ("iphone", "29x29", "3x", 87),
    ("iphone", "40x40", "2x", 80),
    ("iphone", "40x40", "3x", 120),
    ("iphone", "60x60", "2x", 120),
    ("iphone", "60x60", "3x", 180),
    ("ipad", "20x20", "1x", 20),
    ("ipad", "20x20", "2x", 40),
    ("ipad", "29x29", "1x", 29),
    ("ipad", "29x29", "2x", 58),
    ("ipad", "40x40", "1x", 40),
    ("ipad", "40x40", "2x", 80),
    ("ipad", "76x76", "1x", 76),
    ("ipad", "76x76", "2x", 152),
    ("ipad", "83.5x83.5", "2x", 167),
    ("ios-marketing", "1024x1024", "1x", 1024),
)

ANDROID_SIZES = {
    "mipmap-mdpi/ic_trainmate_flow_v2.png": 48,
    "mipmap-hdpi/ic_trainmate_flow_v2.png": 72,
    "mipmap-xhdpi/ic_trainmate_flow_v2.png": 96,
    "mipmap-xxhdpi/ic_trainmate_flow_v2.png": 144,
    "mipmap-xxxhdpi/ic_trainmate_flow_v2.png": 192,
}

WEB_SIZES = {
    "web/icons/flow-v2/Icon-192.png": (192, False),
    "web/icons/flow-v2/Icon-512.png": (512, False),
    "web/icons/flow-v2/Icon-maskable-192.png": (192, True),
    "web/icons/flow-v2/Icon-maskable-512.png": (512, True),
    "web/flow-v2-favicon.png": (64, False),
}

PROTECTED_DIGESTS = {
    "ios-appicon": "c016b972ee528a35e1bfc85d3e51818d672d186cd2c40638b5f1291e636f3d5d",
    "ios-flowdog": "0a5ec5985c09398dcc19ce05ca407da0b0d8902126da432df2a60b55481def18",
    "android-launcher": "370292efdad88add79d3319eae5a4a3fd87e05b93305e480c1e158fa158f7b84",
    "android-flowdog": "e5e4fc4f1e6a94dfd7c56e76e8e9265886095596745c68d9e58c5a3cd2f2d7ec",
    "web-default": "e12761b4c00e7ecbd43908f47334c841a9b14bc24f596d7e45ac35d1ce416645",
}


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _read_source() -> Image.Image:
    if not SOURCE.is_file():
        raise ValueError(f"缺少 Flow V2 品牌标：{SOURCE.relative_to(ROOT)}")
    data = SOURCE.read_bytes()
    if _sha256(data) != SOURCE_SHA256:
        raise ValueError("Flow V2 品牌标 SHA-256 与已审素材不一致")
    with Image.open(io.BytesIO(data)) as image:
        if image.size != (1024, 1024) or image.mode != "RGBA":
            raise ValueError("Flow V2 品牌标必须为 1024×1024 RGBA")
        return image.copy()


def _render_master(source: Image.Image, *, maskable: bool) -> Image.Image:
    """在不改变角色轮廓的前提下生成不透明图标母版。"""
    canvas = Image.new("RGB", (1024, 1024), BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    if maskable:
        circles = (
            (250, 246, 52, ACCENTS[0]),
            (770, 246, 46, ACCENTS[1]),
            (250, 778, 44, ACCENTS[2]),
            (770, 778, 52, ACCENTS[3]),
        )
        character_scale = 0.60
    else:
        circles = (
            (164, 176, 72, ACCENTS[0]),
            (860, 188, 62, ACCENTS[1]),
            (178, 846, 58, ACCENTS[2]),
            (848, 838, 74, ACCENTS[3]),
        )
        character_scale = 0.78
    for center_x, center_y, radius, color in circles:
        draw.ellipse(
            (
                center_x - radius,
                center_y - radius,
                center_x + radius,
                center_y + radius,
            ),
            fill=color,
        )

    character_size = round(1024 * character_scale)
    character = source.resize(
        (character_size, character_size),
        Image.Resampling.LANCZOS,
    )
    offset = ((1024 - character_size) // 2, (1024 - character_size) // 2)
    canvas.paste(character, offset, character)
    return canvas


def _png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue()


def _resized_png(master: Image.Image, size: int) -> bytes:
    image = master.resize((size, size), Image.Resampling.LANCZOS)
    return _png_bytes(image)


def _ios_filename(idiom: str, size: str, scale: str) -> str:
    safe_size = size.replace(".", "-")
    return f"FlowV2-{idiom}-{safe_size}@{scale}.png"


def _expected_files() -> dict[Path, bytes]:
    source = _read_source()
    standard = _render_master(source, maskable=False)
    maskable = _render_master(source, maskable=True)
    outputs: dict[Path, bytes] = {}

    ios_images = []
    for idiom, size, scale, pixels in IOS_SLOTS:
        filename = _ios_filename(idiom, size, scale)
        ios_images.append(
            {
                "size": size,
                "idiom": idiom,
                "filename": filename,
                "scale": scale,
            }
        )
        outputs[IOS_SET / filename] = _resized_png(standard, pixels)
    contents = {
        "images": ios_images,
        "info": {"version": 1, "author": "xcode"},
    }
    outputs[IOS_SET / "Contents.json"] = (
        json.dumps(contents, ensure_ascii=False, indent=2) + "\n"
    ).encode()

    android_root = ROOT / "android/app/src/main/res"
    for relative, pixels in ANDROID_SIZES.items():
        outputs[android_root / relative] = _resized_png(standard, pixels)

    for relative, (pixels, use_maskable) in WEB_SIZES.items():
        master = maskable if use_maskable else standard
        outputs[ROOT / relative] = _resized_png(master, pixels)
    return outputs


def _write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        temporary.write(data)
        temporary_path = Path(temporary.name)
    temporary_path.replace(path)


def _tree_digest(paths: list[Path]) -> str:
    files: list[Path] = []
    for path in paths:
        if path.is_dir():
            files.extend(sorted(item for item in path.rglob("*") if item.is_file()))
        else:
            files.append(path)
    digest = hashlib.sha256()
    for path in files:
        relative = path.relative_to(ROOT).as_posix().encode()
        data = path.read_bytes()
        digest.update(len(relative).to_bytes(4, "big"))
        digest.update(relative)
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
    return digest.hexdigest()


def _validate_protected_files() -> None:
    groups = {
        "ios-appicon": [ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"],
        "ios-flowdog": [ROOT / "ios/Runner/Assets.xcassets/FlowDogIcon.appiconset"],
        "android-launcher": sorted(
            ROOT.glob("android/app/src/main/res/mipmap-*/ic_launcher.png")
        ),
        "android-flowdog": sorted(
            ROOT.glob(
                "android/app/src/main/res/mipmap-*/ic_trainmate_flow_dog.png"
            )
        ),
        "web-default": [
            ROOT / "web/favicon.png",
            *sorted(ROOT.glob("web/icons/Icon-*.png")),
        ],
    }
    for name, paths in groups.items():
        if _tree_digest(paths) != PROTECTED_DIGESTS[name]:
            raise ValueError(f"受保护旧图标发生变化：{name}")


def _validate_config() -> None:
    project = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text()
    if project.count("ASSETCATALOG_COMPILER_APPICON_NAME = FlowV2Icon;") != 3:
        raise ValueError("iOS 必须由三个构建配置共同指向 FlowV2Icon")
    if "ASSETCATALOG_COMPILER_APPICON_NAME = FlowDogIcon;" in project:
        raise ValueError("iOS 构建配置仍引用 FlowDogIcon")

    android = (ROOT / "android/app/src/main/AndroidManifest.xml").read_text()
    if 'android:icon="@mipmap/ic_trainmate_flow_v2"' not in android:
        raise ValueError("AndroidManifest.xml 尚未指向 Flow V2 图标")

    manifest = json.loads((ROOT / "web/manifest.json").read_text())
    expected = [
        "icons/flow-v2/Icon-192.png",
        "icons/flow-v2/Icon-512.png",
        "icons/flow-v2/Icon-maskable-192.png",
        "icons/flow-v2/Icon-maskable-512.png",
    ]
    if [item["src"] for item in manifest["icons"]] != expected:
        raise ValueError("Web manifest 尚未精确指向 Flow V2 图标")
    index = (ROOT / "web/index.html").read_text()
    if 'href="icons/flow-v2/Icon-192.png"' not in index:
        raise ValueError("Web apple-touch-icon 尚未指向 Flow V2")
    if 'href="flow-v2-favicon.png"' not in index:
        raise ValueError("Web favicon 尚未指向 Flow V2")


def _check() -> dict[str, object]:
    expected = _expected_files()
    for path, data in expected.items():
        if not path.is_file():
            raise ValueError(f"缺少 Flow V2 平台图标：{path.relative_to(ROOT)}")
        actual = path.read_bytes()
        if _sha256(actual) != _sha256(data):
            raise ValueError(f"Flow V2 平台图标内容不一致：{path.relative_to(ROOT)}")
        if path.suffix == ".png":
            with Image.open(io.BytesIO(actual)) as image:
                if image.mode != "RGB":
                    raise ValueError(f"平台图标必须完全不透明：{path.relative_to(ROOT)}")
    _validate_protected_files()
    return {
        "status": "ok",
        "sourceSha256": SOURCE_SHA256,
        "ios": len(IOS_SLOTS),
        "android": len(ANDROID_SIZES),
        "web": len(WEB_SIZES),
        "totalPng": sum(path.suffix == ".png" for path in expected),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="只读复算尺寸、模式、SHA-256、配置与旧图标保护状态",
    )
    args = parser.parse_args()
    try:
        if args.check:
            result = _check()
        else:
            _validate_protected_files()
            for path, data in _expected_files().items():
                _write_atomic(path, data)
            result = {
                "status": "generated",
                "ios": len(IOS_SLOTS),
                "android": len(ANDROID_SIZES),
                "web": len(WEB_SIZES),
            }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"Flow V2 平台图标处理失败：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
