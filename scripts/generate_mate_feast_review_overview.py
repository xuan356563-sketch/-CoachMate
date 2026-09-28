#!/usr/bin/env python3
"""由二十张 MATE C-08 动作母图确定性生成审核总览。"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
from pathlib import Path

from PIL import Image

from generate_mate_feast_manifest import 动作名称


项目根目录 = Path(__file__).resolve().parents[1]
素材根目录 = 项目根目录 / "assets/branding/mate-feast-bag-v2"
输出路径 = 素材根目录 / "review/action-overview.png"
画布尺寸 = (1600, 2200)
背景颜色 = "#F5EBD8"
列数 = 4
行数 = 5
横向边距 = 40
纵向边距 = 50
单元间距 = 20


def 解析参数() -> argparse.Namespace:
    解析器 = argparse.ArgumentParser(description=__doc__)
    解析器.add_argument(
        "--check",
        action="store_true",
        help="只读复算审核总览并校验，不改写文件",
    )
    return 解析器.parse_args()


def 生成总览() -> Image.Image:
    可用宽度 = 画布尺寸[0] - 横向边距 * 2 - 单元间距 * (列数 - 1)
    可用高度 = 画布尺寸[1] - 纵向边距 * 2 - 单元间距 * (行数 - 1)
    单元宽度 = 可用宽度 // 列数
    单元高度 = 可用高度 // 行数
    画布 = Image.new("RGBA", 画布尺寸, 背景颜色)

    for 序号, 名称 in enumerate(动作名称):
        路径 = 素材根目录 / f"source/action-masters/{名称}.png"
        if not 路径.is_file():
            raise RuntimeError(f"缺少动作母图：{路径.relative_to(项目根目录)}")
        with Image.open(路径) as 原图:
            原图.load()
            if 原图.mode != "RGBA":
                raise RuntimeError(f"动作母图必须是 RGBA：{名称}")
            边界 = 原图.getchannel("A").getbbox()
            if 边界 is None:
                raise RuntimeError(f"动作母图没有可见内容：{名称}")
            动作图 = 原图.crop(边界)
            动作图.thumbnail(
                (单元宽度 - 30, 单元高度 - 30),
                Image.Resampling.LANCZOS,
            )

        行 = 序号 // 列数
        列 = 序号 % 列数
        单元左侧 = 横向边距 + 列 * (单元宽度 + 单元间距)
        单元顶部 = 纵向边距 + 行 * (单元高度 + 单元间距)
        左侧 = 单元左侧 + (单元宽度 - 动作图.width) // 2
        顶部 = 单元顶部 + (单元高度 - 动作图.height) // 2
        画布.alpha_composite(动作图, (左侧, 顶部))

    return 画布.convert("RGB")


def 预期数据() -> bytes:
    输出 = io.BytesIO()
    生成总览().save(
        输出,
        format="PNG",
        optimize=False,
        compress_level=9,
    )
    return 输出.getvalue()


def main() -> int:
    参数 = 解析参数()
    try:
        数据 = 预期数据()
        if 参数.check:
            if not 输出路径.is_file() or 输出路径.read_bytes() != 数据:
                raise RuntimeError("MATE C-08 审核总览与动作母图不一致")
            状态 = "ok"
        else:
            输出路径.parent.mkdir(parents=True, exist_ok=True)
            输出路径.write_bytes(数据)
            状态 = "generated"
        print(
            json.dumps(
                {
                    "status": 状态,
                    "path": 输出路径.relative_to(项目根目录).as_posix(),
                    "width": 画布尺寸[0],
                    "height": 画布尺寸[1],
                    "sha256": hashlib.sha256(数据).hexdigest(),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    except (OSError, RuntimeError, ValueError) as 错误:
        print(f"MATE C-08 审核总览生成失败：{错误}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
