"""MATE C-08 三端平台图标契约测试。"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import unittest
from pathlib import Path

from PIL import Image, ImageChops


项目根目录 = Path(__file__).resolve().parents[2]
生成器 = 项目根目录 / "scripts/generate_mate_feast_platform_icons.py"
IOS图标集 = 项目根目录 / "ios/Runner/Assets.xcassets/MateFeastIcon.appiconset"
安卓图标 = {
    "mipmap-mdpi/ic_trainmate_mate_feast.png": 48,
    "mipmap-hdpi/ic_trainmate_mate_feast.png": 72,
    "mipmap-xhdpi/ic_trainmate_mate_feast.png": 96,
    "mipmap-xxhdpi/ic_trainmate_mate_feast.png": 144,
    "mipmap-xxxhdpi/ic_trainmate_mate_feast.png": 192,
}
网页图标 = {
    "web/icons/mate-feast/Icon-192.png": 192,
    "web/icons/mate-feast/Icon-512.png": 512,
    "web/icons/mate-feast/Icon-maskable-192.png": 192,
    "web/icons/mate-feast/Icon-maskable-512.png": 512,
    "web/mate-feast-favicon.png": 64,
}


def 快照() -> dict[str, str]:
    文件 = [
        生成器,
        *IOS图标集.glob("*"),
        *(项目根目录 / "android/app/src/main/res" / 项目 for 项目 in 安卓图标),
        *(项目根目录 / 项目 for 项目 in 网页图标),
    ]
    return {
        项目.relative_to(项目根目录).as_posix(): hashlib.sha256(项目.read_bytes()).hexdigest()
        for 项目 in 文件
        if 项目.is_file()
    }


class MateFeast平台图标契约测试(unittest.TestCase):
    def test_三端图标完整且不透明(self) -> None:
        内容 = json.loads((IOS图标集 / "Contents.json").read_text(encoding="utf-8"))
        self.assertEqual(19, len(内容["images"]))
        for 项目 in 内容["images"]:
            with Image.open(IOS图标集 / 项目["filename"]) as 图片:
                self.assertEqual("RGB", 图片.mode)
        for 相对路径, 尺寸 in {**安卓图标, **网页图标}.items():
            路径 = (
                项目根目录 / "android/app/src/main/res" / 相对路径
                if 相对路径.startswith("mipmap")
                else 项目根目录 / 相对路径
            )
            with Image.open(路径) as 图片:
                self.assertEqual((尺寸, 尺寸), 图片.size, 相对路径)
                self.assertEqual("RGB", 图片.mode, 相对路径)

    def test_maskable图标保留安全区(self) -> None:
        标准 = 项目根目录 / "web/icons/mate-feast/Icon-512.png"
        安全区 = 项目根目录 / "web/icons/mate-feast/Icon-maskable-512.png"
        self.assertNotEqual(
            hashlib.sha256(标准.read_bytes()).hexdigest(),
            hashlib.sha256(安全区.read_bytes()).hexdigest(),
        )
        with Image.open(安全区) as 图片:
            背景 = Image.new("RGB", 图片.size, 图片.getpixel((0, 0)))
            边界 = ImageChops.difference(图片, 背景).getbbox()
            self.assertIsNotNone(边界)
            assert 边界 is not None
            self.assertGreaterEqual(边界[0], 88)
            self.assertGreaterEqual(边界[1], 88)
            self.assertLessEqual(边界[2], 424)
            self.assertLessEqual(边界[3], 424)

    def test_旧图标保留但三端配置已切换官方设备面板(self) -> None:
        工程 = (项目根目录 / "ios/Runner.xcodeproj/project.pbxproj").read_text()
        self.assertEqual(
            3,
            工程.count(
                "ASSETCATALOG_COMPILER_APPICON_NAME = CoachMateOfficialIcon;"
            ),
        )
        安卓配置 = (项目根目录 / "android/app/src/main/AndroidManifest.xml").read_text()
        self.assertIn('android:icon="@mipmap/ic_coachmate_official"', 安卓配置)
        网页配置 = json.loads((项目根目录 / "web/manifest.json").read_text())
        self.assertEqual(
            "icons/coachmate-official/Icon-192.png",
            网页配置["icons"][0]["src"],
        )
        首页 = (项目根目录 / "web/index.html").read_text()
        self.assertIn('href="icons/coachmate-official/Icon-192.png"', 首页)
        self.assertIn('href="coachmate-official-favicon.png"', 首页)

    def test_check模式完全只读(self) -> None:
        修改前 = 快照()
        结果 = subprocess.run(
            [sys.executable, str(生成器), "--check"],
            cwd=项目根目录,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, 结果.returncode, 结果.stderr or 结果.stdout)
        self.assertEqual(修改前, 快照())


if __name__ == "__main__":
    unittest.main()
