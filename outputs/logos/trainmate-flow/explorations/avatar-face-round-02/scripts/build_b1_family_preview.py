#!/usr/bin/env python3
"""在不重绘文字与版式的前提下，生成 B1 无面罩品牌家族预览。"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


DEEP_INK = (25, 23, 44)
PEACH = (255, 178, 125)
IVORY = (255, 253, 252)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="生成 B1 无面罩品牌家族预览")
    parser.add_argument("--input", required=True, help="原始品牌家族 PNG")
    parser.add_argument("--output", required=True, help="新预览 PNG")
    return parser.parse_args()


def rounded_mask(size: tuple[int, int], box: tuple[int, int, int, int], radius: int) -> Image.Image:
    """用高分辨率绘制带轻微羽化的圆角遮罩。"""

    scale = 4
    width, height = size
    mask = Image.new("L", (width * scale, height * scale), 0)
    draw = ImageDraw.Draw(mask)
    scaled_box = tuple(value * scale for value in box)
    draw.rounded_rectangle(scaled_box, radius=radius * scale, fill=255)
    mask = mask.resize(size, Image.Resampling.LANCZOS)
    return mask.filter(ImageFilter.GaussianBlur(1.5))


def fit_surface(
    pixels: np.ndarray,
    box: tuple[int, int, int, int],
    *,
    light_surface: bool,
) -> np.ndarray:
    """按每一行左右两侧的原头像颜色插值，恢复连续底色。"""

    height, width, _ = pixels.shape
    x0, y0, x1, y1 = box
    patch_width = x1 - x0
    patch_height = y1 - y0
    patch = np.zeros((patch_height, patch_width, 3), dtype=np.float64)

    def valid(sample: np.ndarray) -> np.ndarray:
        luminance = sample.mean(axis=1)
        saturation = sample.max(axis=1) - sample.min(axis=1)
        if light_surface:
            return (luminance > 205) & (saturation < 45)
        return luminance < 95

    def sample_side(y: int, start: int, end: int) -> np.ndarray:
        for offset in (0, -1, 1, -2, 2, -3, 3, -5, 5, -8, 8):
            row = min(height - 1, max(0, y + offset))
            sample = pixels[row, max(0, start) : min(width, end)].astype(np.float64)
            if sample.size == 0:
                continue
            selected = sample[valid(sample)]
            if selected.shape[0] >= 2:
                return np.median(selected, axis=0)
        raise RuntimeError(f"面罩区域 {box} 的第 {y} 行没有可用底色样本")

    blend = np.linspace(0.0, 1.0, patch_width, dtype=np.float64)[:, None]
    for index, y in enumerate(range(y0, y1)):
        left = sample_side(y, x0 - 18, x0 - 3)
        right = sample_side(y, x1 + 3, x1 + 18)
        patch[index] = left * (1.0 - blend) + right * blend

    return np.clip(patch, 0, 255).astype(np.uint8)


def restore_surface(
    image: Image.Image,
    box: tuple[int, int, int, int],
    *,
    radius: int,
    light_surface: bool,
) -> Image.Image:
    """清除胶囊，并以边界约束的扩散补色消除矩形接缝。"""

    pixels = np.array(image.convert("RGB"))
    patch = fit_surface(pixels, box, light_surface=light_surface)
    mask_image = rounded_mask(image.size, box, radius)
    mask = np.array(mask_image) > 128

    x0, y0, x1, y1 = box
    cx0, cy0 = max(0, x0 - 3), max(0, y0 - 3)
    cx1, cy1 = min(image.width, x1 + 3), min(image.height, y1 + 3)
    local = pixels[cy0:cy1, cx0:cx1].astype(np.float64)
    local_mask = mask[cy0:cy1, cx0:cx1]
    local_y0, local_y1 = y0 - cy0, y1 - cy0
    local_x0, local_x1 = x0 - cx0, x1 - cx0
    local[local_y0:local_y1, local_x0:local_x1] = patch

    # 小尺寸头像的面罩紧贴桃色头带；用深墨补色作为求解边界，
    # 避免桃色向脸部扩散成棕色高光。边界不写回最终图像。
    if not light_surface:
        local[local_y0 - 1, local_x0:local_x1] = patch[0]
        local[local_y1, local_x0:local_x1] = patch[-1]
        local[local_y0:local_y1, local_x0 - 1] = patch[:, 0]
        local[local_y0:local_y1, local_x1] = patch[:, -1]

    inner_mask = local_mask[1:-1, 1:-1]
    grid_y, grid_x = np.indices(inner_mask.shape)
    checker = (grid_x + grid_y) % 2
    center = local[1:-1, 1:-1]
    relaxation = 1.72

    for _ in range(260):
        for parity in (0, 1):
            average = (
                local[:-2, 1:-1]
                + local[2:, 1:-1]
                + local[1:-1, :-2]
                + local[1:-1, 2:]
            ) / 4.0
            selected = inner_mask & (checker == parity)
            center[selected] = (
                (1.0 - relaxation) * center[selected]
                + relaxation * average[selected]
            )

    restored = pixels.copy()
    local_uint8 = np.clip(local, 0, 255).astype(np.uint8)
    restored[cy0:cy1, cx0:cx1][local_mask] = local_uint8[local_mask]
    return Image.composite(Image.fromarray(restored), image, mask_image)


def draw_quadratic(
    draw: ImageDraw.ImageDraw,
    start: tuple[float, float],
    control: tuple[float, float],
    end: tuple[float, float],
    *,
    fill: tuple[int, int, int, int],
    width: int,
    scale: int,
) -> None:
    """绘制圆头二次贝塞尔曲线。"""

    points: list[tuple[int, int]] = []
    for index in range(65):
        t = index / 64
        inverse = 1 - t
        x = inverse * inverse * start[0] + 2 * inverse * t * control[0] + t * t * end[0]
        y = inverse * inverse * start[1] + 2 * inverse * t * control[1] + t * t * end[1]
        points.append((round(x * scale), round(y * scale)))

    stroke = width * scale
    draw.line(points, fill=fill, width=stroke, joint="curve")
    radius = stroke // 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


def draw_face(
    image: Image.Image,
    *,
    eye_center: tuple[int, int],
    eye_diameter: int,
    arc: tuple[tuple[int, int], tuple[int, int], tuple[int, int]],
    mouth: tuple[tuple[int, int], tuple[int, int], tuple[int, int]],
    line_width: int,
    eye_color: tuple[int, int, int],
    mouth_color: tuple[int, int, int],
) -> Image.Image:
    """绘制 B1 的眼点、弯眼和短嘴。"""

    scale = 4
    overlay = Image.new("RGBA", (image.width * scale, image.height * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    cx, cy = eye_center
    radius = eye_diameter * scale // 2
    draw.ellipse(
        (
            cx * scale - radius,
            cy * scale - radius,
            cx * scale + radius,
            cy * scale + radius,
        ),
        fill=(*eye_color, 255),
    )
    draw_quadratic(
        draw,
        arc[0],
        arc[1],
        arc[2],
        fill=(*eye_color, 255),
        width=line_width,
        scale=scale,
    )
    draw_quadratic(
        draw,
        mouth[0],
        mouth[1],
        mouth[2],
        fill=(*mouth_color, 255),
        width=line_width,
        scale=scale,
    )
    overlay = overlay.resize(image.size, Image.Resampling.LANCZOS)
    return Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")


def draw_ribbon_set(
    image: Image.Image,
    *,
    knot_points: tuple[tuple[int, int], ...],
    long_tail: tuple[tuple[int, int], tuple[int, int], tuple[int, int]],
    short_tail: tuple[tuple[int, int], tuple[int, int], tuple[int, int]],
    outer_width: int,
    inner_width: int,
    knot_outline_width: int,
) -> Image.Image:
    """按正式角色语法绘制右侧软结和两条不等长短飘带。"""

    scale = 4
    overlay = Image.new("RGBA", (image.width * scale, image.height * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    # 双尾先画，软结最后覆盖连接处，避免缩小时粘成单块桃色图形。
    for tail in (long_tail, short_tail):
        draw_quadratic(
            draw,
            tail[0],
            tail[1],
            tail[2],
            fill=(*DEEP_INK, 255),
            width=outer_width,
            scale=scale,
        )
        draw_quadratic(
            draw,
            tail[0],
            tail[1],
            tail[2],
            fill=(*PEACH, 255),
            width=inner_width,
            scale=scale,
        )

    scaled_points = [(x * scale, y * scale) for x, y in knot_points]
    draw.polygon(scaled_points, fill=(*PEACH, 255))
    draw.line(
        [*scaled_points, scaled_points[0]],
        fill=(*DEEP_INK, 255),
        width=knot_outline_width * scale,
        joint="curve",
    )

    overlay = overlay.resize(image.size, Image.Resampling.LANCZOS)
    return Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")


def recolor_reverse_headband(image: Image.Image) -> Image.Image:
    """把反白组合的深色适配带恢复为桃色奋斗头带。"""

    scale = 4
    overlay = Image.new("RGBA", (image.width * scale, image.height * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.rounded_rectangle(
        (430 * scale, 1016 * scale, 543 * scale, 1046 * scale),
        radius=15 * scale,
        fill=(*PEACH, 255),
        outline=(*DEEP_INK, 255),
        width=3 * scale,
    )
    overlay = overlay.resize(image.size, Image.Resampling.LANCZOS)
    return Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")


def build_preview(source: Path, output: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(f"找不到原始品牌家族图：{source}")

    image = Image.open(source).convert("RGB")
    if image.size != (1254, 1254):
        raise ValueError(f"品牌家族图尺寸应为 1254×1254，实际为 {image.size[0]}×{image.size[1]}")

    # 只覆盖旧胶囊所在区域，避免触碰字标、头像外轮廓与版式。
    image = restore_surface(image, (229, 314, 499, 413), radius=49, light_surface=False)
    image = restore_surface(image, (228, 711, 361, 768), radius=29, light_surface=False)
    image = restore_surface(image, (901, 732, 1045, 791), radius=31, light_surface=False)
    image = restore_surface(image, (435, 1038, 548, 1086), radius=24, light_surface=True)

    image = draw_face(
        image,
        eye_center=(306, 363),
        eye_diameter=24,
        arc=((388, 370), (421, 348), (453, 365)),
        mouth=((394, 414), (417, 416), (443, 404)),
        line_width=11,
        eye_color=IVORY,
        mouth_color=PEACH,
    )
    image = draw_face(
        image,
        eye_center=(263, 743),
        eye_diameter=12,
        arc=((299, 747), (315, 735), (332, 744)),
        mouth=((302, 775), (313, 777), (326, 770)),
        line_width=6,
        eye_color=IVORY,
        mouth_color=PEACH,
    )
    image = draw_face(
        image,
        eye_center=(929, 760),
        eye_diameter=14,
        arc=((973, 764), (992, 749), (1013, 760)),
        mouth=((977, 796), (992, 798), (1008, 789)),
        line_width=7,
        eye_color=IVORY,
        mouth_color=PEACH,
    )
    image = draw_face(
        image,
        eye_center=(465, 1055),
        eye_diameter=12,
        arc=((497, 1060), (514, 1049), (532, 1057)),
        mouth=((499, 1090), (512, 1092), (526, 1084)),
        line_width=6,
        eye_color=DEEP_INK,
        mouth_color=PEACH,
    )

    # 角色身份元素：四处都保留桃色奋斗头带、软结和双短飘带。
    # 尾端坐标经过字标与图标安全区检查，不移动任何头像或文字。
    image = draw_ribbon_set(
        image,
        knot_points=((510, 269), (520, 264), (531, 266), (541, 273), (547, 282),
                     (546, 292), (539, 302), (529, 307), (518, 304), (509, 298),
                     (505, 288), (506, 278)),
        long_tail=((535, 279), (550, 257), (565, 262)),
        short_tail=((536, 293), (546, 302), (553, 311)),
        outer_width=28,
        inner_width=18,
        knot_outline_width=4,
    )
    image = draw_ribbon_set(
        image,
        knot_points=((360, 698), (364, 695), (369, 696), (374, 700), (375, 705),
                     (373, 710), (368, 713), (363, 712), (359, 708), (358, 702)),
        long_tail=((369, 699), (380, 685), (390, 689)),
        short_tail=((370, 708), (379, 716), (384, 722)),
        outer_width=12,
        inner_width=8,
        knot_outline_width=2,
    )
    image = draw_ribbon_set(
        image,
        knot_points=((1040, 713), (1045, 709), (1051, 710), (1056, 715), (1057, 721),
                     (1054, 727), (1049, 731), (1044, 729), (1040, 725), (1039, 718)),
        long_tail=((1051, 714), (1071, 694), (1088, 698)),
        short_tail=((1052, 725), (1063, 733), (1071, 739)),
        outer_width=16,
        inner_width=10,
        knot_outline_width=2,
    )
    image = recolor_reverse_headband(image)
    image = draw_ribbon_set(
        image,
        knot_points=((546, 1022), (550, 1018), (555, 1020), (559, 1024), (560, 1029),
                     (557, 1034), (553, 1037), (548, 1035), (544, 1031), (544, 1025)),
        long_tail=((555, 1021), (565, 1007), (574, 1010)),
        short_tail=((556, 1031), (562, 1038), (566, 1044)),
        outer_width=12,
        inner_width=8,
        knot_outline_width=2,
    )

    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, format="PNG", optimize=True)


def main() -> None:
    args = parse_args()
    build_preview(Path(args.input), Path(args.output))


if __name__ == "__main__":
    main()
