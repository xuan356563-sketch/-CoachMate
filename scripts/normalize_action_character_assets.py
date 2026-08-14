#!/usr/bin/env python3
"""从两套 1254px 原稿确定性生成视觉尺度统一的 512px App 人物。"""

from __future__ import annotations

import argparse
import json
import math
from collections import deque
from pathlib import Path
from statistics import median

from PIL import Image, ImageChops, ImageFilter


仓库根目录 = Path(__file__).resolve().parents[1]
画布边长 = 512
透明阈值 = 8
形态学滤镜边长 = 15
主体最大边长 = 432

原稿目录 = {
    "navy": 仓库根目录 / "outputs/logos/trainmate-flow/action-set-20/individual",
    "peach-light": 仓库根目录
    / "outputs/logos/trainmate-flow/action-set-20-peach-light/individual",
}
输出根目录 = 仓库根目录 / "assets/branding/action-characters"


def 解析参数() -> argparse.Namespace:
    解析器 = argparse.ArgumentParser(description=__doc__)
    解析器.add_argument(
        "--check",
        action="store_true",
        help="只校验现有 App 人物，不写入文件",
    )
    return 解析器.parse_args()


def 动作文件名() -> list[str]:
    文件集合 = {
        变体: sorted(
            路径.name for 路径 in 目录.glob("*.png") if not 路径.name.startswith(".")
        )
        for 变体, 目录 in 原稿目录.items()
    }
    if any(len(文件名) != 20 for 文件名 in 文件集合.values()):
        raise RuntimeError("两套原稿都必须恰好包含 20 张 PNG")
    if 文件集合["navy"] != 文件集合["peach-light"]:
        raise RuntimeError("两套原稿的文件名必须一一对应")
    return 文件集合["navy"]


def 读取为分析图(路径: Path) -> Image.Image:
    with Image.open(路径) as 图像:
        图像.load()
        if 图像.size != (1254, 1254) or 图像.mode != "RGBA":
            raise RuntimeError(f"原稿必须是 1254×1254 RGBA PNG：{路径}")
        return 图像.resize((画布边长, 画布边长), Image.Resampling.LANCZOS)


def 可见蒙版(图像: Image.Image) -> Image.Image:
    return 图像.getchannel("A").point(
        lambda 值: 255 if 值 > 透明阈值 else 0,
        mode="L",
    )


def 最大连通区域面积(蒙版: Image.Image) -> int:
    宽度, 高度 = 蒙版.size
    像素 = 蒙版.tobytes()
    已访问 = bytearray(宽度 * 高度)
    最大面积 = 0
    for 起点, 值 in enumerate(像素):
        if 值 == 0 or 已访问[起点]:
            continue
        已访问[起点] = 1
        队列: deque[int] = deque([起点])
        面积 = 0
        while 队列:
            索引 = 队列.popleft()
            面积 += 1
            横坐标 = 索引 % 宽度
            纵坐标 = 索引 // 宽度
            for 相邻 in (
                索引 - 1 if 横坐标 > 0 else -1,
                索引 + 1 if 横坐标 + 1 < 宽度 else -1,
                索引 - 宽度 if 纵坐标 > 0 else -1,
                索引 + 宽度 if 纵坐标 + 1 < 高度 else -1,
            ):
                if 相邻 >= 0 and 像素[相邻] and not 已访问[相邻]:
                    已访问[相邻] = 1
                    队列.append(相邻)
        最大面积 = max(最大面积, 面积)
    return 最大面积


def 测量动作(文件名: str) -> dict[str, object]:
    图像组 = [读取为分析图(原稿目录[变体] / 文件名) for 变体 in 原稿目录]
    蒙版 = ImageChops.lighter(可见蒙版(图像组[0]), 可见蒙版(图像组[1]))
    外接框 = 蒙版.getbbox()
    if 外接框 is None:
        raise RuntimeError(f"原稿缺少可见主体：{文件名}")
    打开后蒙版 = 蒙版.filter(
        ImageFilter.MinFilter(形态学滤镜边长)
    ).filter(ImageFilter.MaxFilter(形态学滤镜边长))
    身体面积 = 最大连通区域面积(打开后蒙版)
    if 身体面积 <= 0:
        raise RuntimeError(f"无法识别角色身体：{文件名}")
    return {"bbox": 外接框, "bodyArea": 身体面积}


def 原稿裁切框(分析外接框: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    比例 = 1254 / 画布边长
    左, 上, 右, 下 = 分析外接框
    return (
        max(0, math.floor(左 * 比例)),
        max(0, math.floor(上 * 比例)),
        min(1254, math.ceil(右 * 比例)),
        min(1254, math.ceil(下 * 比例)),
    )


def 生成单图(
    源路径: Path,
    输出路径: Path,
    分析外接框: tuple[int, int, int, int],
    缩放: float,
) -> None:
    左, 上, 右, 下 = 分析外接框
    目标宽度 = max(1, round((右 - 左) * 缩放))
    目标高度 = max(1, round((下 - 上) * 缩放))
    with Image.open(源路径) as 原图:
        原图.load()
        主体 = 原图.convert("RGBA").crop(原稿裁切框(分析外接框))
        主体 = 主体.resize((目标宽度, 目标高度), Image.Resampling.LANCZOS)
    画布 = Image.new("RGBA", (画布边长, 画布边长), (0, 0, 0, 0))
    偏移 = ((画布边长 - 目标宽度) // 2, (画布边长 - 目标高度) // 2)
    画布.alpha_composite(主体, 偏移)
    可见外接框 = 可见蒙版(画布).getbbox()
    if 可见外接框 is None:
        raise RuntimeError(f"生成后缺少可见主体：{源路径}")
    可见主体 = 画布.crop(可见外接框)
    画布 = Image.new("RGBA", (画布边长, 画布边长), (0, 0, 0, 0))
    居中偏移 = (
        (画布边长 - 可见主体.width) // 2,
        (画布边长 - 可见主体.height) // 2,
    )
    画布.alpha_composite(可见主体, 居中偏移)
    输出路径.parent.mkdir(parents=True, exist_ok=True)
    临时路径 = 输出路径.with_name(f".{输出路径.name}.tmp.png")
    画布.save(临时路径, format="PNG", optimize=True)
    临时路径.replace(输出路径)


def 输出外接框(路径: Path) -> tuple[int, int, int, int]:
    with Image.open(路径) as 图像:
        图像.load()
        if 图像.size != (画布边长, 画布边长) or 图像.mode != "RGBA":
            raise RuntimeError(f"App 人物必须是 512×512 RGBA PNG：{路径}")
        外接框 = 可见蒙版(图像).getbbox()
    if 外接框 is None:
        raise RuntimeError(f"App 人物缺少可见主体：{路径}")
    return 外接框


def 校验输出(文件名组: list[str]) -> dict[str, object]:
    最大中心偏差 = 0.0
    最大可见边长 = 0
    for 变体 in 原稿目录:
        输出目录 = 输出根目录 / 变体
        实际文件 = sorted(
            路径.name
            for 路径 in 输出目录.glob("*.png")
            if not 路径.name.startswith(".")
        )
        if 实际文件 != 文件名组:
            raise RuntimeError(f"{变体} App 人物文件数量或名称不正确")
        for 文件名 in 文件名组:
            左, 上, 右, 下 = 输出外接框(输出目录 / 文件名)
            中心偏差 = max(abs((左 + 右) / 2 - 256), abs((上 + 下) / 2 - 256))
            可见边长 = max(右 - 左, 下 - 上)
            最大中心偏差 = max(最大中心偏差, 中心偏差)
            最大可见边长 = max(最大可见边长, 可见边长)
            if 中心偏差 > 2:
                raise RuntimeError(f"人物视觉中心偏移超过 2px：{变体}/{文件名}")
            if 可见边长 > 主体最大边长 + 2:
                raise RuntimeError(f"人物超出统一安全区：{变体}/{文件名}")
    return {
        "files": len(文件名组) * len(原稿目录),
        "maxCenterOffset": 最大中心偏差,
        "maxSubjectEdge": 最大可见边长,
    }


def 清理输出元数据() -> None:
    """移除挂载盘生成的 AppleDouble 文件，避免被 Flutter 当作图片资源。"""
    for 变体 in 原稿目录:
        for 路径 in (输出根目录 / 变体).glob("._*"):
            if 路径.is_file():
                路径.unlink()


def 主函数() -> int:
    参数 = 解析参数()
    文件名组 = 动作文件名()
    if 参数.check:
        print(json.dumps(校验输出(文件名组), ensure_ascii=False, indent=2))
        return 0

    测量结果 = {文件名: 测量动作(文件名) for 文件名 in 文件名组}
    目标身体面积 = median(
        int(结果["bodyArea"]) for 结果 in 测量结果.values()
    )
    受安全区限制: list[str] = []
    for 文件名, 结果 in 测量结果.items():
        外接框 = 结果["bbox"]
        assert isinstance(外接框, tuple)
        身体缩放 = math.sqrt(目标身体面积 / int(结果["bodyArea"]))
        宽度 = 外接框[2] - 外接框[0]
        高度 = 外接框[3] - 外接框[1]
        安全区缩放 = 主体最大边长 / max(宽度, 高度)
        最终缩放 = min(身体缩放, 安全区缩放)
        if 最终缩放 < 身体缩放:
            受安全区限制.append(文件名)
        for 变体, 目录 in 原稿目录.items():
            生成单图(
                目录 / 文件名,
                输出根目录 / 变体 / 文件名,
                外接框,
                最终缩放,
            )

    清理输出元数据()
    报告 = 校验输出(文件名组)
    报告["targetBodyArea"] = 目标身体面积
    报告["fitLimitedActions"] = 受安全区限制
    print(json.dumps(报告, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(主函数())
