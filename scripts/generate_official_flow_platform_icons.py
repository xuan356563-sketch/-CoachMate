#!/usr/bin/env python3
"""从用户确认的 Ninja Flow 官方标识生成三端独立图标。"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
import tempfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/source/trainmate-flow-logo-final-20260717.png"
SOURCE_SHA256 = "8370687c15f3ffa5c131906853ceb845e87ee9b052c759abafc9cd8a2492d365"
IOS_SET = ROOT / "ios/Runner/Assets.xcassets/OfficialFlowIcon.appiconset"
BACKGROUND = "#FEFEFE"
SUBJECT_BOX = (119, 199, 1082, 1021)

IOS_SLOTS = (
    ("iphone", "20x20", "2x", 40), ("iphone", "20x20", "3x", 60),
    ("iphone", "29x29", "1x", 29), ("iphone", "29x29", "2x", 58),
    ("iphone", "29x29", "3x", 87), ("iphone", "40x40", "2x", 80),
    ("iphone", "40x40", "3x", 120), ("iphone", "60x60", "2x", 120),
    ("iphone", "60x60", "3x", 180), ("ipad", "20x20", "1x", 20),
    ("ipad", "20x20", "2x", 40), ("ipad", "29x29", "1x", 29),
    ("ipad", "29x29", "2x", 58), ("ipad", "40x40", "1x", 40),
    ("ipad", "40x40", "2x", 80), ("ipad", "76x76", "1x", 76),
    ("ipad", "76x76", "2x", 152), ("ipad", "83.5x83.5", "2x", 167),
    ("ios-marketing", "1024x1024", "1x", 1024),
)
ANDROID_SIZES = {
    "mipmap-mdpi/ic_trainmate_official_flow.png": 48,
    "mipmap-hdpi/ic_trainmate_official_flow.png": 72,
    "mipmap-xhdpi/ic_trainmate_official_flow.png": 96,
    "mipmap-xxhdpi/ic_trainmate_official_flow.png": 144,
    "mipmap-xxxhdpi/ic_trainmate_official_flow.png": 192,
}
WEB_SIZES = {
    "web/icons/official-flow/Icon-192.png": (192, False),
    "web/icons/official-flow/Icon-512.png": (512, False),
    "web/icons/official-flow/Icon-maskable-192.png": (192, True),
    "web/icons/official-flow/Icon-maskable-512.png": (512, True),
    "web/official-flow-favicon.png": (64, False),
}


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _source() -> Image.Image:
    data = SOURCE.read_bytes()
    if _sha256(data) != SOURCE_SHA256:
        raise ValueError("Ninja Flow 官方标识 SHA-256 与用户确认源文件不一致")
    with Image.open(io.BytesIO(data)) as image:
        if image.size != (1254, 1254) or image.mode != "RGB":
            raise ValueError("Ninja Flow 官方标识必须为 1254×1254 RGB PNG")
        return image.crop(SUBJECT_BOX).copy()


def _master(source: Image.Image, *, maskable: bool) -> Image.Image:
    """裁切官方标识主体后放入安全区，绝不缩小整张白底源图。"""
    canvas = Image.new("RGB", (1024, 1024), BACKGROUND)
    scale = 0.60 if maskable else 0.78
    width = round(1024 * scale)
    height = round(source.height * width / source.width)
    subject = source.resize((width, height), Image.Resampling.LANCZOS)
    canvas.paste(subject, ((1024 - width) // 2, (1024 - height) // 2))
    return canvas


def _png(image: Image.Image, size: int) -> bytes:
    output = io.BytesIO()
    image.resize((size, size), Image.Resampling.LANCZOS).save(
        output, format="PNG", optimize=False, compress_level=9
    )
    return output.getvalue()


def _name(idiom: str, size: str, scale: str) -> str:
    return f"OfficialFlow-{idiom}-{size.replace('.', '-')}@{scale}.png"


def _expected() -> dict[Path, bytes]:
    standard = _master(_source(), maskable=False)
    maskable = _master(_source(), maskable=True)
    files: dict[Path, bytes] = {}
    images: list[dict[str, str]] = []
    for idiom, size, scale, pixels in IOS_SLOTS:
        filename = _name(idiom, size, scale)
        images.append({"size": size, "idiom": idiom, "filename": filename, "scale": scale})
        files[IOS_SET / filename] = _png(standard, pixels)
    files[IOS_SET / "Contents.json"] = (
        json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, ensure_ascii=False, indent=2) + "\n"
    ).encode()
    for relative, pixels in ANDROID_SIZES.items():
        files[ROOT / "android/app/src/main/res" / relative] = _png(standard, pixels)
    for relative, (pixels, use_maskable) in WEB_SIZES.items():
        files[ROOT / relative] = _png(maskable if use_maskable else standard, pixels)
    return files


def _write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        temporary.write(data)
        temporary_path = Path(temporary.name)
    temporary_path.replace(path)


def _validate_config() -> None:
    project = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text()
    if project.count("ASSETCATALOG_COMPILER_APPICON_NAME = OfficialFlowIcon;") != 3:
        raise ValueError("iOS 三个构建配置必须共同指向 OfficialFlowIcon")
    android = (ROOT / "android/app/src/main/AndroidManifest.xml").read_text()
    if 'android:icon="@mipmap/ic_trainmate_official_flow"' not in android:
        raise ValueError("AndroidManifest.xml 尚未指向 Ninja Flow 官方图标")
    manifest = json.loads((ROOT / "web/manifest.json").read_text())
    expected = [
        "icons/official-flow/Icon-192.png", "icons/official-flow/Icon-512.png",
        "icons/official-flow/Icon-maskable-192.png", "icons/official-flow/Icon-maskable-512.png",
    ]
    if [item["src"] for item in manifest["icons"]] != expected:
        raise ValueError("Web manifest 尚未精确指向 Ninja Flow 官方图标")
    index = (ROOT / "web/index.html").read_text()
    if 'href="icons/official-flow/Icon-192.png"' not in index or 'href="official-flow-favicon.png"' not in index:
        raise ValueError("Web index 尚未指向 Ninja Flow 官方图标")


def _check() -> dict[str, object]:
    expected = _expected()
    for path, data in expected.items():
        if not path.is_file() or _sha256(path.read_bytes()) != _sha256(data):
            raise ValueError(f"官方图标内容不一致：{path.relative_to(ROOT)}")
        if path.suffix == ".png":
            with Image.open(path) as image:
                if image.mode != "RGB":
                    raise ValueError(f"官方图标必须完全不透明：{path.relative_to(ROOT)}")
    _validate_config()
    return {"status": "ok", "ios": len(IOS_SLOTS), "android": len(ANDROID_SIZES), "web": len(WEB_SIZES)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="只读复算图标、尺寸与三端配置")
    args = parser.parse_args()
    try:
        if args.check:
            result = _check()
        else:
            for path, data in _expected().items():
                _write(path, data)
            result = {"status": "generated", "ios": len(IOS_SLOTS), "android": len(ANDROID_SIZES), "web": len(WEB_SIZES)}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"Ninja Flow 官方图标处理失败：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
