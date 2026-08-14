from __future__ import annotations

import contextlib
import copy
import importlib.util
import io
import json
import math
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image


脚本目录 = Path(__file__).resolve().parents[1]
验证器路径 = 脚本目录 / "verify_brand_assets.py"
清单路径 = 脚本目录 / "brand_assets_manifest.json"

模块规格 = importlib.util.spec_from_file_location("verify_brand_assets", 验证器路径)
if 模块规格 is None or 模块规格.loader is None:
    raise RuntimeError("无法加载品牌资产验证器")
品牌资产 = importlib.util.module_from_spec(模块规格)
模块规格.loader.exec_module(品牌资产)


标准头像节点 = (
    "flow-head",
    "training-headband",
    "headband-knot",
    "ribbon-long",
    "ribbon-short",
    "ai-visor",
    "face-eye-dot",
    "face-eye-arc",
    "face-mouth",
)
小尺寸头像节点 = tuple(节点 for 节点 in 标准头像节点 if 节点 != "face-mouth")
应用图标节点 = (
    "flow-head",
    "training-headband",
    "headband-knot",
    "ribbon-long",
    "ribbon-short",
    "face-capsule",
    "face-eye-dot",
    "face-eye-arc",
    "face-mouth",
)
应用图标渐变节点 = (
    "icon-background-gradient",
    "flow-body-gradient",
    "headband-gradient",
)
正式源文件类型 = {
    "trainmate-flow-brandmark.svg": "brandmark",
    "trainmate-flow-brandmark-small.svg": "brandmark-small",
    "trainmate-flow-brandmark-reverse.svg": "brandmark",
    "trainmate-flow-brandmark-mono.svg": "brandmark",
    "trainmate-flow-character.svg": "character",
    "trainmate-flow-wordmark.svg": "formal",
    "trainmate-flow-wordmark-horizontal.svg": "formal",
    "trainmate-flow-lockup.svg": "lockup",
    "trainmate-flow-character-lockup.svg": "character",
    "trainmate-flow-submark.svg": "formal",
    "trainmate-flow-app-icon.svg": "app-icon",
    "trainmate-flow-app-icon-maskable.svg": "app-icon-maskable",
}


class 品牌资产测试基类(unittest.TestCase):
    def setUp(self) -> None:
        self._临时目录 = tempfile.TemporaryDirectory()
        self.根目录 = Path(self._临时目录.name)

    def tearDown(self) -> None:
        self._临时目录.cleanup()

    def 写入_svg(
        self,
        文件名: str,
        *,
        节点: tuple[str, ...] = (),
        附加内容: str = "",
        view_box: str | None = "0 0 1024 1024",
        根属性: str = "",
    ) -> Path:
        view_box_属性 = f' viewBox="{view_box}"' if view_box is not None else ""
        根属性文本 = f" {根属性}" if 根属性 else ""
        节点内容 = "".join(
            f'<g id="{节点名}" fill="#19172C" />' for 节点名 in 节点
        )
        路径 = self.根目录 / 文件名
        路径.write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg"{view_box_属性}{根属性文本}>'
            f"{节点内容}{附加内容}</svg>",
            encoding="utf-8",
        )
        return 路径

    def 写入_png(self, 文件名: str, 尺寸: tuple[int, int], 模式: str) -> Path:
        路径 = self.根目录 / 文件名
        颜色 = (25, 23, 44, 255) if 模式 == "RGBA" else (25, 23, 44)
        Image.new(模式, 尺寸, 颜色).save(路径)
        return 路径

    def 读取_深蓝主体占比(self, 路径: Path) -> tuple[float, float]:
        左, 上, 右, 下, 宽度, 高度 = self.读取_深蓝主体边界(路径)
        return ((右 - 左) / 宽度, (下 - 上) / 高度)

    def 读取_深蓝主体边界(self, 路径: Path) -> tuple[int, int, int, int, int, int]:
        with Image.open(路径) as 图像:
            rgb图像 = 图像.convert("RGB")
            主体遮罩 = Image.new("L", rgb图像.size)
            像素数据 = (
                rgb图像.get_flattened_data()
                if hasattr(rgb图像, "get_flattened_data")
                else rgb图像.getdata()
            )
            主体遮罩.putdata([
                255 if 红 <= 45 and 绿 <= 45 and 蓝 <= 65 else 0
                for 红, 绿, 蓝 in 像素数据
            ])
            边界 = 主体遮罩.getbbox()
            self.assertIsNotNone(边界, f"未识别到深蓝主体：{路径}")
            assert 边界 is not None
            左, 上, 右, 下 = 边界
            return 左, 上, 右, 下, rgb图像.width, rgb图像.height

    def 读取_参考橙配饰边界(self, 路径: Path) -> tuple[int, int, int, int]:
        with Image.open(路径) as 图像:
            rgb图像 = 图像.convert("RGB")
            配饰遮罩 = Image.new("L", rgb图像.size)
            像素数据 = (
                rgb图像.get_flattened_data()
                if hasattr(rgb图像, "get_flattened_data")
                else rgb图像.getdata()
            )
            配饰遮罩.putdata([
                255
                if 红 >= 150 and 55 <= 绿 <= 190 and 蓝 <= 100 and 红 - 绿 >= 40
                else 0
                for 红, 绿, 蓝 in 像素数据
            ])
            边界 = 配饰遮罩.getbbox()
            self.assertIsNotNone(边界, f"未识别到参考橙配饰：{路径}")
            assert 边界 is not None
            return 边界

    def 读取_alpha_最大半径占比(self, 路径: Path) -> float:
        with Image.open(路径) as 图像:
            rgba图像 = 图像.convert("RGBA")
            中心X = rgba图像.width / 2
            中心Y = rgba图像.height / 2
            alpha数据 = (
                rgba图像.getchannel("A").get_flattened_data()
                if hasattr(rgba图像.getchannel("A"), "get_flattened_data")
                else rgba图像.getchannel("A").getdata()
            )
            最大半径 = max(
                math.hypot(
                    索引 % rgba图像.width + .5 - 中心X,
                    索引 // rgba图像.width + .5 - 中心Y,
                )
                for 索引, alpha in enumerate(alpha数据)
                if alpha > 8
            )
            return 最大半径 / rgba图像.width

    def 读取_非背景最大半径占比(self, 路径: Path) -> float:
        with Image.open(路径) as 图像:
            rgb图像 = 图像.convert("RGB")
            中心X = rgb图像.width / 2
            中心Y = rgb图像.height / 2
            像素数据 = (
                rgb图像.get_flattened_data()
                if hasattr(rgb图像, "get_flattened_data")
                else rgb图像.getdata()
            )
            内容索引 = [
                索引
                for 索引, (红, 绿, 蓝) in enumerate(像素数据)
                if max(abs(红 - 254), abs(绿 - 254), abs(蓝 - 254)) > 16
            ]
            self.assertTrue(内容索引, f"未识别到定版 Logo 主体：{路径}")
            最大半径 = max(
                math.hypot(
                    索引 % rgb图像.width + .5 - 中心X,
                    索引 // rgb图像.width + .5 - 中心Y,
                )
                for 索引 in 内容索引
            )
            return 最大半径 / rgb图像.width

    def 写入_参考风格App图标(
        self,
        文件名: str,
        *,
        头带亮色: str = "#EAA93A",
        头带深色: str = "#C65F14",
        嘴部描边: str = "#FFB27D",
        附加内容: str = "",
    ) -> Path:
        return self.写入_svg(
            文件名,
            节点=tuple(节点 for 节点 in 应用图标节点 if 节点 != "face-mouth"),
            附加内容=f"""
                <defs>
                  <linearGradient id="icon-background-gradient">
                    <stop offset="0" stop-color="#FFFDFC" />
                    <stop offset="1" stop-color="#FFE2B8" />
                  </linearGradient>
                  <linearGradient id="flow-body-gradient">
                    <stop offset="0" stop-color="#19172C" />
                    <stop offset="1" stop-color="#11101F" />
                  </linearGradient>
                  <linearGradient id="headband-gradient">
                    <stop offset="0" stop-color="{头带亮色}" />
                    <stop offset="1" stop-color="{头带深色}" />
                  </linearGradient>
                </defs>
                <rect id="icon-background" width="1024" height="1024"
                      fill="url(#icon-background-gradient)" />
                <path id="face-mouth" d="M0 0h10"
                      fill="none" stroke="{嘴部描边}" />
                {附加内容}
            """,
        )


class 正式SVG契约测试(品牌资产测试基类):
    def test_正式_svg_拒绝危险节点外部链接和营销纹理(self) -> None:
        路径 = self.写入_svg(
            "formal.svg",
            附加内容="""
                <image href="data:image/png;base64,AA==" />
                <text>智练</text>
                <filter id="shadow" />
                <linearGradient id="linear" />
                <radialGradient id="radial" />
                <script>window.alert(1)</script>
                <use href="https://example.com/external.svg#shape" />
                <use href="trainmate-flow-marketing-texture.svg#texture" />
            """,
        )

        问题 = 品牌资产.validate_svg(路径)

        self.assertIn("正式 SVG 不得包含嵌入位图", 问题)
        self.assertIn("正式 SVG 不得保留可变文字", 问题)
        self.assertIn("正式 SVG 不得包含滤镜", 问题)
        self.assertIn("正式 SVG 不得包含线性渐变", 问题)
        self.assertIn("正式 SVG 不得包含径向渐变", 问题)
        self.assertIn("正式 SVG 不得包含脚本", 问题)
        self.assertIn("正式 SVG 不得包含外部链接", 问题)
        self.assertIn("正式 SVG 不得引用营销纹理", 问题)

    def test_正式_svg_必须有合法_viewbox(self) -> None:
        路径 = self.写入_svg("missing-viewbox.svg", view_box=None)

        self.assertIn("正式 SVG 缺少合法 viewBox", 品牌资产.validate_svg(路径))

    def test_正式_svg_颜色只能来自白名单(self) -> None:
        路径 = self.写入_svg(
            "wrong-color.svg",
            附加内容='<path fill="#000000" d="M0 0h10v10z" />',
        )

        self.assertIn(
            "正式 SVG 使用了非白名单颜色：#000000",
            品牌资产.validate_svg(路径),
        )

    def test_正式_svg_拒绝App图标专用参考橙(self) -> None:
        路径 = self.写入_svg(
            "formal-cherry-red.svg",
            附加内容='<path fill="#EAA93A" d="M0 0h10v10z" />',
        )

        self.assertIn(
            "正式 SVG 使用了非白名单颜色：#EAA93A",
            品牌资产.validate_svg(路径),
        )

    def test_正式_svg_禁止_style_节点(self) -> None:
        路径 = self.写入_svg(
            "style.svg",
            附加内容='<style>@import url("https://example.com/a.css"); .a{fill:#000}</style>',
        )

        self.assertIn("正式 SVG 不得包含 style 节点", 品牌资产.validate_svg(路径))

    def test_正式_svg_禁止事件属性(self) -> None:
        路径 = self.写入_svg(
            "event.svg",
            附加内容='<path onclick="alert(1)" fill="#19172C" d="M0 0h10v10z" />',
        )

        self.assertIn(
            "正式 SVG 不得包含事件属性：onclick",
            品牌资产.validate_svg(路径),
        )

    def test_正式_svg_禁止_mask_节点和属性(self) -> None:
        for 应用方式 in (
            'mask="url(#transparent-mask)"',
            'style="mask: url(#transparent-mask)"',
        ):
            with self.subTest(应用方式=应用方式):
                路径 = self.写入_svg(
                    "mask.svg",
                    节点=小尺寸头像节点,
                    附加内容=(
                        '<mask id="transparent-mask">'
                        '<rect width="1024" height="1024" fill="#FFE2B8" '
                        'fill-opacity="0" />'
                        "</mask>"
                        '<rect width="1024" height="1024" fill="#FFE2B8" '
                        f"{应用方式} />"
                    ),
                )

                问题 = 品牌资产.validate_svg(路径, asset_kind="app-icon")
                self.assertIn("正式 SVG 不得包含 mask 节点", 问题)
                self.assertIn("正式 SVG 不得包含 mask 属性", 问题)

    def test_正式_svg_禁止_clipPath_节点和属性(self) -> None:
        for 应用方式 in (
            'clip-path="url(#empty-clip)"',
            'style="clip-path: url(#empty-clip)"',
        ):
            with self.subTest(应用方式=应用方式):
                路径 = self.写入_svg(
                    "clip-path.svg",
                    节点=小尺寸头像节点,
                    附加内容=(
                        '<clipPath id="empty-clip" />'
                        '<rect width="1024" height="1024" fill="#FFE2B8" '
                        f"{应用方式} />"
                    ),
                )

                问题 = 品牌资产.validate_svg(
                    路径,
                    asset_kind="app-icon-maskable",
                )
                self.assertIn("正式 SVG 不得包含 clipPath 节点", 问题)
                self.assertIn("正式 SVG 不得包含 clip-path 属性", 问题)

    def test_正式_svg_禁止_xml_stylesheet_处理指令(self) -> None:
        路径 = self.根目录 / "xml-stylesheet.svg"
        路径.write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<?xml-stylesheet href="https://example.com/brand.css"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" />',
            encoding="utf-8",
        )

        self.assertIn("正式 SVG 不得包含处理指令", 品牌资产.validate_svg(路径))

    def test_正式_svg_禁止相对路径处理指令(self) -> None:
        路径 = self.根目录 / "relative-processing-instruction.svg"
        路径.write_text(
            '<?brand-source href="./local-brand.css"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" />',
            encoding="utf-8",
        )

        self.assertIn("正式 SVG 不得包含处理指令", 品牌资产.validate_svg(路径))

    def test_正式_svg_拒绝UTF16远程处理指令(self) -> None:
        路径 = self.根目录 / "utf16-remote-processing-instruction.svg"
        路径.write_text(
            '<?xml version="1.0" encoding="UTF-16"?>\n'
            '<?xml-stylesheet href="https://example.com/brand.css"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" />',
            encoding="utf-16",
        )

        self.assertIn("正式 SVG 必须使用 UTF-8 编码", 品牌资产.validate_svg(路径))

    def test_正式_svg_拒绝UTF16相对路径处理指令(self) -> None:
        路径 = self.根目录 / "utf16-relative-processing-instruction.svg"
        路径.write_text(
            '<?xml version="1.0" encoding="UTF-16"?>\n'
            '<?brand-source href="./local-brand.css"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" />',
            encoding="utf-16",
        )

        self.assertIn("正式 SVG 必须使用 UTF-8 编码", 品牌资产.validate_svg(路径))

    def test_正式_svg_拒绝声明为其他编码(self) -> None:
        路径 = self.根目录 / "latin1-declaration.svg"
        路径.write_bytes(
            (
                '<?xml version="1.0" encoding="ISO-8859-1"?>\n'
                '<svg xmlns="http://www.w3.org/2000/svg" '
                'viewBox="0 0 1024 1024" />'
            ).encode("ascii")
        )

        self.assertIn("正式 SVG 必须使用 UTF-8 编码", 品牌资产.validate_svg(路径))

    def test_正式_svg_接受UTF8_BOM(self) -> None:
        路径 = self.根目录 / "utf8-bom.svg"
        路径.write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" />',
            encoding="utf-8-sig",
        )

        self.assertEqual([], 品牌资产.validate_svg(路径))

    def test_标准头像缺软结或任一飘带节点会失败(self) -> None:
        for 缺失节点 in ("headband-knot", "ribbon-long", "ribbon-short"):
            with self.subTest(缺失节点=缺失节点):
                路径 = self.写入_svg(
                    f"brandmark-{缺失节点}.svg",
                    节点=tuple(节点 for 节点 in 标准头像节点 if 节点 != 缺失节点),
                )

                self.assertIn(
                    f"标准头像缺少固定节点：{缺失节点}",
                    品牌资产.validate_svg(路径, asset_kind="brandmark"),
                )

    def test_小尺寸头像禁止_face_mouth_且必须保留软结和飘带(self) -> None:
        含微笑路径 = self.写入_svg("small-with-mouth.svg", 节点=标准头像节点)
        self.assertIn(
            "小尺寸头像不得包含 face-mouth 节点",
            品牌资产.validate_svg(含微笑路径, asset_kind="brandmark-small"),
        )

        小尺寸节点 = tuple(节点 for 节点 in 标准头像节点 if 节点 != "face-mouth")
        for 缺失节点 in ("headband-knot", "ribbon-long", "ribbon-short"):
            with self.subTest(缺失节点=缺失节点):
                路径 = self.写入_svg(
                    f"small-{缺失节点}.svg",
                    节点=tuple(节点 for 节点 in 小尺寸节点 if 节点 != 缺失节点),
                )

                self.assertIn(
                    f"小尺寸头像缺少固定节点：{缺失节点}",
                    品牌资产.validate_svg(路径, asset_kind="brandmark-small"),
                )

    def test_完整角色缺任一细线四肢节点会失败(self) -> None:
        完整角色节点 = 标准头像节点 + (
            "arm-left",
            "arm-right",
            "leg-left",
            "leg-right",
        )
        for 缺失节点 in ("arm-left", "arm-right", "leg-left", "leg-right"):
            with self.subTest(缺失节点=缺失节点):
                路径 = self.写入_svg(
                    f"character-{缺失节点}.svg",
                    节点=tuple(节点 for 节点 in 完整角色节点 if 节点 != 缺失节点),
                )

                self.assertIn(
                    f"完整角色缺少固定节点：{缺失节点}",
                    品牌资产.validate_svg(路径, asset_kind="character"),
                )

    def test_主品牌组合标缺软结或任一飘带节点会失败(self) -> None:
        for 缺失节点 in ("headband-knot", "ribbon-long", "ribbon-short"):
            with self.subTest(缺失节点=缺失节点):
                路径 = self.写入_svg(
                    f"lockup-{缺失节点}.svg",
                    节点=tuple(节点 for 节点 in 标准头像节点 if 节点 != 缺失节点),
                )

                self.assertIn(
                    f"主品牌组合标缺少固定节点：{缺失节点}",
                    品牌资产.validate_svg(路径, asset_kind="lockup"),
                )

    def test_动态角度与参考图排版契约相互独立(self) -> None:
        路径 = self.写入_svg(
            "trainmate-flow-wordmark.svg",
            附加内容=(
                '<g id="glyph-zhi-position" '
                'transform="translate(273.32 102.65) scale(.4225 .406) '
                'matrix(1 0 -0.08749 1 44.18 0)" />'
                '<g id="glyph-lian-position" '
                'transform="translate(430.34 100.22) scale(.4154 .413) '
                'matrix(1 0 -0.08749 1 44.18 0)" />'
                '<g id="wordmark-en-position" '
                'transform="translate(140 -14) scale(.797)" />'
                '<g id="wordmark-en" '
                'transform="matrix(1 0 -0.12278 1 77.83 0) translate(-54 2)" />'
            ),
        )
        self.assertEqual([], 品牌资产.validate_motion_contract(路径))

        路径.write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1204 720">'
            '<g id="glyph-zhi-position" transform="scale(.9)" />'
            '<g id="glyph-lian-position" />'
            '<g id="wordmark-en-position" transform="translate(0 0)" />'
            '<g id="wordmark-en" transform="rotate(5 550 350)" />'
            '</svg>',
            encoding="utf-8",
        )
        问题 = 品牌资产.validate_motion_contract(路径)
        self.assertIn(
            "动态角度错误：glyph-zhi-position 应为 "
            "translate(273.32 102.65) scale(.4225 .406) "
            "matrix(1 0 -0.08749 1 44.18 0)",
            问题,
        )
        self.assertIn(
            "动态角度错误：glyph-lian-position 应为 "
            "translate(430.34 100.22) scale(.4154 .413) "
            "matrix(1 0 -0.08749 1 44.18 0)",
            问题,
        )
        self.assertIn(
            "动态角度错误：wordmark-en-position 应为 "
            "translate(140 -14) scale(.797)",
            问题,
        )
        self.assertIn(
            "动态角度错误：wordmark-en 应为 "
            "matrix(1 0 -0.12278 1 77.83 0) translate(-54 2)",
            问题,
        )

    def test_App图标使用参考图形主体并保留奋斗头带和双飘带(self) -> None:
        批准飘带路径 = {
            "ribbon-long": (
                "M206 386C174 374 147 364 121 368C95 372 78 365 61 352"
                "C52 345 41 348 38 358C35 368 42 378 52 383"
                "C72 395 95 399 121 393C149 387 172 398 199 417Z"
            ),
            "ribbon-short": (
                "M207 417C181 410 159 411 140 421C122 431 108 433 94 427"
                "C84 423 75 429 74 439C73 449 81 457 92 459"
                "C110 462 128 457 147 447C166 437 184 440 207 450Z"
            ),
        }
        批准变换 = {
            "trainmate-flow-app-icon.svg": {
                "app-icon-layout": "translate(-13 -72) scale(1.10)",
                "flow-avatar": "rotate(2 512 540)",
            },
            "trainmate-flow-app-icon-maskable.svg": {
                "app-icon-layout": "translate(192 156) scale(.67)",
                "flow-avatar": "rotate(2 512 540)",
            },
        }
        结构节点 = {
            "flow-head",
            "headband-ribbons",
            "training-headband-layer",
            "headband-knot-layer",
            "flow-face",
            "face-mouth",
        }
        禁止肢体节点 = {
            "arm-left",
            "arm-right",
            "leg-left",
            "leg-right",
            "hand-left",
            "hand-right",
            "foot-left",
            "foot-right",
        }
        旧版雕塑节点 = {
            "flow-body-core",
            "flow-face-core",
            "training-headband-emphasis",
            "headband-knot-emphasis",
        }

        for 文件名, 文件批准变换 in 批准变换.items():
            with self.subTest(文件名=文件名):
                self.assertEqual(
                    文件批准变换,
                    品牌资产.EXPECTED_MOTION_TRANSFORMS[文件名],
                )

                正式源稿 = (
                    品牌资产.REPOSITORY_ROOT
                    / "assets"
                    / "branding"
                    / "source"
                    / 文件名
                )
                节点索引 = {
                    节点.attrib.get("id"): 节点
                    for 节点 in ET.parse(正式源稿).getroot().iter()
                    if 节点.attrib.get("id")
                }
                头像直属节点 = {
                    节点.attrib.get("id")
                    for 节点 in list(节点索引["flow-avatar"])
                    if 节点.attrib.get("id")
                }
                self.assertTrue(
                    结构节点.issubset(头像直属节点),
                    "主体、头带、软结、胶囊脸和双飘带必须组成角色头像",
                )
                self.assertTrue(旧版雕塑节点.isdisjoint(节点索引))
                self.assertTrue(禁止肢体节点.isdisjoint(节点索引))

                实际变换 = {
                    节点: " ".join(节点索引[节点].attrib["transform"].split())
                    for 节点 in 文件批准变换
                }
                self.assertEqual(文件批准变换, 实际变换)
                self.assertEqual([], 品牌资产.validate_motion_contract(正式源稿))

                for 飘带节点 in ("ribbon-long", "ribbon-short"):
                    飘带 = 节点索引[飘带节点]
                    self.assertEqual("path", 飘带.tag.rsplit("}", 1)[-1])
                    self.assertEqual("url(#headband-gradient)", 飘带.attrib["fill"])
                    self.assertEqual(
                        批准飘带路径[飘带节点],
                        飘带.attrib["d"],
                        "双飘带必须保持动作角色家族的一长一短轻薄波浪结构",
                    )
                    self.assertNotIn("stroke", 飘带.attrib)
                    self.assertNotIn("transform", 飘带.attrib)

                self.assertEqual(
                    "path",
                    节点索引["headband-knot"].tag.rsplit("}", 1)[-1],
                    "软结必须是有机闭合路径，不能退回正圆",
                )
                self.assertEqual(
                    "circle",
                    节点索引["face-eye-dot"].tag.rsplit("}", 1)[-1],
                )
                self.assertEqual(
                    "circle",
                    节点索引["face-eye-arc"].tag.rsplit("}", 1)[-1],
                    "角色头像必须使用双圆点眼，不能退回眨眼弧线",
                )
                self.assertNotIn("transform", 节点索引["flow-head"].attrib)
                self.assertEqual(
                    "path",
                    节点索引["flow-head"].tag.rsplit("}", 1)[-1],
                )
                self.assertEqual(
                    "url(#flow-body-gradient)",
                    节点索引["flow-head"].attrib["fill"],
                )
                self.assertEqual(
                    1,
                    节点索引["flow-head"].attrib["d"].count("M"),
                    "参考图形主体必须保持连续轮廓，不能拆成容易误读的耳朵碎片",
                )
                标题 = 节点索引["title"]
                self.assertIn("参考图形主体版", "".join(标题.itertext()))

    def test_App图标禁止混入完整角色的手脚节点(self) -> None:
        路径 = self.写入_参考风格App图标(
            "app-icon-with-limbs.svg",
            附加内容='<path id="arm-left" fill="none" stroke="#11101F" />',
        )

        self.assertIn(
            "App 图标不得包含角色肢体节点：arm-left",
            品牌资产.validate_svg(路径, asset_kind="app-icon"),
        )

    def test_App图标必须有完整不透明品牌浅桃柔光底(self) -> None:
        路径 = self.写入_svg("app-icon.svg")

        self.assertIn(
            "App 图标必须包含完整不透明的品牌浅桃柔光背景",
            品牌资产.validate_svg(路径, asset_kind="app-icon"),
        )

    def test_App图标允许品牌色渐变(self) -> None:
        路径 = self.写入_参考风格App图标("app-icon.svg")

        问题 = 品牌资产.validate_svg(路径, asset_kind="app-icon")

        self.assertNotIn("正式 SVG 不得包含线性渐变", 问题)
        self.assertFalse(any("非白名单颜色" in 问题项 for 问题项 in 问题))
        self.assertNotIn("App 图标奋斗头带必须使用参考橙色渐变", 问题)
        self.assertNotIn("App 图标桃色嘴必须保持 #FFB27D", 问题)
        self.assertNotIn("App 图标必须包含完整不透明的品牌浅桃柔光背景", 问题)

    def test_App图标参考橙只能用于奋斗头带渐变(self) -> None:
        路径 = self.写入_参考风格App图标(
            "app-icon-cherry-misuse.svg",
            附加内容='<path fill="#EAA93A" d="M0 0h10v10z" />',
        )

        self.assertIn(
            "正式 SVG 使用了非白名单颜色：#EAA93A",
            品牌资产.validate_svg(路径, asset_kind="app-icon"),
        )

    def test_App图标桃色嘴不得跟随头带变红(self) -> None:
        路径 = self.写入_参考风格App图标(
            "app-icon-red-mouth.svg",
            嘴部描边="url(#headband-gradient)",
        )

        self.assertIn(
            "App 图标桃色嘴必须保持 #FFB27D",
            品牌资产.validate_svg(路径, asset_kind="app-icon"),
        )

    def test_App图标奋斗头带参考橙渐变端点不可颠倒(self) -> None:
        路径 = self.写入_参考风格App图标(
            "app-icon-reversed-cherry.svg",
            头带亮色="#C65F14",
            头带深色="#EAA93A",
        )

        self.assertIn(
            "App 图标奋斗头带必须使用参考橙色渐变",
            品牌资产.validate_svg(路径, asset_kind="app-icon"),
        )

    def test_App图标拒绝品牌色之外的蓝紫色(self) -> None:
        路径 = self.写入_svg(
            "app-icon-wrong-color.svg",
            节点=应用图标节点,
            附加内容=(
                '<path fill="#4338F2" d="M0 0h10v10z" />'
                '<rect id="icon-background" width="1024" height="1024" '
                'fill="#FFE2B8" />'
            ),
        )

        self.assertIn(
            "正式 SVG 使用了非白名单颜色：#4338F2",
            品牌资产.validate_svg(路径, asset_kind="app-icon"),
        )

    def test_App图标缺任一参考风格渐变会失败(self) -> None:
        背景 = (
            '<rect id="icon-background" width="1024" height="1024" '
            'fill="#FFE2B8" />'
        )
        for 缺失节点 in 应用图标渐变节点:
            with self.subTest(缺失节点=缺失节点):
                渐变 = "".join(
                    f'<linearGradient id="{节点}" />'
                    for 节点 in 应用图标渐变节点
                    if 节点 != 缺失节点
                )
                路径 = self.写入_svg(
                    f"app-icon-{缺失节点}.svg",
                    节点=应用图标节点,
                    附加内容=f"<defs>{渐变}</defs>{背景}",
                )

                self.assertIn(
                    f"App 图标缺少参考风格渐变：{缺失节点}",
                    品牌资产.validate_svg(路径, asset_kind="app-icon"),
                )

    def test_两类App图标缺任一胶囊脸节点会失败(self) -> None:
        背景 = (
            '<rect id="icon-background" width="1024" height="1024" '
            'fill="#FFE2B8" />'
        )
        for 资产类型 in ("app-icon", "app-icon-maskable"):
            for 缺失节点 in 应用图标节点:
                with self.subTest(资产类型=资产类型, 缺失节点=缺失节点):
                    路径 = self.写入_svg(
                        f"{资产类型}-{缺失节点}.svg",
                        节点=tuple(
                            节点 for 节点 in 应用图标节点 if 节点 != 缺失节点
                        ),
                        附加内容=背景,
                    )

                    self.assertIn(
                        f"App 图标缺少固定节点：{缺失节点}",
                        品牌资产.validate_svg(路径, asset_kind=资产类型),
                    )

    def test_App图标背景位于透明或隐藏祖先组时会失败(self) -> None:
        for 祖先属性 in ('opacity="0"', 'display="none"', 'visibility="hidden"'):
            with self.subTest(祖先属性=祖先属性):
                路径 = self.写入_svg(
                    "hidden-parent.svg",
                    节点=应用图标节点,
                    附加内容=(
                        f'<g {祖先属性}>'
                        '<rect id="icon-background" width="1024" height="1024" '
                        'fill="#FFE2B8" />'
                        "</g>"
                    ),
                )

                self.assertIn(
                    "App 图标必须包含完整不透明的品牌浅桃柔光背景",
                    品牌资产.validate_svg(路径, asset_kind="app-icon"),
                )

    def test_App图标背景自身隐藏时会失败(self) -> None:
        for 隐藏属性 in ('display="none"', 'visibility="hidden"'):
            with self.subTest(隐藏属性=隐藏属性):
                路径 = self.写入_svg(
                    "hidden-rect.svg",
                    节点=应用图标节点,
                    附加内容=(
                        f'<rect id="icon-background" width="1024" height="1024" fill="#FFE2B8" '
                        f"{隐藏属性} />"
                    ),
                )

                self.assertIn(
                    "App 图标必须包含完整不透明的品牌浅桃柔光背景",
                    品牌资产.validate_svg(路径, asset_kind="app-icon-maskable"),
                )

    def test_App图标根级fill_opacity透明时会失败(self) -> None:
        背景 = (
            '<rect id="icon-background" width="1024" height="1024" '
            'fill="#FFE2B8" />'
        )
        for 根属性 in ('fill-opacity="0"', 'style="fill-opacity: 0"'):
            with self.subTest(根属性=根属性):
                路径 = self.写入_svg(
                    "root-fill-opacity.svg",
                    节点=应用图标节点,
                    附加内容=背景,
                    根属性=根属性,
                )

                self.assertIn(
                    "App 图标必须包含完整不透明的品牌浅桃柔光背景",
                    品牌资产.validate_svg(路径, asset_kind="app-icon"),
                )


class PNG与平台契约测试(品牌资产测试基类):
    def test_平台App图标主体占比符合定版冲刺角色结构(self) -> None:
        样本 = (
            (
                品牌资产.REPOSITORY_ROOT
                / "ios"
                / "Runner"
                / "Assets.xcassets"
                / "AppIcon.appiconset"
                / "Icon-App-1024x1024@1x.png",
                .62,
                .65,
                .59,
                .62,
            ),
            (
                品牌资产.REPOSITORY_ROOT
                / "web"
                / "icons"
                / "Icon-maskable-512.png",
                .56,
                .59,
                .52,
                .56,
            ),
        )

        for 路径, 最小宽度占比, 最大宽度占比, 最小高度占比, 最大高度占比 in 样本:
            with self.subTest(路径=路径):
                宽度占比, 高度占比 = self.读取_深蓝主体占比(路径)
                self.assertGreaterEqual(宽度占比, 最小宽度占比)
                self.assertLessEqual(宽度占比, 最大宽度占比)
                self.assertGreaterEqual(高度占比, 最小高度占比)
                self.assertLessEqual(高度占比, 最大高度占比)

    def test_定版图标的奋斗配饰完整且Maskable位于安全圆(self) -> None:
        普通图标 = (
            品牌资产.REPOSITORY_ROOT
            / "ios"
            / "Runner"
            / "Assets.xcassets"
            / "AppIcon.appiconset"
            / "Icon-App-1024x1024@1x.png"
        )
        配饰左边界, _, 配饰右边界, _ = self.读取_参考橙配饰边界(普通图标)
        self.assertGreaterEqual(
            配饰左边界,
            90,
            "定版图标必须为奋斗头带、软结和双飘带保留至少 90px 左边距",
        )
        self.assertLessEqual(
            配饰右边界,
            900,
            "定版图标必须为奋斗头带、软结和双飘带保留至少 124px 右边距",
        )

        Maskable前景 = (
            品牌资产.REPOSITORY_ROOT
            / "android"
            / "app"
            / "src"
            / "main"
            / "res"
            / "drawable-xxxhdpi"
            / "ic_launcher_foreground.png"
        )
        self.assertLessEqual(
            self.读取_非背景最大半径占比(Maskable前景),
            .401,
            "Maskable 前景必须完整位于直径 80% 的平台安全圆内",
        )

    def test_三端图标与定版母版保持逐像素一致(self) -> None:
        清单 = 品牌资产.load_manifest()
        样本 = (
            (
                品牌资产.REPOSITORY_ROOT
                / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png",
                180,
                False,
            ),
            (
                品牌资产.REPOSITORY_ROOT
                / "android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png",
                432,
                True,
            ),
            (
                品牌资产.REPOSITORY_ROOT / "web/icons/Icon-maskable-512.png",
                512,
                True,
            ),
        )
        for 路径, 尺寸, 使用安全区 in 样本:
            with self.subTest(路径=路径):
                self.assertEqual(
                    [],
                    品牌资产.validate_deterministic_platform_png(
                        路径,
                        尺寸,
                        清单,
                        maskable=使用安全区,
                    ),
                )

    def test_PNG尺寸错误会失败(self) -> None:
        路径 = self.写入_png("wrong-size.png", (31, 32), "RGB")

        self.assertIn(
            "PNG 尺寸错误：期望 32×32，实际 31×32",
            品牌资产.validate_png(路径, 32, 32),
        )

    def test_直接禁止Alpha时返回iOS中文错误(self) -> None:
        路径 = self.写入_png("ios-alpha.png", (1024, 1024), "RGBA")

        self.assertIn(
            "iOS 图标不得包含 Alpha 通道",
            品牌资产.validate_png(路径, 1024, 1024, allow_alpha=False),
        )

    def test_iOS规则从Contents读取且Alpha会失败(self) -> None:
        图标目录 = self.根目录 / "AppIcon.appiconset"
        图标目录.mkdir()
        内容路径 = 图标目录 / "Contents.json"
        内容路径.write_text(
            json.dumps(
                {
                    "images": [
                        {
                            "size": "20x20",
                            "scale": "2x",
                            "idiom": "iphone",
                            "filename": "自定义文件名.png",
                        }
                    ],
                    "info": {"version": 1, "author": "xcode"},
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        Image.new("RGBA", (40, 40), (255, 226, 184, 255)).save(
            图标目录 / "自定义文件名.png"
        )

        问题 = 品牌资产.validate_ios_catalog(内容路径)

        self.assertIn("iOS 图标不得包含 Alpha 通道：自定义文件名.png", 问题)
        self.assertFalse(any("Icon-App-" in 问题项 for 问题项 in 问题))

    def test_iOS自定义文件名和尺寸可完全由Contents驱动(self) -> None:
        图标目录 = self.根目录 / "AppIcon.appiconset"
        图标目录.mkdir()
        内容路径 = 图标目录 / "Contents.json"
        内容路径.write_text(
            json.dumps(
                {
                    "images": [
                        {
                            "size": "29x29",
                            "scale": "3x",
                            "idiom": "iphone",
                            "filename": "任意名称.png",
                        }
                    ]
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        Image.new("RGB", (87, 87), (255, 226, 184)).save(图标目录 / "任意名称.png")

        self.assertEqual([], 品牌资产.validate_ios_catalog(内容路径))

    def test_iOS允许相同像素尺寸的槽位复用同一文件(self) -> None:
        图标目录 = self.根目录 / "AppIcon.appiconset"
        图标目录.mkdir()
        内容路径 = 图标目录 / "Contents.json"
        内容路径.write_text(
            json.dumps(
                {
                    "images": [
                        {
                            "size": "20x20",
                            "scale": "2x",
                            "idiom": "iphone",
                            "filename": "共用图标.png",
                        },
                        {
                            "size": "40x40",
                            "scale": "1x",
                            "idiom": "ipad",
                            "filename": "共用图标.png",
                        },
                    ]
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        Image.new("RGB", (40, 40), (255, 226, 184)).save(图标目录 / "共用图标.png")

        self.assertEqual([], 品牌资产.validate_ios_catalog(内容路径))

    def test_iOS禁止不同像素尺寸的槽位复用同一文件(self) -> None:
        图标目录 = self.根目录 / "AppIcon.appiconset"
        图标目录.mkdir()
        内容路径 = 图标目录 / "Contents.json"
        内容路径.write_text(
            json.dumps(
                {
                    "images": [
                        {
                            "size": "20x20",
                            "scale": "2x",
                            "filename": "冲突图标.png",
                        },
                        {
                            "size": "29x29",
                            "scale": "2x",
                            "filename": "冲突图标.png",
                        },
                    ]
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        Image.new("RGB", (40, 40), (255, 226, 184)).save(图标目录 / "冲突图标.png")

        self.assertIn(
            "iOS Contents.json 同一文件被不同像素尺寸引用：冲突图标.png",
            品牌资产.validate_ios_catalog(内容路径),
        )

    def test_Web_Maskable图标透明会失败(self) -> None:
        路径 = self.写入_png("maskable.png", (192, 192), "RGBA")
        图片 = Image.open(路径)
        图片.putpixel((0, 0), (255, 226, 184, 0))
        图片.save(路径)

        self.assertIn(
            "Web Maskable 图标必须完整不透明",
            品牌资产.validate_png(
                路径,
                192,
                192,
                require_opaque=True,
                platform="web-maskable",
            ),
        )

    def test_平台任务不得使用营销纹理(self) -> None:
        清单 = {
            "platformSources": {
                "ios": ["trainmate-flow-marketing-texture.svg"],
                "android": ["trainmate-flow-app-icon.svg"],
                "web": ["trainmate-flow-app-icon-maskable.svg"],
            }
        }

        self.assertIn(
            "ios 平台任务不得使用营销纹理",
            品牌资产.validate_platform_source_contract(清单),
        )


class 导出与命令行契约测试(unittest.TestCase):
    def test_小尺寸与标准头像源稿选择规则(self) -> None:
        for 尺寸 in (16, 24, 32, 48):
            with self.subTest(尺寸=尺寸):
                self.assertEqual(
                    "trainmate-flow-brandmark-small.svg",
                    品牌资产.select_avatar_source(尺寸),
                )
        for 尺寸 in (64, 128, 256, 512, 1024):
            with self.subTest(尺寸=尺寸):
                self.assertEqual(
                    "trainmate-flow-brandmark.svg",
                    品牌资产.select_avatar_source(尺寸),
                )

    def test_命令行参数支持全部校验范围(self) -> None:
        解析器 = 品牌资产.build_parser()
        for 平台 in ("source", "exports", "ios", "android", "web", "all"):
            with self.subTest(平台=平台):
                self.assertEqual(
                    平台,
                    解析器.parse_args(["--platform", 平台]).platform,
                )

    def test_命令行错误和帮助文字使用中文(self) -> None:
        解析器 = 品牌资产.build_parser()
        帮助文本 = 解析器.format_help()
        self.assertIn("用法：", 帮助文本)
        self.assertIn("选择校验范围", 帮助文本)
        self.assertNotIn("usage:", 帮助文本)
        self.assertNotIn("options:", 帮助文本)

        错误输出 = io.StringIO()
        with contextlib.redirect_stderr(错误输出), self.assertRaises(SystemExit):
            解析器.parse_args(["--platform", "unknown"])
        self.assertIn("错误：命令行参数无效", 错误输出.getvalue())
        self.assertNotIn("invalid choice", 错误输出.getvalue())


class 资产清单契约测试(unittest.TestCase):
    def test_清单完整记录正式源稿色值和导出尺寸(self) -> None:
        清单 = json.loads(清单路径.read_text(encoding="utf-8"))
        self.assertEqual(2, 清单["schemaVersion"])
        self.assertEqual(
            {
                "file": "trainmate-flow-logo-final-20260717.png",
                "sha256": "8370687c15f3ffa5c131906853ceb845e87ee9b052c759abafc9cd8a2492d365",
                "width": 1254,
                "height": 1254,
                "mode": "RGB",
                "maskableScale": 0.9,
                "maskableBackground": "#FEFEFE",
            },
            清单["appIconMaster"],
        )
        self.assertEqual(
            {
                "ink": "#19172C",
                "deepInk": "#11101F",
                "paper": "#FFFDFC",
                "peach": "#FFB27D",
                "peachLight": "#FFE2B8",
            },
            清单["colors"],
        )
        self.assertEqual(
            [16, 24, 32, 48, 64, 128, 256, 512, 1024],
            清单["exportSizes"],
        )
        self.assertEqual([96, 128, 256, 512, 1024], 清单["characterExportSizes"])
        self.assertEqual(48, 清单["smallSourceMaxSize"])

        self.assertEqual(
            {
                "trainmate-flow-brandmark.svg",
                "trainmate-flow-brandmark-small.svg",
                "trainmate-flow-brandmark-reverse.svg",
                "trainmate-flow-brandmark-mono.svg",
                "trainmate-flow-character.svg",
                "trainmate-flow-wordmark.svg",
                "trainmate-flow-wordmark-horizontal.svg",
                "trainmate-flow-lockup.svg",
                "trainmate-flow-character-lockup.svg",
                "trainmate-flow-submark.svg",
                "trainmate-flow-app-icon.svg",
                "trainmate-flow-app-icon-maskable.svg",
            },
            {项目["file"] for 项目 in 清单["formalSources"]},
        )
        self.assertEqual(
            正式源文件类型,
            {项目["file"]: 项目["kind"] for 项目 in 清单["formalSources"]},
        )
        self.assertEqual(
            "trainmate-flow-marketing-texture.svg",
            清单["marketingTexture"],
        )
        self.assertEqual([], 品牌资产.validate_platform_source_contract(清单))
        self.assertEqual(
            {
                "ios": ["trainmate-flow-logo-final-20260717.png"],
                "android": ["trainmate-flow-logo-final-20260717.png"],
                "web": ["trainmate-flow-logo-final-20260717.png"],
            },
            清单["platformSources"],
        )

    def test_定版Logo母版摘要和像素规格不可漂移(self) -> None:
        清单 = json.loads(清单路径.read_text(encoding="utf-8"))
        self.assertEqual([], 品牌资产.validate_app_icon_master(清单))

        篡改清单 = copy.deepcopy(清单)
        篡改清单["appIconMaster"]["sha256"] = "0" * 64
        self.assertIn(
            "定版 Logo 配置错误：sha256",
            品牌资产.validate_app_icon_master(篡改清单),
        )

    def test_正式源文件类型不能降级为formal绕过节点校验(self) -> None:
        原始清单 = json.loads(清单路径.read_text(encoding="utf-8"))
        for 文件名, 预期类型 in 正式源文件类型.items():
            if 预期类型 == "formal":
                continue
            with self.subTest(文件名=文件名):
                篡改清单 = copy.deepcopy(原始清单)
                for 项目 in 篡改清单["formalSources"]:
                    if 项目["file"] == 文件名:
                        项目["kind"] = "formal"
                        break

                self.assertIn(
                    f"资产清单源文件类型错误：{文件名} 应为 {预期类型}",
                    品牌资产.validate_manifest_contract(篡改清单),
                )


if __name__ == "__main__":
    unittest.main()
