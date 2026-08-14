#!/usr/bin/env python3
"""从定版 PNG 母版确定性生成应用内、iOS、Android 与 Web 品牌图标。"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from collections import deque
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

from PIL import Image


仓库根目录 = Path(__file__).resolve().parents[1]
清单路径 = Path(__file__).with_name("brand_assets_manifest.json")
归档相对目录 = Path("outputs/logos/trainmate-flow/final-logo-v12")


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


def 计算像素尺寸(size: str, scale: str) -> int:
    try:
        宽度, 高度 = size.lower().split("x", 1)
        if Decimal(宽度) != Decimal(高度) or not scale.lower().endswith("x"):
            raise ValueError
        像素 = Decimal(宽度) * Decimal(scale[:-1])
        if 像素 <= 0 or 像素 != 像素.to_integral_value():
            raise ValueError
        return int(像素)
    except (InvalidOperation, ValueError) as 错误:
        raise RuntimeError(f"iOS 图标尺寸配置无效：size={size}, scale={scale}") from 错误


def 读取定版母版(清单: dict[str, Any]) -> Path:
    配置 = 清单.get("appIconMaster")
    if not isinstance(配置, dict):
        raise RuntimeError("品牌资产清单缺少 appIconMaster")
    路径 = 仓库根目录 / str(清单["sourceDirectory"]) / str(配置.get("file", ""))
    if not 路径.is_file():
        raise RuntimeError(f"定版 Logo 母版不存在：{路径}")
    摘要 = hashlib.sha256(路径.read_bytes()).hexdigest()
    if 摘要 != 配置.get("sha256"):
        raise RuntimeError("定版 Logo 母版摘要与品牌资产清单不一致")
    with Image.open(路径) as 图像:
        图像.load()
        if 图像.size != (int(配置["width"]), int(配置["height"])):
            raise RuntimeError("定版 Logo 母版尺寸与品牌资产清单不一致")
        if 图像.mode != 配置.get("mode"):
            raise RuntimeError("定版 Logo 母版颜色模式与品牌资产清单不一致")
    return 路径


def 导出PNG(母版: Path, 输出: Path, 尺寸: int) -> None:
    输出.parent.mkdir(parents=True, exist_ok=True)
    临时输出 = 输出.with_name(f".{输出.name}.tmp.png")
    with Image.open(母版) as 图像:
        图像.load()
        结果 = 图像.convert("RGB").resize((尺寸, 尺寸), Image.Resampling.LANCZOS)
        结果.save(临时输出, format="PNG", optimize=True)
    临时输出.replace(输出)


def 生成Maskable母版(清单: dict[str, Any], 标准母版: Path, 输出: Path) -> None:
    配置 = 清单["appIconMaster"]
    缩放 = float(配置["maskableScale"])
    if not 0 < 缩放 <= 1:
        raise RuntimeError("Maskable 安全区缩放必须大于 0 且不超过 1")
    with Image.open(标准母版) as 图像:
        图像.load()
        源图 = 图像.convert("RGB")
        边长 = 源图.width
        内容边长 = round(边长 * 缩放)
        内容 = 源图.resize((内容边长, 内容边长), Image.Resampling.LANCZOS)
        画布 = Image.new("RGB", 源图.size, str(配置["maskableBackground"]))
        偏移 = ((边长 - 内容边长) // 2, (边长 - 内容边长) // 2)
        画布.paste(内容, 偏移)
        输出.parent.mkdir(parents=True, exist_ok=True)
        画布.save(输出, format="PNG", optimize=True)


def 提取应用内透明标志(标准母版: Path) -> Image.Image:
    """仅移除与画布边缘连通的近白底，保留胶囊脸与高光。"""
    with Image.open(标准母版) as 图像:
        图像.load()
        rgb图像 = 图像.convert("RGB")
    宽度, 高度 = rgb图像.size
    像素 = list(
        rgb图像.get_flattened_data()
        if hasattr(rgb图像, "get_flattened_data")
        else rgb图像.getdata()
    )

    def 是外部近白底(索引: int) -> bool:
        红, 绿, 蓝 = 像素[索引]
        return min(红, 绿, 蓝) >= 170 and max(红, 绿, 蓝) - min(红, 绿, 蓝) <= 45

    已访问 = bytearray(宽度 * 高度)
    队列: deque[int] = deque()
    for 横坐标 in range(宽度):
        for 索引 in (横坐标, (高度 - 1) * 宽度 + 横坐标):
            if not 已访问[索引] and 是外部近白底(索引):
                已访问[索引] = 1
                队列.append(索引)
    for 纵坐标 in range(高度):
        for 索引 in (纵坐标 * 宽度, 纵坐标 * 宽度 + 宽度 - 1):
            if not 已访问[索引] and 是外部近白底(索引):
                已访问[索引] = 1
                队列.append(索引)
    while 队列:
        索引 = 队列.popleft()
        横坐标 = 索引 % 宽度
        纵坐标 = 索引 // 宽度
        for 相邻 in (
            索引 - 1 if 横坐标 > 0 else -1,
            索引 + 1 if 横坐标 + 1 < 宽度 else -1,
            索引 - 宽度 if 纵坐标 > 0 else -1,
            索引 + 宽度 if 纵坐标 + 1 < 高度 else -1,
        ):
            if 相邻 >= 0 and not 已访问[相邻] and 是外部近白底(相邻):
                已访问[相邻] = 1
                队列.append(相邻)

    rgba像素: list[tuple[int, int, int, int]] = []
    for 索引, (红, 绿, 蓝) in enumerate(像素):
        if not 已访问[索引]:
            rgba像素.append((红, 绿, 蓝, 255))
            continue
        最大差值 = max(254 - 红, 254 - 绿, 254 - 蓝, 0)
        alpha = min(255, round(最大差值 * 255 / 64))
        if alpha <= 64:
            rgba像素.append((254, 254, 254, 0))
            continue
        透明比例 = alpha / 255
        前景颜色 = tuple(
            max(0, min(255, round((通道 - 254 * (1 - 透明比例)) / 透明比例)))
            for 通道 in (红, 绿, 蓝)
        )
        rgba像素.append((*前景颜色, alpha))
    结果 = Image.new("RGBA", rgb图像.size)
    结果.putdata(rgba像素)
    return 结果


def 生成应用内品牌导出(清单: dict[str, Any], 标准母版: Path) -> int:
    导出配置 = 清单["exports"]
    导出目录 = 仓库根目录 / str(导出配置["directory"])
    导出目录.mkdir(parents=True, exist_ok=True)
    透明标志 = 提取应用内透明标志(标准母版)
    透明标志.resize((256, 256), Image.Resampling.LANCZOS).save(
        导出目录 / str(导出配置["finalLogoFile"]),
        format="PNG",
        optimize=True,
    )

    # 中文与 TrainMate 字标沿用已批准的像素源，仅替换左侧头像，避免字体漂移。
    旧组合图 = 导出目录 / str(导出配置["lockupFile"])
    新组合图 = 导出目录 / str(导出配置["finalLockupFile"])
    if not 旧组合图.is_file():
        raise RuntimeError(f"既有品牌组合图不存在：{旧组合图}")
    with Image.open(旧组合图) as 旧图像:
        旧图像.load()
        画布 = Image.new("RGBA", 旧图像.size, (0, 0, 0, 0))
        标志 = 透明标志.resize((600, 600), Image.Resampling.LANCZOS)
        画布.alpha_composite(标志, (18, 13))
        字标区域 = 旧图像.convert("RGBA").crop((630, 0, 1600, 626))
        画布.alpha_composite(字标区域, (630, 0))
        画布.save(新组合图, format="PNG", optimize=True)
    return 2


def 生成iOS(清单: dict[str, Any], 标准母版: Path) -> int:
    内容路径 = 仓库根目录 / str(清单["iosContents"])
    try:
        内容 = json.loads(内容路径.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as 错误:
        raise RuntimeError(f"iOS Contents.json 无法解析：{内容路径}") from 错误
    文件尺寸: dict[str, int] = {}
    for 条目 in 内容.get("images", []):
        if not isinstance(条目, dict) or not 条目.get("filename"):
            raise RuntimeError("iOS Contents.json 存在缺少 filename 的图标条目")
        文件名 = str(条目["filename"])
        尺寸 = 计算像素尺寸(str(条目.get("size", "")), str(条目.get("scale", "")))
        if 文件名 in 文件尺寸 and 文件尺寸[文件名] != 尺寸:
            raise RuntimeError(f"iOS 同一图标文件被不同像素尺寸引用：{文件名}")
        文件尺寸[文件名] = 尺寸
    for 文件名, 尺寸 in 文件尺寸.items():
        导出PNG(标准母版, 内容路径.parent / 文件名, 尺寸)
    return len(文件尺寸)


def 生成Android(清单: dict[str, Any], 标准母版: Path, Maskable母版: Path) -> int:
    配置 = 清单["android"]
    资源根目录 = 仓库根目录 / str(配置["resourceRoot"])
    数量 = 0
    for 密度, 尺寸 in 清单["androidLegacy"].items():
        导出PNG(标准母版, 资源根目录 / f"mipmap-{密度}" / "ic_launcher.png", int(尺寸))
        数量 += 1
    for 密度, 尺寸 in 清单["androidAdaptiveForeground"].items():
        导出PNG(
            Maskable母版,
            资源根目录 / f"drawable-{密度}" / "ic_launcher_foreground.png",
            int(尺寸),
        )
        数量 += 1
    return 数量


def 生成Web(清单: dict[str, Any], 标准母版: Path, Maskable母版: Path) -> int:
    数量 = 0
    for 相对路径, 尺寸 in 清单["web"].items():
        母版 = Maskable母版 if "maskable" in 相对路径.lower() else 标准母版
        导出PNG(母版, 仓库根目录 / "web" / 相对路径, int(尺寸))
        数量 += 1
    return 数量


def 生成归档(清单: dict[str, Any], 标准母版: Path, Maskable母版: Path) -> int:
    归档目录 = 仓库根目录 / 归档相对目录
    归档目录.mkdir(parents=True, exist_ok=True)
    原稿副本 = 归档目录 / 标准母版.name
    shutil.copyfile(标准母版, 原稿副本)
    文件列表 = [原稿副本]
    for 尺寸 in (16, 32, 60, 120, 180, 1024):
        输出 = 归档目录 / f"trainmate-flow-logo-final-{尺寸}.png"
        导出PNG(标准母版, 输出, 尺寸)
        文件列表.append(输出)
    Maskable输出 = 归档目录 / "trainmate-flow-logo-final-maskable-512.png"
    导出PNG(Maskable母版, Maskable输出, 512)
    文件列表.append(Maskable输出)
    记录 = {
        "schemaVersion": 1,
        "source": {
            "file": 标准母版.name,
            "sha256": 清单["appIconMaster"]["sha256"],
            "dimensions": [清单["appIconMaster"]["width"], 清单["appIconMaster"]["height"]],
            "mode": 清单["appIconMaster"]["mode"],
        },
        "rules": {
            "standard": "保持完整构图，使用 Pillow LANCZOS 等比缩放",
            "maskable": f"在 {清单['appIconMaster']['maskableBackground']} 底色上居中缩放至 {清单['appIconMaster']['maskableScale']:.0%}",
            "platformBackgroundRemoval": False,
            "inAppDisplay": "仅移除与画布边缘连通的近白底，保留胶囊脸与高光",
            "recolor": False,
        },
        "files": [
            {
                "file": 文件.name,
                "sha256": hashlib.sha256(文件.read_bytes()).hexdigest(),
            }
            for 文件 in 文件列表
        ],
    }
    (归档目录 / "export-manifest.json").write_text(
        json.dumps(记录, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return len(文件列表) + 1


def 构建参数解析器() -> argparse.ArgumentParser:
    解析器 = argparse.ArgumentParser(description="生成智练 TrainMate 定版 Logo 与三端平台图标")
    解析器.add_argument(
        "--platform",
        required=True,
        choices=("ios", "android", "web", "all"),
        help="选择要生成的平台",
    )
    return 解析器


def main() -> int:
    参数 = 构建参数解析器().parse_args()
    try:
        清单 = 读取清单()
        标准母版 = 读取定版母版(清单)
        Maskable母版 = 仓库根目录 / ".dart_tool" / "trainmate-branding" / "app-icon-maskable.png"
        生成Maskable母版(清单, 标准母版, Maskable母版)

        数量 = 生成应用内品牌导出(清单, 标准母版)
        if 参数.platform in {"ios", "all"}:
            数量 += 生成iOS(清单, 标准母版)
        if 参数.platform in {"android", "all"}:
            数量 += 生成Android(清单, 标准母版, Maskable母版)
        if 参数.platform in {"web", "all"}:
            数量 += 生成Web(清单, 标准母版, Maskable母版)
        if 参数.platform == "all":
            数量 += 生成归档(清单, 标准母版, Maskable母版)
    except (OSError, RuntimeError, KeyError, TypeError, ValueError) as 错误:
        print(f"平台图标生成失败：{错误}")
        return 1
    print(f"平台图标生成完成：{参数.platform}，共写入 {数量} 个文件")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
