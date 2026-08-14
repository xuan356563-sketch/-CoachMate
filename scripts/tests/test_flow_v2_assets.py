from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path

from PIL import Image


项目根目录 = Path(__file__).resolve().parents[2]
素材根目录 = 项目根目录 / "assets/branding/flow-v2-color-detail"
清单路径 = 素材根目录 / "manifest.json"
动作名称 = (
    "01-pointing-guide", "02-running", "03-side-lunge-stretch", "04-seated-meditation",
    "05-jumping-jack", "06-high-knees", "07-sprint", "08-jump-rope", "09-burpee",
    "10-squat", "11-forward-lunge", "12-push-up", "13-plank", "14-mountain-climber",
    "15-sit-up-crunch", "16-dumbbell-curl", "17-dumbbell-overhead-press",
    "18-standing-side-stretch", "19-seated-forward-fold", "20-tree-pose-balance",
)
色板 = {
    "bodyBase": "#19172C",
    "bodyHighlight": "#4B4EC8",
    "bodyShadow": "#0E0D1B",
    "paper": "#FFFDFC",
    "coral": "#FF6B4A",
    "apricot": "#FFB25B",
    "sunny": "#FFD447",
    "mint": "#42D9C1",
    "sky": "#55B8FF",
    "energyPurple": "#8B72FF",
    "blush": "#FF8FA3",
}
固定字段 = {
    "id", "sourcePath", "outputPath", "variant", "width", "height", "sha256",
    "sourceSha256", "alphaIou", "reviewStatus",
}
品牌资产契约 = {
    "flow-character": {
        "sourcePath": "assets/branding/exports/png/trainmate-flow-character-1024.png",
        "outputPath": "assets/branding/flow-v2-color-detail/exports/png/trainmate-flow-character-1024.png",
        "variant": "brand",
        "width": 1024,
        "height": 1024,
    },
    "flow-brandmark": {
        "sourcePath": "assets/branding/exports/png/trainmate-flow-brandmark-1024.png",
        "outputPath": "assets/branding/flow-v2-color-detail/exports/png/trainmate-flow-brandmark-1024.png",
        "variant": "brand",
        "width": 1024,
        "height": 1024,
    },
    "flow-lockup": {
        "sourcePath": "assets/branding/exports/png/trainmate-flow-lockup-1600.png",
        "outputPath": "assets/branding/flow-v2-color-detail/exports/png/trainmate-flow-lockup-1600.png",
        "variant": "brand",
        "width": 1600,
        "height": 626,
    },
}
V2运行时目录 = (
    "assets/branding/flow-v2-color-detail/exports/png/",
    "assets/branding/flow-v2-color-detail/action-characters/navy/",
    "assets/branding/flow-v2-color-detail/action-characters/peach-light/",
)
总览路径 = 素材根目录 / "review/flow-v2-action-set-overview.png"


def 计算_sha256(路径: Path) -> str:
    摘要 = hashlib.sha256()
    with 路径.open("rb") as 文件:
        for 数据块 in iter(lambda: 文件.read(65536), b""):
            摘要.update(数据块)
    return 摘要.hexdigest()


def 计算_alpha_iou(来源: Image.Image, 输出: Image.Image) -> float:
    来源集合 = {索引 for 索引, 值 in enumerate(来源.getchannel("A").tobytes()) if 值}
    输出集合 = {索引 for 索引, 值 in enumerate(输出.getchannel("A").tobytes()) if 值}
    并集 = 来源集合 | 输出集合
    return 1.0 if not 并集 else len(来源集合 & 输出集合) / len(并集)


def 读取_flutter资产声明(pubspec文本: str) -> list[str]:
    """读取本项目 flutter.assets 的一级 YAML 列表，避免引入 YAML 依赖。"""
    行组 = pubspec文本.splitlines()
    try:
        flutter起始行 = 行组.index("flutter:") + 1
    except ValueError as 错误:
        raise AssertionError("pubspec.yaml 缺少 flutter 声明") from 错误

    资产起始行 = None
    for 行号 in range(flutter起始行, len(行组)):
        行 = 行组[行号]
        if 行 and not 行.startswith("  "):
            break
        if 行 == "  assets:":
            资产起始行 = 行号 + 1
            break
    if 资产起始行 is None:
        raise AssertionError("pubspec.yaml 缺少 flutter.assets 声明")

    资产 = []
    for 行 in 行组[资产起始行:]:
        if 行 and not 行.startswith("    "):
            break
        if 行.startswith("    - "):
            资产.append(行.removeprefix("    - ").strip())
    return 资产


class FlowV2素材契约测试(unittest.TestCase):
    def setUp(self) -> None:
        with 清单路径.open(encoding="utf-8") as 文件:
            self.清单 = json.load(文件)

    def test_顶层契约和目录声明固定(self) -> None:
        self.assertEqual("flow-v2-color-detail", self.清单["version"])
        self.assertEqual("pending-human-visual-review", self.清单["status"])
        self.assertEqual(
            "internal-old-flow-only-pending-human-review", self.清单["rightsStatus"]
        )
        self.assertEqual(色板, self.清单["palette"])
        self.assertTrue(isinstance(self.清单["assets"], list))

        for 相对目录 in (
            "exports/png",
            "action-characters/navy",
            "action-characters/peach-light",
            "source",
            "review",
        ):
            self.assertTrue((素材根目录 / 相对目录).is_dir(), 相对目录)

    def test_预登记品牌和四十个动作输出(self) -> None:
        资产 = self.清单["assets"]
        self.assertEqual(43, len(资产))
        self.assertEqual(43, len({项目["id"] for 项目 in 资产}))

        品牌资产 = {项目["id"]: 项目 for 项目 in 资产 if 项目["variant"] == "brand"}
        self.assertEqual(
            {"flow-character", "flow-brandmark", "flow-lockup"}, set(品牌资产)
        )
        self.assertEqual(
            品牌资产契约,
            {
                标识: {字段: 项目[字段] for 字段 in 期望}
                for 标识, 期望 in 品牌资产契约.items()
                for 项目 in (品牌资产[标识],)
            },
        )

        动作资产 = [项目 for 项目 in 资产 if 项目["variant"] in {"navy", "peach-light"}]
        self.assertEqual(40, len(动作资产))
        self.assertEqual(
            {(动作, 变体) for 动作 in 动作名称 for 变体 in ("navy", "peach-light")},
            {(项目["id"].removeprefix("action-").removesuffix(f"-{项目['variant']}"), 项目["variant"]) for 项目 in 动作资产},
        )
        for 项目 in 动作资产:
            self.assertEqual((512, 512), (项目["width"], 项目["height"]))
            self.assertEqual(
                f"assets/branding/action-characters/{项目['variant']}/"
                f"{项目['id'].removeprefix('action-').removesuffix(f'-{项目['variant']}')}.png",
                项目["sourcePath"],
            )
            self.assertEqual(
                f"assets/branding/flow-v2-color-detail/action-characters/{项目['variant']}/"
                f"{项目['id'].removeprefix('action-').removesuffix(f'-{项目['variant']}')}.png",
                项目["outputPath"],
            )

    def test_每项实时校验来源与正式输出(self) -> None:
        for 项目 in self.清单["assets"]:
            self.assertEqual(固定字段, set(项目))
            来源路径 = 项目根目录 / 项目["sourcePath"]
            输出路径 = 项目根目录 / 项目["outputPath"]
            self.assertTrue(来源路径.is_file(), 项目["sourcePath"])
            self.assertTrue(输出路径.is_file(), 项目["outputPath"])
            self.assertEqual(计算_sha256(来源路径), 项目["sourceSha256"])
            self.assertEqual(计算_sha256(输出路径), 项目["sha256"])
            self.assertEqual(1.0, 项目["alphaIou"])
            self.assertEqual("generated-pending-human-review", 项目["reviewStatus"])

            with Image.open(来源路径) as 来源图, Image.open(输出路径) as 输出图:
                来源图.load()
                输出图.load()
                self.assertEqual("RGBA", 输出图.mode)
                self.assertEqual((项目["width"], 项目["height"]), 输出图.size)
                self.assertEqual(来源图.size, 输出图.size)
                self.assertEqual(
                    来源图.getchannel("A").tobytes(),
                    输出图.getchannel("A").tobytes(),
                    项目["id"],
                )
                self.assertEqual(1.0, 计算_alpha_iou(来源图, 输出图))
                self.assertEqual(来源图.getbbox(), 输出图.getbbox())
                self.assertNotEqual(
                    来源图.convert("RGB").tobytes(),
                    输出图.convert("RGB").tobytes(),
                    项目["id"],
                )

    def test_四十个动作文件名严格对应且双版不同(self) -> None:
        for 变体 in ("navy", "peach-light"):
            目录 = 素材根目录 / "action-characters" / 变体
            self.assertEqual(
                [f"{动作}.png" for 动作 in 动作名称],
                sorted(路径.name for 路径 in 目录.glob("*.png")),
            )
        for 动作 in 动作名称:
            深蓝 = 素材根目录 / "action-characters/navy" / f"{动作}.png"
            浅色 = 素材根目录 / "action-characters/peach-light" / f"{动作}.png"
            self.assertNotEqual(计算_sha256(深蓝), 计算_sha256(浅色), 动作)

    def test_组合标文字区域保持原像素(self) -> None:
        项目 = next(项目 for 项目 in self.清单["assets"] if 项目["id"] == "flow-lockup")
        with Image.open(项目根目录 / 项目["sourcePath"]) as 来源, Image.open(
            项目根目录 / 项目["outputPath"]
        ) as 输出:
            self.assertEqual(来源.crop((630, 0, 1600, 626)).tobytes(), 输出.crop((630, 0, 1600, 626)).tobytes())

    def test_动作总览已生成(self) -> None:
        self.assertTrue(总览路径.is_file())
        with Image.open(总览路径) as 总览:
            总览.load()
            self.assertEqual("RGBA", 总览.mode)
            self.assertGreaterEqual(总览.width, 1280)
            self.assertGreaterEqual(总览.height, 2048)

    def test_pubspec_仅声明_v2运行时目录(self) -> None:
        pubspec文本 = (项目根目录 / "pubspec.yaml").read_text(encoding="utf-8")
        V2声明 = [
            路径
            for 路径 in 读取_flutter资产声明(pubspec文本)
            if 路径.startswith("assets/branding/flow-v2-color-detail/")
        ]
        self.assertEqual(list(V2运行时目录), V2声明)
        self.assertEqual(len(V2运行时目录), len(set(V2声明)))


if __name__ == "__main__":
    unittest.main()
