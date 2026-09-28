"""MATE C-08 素材包契约测试。"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import unittest
from pathlib import Path

from PIL import Image


项目根目录 = Path(__file__).resolve().parents[2]
素材根目录 = 项目根目录 / "assets/branding/mate-feast-bag-v2"
清单路径 = 素材根目录 / "manifest.json"
总览生成器 = 项目根目录 / "scripts/generate_mate_feast_review_overview.py"
动作名称 = (
    "01-pointing-guide",
    "02-running",
    "03-side-lunge-stretch",
    "04-seated-meditation",
    "05-jumping-jack",
    "06-high-knees",
    "07-sprint",
    "08-jump-rope",
    "09-burpee",
    "10-squat",
    "11-forward-lunge",
    "12-push-up",
    "13-plank",
    "14-mountain-climber",
    "15-sit-up-crunch",
    "16-dumbbell-curl",
    "17-dumbbell-overhead-press",
    "18-standing-side-stretch",
    "19-seated-forward-fold",
    "20-tree-pose-balance",
)
成长阶段 = ("pattern_egg", "sprout", "junior", "advanced", "champion")
伙伴心情 = ("excited", "happy", "curious", "calm", "waiting")
色板 = (
    "#C1512E",
    "#D6B489",
    "#F5EBD8",
    "#E8467F",
    "#1A1512",
    "#2438CE",
)


def 计算哈希(路径: Path) -> str:
    return hashlib.sha256(路径.read_bytes()).hexdigest()


class MateFeast素材契约测试(unittest.TestCase):
    def setUp(self) -> None:
        self.assertTrue(清单路径.is_file(), "缺少 MATE C-08 素材清单")
        self.清单 = json.loads(清单路径.read_text(encoding="utf-8"))

    def test_母版和角色契约固定(self) -> None:
        self.assertEqual("mate-feast-bag-v2", self.清单["version"])
        self.assertEqual("pending-human-visual-review", self.清单["status"])
        self.assertEqual(list(色板), self.清单["palette"])
        参考 = self.清单["reference"]
        self.assertEqual((1536, 1024), (参考["width"], 参考["height"]))
        self.assertEqual(
            "a5c036d681f7b564411e711511f8007047db2c8e3e194f9d10aac788534a153d",
            参考["sha256"],
        )
        self.assertTrue((项目根目录 / 参考["path"]).is_file())
        self.assertEqual(参考["sha256"], 计算哈希(项目根目录 / 参考["path"]))

    def test_二十张动作母图和四十张运行时动作完整(self) -> None:
        动作 = self.清单["actions"]
        self.assertEqual(set(动作名称), set(动作))
        输出路径 = set()
        for 名称, 项目 in 动作.items():
            母图路径 = 项目根目录 / 项目["masterPath"]
            self.assertTrue(母图路径.is_file(), 名称)
            with Image.open(母图路径) as 母图:
                self.assertEqual((1024, 1024), 母图.size, 名称)
                self.assertEqual("RGBA", 母图.mode, 名称)
                self.assertLess(min(母图.getchannel("A").getextrema()), 255, 名称)
            for 变体 in ("navy", "peach-light"):
                路径 = 项目根目录 / 项目["variants"][变体]["path"]
                输出路径.add(路径)
                self.assertTrue(路径.is_file(), f"{名称}-{变体}")
                with Image.open(路径) as 图片:
                    self.assertEqual((512, 512), 图片.size)
                    self.assertEqual("RGBA", 图片.mode)
                    self.assertLess(min(图片.getchannel("A").getextrema()), 255)
                self.assertEqual(计算哈希(路径), 项目["variants"][变体]["sha256"])
        self.assertEqual(40, len(输出路径))

    def test_二十五种伙伴状态完整且路径唯一(self) -> None:
        状态 = self.清单["companionStates"]
        self.assertEqual(25, len(状态))
        self.assertEqual(
            {f"{阶段}-{心情}" for 阶段 in 成长阶段 for 心情 in 伙伴心情},
            set(状态),
        )
        路径集合 = {项目["path"] for 项目 in 状态.values()}
        self.assertEqual(25, len(路径集合))
        for 标识, 项目 in 状态.items():
            路径 = 项目根目录 / 项目["path"]
            self.assertTrue(路径.is_file(), 标识)
            with Image.open(路径) as 图片:
                self.assertEqual((512, 512), 图片.size)
                self.assertEqual("RGBA", 图片.mode)
                self.assertLess(min(图片.getchannel("A").getextrema()), 255)
            self.assertEqual(计算哈希(路径), 项目["sha256"])

    def test_品牌资产及审核总览完整(self) -> None:
        self.assertEqual(
            {"character", "brandmark", "compactMark"},
            set(self.清单["brandAssets"]),
        )
        for 项目 in self.清单["brandAssets"].values():
            路径 = 项目根目录 / 项目["path"]
            self.assertTrue(路径.is_file())
            with Image.open(路径) as 图片:
                self.assertEqual("RGBA", 图片.mode)
                self.assertLess(min(图片.getchannel("A").getextrema()), 255)
            self.assertEqual(计算哈希(路径), 项目["sha256"])
        总览 = 项目根目录 / self.清单["reviewOverview"]["path"]
        self.assertTrue(总览.is_file())
        with Image.open(总览) as 图片:
            self.assertEqual(图片.size, (1600, 2200))
            self.assertEqual(图片.mode, "RGB")
        self.assertEqual(
            self.清单["reviewOverview"]["sha256"],
            计算哈希(总览),
        )

    def test_审核总览生成器_check模式完全只读(self) -> None:
        总览 = 项目根目录 / self.清单["reviewOverview"]["path"]
        执行前 = 计算哈希(总览)
        结果 = subprocess.run(
            [sys.executable, str(总览生成器), "--check"],
            cwd=项目根目录,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(结果.returncode, 0, 结果.stderr or 结果.stdout)
        self.assertEqual(执行前, 计算哈希(总览))


if __name__ == "__main__":
    unittest.main()
