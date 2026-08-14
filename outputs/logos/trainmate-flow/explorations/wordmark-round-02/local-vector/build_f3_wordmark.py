#!/usr/bin/env python3
"""生成 F3「克制运动软笔」可控本地矢量方向稿。"""

from __future__ import annotations

import math
import subprocess
from pathlib import Path
from xml.sax.saxutils import escape

from fontTools.misc.transform import Transform
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont


HERE = Path(__file__).resolve().parent
SVG_OUTPUT = HERE / "f3-controlled-sport-brush.svg"
PNG_OUTPUT = HERE / "f3-controlled-sport-brush.png"
FONT_PATH = Path(
    "/Users/gaoxiaopang/Library/Fonts/AlibabaPuHuiTi-3-65-Medium.otf"
)

INK = "#19172C"
PAPER = "#FFFDFC"
FORWARD_SHEAR = math.tan(math.radians(5))


def glyph_metrics(font: TTFont, char: str) -> tuple[tuple[float, ...], float]:
    """读取字符边界和字宽。"""
    cmap = font.getBestCmap()
    glyph_name = cmap.get(ord(char))
    if glyph_name is None:
        raise ValueError(f"字体缺少字符：{char}")
    glyph_set = font.getGlyphSet()
    glyph = glyph_set[glyph_name]
    bounds_pen = BoundsPen(glyph_set)
    glyph.draw(bounds_pen)
    if bounds_pen.bounds is None:
        raise ValueError(f"字符没有可用轮廓：{char}")
    advance, _ = font["hmtx"].metrics[glyph_name]
    return bounds_pen.bounds, advance


def transformed_path(font: TTFont, char: str, transform: Transform) -> str:
    """把字符轮廓转换为已经定位的 SVG 路径。"""
    cmap = font.getBestCmap()
    glyph_set = font.getGlyphSet()
    glyph = glyph_set[cmap[ord(char)]]
    svg_pen = SVGPathPen(glyph_set)
    glyph.draw(TransformPen(svg_pen, transform))
    return svg_pen.getCommands()


def fit_forward_glyph(
    font: TTFont,
    char: str,
    box: tuple[float, float, float, float],
) -> str:
    """把单字放入指定区域，并以剪切建立约五度向前笔势。"""
    x0, y0, x1, y1 = box
    (gx0, gy0, gx1, gy1), _ = glyph_metrics(font, char)
    glyph_width = gx1 - gx0
    glyph_height = gy1 - gy0
    scale = min(
        (x1 - x0) / (glyph_width + FORWARD_SHEAR * glyph_height),
        (y1 - y0) / glyph_height,
    )
    visual_width = (glyph_width + FORWARD_SHEAR * glyph_height) * scale
    visual_height = glyph_height * scale
    left = x0 + ((x1 - x0) - visual_width) / 2
    top = y0 + ((y1 - y0) - visual_height) / 2
    transform = Transform(
        scale,
        0,
        FORWARD_SHEAR * scale,
        -scale,
        left - scale * gx0 - FORWARD_SHEAR * scale * gy0,
        top + scale * gy1,
    )
    return transformed_path(font, char, transform)


def transformed_bounds(
    bounds: tuple[float, ...], transform: Transform
) -> tuple[float, float, float, float]:
    """计算变换后的轴对齐边界。"""
    gx0, gy0, gx1, gy1 = bounds
    points = [
        transform.transformPoint(point)
        for point in ((gx0, gy0), (gx0, gy1), (gx1, gy0), (gx1, gy1))
    ]
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return min(xs), min(ys), max(xs), max(ys)


def build_latin_paths(
    font: TTFont,
) -> tuple[list[tuple[str, str]], tuple[float, float, float, float]]:
    """生成断开的运动英文，并只在 n/M 之间保留一个短桥。"""
    text = "TrainMate"
    metrics = [glyph_metrics(font, char) for char in text]
    target_left = 84.0
    target_right = 946.0
    tracking = 7.0
    raw_advance = sum(advance for _, advance in metrics)
    scale_x = (target_right - target_left - tracking * (len(text) - 1)) / raw_advance
    base_scale_y = 0.176
    baseline = 858.0
    baseline_offsets = (0, 2, 3, 0, 2, -2, 3, 0, 2)

    paths: list[tuple[str, str]] = []
    boxes: dict[str, tuple[float, float, float, float]] = {}
    cursor = target_left
    for index, (char, (bounds, advance)) in enumerate(zip(text, metrics)):
        gx0, gy0, _, _ = bounds
        local_scale_y = base_scale_y * (1.055 if char in {"T", "M"} else 1.0)
        local_baseline = baseline + baseline_offsets[index]
        transform = Transform(
            scale_x,
            0,
            FORWARD_SHEAR * local_scale_y,
            -local_scale_y,
            cursor - scale_x * gx0 - FORWARD_SHEAR * local_scale_y * gy0,
            local_baseline + local_scale_y * gy0,
        )
        paths.append((char, transformed_path(font, char, transform)))
        boxes[f"{index}-{char}"] = transformed_bounds(bounds, transform)
        cursor += advance * scale_x + tracking

    n_box = boxes["4-n"]
    m_box = boxes["5-M"]
    bridge = (
        n_box[2] - 5,
        baseline - 34,
        m_box[0] + 6,
        baseline - 43,
    )
    return paths, bridge


def main() -> None:
    if not FONT_PATH.exists():
        raise FileNotFoundError(f"缺少本地字体：{FONT_PATH}")

    font = TTFont(FONT_PATH)
    zhi_path = fit_forward_glyph(font, "智", (102, 150, 486, 610))
    lian_path = fit_forward_glyph(font, "练", (528, 142, 922, 610))
    latin_paths, bridge = build_latin_paths(font)

    latin_svg = "\n".join(
        f'    <path id="glyph-en-{index}" data-char="{escape(char)}" d="{path}" />'
        for index, (char, path) in enumerate(latin_paths)
    )
    bridge_start_x, bridge_start_y, bridge_end_x, bridge_end_y = bridge

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"
  viewBox="0 0 1024 1024" role="img" aria-label="智练 TrainMate">
  <title>智练 TrainMate</title>
  <rect width="1024" height="1024" fill="{PAPER}" />
  <g id="wordmark-zh" fill="{INK}" stroke="{INK}" stroke-width="18"
    stroke-linecap="round" stroke-linejoin="round">
    <path id="glyph-zhi" data-char="智" d="{zhi_path}" />
    <path id="glyph-lian" data-char="练" d="{lian_path}" />
  </g>
  <g id="wordmark-en" fill="{INK}" stroke="{INK}" stroke-width="12"
    stroke-linecap="round" stroke-linejoin="round" aria-label="TrainMate">
{latin_svg}
    <path id="bridge-nM" d="M{bridge_start_x:.2f} {bridge_start_y:.2f}
      Q{(bridge_start_x + bridge_end_x) / 2:.2f} {bridge_start_y - 8:.2f}
      {bridge_end_x:.2f} {bridge_end_y:.2f}" fill="none" stroke="{INK}"
      stroke-width="13" stroke-linecap="round" />
  </g>
</svg>
"""
    SVG_OUTPUT.write_text(svg, encoding="utf-8")
    subprocess.run(
        [
            "/usr/bin/sips",
            "-s",
            "format",
            "png",
            "-z",
            "1024",
            "1024",
            str(SVG_OUTPUT),
            "--out",
            str(PNG_OUTPUT),
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
