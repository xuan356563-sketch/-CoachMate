"""CoachMate 官方 Logo 第一阶段审图素材契约。"""

from __future__ import annotations

import hashlib
import json
import subprocess
import unittest
from pathlib import Path

from PIL import Image


项目根目录 = Path(__file__).resolve().parents[2]
素材根目录 = 项目根目录 / "assets/branding/coachmate-official-logo-v1"
官方源图哈希 = "bdba7b1a2e5a9b2bf1939a1d5b444a146235e111abe567770279bd2f74a4c054"


class CoachMate官方Logo审图素材测试(unittest.TestCase):
    def test_官方源图保持原始内容(self) -> None:
        路径 = 素材根目录 / "source/official-logo-user-provided.png"
        self.assertTrue(路径.is_file())
        self.assertEqual(hashlib.sha256(路径.read_bytes()).hexdigest(), 官方源图哈希)
        with Image.open(路径) as 图片:
            self.assertEqual(图片.size, (5404, 3040))
            self.assertEqual(图片.mode, "RGB")

    def test_设备面板母图为真实透明_png(self) -> None:
        路径 = 素材根目录 / "exports/png/coachmate-device-panel-1024.png"
        with Image.open(路径) as 图片:
            图片.load()
            self.assertEqual(图片.size, (1024, 1024))
            self.assertEqual(图片.mode, "RGBA")
            self.assertEqual(图片.getchannel("A").getextrema(), (0, 255))

    def test_完整品牌人物母图为真实透明_png(self) -> None:
        路径 = 素材根目录 / "exports/png/coachmate-brand-character-1024.png"
        with Image.open(路径) as 图片:
            图片.load()
            self.assertEqual(图片.size, (1024, 1024))
            self.assertEqual(图片.mode, "RGBA")
            self.assertEqual(图片.getchannel("A").getextrema(), (0, 255))

    def test_清单记录已确认并允许运行时接入(self) -> None:
        清单 = json.loads((素材根目录 / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(清单["status"], "approved-for-runtime")
        self.assertTrue(清单["runtimeIntegrated"])
        self.assertTrue(清单["reviewGate"]["required"])
        self.assertEqual(清单["reviewGate"]["approvedAt"], "2026-08-15")
        self.assertEqual(
            清单["promptVersion"], "coachmate-official-brand-character-v1.3-full-body"
        )
        self.assertEqual(
            清单["devicePanelPromptVersion"],
            "coachmate-official-device-panel-v1.2-paper-bag",
        )
        self.assertTrue(any("绑带" in 条目 for 条目 in 清单["reviewGate"]["criteria"]))
        self.assertTrue(any("纸袋" in 条目 for 条目 in 清单["reviewGate"]["criteria"]))
        self.assertTrue(any("完整人物" in 条目 for 条目 in 清单["reviewGate"]["criteria"]))
        self.assertEqual(
            清单["runtimeAssets"]["brandmark"]["path"],
            "assets/branding/coachmate-official-logo-v1/exports/png/"
            "coachmate-device-panel-1024.png",
        )
        self.assertEqual(
            清单["runtimeAssets"]["character"]["path"],
            "assets/branding/coachmate-official-logo-v1/exports/png/"
            "coachmate-brand-character-1024.png",
        )
        self.assertEqual(
            清单["runtimeAssets"]["lockup"]["path"],
            "assets/branding/coachmate-official-logo-v1/exports/png/"
            "coachmate-official-lockup-2048x1152.png",
        )

    def test_官方组合标运行时导出保持原图内容比例并移除外部白底(self) -> None:
        路径 = 素材根目录 / "exports/png/coachmate-official-lockup-2048x1152.png"
        with Image.open(路径) as 图片:
            图片.load()
            self.assertEqual(图片.size, (2048, 1152))
            self.assertEqual(图片.mode, "RGBA")
            self.assertEqual(图片.getchannel("A").getextrema(), (0, 255))
            for 坐标 in ((0, 0), (2047, 0), (0, 1151), (2047, 1151)):
                self.assertEqual(图片.getpixel(坐标)[3], 0)

    def test_无绑带首版只作为历史留档(self) -> None:
        留档 = 素材根目录 / "source/device-panel-generated-transparent-v1-without-tie.png"
        self.assertTrue(留档.is_file())
        清单文本 = (素材根目录 / "manifest.json").read_text(encoding="utf-8")
        self.assertNotIn(留档.name, 清单文本)

    def test_饭盒感绑带版只作为历史留档(self) -> None:
        留档 = 素材根目录 / "source/device-panel-generated-transparent-v1.1-tied-boxy.png"
        self.assertTrue(留档.is_file())
        清单文本 = (素材根目录 / "manifest.json").read_text(encoding="utf-8")
        self.assertNotIn(留档.name, 清单文本)

    def test_生成器只读校验通过(self) -> None:
        结果 = subprocess.run(
            ["python3", "scripts/generate_coachmate_official_review_assets.py", "--check"],
            cwd=项目根目录,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(结果.returncode, 0, msg=结果.stdout + 结果.stderr)

    def test_否决原型未进入当前品牌加载链(self) -> None:
        品牌实现 = (项目根目录 / "lib/core/widgets/trainmate_branding.dart").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("coachmate-device-panel-v1", 品牌实现)
        self.assertIn("coachmate-official-logo-v1", 品牌实现)


if __name__ == "__main__":
    unittest.main()
