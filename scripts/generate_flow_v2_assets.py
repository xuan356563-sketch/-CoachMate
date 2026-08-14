#!/usr/bin/env python3
"""基于旧 Flow PNG 确定性生成 Flow V2 正式素材。

脚本只改写可见像素的 RGB，输出 Alpha 逐像素沿用来源。
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image


项目根目录 = Path(__file__).resolve().parents[1]
素材根目录 = 项目根目录 / "assets/branding/flow-v2-color-detail"
清单路径 = 素材根目录 / "manifest.json"
总览路径 = 素材根目录 / "review/flow-v2-action-set-overview.png"
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

深蓝基色 = (25, 23, 44)
深蓝高光 = (75, 78, 200)
深蓝阴影 = (14, 13, 27)
纸白 = (255, 253, 252)
珊瑚橙 = (255, 107, 74)
杏桃高光 = (255, 178, 91)
晴日黄 = (255, 212, 71)
薄荷青 = (66, 217, 193)
天空蓝 = (85, 184, 255)
活力紫 = (139, 114, 255)
腮红 = (255, 143, 163)
浅色主体 = (255, 226, 184)
浅色高光 = (255, 249, 231)
浅色阴影 = (225, 174, 122)


def 解析参数() -> argparse.Namespace:
    解析器 = argparse.ArgumentParser(description=__doc__)
    解析器.add_argument(
        "--check",
        action="store_true",
        help="只读复算并校验现有输出，不改写文件",
    )
    return 解析器.parse_args()


def 计算_sha256(路径: Path) -> str:
    摘要 = hashlib.sha256()
    with 路径.open("rb") as 文件:
        for 数据块 in iter(lambda: 文件.read(65536), b""):
            摘要.update(数据块)
    return 摘要.hexdigest()


def 读取清单() -> dict[str, Any]:
    try:
        清单 = json.loads(清单路径.read_text(encoding="utf-8"))
    except FileNotFoundError as 错误:
        raise RuntimeError(f"Flow V2 清单不存在：{清单路径}") from 错误
    except (OSError, json.JSONDecodeError) as 错误:
        raise RuntimeError("Flow V2 清单无法解析") from 错误
    if not isinstance(清单, dict) or not isinstance(清单.get("assets"), list):
        raise RuntimeError("Flow V2 清单结构无效")
    if len(清单["assets"]) != 43:
        raise RuntimeError("Flow V2 清单必须恰好包含 43 项素材")
    return 清单


def 混合颜色(起点: tuple[int, int, int], 终点: tuple[int, int, int], 比例: float) -> tuple[int, int, int]:
    限定比例 = max(0.0, min(1.0, 比例))
    return tuple(
        round(起点[索引] + (终点[索引] - 起点[索引]) * 限定比例)
        for 索引 in range(3)
    )


def 动作点缀色(标识: str) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    try:
        编号 = int(标识.removeprefix("action-").split("-", 1)[0])
    except ValueError:
        return 珊瑚橙, 杏桃高光
    if 编号 == 1:
        return 天空蓝, 晴日黄
    if 编号 in {2, 5, 6, 7, 8, 9, 14}:
        return 珊瑚橙, 薄荷青
    if 编号 in {3, 4, 18, 19, 20}:
        return 薄荷青, 天空蓝
    return 活力紫, 晴日黄


def 调整像素(
    颜色: tuple[int, int, int],
    *,
    变体: str,
    标识: str,
    横坐标: int,
    纵坐标: int,
    宽度: int,
    高度: int,
) -> tuple[int, int, int]:
    红, 绿, 蓝 = 颜色
    亮度 = (红 * 299 + 绿 * 587 + 蓝 * 114) / 1000
    左上光 = (1 - 横坐标 / max(1, 宽度 - 1)) * 0.55 + (
        1 - 纵坐标 / max(1, 高度 - 1)
    ) * 0.45

    # 珊瑚/杏桃区优先处理，避免被浅色主体规则吸收。
    if 红 >= 145 and 红 >= 绿 + 35 and 绿 >= 蓝 + 8 and 蓝 <= 130:
        比例 = (亮度 - 105) / 115 * 0.75 + 左上光 * 0.25
        return 混合颜色(珊瑚橙, 杏桃高光, 比例)

    if 变体 == "peach-light":
        if 红 >= 155 and 绿 >= 105 and 蓝 <= 225 and 红 >= 绿:
            if 亮度 < 190:
                return 混合颜色(浅色阴影, 浅色主体, (亮度 - 120) / 70)
            比例 = (亮度 - 190) / 65 * 0.75 + 左上光 * 0.25
            return 混合颜色(浅色主体, 浅色高光, 比例)

    # 深蓝主体的原始明暗和空间位置共同驱动两级光影。
    if 红 <= 115 and 绿 <= 115 and 蓝 <= 150:
        if 亮度 < 16:
            return 深蓝阴影
        if 亮度 < 29:
            return 深蓝基色
        比例 = (亮度 - 29) / 75 * 0.72 + 左上光 * 0.28
        return 混合颜色(深蓝基色, 深蓝高光, 比例)

    if min(红, 绿, 蓝) >= 220 and max(红, 绿, 蓝) - min(红, 绿, 蓝) <= 26:
        return 纸白

    主点缀, 次点缀 = 动作点缀色(标识)
    饱和度 = max(红, 绿, 蓝) - min(红, 绿, 蓝)
    if 饱和度 >= 55 and max(红, 绿, 蓝) >= 120:
        if 蓝 > 红 * 1.15 or 绿 > 红 * 1.15:
            return 混合颜色(主点缀, 次点缀, 左上光)
        if 红 > 蓝 * 1.25:
            return 混合颜色(珊瑚橙, 腮红, min(1.0, 绿 / 210))
    return 颜色


def 生成单图(项目: dict[str, Any]) -> None:
    来源路径 = 项目根目录 / str(项目["sourcePath"])
    输出路径 = 项目根目录 / str(项目["outputPath"])
    with Image.open(来源路径) as 来源:
        来源.load()
        if 来源.mode != "RGBA":
            raise RuntimeError(f"来源必须是 RGBA PNG：{项目['sourcePath']}")
        if 来源.size != (int(项目["width"]), int(项目["height"])):
            raise RuntimeError(f"来源尺寸与清单不一致：{项目['sourcePath']}")
        原像素 = list(
            来源.get_flattened_data()
            if hasattr(来源, "get_flattened_data")
            else 来源.getdata()
        )

    宽度, 高度 = int(项目["width"]), int(项目["height"])
    是组合标 = 项目["id"] == "flow-lockup"
    新像素: list[tuple[int, int, int, int]] = []
    for 索引, (红, 绿, 蓝, alpha) in enumerate(原像素):
        横坐标 = 索引 % 宽度
        纵坐标 = 索引 // 宽度
        if alpha == 0 or (是组合标 and 横坐标 >= 630):
            新像素.append((红, 绿, 蓝, alpha))
            continue
        新颜色 = 调整像素(
            (红, 绿, 蓝),
            变体=str(项目["variant"]),
            标识=str(项目["id"]),
            横坐标=横坐标,
            纵坐标=纵坐标,
            宽度=宽度,
            高度=高度,
        )
        新像素.append((*新颜色, alpha))

    输出 = Image.new("RGBA", (宽度, 高度))
    输出.putdata(新像素)
    if 输出.getchannel("A").tobytes() != bytes(像素[3] for 像素 in 原像素):
        raise RuntimeError(f"内部错误：Alpha 通道发生变化：{项目['id']}")
    输出路径.parent.mkdir(parents=True, exist_ok=True)
    临时路径 = 输出路径.with_name(f".{输出路径.name}.tmp.png")
    输出.save(临时路径, format="PNG", optimize=True)
    临时路径.replace(输出路径)


def 生成动作总览() -> None:
    单元格 = 256
    列数 = 5
    行数 = 8
    画布 = Image.new("RGBA", (列数 * 单元格, 行数 * 单元格), 纸白 + (255,))
    for 变体索引, 变体 in enumerate(("navy", "peach-light")):
        底色 = 纸白 + (255,) if 变体 == "navy" else 深蓝基色 + (255,)
        for 动作索引, 动作 in enumerate(动作名称):
            列号 = 动作索引 % 列数
            行号 = 变体索引 * 4 + 动作索引 // 列数
            左 = 列号 * 单元格
            上 = 行号 * 单元格
            画布.paste(底色, (左, 上, 左 + 单元格, 上 + 单元格))
            路径 = 素材根目录 / "action-characters" / 变体 / f"{动作}.png"
            with Image.open(路径) as 图像:
                图像.load()
                缩略图 = 图像.resize((单元格, 单元格), Image.Resampling.LANCZOS)
            画布.alpha_composite(缩略图, (左, 上))
    总览路径.parent.mkdir(parents=True, exist_ok=True)
    临时路径 = 总览路径.with_name(f".{总览路径.name}.tmp.png")
    画布.save(临时路径, format="PNG", optimize=True)
    临时路径.replace(总览路径)


def 计算_alpha_iou(来源: Image.Image, 输出: Image.Image) -> float:
    来源数据 = 来源.getchannel("A").tobytes()
    输出数据 = 输出.getchannel("A").tobytes()
    交集 = sum(bool(来源值) and bool(输出值) for 来源值, 输出值 in zip(来源数据, 输出数据))
    并集 = sum(bool(来源值) or bool(输出值) for 来源值, 输出值 in zip(来源数据, 输出数据))
    return 1.0 if 并集 == 0 else 交集 / 并集


def 校验单项(项目: dict[str, Any]) -> None:
    来源路径 = 项目根目录 / str(项目["sourcePath"])
    输出路径 = 项目根目录 / str(项目["outputPath"])
    if not 来源路径.is_file() or not 输出路径.is_file():
        raise RuntimeError(f"来源或输出不存在：{项目['id']}")
    if 计算_sha256(来源路径) != 项目.get("sourceSha256"):
        raise RuntimeError(f"来源 SHA-256 与清单不一致：{项目['id']}")
    if 计算_sha256(输出路径) != 项目.get("sha256"):
        raise RuntimeError(f"输出 SHA-256 与清单不一致：{项目['id']}")
    with Image.open(来源路径) as 来源, Image.open(输出路径) as 输出:
        来源.load()
        输出.load()
        期望尺寸 = (int(项目["width"]), int(项目["height"]))
        if 来源.mode != "RGBA" or 输出.mode != "RGBA" or 来源.size != 期望尺寸 or 输出.size != 期望尺寸:
            raise RuntimeError(f"尺寸或颜色模式无效：{项目['id']}")
        if 来源.getchannel("A").tobytes() != 输出.getchannel("A").tobytes():
            raise RuntimeError(f"Alpha 通道不完全一致：{项目['id']}")
        if 来源.getbbox() != 输出.getbbox():
            raise RuntimeError(f"主体边界偏移不是 0px：{项目['id']}")
        if 计算_alpha_iou(来源, 输出) != 1.0 or 项目.get("alphaIou") != 1.0:
            raise RuntimeError(f"Alpha IoU 不是 1.0：{项目['id']}")
        if 来源.convert("RGB").tobytes() == 输出.convert("RGB").tobytes():
            raise RuntimeError(f"输出 RGB 未发生变化：{项目['id']}")
        if 项目["id"] == "flow-lockup" and 来源.crop((630, 0, 1600, 626)).tobytes() != 输出.crop((630, 0, 1600, 626)).tobytes():
            raise RuntimeError("组合标的中文与 TrainMate 字标像素发生变化")
    if 项目.get("reviewStatus") != "generated-pending-human-review":
        raise RuntimeError(f"素材状态不在待人工审核边界：{项目['id']}")


def 校验全部(清单: dict[str, Any]) -> dict[str, Any]:
    if 清单.get("status") != "pending-human-visual-review":
        raise RuntimeError("顶层状态必须保持 pending-human-visual-review")
    for 项目 in 清单["assets"]:
        校验单项(项目)
    for 变体 in ("navy", "peach-light"):
        目录 = 素材根目录 / "action-characters" / 变体
        实际文件名 = sorted(路径.name for 路径 in 目录.glob("*.png"))
        if 实际文件名 != [f"{动作}.png" for 动作 in 动作名称]:
            raise RuntimeError(f"{变体} 动作文件名与 20 项契约不一致")
    if not 总览路径.is_file():
        raise RuntimeError("动作总览不存在")
    with Image.open(总览路径) as 总览:
        总览.load()
        if 总览.mode != "RGBA" or 总览.size != (1280, 2048):
            raise RuntimeError("动作总览必须是 1280×2048 RGBA PNG")
    return {
        "assets": len(清单["assets"]),
        "actions": 40,
        "brandAssets": 3,
        "overview": 1,
        "alphaIou": 1.0,
        "maxBoundaryOffsetPx": 0,
        "status": 清单["status"],
    }


def 写入清单(清单: dict[str, Any]) -> None:
    """保留已建立清单的紧凑资产行格式，只替换 43 个项目行。"""
    项目索引 = {str(项目["id"]): 项目 for 项目 in 清单["assets"]}
    新行组: list[str] = []
    for 行 in 清单路径.read_text(encoding="utf-8").splitlines():
        去空格 = 行.strip().removesuffix(",")
        if 去空格.startswith('{"id":'):
            旧项目 = json.loads(去空格)
            逗号 = "," if 行.rstrip().endswith(",") else ""
            行 = "    " + json.dumps(项目索引[旧项目["id"]], ensure_ascii=False, separators=(",", ":")) + 逗号
        新行组.append(行)
    临时路径 = 清单路径.with_name(f".{清单路径.name}.tmp")
    临时路径.write_text("\n".join(新行组) + "\n", encoding="utf-8")
    临时路径.replace(清单路径)


def 生成全部(清单: dict[str, Any]) -> dict[str, Any]:
    for 项目 in 清单["assets"]:
        来源路径 = 项目根目录 / str(项目["sourcePath"])
        if not 来源路径.is_file():
            raise RuntimeError(f"来源不存在：{项目['sourcePath']}")
        if 计算_sha256(来源路径) != 项目.get("sourceSha256"):
            raise RuntimeError(f"来源 SHA-256 已漂移，拒绝生成：{项目['id']}")
        生成单图(项目)

    生成动作总览()
    for 项目 in 清单["assets"]:
        输出路径 = 项目根目录 / str(项目["outputPath"])
        项目["sha256"] = 计算_sha256(输出路径)
        项目["alphaIou"] = 1.0
        项目["reviewStatus"] = "generated-pending-human-review"
    写入清单(清单)
    return 校验全部(读取清单())


def 主函数() -> int:
    参数 = 解析参数()
    try:
        清单 = 读取清单()
        报告 = 校验全部(清单) if 参数.check else 生成全部(清单)
    except (OSError, RuntimeError, KeyError, TypeError, ValueError) as 错误:
        print(f"Flow V2 素材处理失败：{错误}")
        return 1
    print(json.dumps(报告, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(主函数())
