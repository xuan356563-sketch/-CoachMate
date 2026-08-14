"""Flow V2 三端独立图标契约测试。"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import unittest
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "scripts/generate_flow_v2_platform_icons.py"
IOS_SET = ROOT / "ios/Runner/Assets.xcassets/FlowV2Icon.appiconset"

IOS_SLOTS = {
    ("iphone", "20x20", "2x"): 40,
    ("iphone", "20x20", "3x"): 60,
    ("iphone", "29x29", "1x"): 29,
    ("iphone", "29x29", "2x"): 58,
    ("iphone", "29x29", "3x"): 87,
    ("iphone", "40x40", "2x"): 80,
    ("iphone", "40x40", "3x"): 120,
    ("iphone", "60x60", "2x"): 120,
    ("iphone", "60x60", "3x"): 180,
    ("ipad", "20x20", "1x"): 20,
    ("ipad", "20x20", "2x"): 40,
    ("ipad", "29x29", "1x"): 29,
    ("ipad", "29x29", "2x"): 58,
    ("ipad", "40x40", "1x"): 40,
    ("ipad", "40x40", "2x"): 80,
    ("ipad", "76x76", "1x"): 76,
    ("ipad", "76x76", "2x"): 152,
    ("ipad", "83.5x83.5", "2x"): 167,
    ("ios-marketing", "1024x1024", "1x"): 1024,
}

ANDROID_ICONS = {
    "mipmap-mdpi/ic_trainmate_flow_v2.png": 48,
    "mipmap-hdpi/ic_trainmate_flow_v2.png": 72,
    "mipmap-xhdpi/ic_trainmate_flow_v2.png": 96,
    "mipmap-xxhdpi/ic_trainmate_flow_v2.png": 144,
    "mipmap-xxxhdpi/ic_trainmate_flow_v2.png": 192,
}

WEB_ICONS = {
    "web/icons/flow-v2/Icon-192.png": 192,
    "web/icons/flow-v2/Icon-512.png": 512,
    "web/icons/flow-v2/Icon-maskable-192.png": 192,
    "web/icons/flow-v2/Icon-maskable-512.png": 512,
    "web/flow-v2-favicon.png": 64,
}

# 本任务开始前现有图标文件的聚合 SHA-256，用于防止生成器覆盖用户改动。
PROTECTED_DIGESTS = {
    "ios-appicon": "c016b972ee528a35e1bfc85d3e51818d672d186cd2c40638b5f1291e636f3d5d",
    "ios-flowdog": "0a5ec5985c09398dcc19ce05ca407da0b0d8902126da432df2a60b55481def18",
    "android-launcher": "370292efdad88add79d3319eae5a4a3fd87e05b93305e480c1e158fa158f7b84",
    "android-flowdog": "e5e4fc4f1e6a94dfd7c56e76e8e9265886095596745c68d9e58c5a3cd2f2d7ec",
    "web-default": "e12761b4c00e7ecbd43908f47334c841a9b14bc24f596d7e45ac35d1ce416645",
}


def _assert_opaque(test: unittest.TestCase, path: Path, size: int) -> None:
    with Image.open(path) as image:
        test.assertEqual(image.size, (size, size), path)
        test.assertEqual(image.mode, "RGB", path)


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


def _output_snapshot() -> dict[str, str]:
    candidates = [GENERATOR, IOS_SET]
    candidates.extend(
        ROOT / "android/app/src/main/res" / relative
        for relative in ANDROID_ICONS
    )
    candidates.extend(ROOT / relative for relative in WEB_ICONS)
    files: list[Path] = []
    for path in candidates:
        if path.is_dir():
            files.extend(sorted(item for item in path.rglob("*") if item.is_file()))
        elif path.is_file():
            files.append(path)
    return {
        path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in files
    }


class FlowV2PlatformIconsTest(unittest.TestCase):
    def test_ios_contents完整且图标不透明(self) -> None:
        contents = json.loads((IOS_SET / "Contents.json").read_text(encoding="utf-8"))
        images = contents["images"]
        actual = {
            (item["idiom"], item["size"], item["scale"]): item["filename"]
            for item in images
        }
        self.assertEqual(set(actual), set(IOS_SLOTS))
        self.assertEqual(len(set(actual.values())), len(IOS_SLOTS))
        for slot, pixels in IOS_SLOTS.items():
            filename = actual[slot]
            self.assertTrue(filename.startswith("FlowV2-"), filename)
            _assert_opaque(self, IOS_SET / filename, pixels)

    def test_android五个密度尺寸精确(self) -> None:
        resource_root = ROOT / "android/app/src/main/res"
        for relative, size in ANDROID_ICONS.items():
            _assert_opaque(self, resource_root / relative, size)

    def test_web标准与maskable图标独立且安全区正确(self) -> None:
        for relative, size in WEB_ICONS.items():
            _assert_opaque(self, ROOT / relative, size)
        for size in (192, 512):
            standard = ROOT / f"web/icons/flow-v2/Icon-{size}.png"
            maskable = ROOT / f"web/icons/flow-v2/Icon-maskable-{size}.png"
            self.assertNotEqual(
                hashlib.sha256(standard.read_bytes()).hexdigest(),
                hashlib.sha256(maskable.read_bytes()).hexdigest(),
            )
            with Image.open(maskable) as image:
                background = image.getpixel((0, 0))
                background_image = Image.new("RGB", image.size, background)
                box = ImageChops.difference(image, background_image).getbbox()
                self.assertIsNotNone(box)
                assert box is not None
                safe_margin = int(size * 0.18)
                self.assertGreaterEqual(box[0], safe_margin)
                self.assertGreaterEqual(box[1], safe_margin)
                self.assertLessEqual(box[2], size - safe_margin)
                self.assertLessEqual(box[3], size - safe_margin)

    def test_flow_v2图标集作为兼容回退仍完整保留(self) -> None:
        self.assertTrue(IOS_SET.is_dir())
        for relative in ANDROID_ICONS:
            self.assertTrue(
                (ROOT / "android/app/src/main/res" / relative).is_file(),
                relative,
            )
        for relative in WEB_ICONS:
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test旧图标文件保持任务开始前内容(self) -> None:
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
            self.assertEqual(_tree_digest(paths), PROTECTED_DIGESTS[name], name)

    def test_check模式仅读且复算通过(self) -> None:
        before = _output_snapshot()
        result = subprocess.run(
            [sys.executable, str(GENERATOR), "--check"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertEqual(_output_snapshot(), before)


if __name__ == "__main__":
    unittest.main()
