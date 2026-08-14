#!/usr/bin/env python3
"""从正式 SVG 母版确定性生成品牌 PNG 导出与评审图。"""

from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
from typing import Any

try:
    from PIL import Image, ImageDraw, ImageFont, ImageOps
except ImportError:
    print("品牌评审资产生成失败：缺少 Pillow 图像处理依赖")
    raise SystemExit(1)


仓库根目录 = Path(__file__).resolve().parents[1]
清单路径 = Path(__file__).with_name("brand_assets_manifest.json")
SIPS路径 = Path("/usr/bin/sips")
评审目录 = 仓库根目录 / "outputs/logos/trainmate-flow/vector-review"
展示目录 = 评审目录 / "presentation"
导出清单路径 = 评审目录 / "export-manifest.json"
评审清单路径 = 评审目录 / "review-manifest.json"
品牌总表路径 = 评审目录.parent / "brand-sheet.png"
中文字体路径 = Path("/System/Library/Fonts/Supplemental/Arial Unicode.ttf")

纸白 = "#FFFDFC"
深墨 = "#19172C"


def 读取清单() -> dict[str, Any]:
    try:
        清单 = json.loads(清单路径.read_text(encoding="utf-8"))
    except FileNotFoundError as 错误:
        raise RuntimeError(f"品牌资产清单不存在：{清单路径}") from 错误
    except (OSError, json.JSONDecodeError) as 错误:
        raise RuntimeError("品牌资产清单无法解析") from 错误
    if not isinstance(清单, dict):
        raise RuntimeError("品牌资产清单根节点必须是对象")
    return 清单


def 计算摘要(路径: Path) -> str:
    摘要器 = hashlib.sha256()
    with 路径.open("rb") as 文件:
        for 数据块 in iter(lambda: 文件.read(1024 * 1024), b""):
            摘要器.update(数据块)
    return 摘要器.hexdigest()


def 渲染SVG(源稿: Path, 输出: Path) -> None:
    if not 源稿.is_file():
        raise RuntimeError(f"品牌 SVG 源稿不存在：{源稿}")
    if not SIPS路径.is_file():
        raise RuntimeError("本机缺少 /usr/bin/sips，无法渲染品牌资产")
    输出.parent.mkdir(parents=True, exist_ok=True)
    结果 = subprocess.run(
        [str(SIPS路径), "-s", "format", "png", str(源稿), "--out", str(输出)],
        check=False,
        capture_output=True,
        text=True,
    )
    if 结果.returncode != 0 or not 输出.is_file():
        错误信息 = (结果.stderr or 结果.stdout).strip()
        raise RuntimeError(f"品牌 SVG 源稿渲染失败：{错误信息}")


def 写入PNG(图像: Image.Image, 输出: Path) -> None:
    输出.parent.mkdir(parents=True, exist_ok=True)
    临时输出 = 输出.with_name(f".{输出.name}.tmp.png")
    图像.save(临时输出, format="PNG", optimize=True)
    临时输出.replace(输出)


def 缩放正方形(母版: Path, 输出: Path, 尺寸: int) -> None:
    with Image.open(母版) as 图像:
        图像.load()
        结果 = 图像.convert("RGBA").resize((尺寸, 尺寸), Image.Resampling.LANCZOS)
    写入PNG(结果, 输出)


def 按宽度缩放(母版: Path, 输出: Path, 宽度: int) -> None:
    with Image.open(母版) as 图像:
        图像.load()
        高度 = max(1, round(图像.height * 宽度 / 图像.width))
        结果 = 图像.convert("RGBA").resize((宽度, 高度), Image.Resampling.LANCZOS)
    写入PNG(结果, 输出)


def 复制原始尺寸(母版: Path, 输出: Path) -> None:
    with Image.open(母版) as 图像:
        图像.load()
        结果 = 图像.convert("RGBA")
    写入PNG(结果, 输出)


def 生成展示副本(源图: Path, 输出: Path, 背景色: str) -> None:
    with Image.open(源图) as 图像:
        图像.load()
        前景 = 图像.convert("RGBA")
        背景 = Image.new("RGBA", 前景.size, 背景色)
        结果 = Image.alpha_composite(背景, 前景).convert("RGB")
    写入PNG(结果, 输出)


def 记录文件(路径: Path, 类型: str) -> dict[str, Any]:
    with Image.open(路径) as 图像:
        图像.load()
        尺寸 = [图像.width, 图像.height]
    return {
        "path": str(路径.relative_to(仓库根目录)),
        "kind": 类型,
        "width": 尺寸[0],
        "height": 尺寸[1],
        "sha256": 计算摘要(路径),
    }


def 生成中文品牌总表() -> None:
    try:
        评审项目 = json.loads(评审清单路径.read_text(encoding="utf-8"))
    except FileNotFoundError as 错误:
        raise RuntimeError(f"评审清单不存在：{评审清单路径}") from 错误
    except (OSError, json.JSONDecodeError) as 错误:
        raise RuntimeError("评审清单无法解析") from 错误
    if not isinstance(评审项目, list) or not 评审项目:
        raise RuntimeError("评审清单必须是非空数组")
    if not 中文字体路径.is_file():
        raise RuntimeError(f"系统中文字体不存在：{中文字体路径}")

    列数 = 4
    卡片宽度 = 310
    卡片高度 = 350
    间距 = 18
    外边距 = 32
    头部高度 = 124
    行数 = (len(评审项目) + 列数 - 1) // 列数
    画布宽度 = 外边距 * 2 + 列数 * 卡片宽度 + (列数 - 1) * 间距
    画布高度 = 头部高度 + 外边距 + 行数 * 卡片高度 + (行数 - 1) * 间距 + 外边距
    画布 = Image.new("RGB", (画布宽度, 画布高度), "#F5F2EC")
    绘图 = ImageDraw.Draw(画布)
    绘图.rounded_rectangle(
        (外边距, 20, 画布宽度 - 外边距, 头部高度 - 8),
        radius=24,
        fill=深墨,
    )
    标题字体 = ImageFont.truetype(str(中文字体路径), 32)
    副标题字体 = ImageFont.truetype(str(中文字体路径), 17)
    标签字体 = ImageFont.truetype(str(中文字体路径), 18)
    分类字体 = ImageFont.truetype(str(中文字体路径), 14)
    绘图.text((外边距 + 28, 38), "智练 TrainMate｜参考图排版与动态倾角", fill=纸白, font=标题字体)
    绘图.text(
        (外边距 + 28, 82),
        "横排同基线｜上下排居中｜中文 5°｜英文 7°｜头像 5°｜小头像 3°｜副标 4°",
        fill="#FFB27D",
        font=副标题字体,
    )

    for 序号, 项目 in enumerate(评审项目):
        if not isinstance(项目, dict):
            raise RuntimeError("评审清单项目格式无效")
        源图相对路径 = 项目.get("src")
        if not isinstance(源图相对路径, str) or not 源图相对路径:
            raise RuntimeError("评审清单项目缺少 src")
        源图路径 = 评审目录 / 源图相对路径
        if not 源图路径.is_file():
            raise RuntimeError(f"评审图不存在：{源图路径}")

        行 = 序号 // 列数
        列 = 序号 % 列数
        左 = 外边距 + 列 * (卡片宽度 + 间距)
        上 = 头部高度 + 外边距 + 行 * (卡片高度 + 间距)
        右 = 左 + 卡片宽度
        下 = 上 + 卡片高度
        绘图.rounded_rectangle(
            (左, 上, 右, 下),
            radius=18,
            fill="#FFFDFC",
            outline="#DDD7CC",
            width=2,
        )

        图框 = (左 + 16, 上 + 16, 右 - 16, 上 + 268)
        图框宽度 = 图框[2] - 图框[0]
        图框高度 = 图框[3] - 图框[1]
        with Image.open(源图路径) as 图像:
            图像.load()
            缩略图 = ImageOps.contain(
                图像.convert("RGB"),
                (图框宽度, 图框高度),
                Image.Resampling.LANCZOS,
            )
        图左 = 图框[0] + (图框宽度 - 缩略图.width) // 2
        图上 = 图框[1] + (图框高度 - 缩略图.height) // 2
        画布.paste(缩略图, (图左, 图上))

        索引 = str(项目.get("index", 序号 + 1)).zfill(2)
        分类 = str(项目.get("category", "品牌资产"))
        标题 = str(项目.get("title", 项目.get("label", "未命名资产")))
        绘图.rounded_rectangle(
            (左 + 18, 上 + 278, 左 + 58, 上 + 304),
            radius=13,
            fill="#FFE2B8",
        )
        绘图.text((左 + 28, 上 + 281), 索引, fill=深墨, font=分类字体)
        绘图.text((左 + 68, 上 + 279), 分类, fill="#765D4E", font=分类字体)
        绘图.text((左 + 18, 上 + 311), 标题, fill=深墨, font=标签字体)

    写入PNG(画布, 品牌总表路径)


def main() -> int:
    try:
        清单 = 读取清单()
        源稿目录 = 仓库根目录 / str(清单["sourceDirectory"])
        导出目录 = 仓库根目录 / str(清单["exports"]["directory"])
        头像尺寸 = [int(尺寸) for 尺寸 in 清单["exportSizes"]]
        角色尺寸 = [int(尺寸) for 尺寸 in 清单["characterExportSizes"]]
        小尺寸上限 = int(清单["smallSourceMaxSize"])

        源稿 = {
            "头像": 源稿目录 / "trainmate-flow-brandmark.svg",
            "小头像": 源稿目录 / "trainmate-flow-brandmark-small.svg",
            "反白头像": 源稿目录 / "trainmate-flow-brandmark-reverse.svg",
            "单色头像": 源稿目录 / "trainmate-flow-brandmark-mono.svg",
            "完整角色": 源稿目录 / "trainmate-flow-character.svg",
            "上下排字标": 源稿目录 / "trainmate-flow-wordmark.svg",
            "横排字标": 源稿目录 / "trainmate-flow-wordmark-horizontal.svg",
            "组合标": 源稿目录 / "trainmate-flow-lockup.svg",
            "角色组合标": 源稿目录 / "trainmate-flow-character-lockup.svg",
            "副标": 源稿目录 / "trainmate-flow-submark.svg",
            "App图标": 源稿目录 / "trainmate-flow-app-icon.svg",
        }
        for 路径 in 源稿.values():
            if not 路径.is_file():
                raise RuntimeError(f"品牌 SVG 源稿不存在：{路径}")

        写入记录: list[dict[str, Any]] = []
        with tempfile.TemporaryDirectory(prefix="trainmate-brand-review-") as 临时目录文本:
            临时目录 = Path(临时目录文本)
            母版: dict[str, Path] = {}
            for 名称, 路径 in 源稿.items():
                输出 = 临时目录 / f"{名称}.png"
                渲染SVG(路径, 输出)
                母版[名称] = 输出

            for 尺寸 in 头像尺寸:
                使用小头像 = 尺寸 <= 小尺寸上限
                输出 = 导出目录 / str(清单["exports"]["avatarPattern"]).format(size=尺寸)
                缩放正方形(母版["小头像" if 使用小头像 else "头像"], 输出, 尺寸)
                写入记录.append(记录文件(输出, "头像导出"))

            for 尺寸 in 角色尺寸:
                输出 = 导出目录 / str(清单["exports"]["characterPattern"]).format(size=尺寸)
                缩放正方形(母版["完整角色"], 输出, 尺寸)
                写入记录.append(记录文件(输出, "角色导出"))

            组合标输出 = 导出目录 / str(清单["exports"]["lockupFile"])
            按宽度缩放(母版["组合标"], 组合标输出, 1600)
            写入记录.append(记录文件(组合标输出, "界面组合标导出"))

            评审生成器 = {
                "app-icon-1024.png": lambda 输出: 缩放正方形(母版["App图标"], 输出, 1024),
                "brandmark-1024.png": lambda 输出: 缩放正方形(母版["头像"], 输出, 1024),
                "brandmark-48.png": lambda 输出: 缩放正方形(母版["小头像"], 输出, 48),
                "brandmark-32.png": lambda 输出: 缩放正方形(母版["小头像"], 输出, 32),
                "brandmark-24.png": lambda 输出: 缩放正方形(母版["小头像"], 输出, 24),
                "brandmark-16.png": lambda 输出: 缩放正方形(母版["小头像"], 输出, 16),
                "character-128.png": lambda 输出: 缩放正方形(母版["完整角色"], 输出, 128),
                "character-96.png": lambda 输出: 缩放正方形(母版["完整角色"], 输出, 96),
                "wordmark.png": lambda 输出: 复制原始尺寸(母版["上下排字标"], 输出),
                "wordmark-horizontal.png": lambda 输出: 复制原始尺寸(母版["横排字标"], 输出),
                "lockup.png": lambda 输出: 按宽度缩放(母版["组合标"], 输出, 1600),
                "character-lockup.png": lambda 输出: 按宽度缩放(母版["角色组合标"], 输出, 1600),
                "submark.png": lambda 输出: 缩放正方形(母版["副标"], 输出, 1024),
                "reverse.png": lambda 输出: 缩放正方形(母版["反白头像"], 输出, 1024),
                "mono.png": lambda 输出: 缩放正方形(母版["单色头像"], 输出, 1024),
            }
            for 文件名, 生成器 in 评审生成器.items():
                输出 = 评审目录 / 文件名
                生成器(输出)
                写入记录.append(记录文件(输出, "透明评审图"))
                背景色 = 深墨 if 文件名 == "reverse.png" else 纸白
                展示输出 = 展示目录 / 文件名
                生成展示副本(输出, 展示输出, 背景色)
                写入记录.append(记录文件(展示输出, "展示评审图"))

        生成中文品牌总表()
        写入记录.append(记录文件(品牌总表路径, "中文品牌总表"))

        导出清单 = {
            "schemaVersion": 1,
            "brand": "智练 TrainMate",
            "source": "assets/branding/source",
            "motion": {
                "avatarDegrees": 5,
                "smallAvatarDegrees": 3,
                "submarkDegrees": 4,
                "chineseWordmarkDegrees": 5,
                "englishWordmarkDegrees": 7,
                "baselineRotated": False,
                "wordmarkLayouts": {
                    "horizontal": {
                        "canvas": [1492, 550],
                        "source": "trainmate-flow-wordmark-horizontal.svg",
                        "alignment": "中文顶边对齐，英文按底边与基线对齐",
                    },
                    "stacked": {
                        "canvas": [1204, 720],
                        "source": "trainmate-flow-wordmark.svg",
                        "alignment": "中文字并排居中，英文在下方居中",
                    },
                },
            },
            "sourceFiles": [
                {
                    "path": str(路径.relative_to(仓库根目录)),
                    "sha256": 计算摘要(路径),
                }
                for 路径 in 源稿.values()
            ],
            "outputs": sorted(写入记录, key=lambda 条目: 条目["path"]),
        }
        导出清单路径.write_text(
            json.dumps(导出清单, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    except (OSError, RuntimeError, KeyError, TypeError, ValueError) as 错误:
        print(f"品牌评审资产生成失败：{错误}")
        return 1

    print(f"品牌评审资产生成完成：共写入 {len(写入记录)} 个 PNG")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
