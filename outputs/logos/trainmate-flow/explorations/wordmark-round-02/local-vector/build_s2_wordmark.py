#!/usr/bin/env python3
"""生成 S2「横桥负空间」可控本地矢量方向稿。"""

from __future__ import annotations

from pathlib import Path
from xml.sax.saxutils import escape

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.misc.transform import Transform


HERE = Path(__file__).resolve().parent
OUTPUT = HERE / "s2-horizontal-negative-space.svg"
FONT_PATH = Path(
    "/Users/gaoxiaopang/Library/Fonts/AlibabaPuHuiTi-3-105-Heavy.otf"
)

INK = "#19172C"
PAPER = "#FFFDFC"


def glyph_metrics(font: TTFont, char: str) -> tuple[str, tuple[float, ...], float]:
    """读取单字轮廓、边界与字宽。"""
    cmap = font.getBestCmap()
    glyph_name = cmap[ord(char)]
    glyph_set = font.getGlyphSet()
    glyph = glyph_set[glyph_name]

    bounds_pen = BoundsPen(glyph_set)
    glyph.draw(bounds_pen)
    if bounds_pen.bounds is None:
        raise ValueError(f"字符没有可用轮廓：{char}")

    advance, _ = font["hmtx"].metrics[glyph_name]
    return glyph_name, bounds_pen.bounds, advance


def transformed_glyph_path(
    font: TTFont,
    char: str,
    transform: Transform,
) -> str:
    """把字体轮廓转换为已经定位的 SVG 路径。"""
    cmap = font.getBestCmap()
    glyph_set = font.getGlyphSet()
    glyph = glyph_set[cmap[ord(char)]]
    svg_pen = SVGPathPen(glyph_set)
    transform_pen = TransformPen(svg_pen, transform)
    glyph.draw(transform_pen)
    return svg_pen.getCommands()


def fit_glyph(
    font: TTFont,
    char: str,
    box: tuple[float, float, float, float],
) -> str:
    """将单字等比放入指定区域，并把坐标翻转为 SVG 方向。"""
    x0, y0, x1, y1 = box
    _, (gx0, gy0, gx1, gy1), _ = glyph_metrics(font, char)
    scale = min((x1 - x0) / (gx1 - gx0), (y1 - y0) / (gy1 - gy0))
    width = (gx1 - gx0) * scale
    height = (gy1 - gy0) * scale
    left = x0 + ((x1 - x0) - width) / 2
    top = y0 + ((y1 - y0) - height) / 2
    transform = Transform(
        scale,
        0,
        0,
        -scale,
        left - gx0 * scale,
        top + gy1 * scale,
    )
    return transformed_glyph_path(font, char, transform)


def build_latin_paths(font: TTFont) -> list[tuple[str, str]]:
    """把 TrainMate 排成同源、略宽的结构化英文基座。"""
    text = "TrainMate"
    tracking = 34
    metrics = [glyph_metrics(font, char) for char in text]
    raw_width = sum(metric[2] for metric in metrics) + tracking * (len(text) - 1)
    target_left = 145
    target_right = 879
    scale_x = (target_right - target_left) / raw_width
    scale_y = 0.155
    baseline = 842

    cursor = target_left
    paths: list[tuple[str, str]] = []
    for index, (char, (_, bounds, advance)) in enumerate(zip(text, metrics)):
        gx0, _, _, _ = bounds
        # T、M 稍高，圆形小写略压扁，形成同一套横向结构节奏。
        local_scale_y = scale_y * (1.035 if char in {"T", "M"} else 0.98)
        local_baseline = baseline + (2 if index in {2, 7} else 0)
        transform = Transform(
            scale_x,
            0,
            0,
            -local_scale_y,
            cursor - gx0 * scale_x,
            local_baseline,
        )
        paths.append((char, transformed_glyph_path(font, char, transform)))
        cursor += (advance + tracking) * scale_x
    return paths


def main() -> None:
    if not FONT_PATH.exists():
        raise FileNotFoundError(f"缺少本地字体：{FONT_PATH}")

    font = TTFont(FONT_PATH)
    zhi_path = fit_glyph(font, "智", (104, 174, 473, 610))
    lian_path = fit_glyph(font, "练", (551, 174, 920, 610))
    latin_paths = build_latin_paths(font)

    # 每一段白槽都被限制在各自汉字轮廓内；中间 78px 始终为空。
    slot_levels = (326, 438, 536)
    left_slots = "\n".join(
        f'    <path d="M126 {y} H451" />' for y in slot_levels
    )
    right_slots = "\n".join(
        f'    <path d="M573 {y} H898" />' for y in slot_levels
    )
    latin_svg = "\n".join(
        f'    <path id="glyph-en-{index}" data-char="{escape(char)}" d="{path}" />'
        for index, (char, path) in enumerate(latin_paths)
    )

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"
  viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">
  <title id="title">智练 TrainMate S2 横桥负空间方向稿</title>
  <desc id="desc">智和练各自独立，视觉桥梁只由字内同高度横画与白槽形成。</desc>
  <rect width="1024" height="1024" fill="{PAPER}" />
  <defs>
    <clipPath id="clip-zhi" clipPathUnits="userSpaceOnUse">
      <path d="{zhi_path}" />
    </clipPath>
    <clipPath id="clip-lian" clipPathUnits="userSpaceOnUse">
      <path d="{lian_path}" />
    </clipPath>
  </defs>
  <g id="wordmark-zh" fill="{INK}" stroke="{INK}" stroke-width="15"
    stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke">
    <path id="glyph-zhi" data-char="智" d="{zhi_path}" />
    <path id="glyph-lian" data-char="练" d="{lian_path}" />
  </g>
  <g id="slots-zhi" clip-path="url(#clip-zhi)" fill="none" stroke="{PAPER}"
    stroke-width="13" stroke-linecap="round">
{left_slots}
  </g>
  <g id="slots-lian" clip-path="url(#clip-lian)" fill="none" stroke="{PAPER}"
    stroke-width="13" stroke-linecap="round">
{right_slots}
  </g>
  <g id="wordmark-en" fill="{INK}" stroke="{INK}" stroke-width="4"
    stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"
    aria-label="TrainMate">
{latin_svg}
  </g>
</svg>
"""
    OUTPUT.write_text(svg, encoding="utf-8")


if __name__ == "__main__":
    main()
