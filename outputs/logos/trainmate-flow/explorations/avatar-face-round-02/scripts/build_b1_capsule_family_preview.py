#!/usr/bin/env python3
"""保留原胶囊几何，生成胶囊内 B1 表情与奋斗飘带品牌家族预览。"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

from build_b1_family_preview import (
    DEEP_INK,
    IVORY,
    PEACH,
    draw_face,
    draw_ribbon_set,
    recolor_reverse_headband,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="生成胶囊内 B1 表情与奋斗飘带品牌家族预览")
    parser.add_argument("--input", required=True, help="含原胶囊的品牌家族 PNG")
    parser.add_argument("--output", required=True, help="修正后的品牌家族 PNG")
    return parser.parse_args()


def erase_round_feature(
    image: Image.Image,
    *,
    center: tuple[int, int],
    radius: int,
    light_surface: bool,
) -> Image.Image:
    """用周围胶囊底色清除旧圆眼，不改胶囊边界。"""

    pixels = np.array(image.convert("RGB"), dtype=np.float64)
    x, y = center
    padding = radius + 9
    x0, x1 = x - padding, x + padding + 1
    y0, y1 = y - padding, y + padding + 1
    local = pixels[y0:y1, x0:x1].copy()

    grid_y, grid_x = np.indices(local.shape[:2])
    local_x = grid_x - padding
    local_y = grid_y - padding
    distance_squared = local_x * local_x + local_y * local_y
    mask = distance_squared <= radius * radius
    boundary = (distance_squared >= (radius + 2) ** 2) & (
        distance_squared <= (radius + 7) ** 2
    )

    if not np.any(boundary):
        raise RuntimeError(f"旧眼位置 {center} 周围没有可用的胶囊底色")

    boundary_pixels = local[boundary]
    luminance = boundary_pixels.mean(axis=1)
    valid = luminance > 200 if light_surface else luminance < 100
    if not np.any(valid):
        raise RuntimeError(f"旧眼位置 {center} 周围没有符合胶囊明暗的底色")

    # 胶囊内部接近纯色。过滤旧眼暗边后取中位色，可避免扩散把旧圆眼残影带回。
    local[mask] = np.median(boundary_pixels[valid], axis=0)

    pixels[y0:y1, x0:x1][mask] = local[mask]
    return Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8), mode="RGB")


def add_b1_faces(image: Image.Image) -> Image.Image:
    """在四处原胶囊内放置同一套 B1 表情。"""

    # 先清除原稿的双圆点眼；胶囊形状、圆角和原始底色保持不变。
    old_eyes = (
        ((308, 364), 21, True),
        ((419, 364), 21, True),
        ((269, 738), 10, True),
        ((320, 738), 10, True),
        ((945, 760), 11, True),
        ((1000, 760), 11, True),
        ((469, 1061), 8, False),
        ((513, 1061), 8, False),
    )
    for center, radius, light_surface in old_eyes:
        image = erase_round_feature(
            image,
            center=center,
            radius=radius,
            light_surface=light_surface,
        )

    image = draw_face(
        image,
        eye_center=(309, 362),
        eye_diameter=18,
        arc=((390, 366), (419, 350), (447, 365)),
        mouth=((350, 424), (366, 430), (382, 422)),
        line_width=9,
        eye_color=DEEP_INK,
        mouth_color=PEACH,
    )
    image = draw_face(
        image,
        eye_center=(269, 737),
        eye_diameter=8,
        arc=((306, 740), (320, 732), (333, 739)),
        mouth=((286, 773), (294, 777), (302, 772)),
        line_width=4,
        eye_color=DEEP_INK,
        mouth_color=PEACH,
    )
    image = draw_face(
        image,
        eye_center=(945, 759),
        eye_diameter=9,
        arc=((985, 762), (1000, 753), (1014, 761)),
        mouth=((963, 796), (972, 801), (981, 795)),
        line_width=4,
        eye_color=DEEP_INK,
        mouth_color=PEACH,
    )
    image = draw_face(
        image,
        eye_center=(469, 1060),
        eye_diameter=7,
        arc=((501, 1062), (512, 1055), (523, 1061)),
        mouth=((484, 1092), (492, 1096), (500, 1091)),
        line_width=3,
        eye_color=IVORY,
        mouth_color=PEACH,
    )
    return image


def add_identity_ribbons(image: Image.Image) -> Image.Image:
    """为四处头像补齐已确认的桃色软结与两条不等长短飘带。"""

    image = draw_ribbon_set(
        image,
        knot_points=(
            (510, 269), (520, 264), (531, 266), (541, 273), (547, 282),
            (546, 292), (539, 302), (529, 307), (518, 304), (509, 298),
            (505, 288), (506, 278),
        ),
        long_tail=((535, 279), (550, 257), (565, 262)),
        short_tail=((536, 293), (546, 302), (553, 311)),
        outer_width=28,
        inner_width=18,
        knot_outline_width=4,
    )
    image = draw_ribbon_set(
        image,
        knot_points=(
            (360, 698), (364, 695), (369, 696), (374, 700), (375, 705),
            (373, 710), (368, 713), (363, 712), (359, 708), (358, 702),
        ),
        long_tail=((369, 699), (380, 685), (390, 689)),
        short_tail=((370, 708), (379, 716), (384, 722)),
        outer_width=12,
        inner_width=8,
        knot_outline_width=2,
    )
    image = draw_ribbon_set(
        image,
        knot_points=(
            (1040, 713), (1045, 709), (1051, 710), (1056, 715), (1057, 721),
            (1054, 727), (1049, 731), (1044, 729), (1040, 725), (1039, 718),
        ),
        long_tail=((1051, 714), (1071, 694), (1088, 698)),
        short_tail=((1052, 725), (1063, 733), (1071, 739)),
        outer_width=16,
        inner_width=10,
        knot_outline_width=2,
    )
    image = recolor_reverse_headband(image)
    image = draw_ribbon_set(
        image,
        knot_points=(
            (546, 1022), (550, 1018), (555, 1020), (559, 1024), (560, 1029),
            (557, 1034), (553, 1037), (548, 1035), (544, 1031), (544, 1025),
        ),
        long_tail=((555, 1021), (565, 1007), (574, 1010)),
        short_tail=((556, 1031), (562, 1038), (566, 1044)),
        outer_width=12,
        inner_width=8,
        knot_outline_width=2,
    )
    return image


def build_preview(source: Path, output: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(f"找不到含原胶囊的品牌家族图：{source}")

    image = Image.open(source).convert("RGB")
    if image.size != (1254, 1254):
        raise ValueError(
            f"品牌家族图尺寸应为 1254×1254，实际为 {image.size[0]}×{image.size[1]}"
        )

    image = add_b1_faces(image)
    image = add_identity_ribbons(image)

    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, format="PNG", optimize=True)


def main() -> None:
    args = parse_args()
    build_preview(Path(args.input), Path(args.output))


if __name__ == "__main__":
    main()
