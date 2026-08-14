"""Ninja Flow 官方标识三端图标契约测试。"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import unittest
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "scripts/generate_official_flow_platform_icons.py"
IOS_SET = ROOT / "ios/Runner/Assets.xcassets/OfficialFlowIcon.appiconset"
ANDROID = {
    "mipmap-mdpi/ic_trainmate_official_flow.png": 48,
    "mipmap-hdpi/ic_trainmate_official_flow.png": 72,
    "mipmap-xhdpi/ic_trainmate_official_flow.png": 96,
    "mipmap-xxhdpi/ic_trainmate_official_flow.png": 144,
    "mipmap-xxxhdpi/ic_trainmate_official_flow.png": 192,
}
WEB = {
    "web/icons/official-flow/Icon-192.png": 192,
    "web/icons/official-flow/Icon-512.png": 512,
    "web/icons/official-flow/Icon-maskable-192.png": 192,
    "web/icons/official-flow/Icon-maskable-512.png": 512,
    "web/official-flow-favicon.png": 64,
}


def _snapshot() -> dict[str, str]:
    files = [GENERATOR, *IOS_SET.glob("*"), *(ROOT / "android/app/src/main/res" / item for item in ANDROID), *(ROOT / item for item in WEB)]
    return {item.relative_to(ROOT).as_posix(): hashlib.sha256(item.read_bytes()).hexdigest() for item in files if item.is_file()}


class OfficialFlowPlatformIconsTest(unittest.TestCase):
    def test_官方图标三端尺寸完整且不透明(self) -> None:
        contents = json.loads((IOS_SET / "Contents.json").read_text())
        self.assertEqual(len(contents["images"]), 19)
        for item in contents["images"]:
            with Image.open(IOS_SET / item["filename"]) as image:
                self.assertEqual(image.mode, "RGB")
        for relative, size in {**ANDROID, **WEB}.items():
            path = ROOT / "android/app/src/main/res" / relative if relative.startswith("mipmap") else ROOT / relative
            with Image.open(path) as image:
                self.assertEqual(image.size, (size, size), relative)
                self.assertEqual(image.mode, "RGB", relative)

    def test_maskable图标使用更大的安全边距(self) -> None:
        standard = ROOT / "web/icons/official-flow/Icon-512.png"
        maskable = ROOT / "web/icons/official-flow/Icon-maskable-512.png"
        self.assertNotEqual(hashlib.sha256(standard.read_bytes()).hexdigest(), hashlib.sha256(maskable.read_bytes()).hexdigest())
        with Image.open(maskable) as image:
            background = Image.new("RGB", image.size, image.getpixel((0, 0)))
            box = ImageChops.difference(image, background).getbbox()
            self.assertIsNotNone(box)
            assert box is not None
            self.assertGreaterEqual(box[0], 92)
            self.assertGreaterEqual(box[1], 92)
            self.assertLessEqual(box[2], 420)
            self.assertLessEqual(box[3], 420)

    def test三端配置仅指向官方标识(self) -> None:
        project = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text()
        self.assertEqual(project.count("ASSETCATALOG_COMPILER_APPICON_NAME = OfficialFlowIcon;"), 3)
        self.assertIn('android:icon="@mipmap/ic_trainmate_official_flow"', (ROOT / "android/app/src/main/AndroidManifest.xml").read_text())
        manifest = json.loads((ROOT / "web/manifest.json").read_text())
        self.assertEqual(manifest["icons"][0]["src"], "icons/official-flow/Icon-192.png")

    def test_check模式完全只读(self) -> None:
        before = _snapshot()
        result = subprocess.run([sys.executable, str(GENERATOR), "--check"], cwd=ROOT, text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertEqual(before, _snapshot())


if __name__ == "__main__":
    unittest.main()
