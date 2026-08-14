#!/usr/bin/env python3
"""将透明动作角色按固定顺序排成无文字总览图。"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="生成 TrainMate 动作角色总览图")
    parser.add_argument("--input-dir", action="append", required=True, help="输入目录，可重复传入")
    parser.add_argument("--names", nargs="+", required=True, help="按顺序排列的文件名")
    parser.add_argument("--output", required=True, help="输出 PNG 路径")
    parser.add_argument("--columns", type=int, default=5)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--width", type=int, default=1254)
    parser.add_argument("--height", type=int, default=1254)
    parser.add_argument("--cell-padding", type=float, default=0.08)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    expected = args.columns * args.rows
    if len(args.names) != expected:
        raise SystemExit(f"文件数量必须为 {expected}，实际为 {len(args.names)}")

    canvas = Image.new("RGBA", (args.width, args.height), "#FFFDFC")
    cell_width = args.width / args.columns
    cell_height = args.height / args.rows
    pad_x = int(cell_width * args.cell_padding)
    pad_y = int(cell_height * args.cell_padding)

    input_dirs = [Path(value) for value in args.input_dir]
    for index, name in enumerate(args.names):
        source = next((directory / name for directory in input_dirs if (directory / name).is_file()), None)
        if source is None:
            raise SystemExit(f"未找到输入文件：{name}")

        with Image.open(source).convert("RGBA") as image:
            alpha_box = image.getchannel("A").getbbox()
            if alpha_box is None:
                raise SystemExit(f"输入文件没有可见主体：{source}")
            subject = image.crop(alpha_box)
            max_width = max(1, int(cell_width) - pad_x * 2)
            max_height = max(1, int(cell_height) - pad_y * 2)
            subject.thumbnail((max_width, max_height), Image.Resampling.LANCZOS)

            column = index % args.columns
            row = index // args.columns
            left = int(column * cell_width + (cell_width - subject.width) / 2)
            top = int(row * cell_height + (cell_height - subject.height) / 2)
            canvas.alpha_composite(subject, (left, top))

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, format="PNG", optimize=True)
    print(output.resolve())


if __name__ == "__main__":
    main()
