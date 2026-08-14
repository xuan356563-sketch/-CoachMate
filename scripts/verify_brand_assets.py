#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

try:
    from PIL import Image, ImageChops, ImageStat
except ImportError:
    Image = None
    ImageChops = None
    ImageStat = None


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST_PATH = Path(__file__).with_name("brand_assets_manifest.json")
MARKETING_TEXTURE = "trainmate-flow-marketing-texture.svg"
FINAL_LOGO_FILE = "trainmate-flow-logo-final-20260717.png"
FINAL_LOGO_SHA256 = "8370687c15f3ffa5c131906853ceb845e87ee9b052c759abafc9cd8a2492d365"
FINAL_LOGO_SIZE = (1254, 1254)
FINAL_LOGO_MODE = "RGB"
PILLOW_ERROR = (
    "缺少本机图像校验工具 Pillow；请先恢复已安装环境，不要自动修改项目依赖。"
)

ALLOWED_COLORS = {
    "#19172C",
    "#11101F",
    "#FFFDFC",
    "#FFB27D",
    "#FFE2B8",
}
EXPECTED_COLORS = {
    "ink": "#19172C",
    "deepInk": "#11101F",
    "paper": "#FFFDFC",
    "peach": "#FFB27D",
    "peachLight": "#FFE2B8",
}
APP_ICON_ALLOWED_COLORS = frozenset(ALLOWED_COLORS)
APP_ICON_BACKGROUND_COLOR = EXPECTED_COLORS["peachLight"]
APP_ICON_HEADBAND_GRADIENT_COLORS = ("#EAA93A", "#C65F14")
APP_ICON_MOUTH_COLOR = EXPECTED_COLORS["peach"]
EXPECTED_SOURCE_KINDS = {
    "trainmate-flow-brandmark.svg": "brandmark",
    "trainmate-flow-brandmark-small.svg": "brandmark-small",
    "trainmate-flow-brandmark-reverse.svg": "brandmark",
    "trainmate-flow-brandmark-mono.svg": "brandmark",
    "trainmate-flow-character.svg": "character",
    "trainmate-flow-wordmark.svg": "formal",
    "trainmate-flow-wordmark-horizontal.svg": "formal",
    "trainmate-flow-lockup.svg": "lockup",
    "trainmate-flow-character-lockup.svg": "character",
    "trainmate-flow-submark.svg": "formal",
    "trainmate-flow-app-icon.svg": "app-icon",
    "trainmate-flow-app-icon-maskable.svg": "app-icon-maskable",
}
EXPECTED_FORMAL_SOURCES = set(EXPECTED_SOURCE_KINDS)
EXPECTED_EXPORT_SIZES = [16, 24, 32, 48, 64, 128, 256, 512, 1024]
EXPECTED_CHARACTER_SIZES = [96, 128, 256, 512, 1024]

STANDARD_BRANDMARK_IDS = {
    "flow-head",
    "training-headband",
    "headband-knot",
    "ribbon-long",
    "ribbon-short",
    "ai-visor",
    "face-eye-dot",
    "face-eye-arc",
    "face-mouth",
}
SMALL_BRANDMARK_IDS = STANDARD_BRANDMARK_IDS - {"face-mouth"}
APP_ICON_IDS = {
    "flow-head",
    "training-headband",
    "headband-knot",
    "ribbon-long",
    "ribbon-short",
    "face-capsule",
    "face-eye-dot",
    "face-eye-arc",
    "face-mouth",
}
APP_ICON_FORBIDDEN_IDS = {
    "arm-left",
    "arm-right",
    "leg-left",
    "leg-right",
    "hand-left",
    "hand-right",
    "foot-left",
    "foot-right",
}
APP_ICON_GRADIENT_IDS = {
    "icon-background-gradient",
    "flow-body-gradient",
    "headband-gradient",
}
CHARACTER_IDS = SMALL_BRANDMARK_IDS | {
    "arm-left",
    "arm-right",
    "leg-left",
    "leg-right",
    "face-mouth",
}
EXPECTED_MOTION_TRANSFORMS = {
    "trainmate-flow-brandmark.svg": {
        "flow-avatar": "translate(-48 0) rotate(5 512 540)",
    },
    "trainmate-flow-brandmark-small.svg": {
        "flow-avatar-small": "translate(-56 0) rotate(3 512 540)",
    },
    "trainmate-flow-brandmark-reverse.svg": {
        "flow-avatar": "translate(-48 0) rotate(5 512 540)",
    },
    "trainmate-flow-brandmark-mono.svg": {
        "flow-avatar": "translate(-48 0) rotate(5 512 540)",
    },
    "trainmate-flow-character.svg": {
        "flow-character": "rotate(5 512 540)",
    },
    "trainmate-flow-wordmark.svg": {
        "glyph-zhi-position": (
            "translate(273.32 102.65) scale(.4225 .406) "
            "matrix(1 0 -0.08749 1 44.18 0)"
        ),
        "glyph-lian-position": (
            "translate(430.34 100.22) scale(.4154 .413) "
            "matrix(1 0 -0.08749 1 44.18 0)"
        ),
        "wordmark-en-position": "translate(140 -14) scale(.797)",
        "wordmark-en": "matrix(1 0 -0.12278 1 77.83 0) translate(-54 2)",
    },
    "trainmate-flow-wordmark-horizontal.svg": {
        "glyph-zhi-position": (
            "translate(61.32 168.65) scale(.4225 .406) "
            "matrix(1 0 -0.08749 1 44.18 0)"
        ),
        "glyph-lian-position": (
            "translate(171.34 166.22) scale(.4154 .413) "
            "matrix(1 0 -0.08749 1 44.18 0)"
        ),
        "wordmark-en-position": "translate(577 -127) scale(.797)",
        "wordmark-en": "matrix(1 0 -0.12278 1 77.83 0) translate(-54 2)",
    },
    "trainmate-flow-lockup.svg": {
        "flow-avatar": "rotate(5 512 540)",
        "wordmark-lockup-horizontal": "translate(830 173) scale(.95)",
        "glyph-zhi-position": (
            "translate(61.32 168.65) scale(.4225 .406) "
            "matrix(1 0 -0.08749 1 44.18 0)"
        ),
        "glyph-lian-position": (
            "translate(171.34 166.22) scale(.4154 .413) "
            "matrix(1 0 -0.08749 1 44.18 0)"
        ),
        "wordmark-en-position": "translate(577 -127) scale(.797)",
        "wordmark-en": "matrix(1 0 -0.12278 1 77.83 0) translate(-54 2)",
    },
    "trainmate-flow-character-lockup.svg": {
        "flow-character": "rotate(5 512 540)",
        "wordmark-lockup-vertical": "translate(1220 145) scale(1.05)",
        "glyph-zhi-position": (
            "translate(273.32 102.65) scale(.4225 .406) "
            "matrix(1 0 -0.08749 1 44.18 0)"
        ),
        "glyph-lian-position": (
            "translate(430.34 100.22) scale(.4154 .413) "
            "matrix(1 0 -0.08749 1 44.18 0)"
        ),
        "wordmark-en-position": "translate(140 -14) scale(.797)",
        "wordmark-en": "matrix(1 0 -0.12278 1 77.83 0) translate(-54 2)",
    },
    "trainmate-flow-submark.svg": {
        "flow-avatar-submark": "translate(-56 0) rotate(4 512 540)",
    },
    "trainmate-flow-app-icon.svg": {
        "app-icon-layout": "translate(-13 -72) scale(1.10)",
        "flow-avatar": "rotate(2 512 540)",
    },
    "trainmate-flow-app-icon-maskable.svg": {
        "app-icon-layout": "translate(192 156) scale(.67)",
        "flow-avatar": "rotate(2 512 540)",
    },
}

FORBIDDEN_TAG_MESSAGES = {
    "image": "正式 SVG 不得包含嵌入位图",
    "text": "正式 SVG 不得保留可变文字",
    "filter": "正式 SVG 不得包含滤镜",
    "lineargradient": "正式 SVG 不得包含线性渐变",
    "radialgradient": "正式 SVG 不得包含径向渐变",
    "script": "正式 SVG 不得包含脚本",
    "style": "正式 SVG 不得包含 style 节点",
    "mask": "正式 SVG 不得包含 mask 节点",
    "clippath": "正式 SVG 不得包含 clipPath 节点",
}
FORBIDDEN_ATTRIBUTE_MESSAGES = {
    "mask": "正式 SVG 不得包含 mask 属性",
    "clip-path": "正式 SVG 不得包含 clip-path 属性",
}
PROCESSING_INSTRUCTION_PATTERN = re.compile(
    r"<\?(?!xml(?:\s|\?>))",
    flags=re.IGNORECASE,
)
XML_DECLARATION_ENCODING_PATTERN = re.compile(
    r'''^\s*<\?xml\b[^?]*\bencoding\s*=\s*["']([^"']+)["']''',
    flags=re.IGNORECASE,
)
COLOR_ATTRIBUTES = {
    "color",
    "fill",
    "stroke",
    "stop-color",
    "flood-color",
    "lighting-color",
}
ANDROID_NAMESPACE = "http://schemas.android.com/apk/res/android"


def _append_unique(issues: list[str], message: str) -> None:
    if message not in issues:
        issues.append(message)


def _local_name(name: str) -> str:
    return name.rsplit("}", 1)[-1]


def _parse_view_box(value: str | None) -> tuple[float, float, float, float] | None:
    if not value:
        return None
    parts = [part for part in re.split(r"[\s,]+", value.strip()) if part]
    if len(parts) != 4:
        return None
    try:
        numbers = tuple(float(part) for part in parts)
    except ValueError:
        return None
    if not all(math.isfinite(number) for number in numbers):
        return None
    if numbers[2] <= 0 or numbers[3] <= 0:
        return None
    return numbers


def _style_values(style: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for declaration in style.split(";"):
        if ":" not in declaration:
            continue
        name, value = declaration.split(":", 1)
        values[name.strip().lower()] = value.strip()
    return values


def _paint_value(element: ET.Element, attribute_name: str) -> str:
    """读取绘制属性，内联 style 优先于同名 XML 属性。"""
    style = _style_values(element.attrib.get("style", ""))
    return style.get(attribute_name, element.attrib.get(attribute_name, "")).strip()


def _normalize_gradient_offset(value: str | None) -> float | None:
    if value is None:
        return None
    text = value.strip()
    try:
        offset = float(text[:-1]) / 100 if text.endswith("%") else float(text)
    except ValueError:
        return None
    if not math.isfinite(offset):
        return None
    if math.isclose(offset, 0.0, abs_tol=1e-9):
        return 0.0
    if math.isclose(offset, 1.0, abs_tol=1e-9):
        return 1.0
    return offset


def _is_app_icon_headband_stop_color(
    element: ET.Element,
    parent: ET.Element | None,
    normalized_color: str,
) -> bool:
    return bool(
        _local_name(element.tag).lower() == "stop"
        and parent is not None
        and parent.attrib.get("id") == "headband-gradient"
        and normalized_color in APP_ICON_HEADBAND_GRADIENT_COLORS
    )


def _validate_app_icon_accent_contract(
    root: ET.Element,
    issues: list[str],
) -> None:
    elements_by_id = {
        element.attrib["id"]: element
        for element in root.iter()
        if "id" in element.attrib
    }
    headband_gradient = elements_by_id.get("headband-gradient")
    if headband_gradient is not None:
        endpoint_colors: dict[float, str] = {}
        for stop in list(headband_gradient):
            if _local_name(stop.tag).lower() != "stop":
                continue
            offset = _normalize_gradient_offset(stop.attrib.get("offset"))
            if offset not in {0.0, 1.0}:
                continue
            endpoint_colors[offset] = _paint_value(stop, "stop-color").upper()
        if (
            endpoint_colors.get(0.0) != APP_ICON_HEADBAND_GRADIENT_COLORS[0]
            or endpoint_colors.get(1.0) != APP_ICON_HEADBAND_GRADIENT_COLORS[1]
        ):
            _append_unique(issues, "App 图标奋斗头带必须使用参考橙色渐变")

    face_mouth = elements_by_id.get("face-mouth")
    if (
        face_mouth is not None
        and _paint_value(face_mouth, "stroke").upper() != APP_ICON_MOUTH_COLOR
    ):
        _append_unique(issues, "App 图标桃色嘴必须保持 #FFB27D")


def _is_external_reference(attribute_name: str, value: str) -> bool:
    cleaned = value.strip().strip("'\"")
    if attribute_name in {"href", "src"} and cleaned and not cleaned.startswith("#"):
        return True
    for match in re.finditer(r"url\(([^)]+)\)", value, flags=re.IGNORECASE):
        reference = match.group(1).strip().strip("'\"")
        if reference and not reference.startswith("#"):
            return True
    return False


def _opacity_is_full(value: str | None) -> bool:
    if value is None or value.strip() == "":
        return True
    try:
        return float(value) == 1.0
    except ValueError:
        return False


def _rect_covers_view_box(
    element: ET.Element,
    view_box: tuple[float, float, float, float],
) -> bool:
    view_x, view_y, view_width, view_height = view_box
    width = element.attrib.get("width")
    height = element.attrib.get("height")
    if width == "100%" and height == "100%":
        return True
    try:
        rect_x = float(element.attrib.get("x", "0"))
        rect_y = float(element.attrib.get("y", "0"))
        rect_width = float(width or "0")
        rect_height = float(height or "0")
    except ValueError:
        return False
    return (
        rect_x <= view_x
        and rect_y <= view_y
        and rect_x + rect_width >= view_x + view_width
        and rect_y + rect_height >= view_y + view_height
    )


def _has_opaque_app_icon_background(
    root: ET.Element,
    view_box: tuple[float, float, float, float] | None,
) -> bool:
    root_style = _style_values(root.attrib.get("style", ""))
    root_opacity = root_style.get("opacity", root.attrib.get("opacity"))
    root_fill_opacity = root_style.get(
        "fill-opacity", root.attrib.get("fill-opacity")
    )
    root_display = root_style.get("display", root.attrib.get("display", ""))
    root_visibility = root_style.get(
        "visibility", root.attrib.get("visibility", "")
    )
    if (
        view_box is None
        or not _opacity_is_full(root_opacity)
        or not _opacity_is_full(root_fill_opacity)
        or root_display.strip().lower() == "none"
        or root_visibility.strip().lower() in {"hidden", "collapse"}
    ):
        return False
    for element in list(root):
        if _local_name(element.tag).lower() != "rect":
            continue
        if element.attrib.get("id") != "icon-background":
            continue
        style = _style_values(element.attrib.get("style", ""))
        fill = style.get("fill", element.attrib.get("fill", ""))
        opacity = style.get("opacity", element.attrib.get("opacity"))
        fill_opacity = style.get(
            "fill-opacity", element.attrib.get("fill-opacity")
        )
        display = style.get("display", element.attrib.get("display", ""))
        visibility = style.get(
            "visibility", element.attrib.get("visibility", "")
        )
        fill_upper = fill.upper()
        if fill_upper == APP_ICON_BACKGROUND_COLOR:
            背景填充有效 = True
        else:
            渐变引用 = re.fullmatch(r"url\(#([^)]+)\)", fill, flags=re.IGNORECASE)
            背景填充有效 = bool(
                渐变引用 and 渐变引用.group(1) == "icon-background-gradient"
            )
        if not 背景填充有效:
            continue
        if not _opacity_is_full(opacity) or not _opacity_is_full(fill_opacity):
            continue
        if display.strip().lower() == "none":
            continue
        if visibility.strip().lower() in {"hidden", "collapse"}:
            continue
        if _rect_covers_view_box(element, view_box):
            return True
    return False


def validate_svg(path: str | Path, asset_kind: str = "formal") -> list[str]:
    """校验单个正式 SVG 的结构、颜色和固定节点。"""
    svg_path = Path(path)
    if not svg_path.is_file():
        return [f"正式 SVG 文件不存在：{svg_path}"]
    try:
        raw_svg = svg_path.read_bytes()
    except OSError:
        return [f"正式 SVG 无法解析：{svg_path.name}"]
    try:
        svg_text = raw_svg.decode("utf-8-sig")
    except UnicodeDecodeError:
        return ["正式 SVG 必须使用 UTF-8 编码"]
    if "\x00" in svg_text:
        return ["正式 SVG 必须使用 UTF-8 编码"]
    encoding_match = XML_DECLARATION_ENCODING_PATTERN.search(svg_text)
    if encoding_match and encoding_match.group(1).upper() != "UTF-8":
        return ["正式 SVG 必须使用 UTF-8 编码"]
    try:
        root = ET.fromstring(svg_text)
    except (ET.ParseError, ValueError):
        return [f"正式 SVG 无法解析：{svg_path.name}"]

    issues: list[str] = []
    图标资产 = asset_kind in {"app-icon", "app-icon-maskable"}
    if PROCESSING_INSTRUCTION_PATTERN.search(svg_text):
        _append_unique(issues, "正式 SVG 不得包含处理指令")
    if _local_name(root.tag).lower() != "svg":
        _append_unique(issues, "正式 SVG 根节点必须是 svg")
    view_box = _parse_view_box(root.attrib.get("viewBox"))
    if view_box is None:
        _append_unique(issues, "正式 SVG 缺少合法 viewBox")

    found_ids: set[str] = set()
    found_gradient_ids: set[str] = set()
    parent_by_element = {
        child: parent for parent in root.iter() for child in list(parent)
    }
    for element in root.iter():
        tag_name = _local_name(element.tag).lower()
        if tag_name in FORBIDDEN_TAG_MESSAGES:
            if not (图标资产 and tag_name in {"lineargradient", "radialgradient"}):
                _append_unique(issues, FORBIDDEN_TAG_MESSAGES[tag_name])
        element_id = element.attrib.get("id")
        if element_id:
            found_ids.add(element_id)
            if tag_name in {"lineargradient", "radialgradient"}:
                found_gradient_ids.add(element_id)

        style = _style_values(element.attrib.get("style", ""))
        for attribute, value in element.attrib.items():
            attribute_name = _local_name(attribute).lower()
            if attribute_name in FORBIDDEN_ATTRIBUTE_MESSAGES:
                _append_unique(
                    issues,
                    FORBIDDEN_ATTRIBUTE_MESSAGES[attribute_name],
                )
            if attribute_name.startswith("on"):
                _append_unique(
                    issues,
                    f"正式 SVG 不得包含事件属性：{attribute_name}",
                )
            if _is_external_reference(attribute_name, value):
                _append_unique(issues, "正式 SVG 不得包含外部链接")
            if MARKETING_TEXTURE.lower() in value.lower():
                _append_unique(issues, "正式 SVG 不得引用营销纹理")
            if attribute_name in COLOR_ATTRIBUTES:
                normalized = value.strip().upper()
                图标内部渐变引用 = bool(
                    图标资产
                    and re.fullmatch(r"url\(#[^)]+\)", value.strip(), flags=re.IGNORECASE)
                )
                头带参考橙端点 = bool(
                    图标资产
                    and _is_app_icon_headband_stop_color(
                        element,
                        parent_by_element.get(element),
                        normalized,
                    )
                )
                允许颜色 = APP_ICON_ALLOWED_COLORS if 图标资产 else ALLOWED_COLORS
                if (
                    normalized != "NONE"
                    and not 图标内部渐变引用
                    and not 头带参考橙端点
                    and normalized not in 允许颜色
                ):
                    _append_unique(issues, f"正式 SVG 使用了非白名单颜色：{value.strip()}")

        for attribute_name, message in FORBIDDEN_ATTRIBUTE_MESSAGES.items():
            if attribute_name in style:
                _append_unique(issues, message)

        for color_name in COLOR_ATTRIBUTES:
            if color_name not in style:
                continue
            value = style[color_name]
            normalized = value.upper()
            图标内部渐变引用 = bool(
                图标资产
                and re.fullmatch(r"url\(#[^)]+\)", value, flags=re.IGNORECASE)
            )
            头带参考橙端点 = bool(
                图标资产
                and _is_app_icon_headband_stop_color(
                    element,
                    parent_by_element.get(element),
                    normalized,
                )
            )
            允许颜色 = APP_ICON_ALLOWED_COLORS if 图标资产 else ALLOWED_COLORS
            if (
                normalized != "NONE"
                and not 图标内部渐变引用
                and not 头带参考橙端点
                and normalized not in 允许颜色
            ):
                _append_unique(issues, f"正式 SVG 使用了非白名单颜色：{value}")

        text = element.text or ""
        if MARKETING_TEXTURE.lower() in text.lower():
            _append_unique(issues, "正式 SVG 不得引用营销纹理")
        if re.search(r"(?:https?:|file:|data:|url\()", text, flags=re.IGNORECASE):
            _append_unique(issues, "正式 SVG 不得包含外部链接")

    if asset_kind == "brandmark":
        for missing_id in sorted(STANDARD_BRANDMARK_IDS - found_ids):
            issues.append(f"标准头像缺少固定节点：{missing_id}")
    elif asset_kind == "brandmark-small":
        for missing_id in sorted(SMALL_BRANDMARK_IDS - found_ids):
            issues.append(f"小尺寸头像缺少固定节点：{missing_id}")
        if "face-mouth" in found_ids:
            issues.append("小尺寸头像不得包含 face-mouth 节点")
    elif asset_kind == "character":
        for missing_id in sorted(CHARACTER_IDS - found_ids):
            issues.append(f"完整角色缺少固定节点：{missing_id}")
    elif asset_kind == "lockup":
        for missing_id in sorted(STANDARD_BRANDMARK_IDS - found_ids):
            issues.append(f"主品牌组合标缺少固定节点：{missing_id}")
    elif asset_kind in {"app-icon", "app-icon-maskable"}:
        for missing_id in sorted(APP_ICON_IDS - found_ids):
            issues.append(f"App 图标缺少固定节点：{missing_id}")
        for forbidden_id in sorted(APP_ICON_FORBIDDEN_IDS & found_ids):
            issues.append(f"App 图标不得包含角色肢体节点：{forbidden_id}")
        for missing_id in sorted(APP_ICON_GRADIENT_IDS - found_gradient_ids):
            issues.append(f"App 图标缺少参考风格渐变：{missing_id}")
        _validate_app_icon_accent_contract(root, issues)
        if not _has_opaque_app_icon_background(root, view_box):
            issues.append("App 图标必须包含完整不透明的品牌浅桃柔光背景")

    return issues


def validate_motion_contract(svg_path: str | Path) -> list[str]:
    """校验头像旋转和字标剪切，防止品牌家族局部回退为直立稿。"""
    path = Path(svg_path)
    expected = EXPECTED_MOTION_TRANSFORMS.get(path.name)
    if not expected:
        return []
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError):
        return [f"动态角度源稿无法解析：{path.name}"]

    elements_by_id = {
        element.attrib["id"]: element
        for element in root.iter()
        if "id" in element.attrib
    }
    issues: list[str] = []
    for element_id, expected_transform in expected.items():
        element = elements_by_id.get(element_id)
        if element is None:
            issues.append(f"动态角度缺少节点：{element_id}")
            continue
        actual = " ".join(element.attrib.get("transform", "").split())
        if actual != expected_transform:
            issues.append(
                f"动态角度错误：{element_id} 应为 {expected_transform}"
            )
    return issues


def _png_has_alpha_channel(image: Any) -> bool:
    return "A" in image.getbands() or "transparency" in image.info


def _png_is_fully_opaque(image: Any) -> bool:
    if not _png_has_alpha_channel(image):
        return True
    alpha = image.convert("RGBA").getchannel("A")
    minimum, maximum = alpha.getextrema()
    return minimum == 255 and maximum == 255


def validate_png(
    path: str | Path,
    width: int,
    height: int,
    *,
    allow_alpha: bool = True,
    require_opaque: bool = False,
    platform: str | None = None,
) -> list[str]:
    """校验 PNG 尺寸以及平台透明度规则。"""
    png_path = Path(path)
    if Image is None:
        return [PILLOW_ERROR]
    if not png_path.is_file():
        return [f"PNG 文件不存在：{png_path}"]
    try:
        with Image.open(png_path) as image:
            image.load()
            issues: list[str] = []
            if image.size != (width, height):
                issues.append(
                    f"PNG 尺寸错误：期望 {width}×{height}，"
                    f"实际 {image.width}×{image.height}"
                )
            if not allow_alpha and _png_has_alpha_channel(image):
                if platform in {None, "ios"}:
                    issues.append("iOS 图标不得包含 Alpha 通道")
                else:
                    issues.append("PNG 不得包含 Alpha 通道")
            if require_opaque and not _png_is_fully_opaque(image):
                if platform == "web-maskable":
                    issues.append("Web Maskable 图标必须完整不透明")
                else:
                    issues.append("PNG 必须完整不透明")
            return issues
    except (OSError, ValueError):
        return [f"PNG 无法读取：{png_path.name}"]


def validate_app_icon_master(
    manifest: dict[str, Any],
    repository_root: Path = REPOSITORY_ROOT,
) -> list[str]:
    """校验用户确认的定版母版未被替换、重采样或改色。"""
    config = manifest.get("appIconMaster")
    if not isinstance(config, dict):
        return ["资产清单缺少 appIconMaster"]
    expected = {
        "file": FINAL_LOGO_FILE,
        "sha256": FINAL_LOGO_SHA256,
        "width": FINAL_LOGO_SIZE[0],
        "height": FINAL_LOGO_SIZE[1],
        "mode": FINAL_LOGO_MODE,
        "maskableScale": 0.9,
        "maskableBackground": "#FEFEFE",
    }
    issues: list[str] = []
    for key, value in expected.items():
        if config.get(key) != value:
            issues.append(f"定版 Logo 配置错误：{key}")
    path = (
        repository_root
        / str(manifest.get("sourceDirectory", "assets/branding/source"))
        / str(config.get("file", ""))
    )
    if not path.is_file():
        return issues + [f"定版 Logo 母版不存在：{path}"]
    if hashlib.sha256(path.read_bytes()).hexdigest() != FINAL_LOGO_SHA256:
        issues.append("定版 Logo 母版 SHA-256 不一致")
    if Image is None:
        return issues + [PILLOW_ERROR]
    try:
        with Image.open(path) as image:
            image.load()
            if image.size != FINAL_LOGO_SIZE:
                issues.append("定版 Logo 母版尺寸必须是 1254×1254")
            if image.mode != FINAL_LOGO_MODE:
                issues.append("定版 Logo 母版必须是 RGB 且不含 Alpha 通道")
    except (OSError, ValueError):
        issues.append("定版 Logo 母版无法读取")
    return issues


def _load_master_images(
    manifest: dict[str, Any],
    repository_root: Path,
) -> tuple[Any, Any]:
    config = manifest["appIconMaster"]
    path = (
        repository_root
        / str(manifest["sourceDirectory"])
        / str(config["file"])
    )
    with Image.open(path) as image:
        standard = image.convert("RGB")
        standard.load()
    content_size = round(standard.width * float(config["maskableScale"]))
    content = standard.resize(
        (content_size, content_size),
        Image.Resampling.LANCZOS,
    )
    maskable = Image.new("RGB", standard.size, str(config["maskableBackground"]))
    offset = (
        (standard.width - content_size) // 2,
        (standard.height - content_size) // 2,
    )
    maskable.paste(content, offset)
    return standard, maskable


def validate_deterministic_platform_png(
    path: str | Path,
    size: int,
    manifest: dict[str, Any],
    repository_root: Path = REPOSITORY_ROOT,
    *,
    maskable: bool = False,
) -> list[str]:
    """逐像素确认平台图标只执行清单允许的确定性缩放。"""
    if Image is None or ImageChops is None:
        return [PILLOW_ERROR]
    png_path = Path(path)
    if not png_path.is_file():
        return [f"PNG 文件不存在：{png_path}"]
    try:
        standard, safe = _load_master_images(manifest, repository_root)
        expected_source = safe if maskable else standard
        expected = expected_source.resize((size, size), Image.Resampling.LANCZOS)
        with Image.open(png_path) as image:
            actual = image.convert("RGB")
            actual.load()
        if actual.size != expected.size:
            return []
        if ImageChops.difference(actual, expected).getbbox() is not None:
            return ["平台图标像素与定版母版的确定性导出结果不一致"]
        return []
    except (KeyError, OSError, TypeError, ValueError):
        return ["无法计算平台图标的定版母版对照结果"]


def validate_display_logo_export(
    path: str | Path,
    manifest: dict[str, Any],
    repository_root: Path = REPOSITORY_ROOT,
) -> list[str]:
    """校验应用内透明衍生图保留主体，且只移除边缘连通的近白底。"""
    issues = validate_png(path, 256, 256)
    if issues or Image is None or ImageChops is None or ImageStat is None:
        return issues
    try:
        with Image.open(path) as image:
            actual = image.convert("RGBA")
            actual.load()
        alpha = actual.getchannel("A")
        if alpha.getextrema() != (0, 255):
            issues.append("应用内定版 Logo 必须同时包含透明背景和完整不透明主体")
        for corner in ((0, 0), (255, 0), (0, 255), (255, 255)):
            if actual.getpixel(corner)[3] != 0:
                issues.append("应用内定版 Logo 四角必须透明")
                break
        standard, _ = _load_master_images(manifest, repository_root)
        expected = standard.resize((256, 256), Image.Resampling.LANCZOS)
        background = Image.new(
            "RGBA",
            actual.size,
            str(manifest["appIconMaster"]["maskableBackground"]),
        )
        background.alpha_composite(actual)
        difference = ImageChops.difference(expected, background.convert("RGB"))
        if max(ImageStat.Stat(difference).mean) > 0.6:
            issues.append("应用内定版 Logo 透明衍生图与原母版主体不一致")
    except (KeyError, OSError, TypeError, ValueError):
        issues.append("应用内定版 Logo 透明衍生图无法校验")
    return issues


def _ios_pixel_size(size: str, scale: str) -> tuple[int, int] | None:
    try:
        width_text, height_text = size.lower().split("x", 1)
        scale_text = scale.lower()
        if not scale_text.endswith("x"):
            return None
        factor = Decimal(scale_text[:-1])
        width = Decimal(width_text) * factor
        height = Decimal(height_text) * factor
        if width != width.to_integral_value() or height != height.to_integral_value():
            return None
        if width <= 0 or height <= 0:
            return None
        return int(width), int(height)
    except (InvalidOperation, ValueError):
        return None


def validate_ios_catalog(contents_path: str | Path) -> list[str]:
    """直接读取 Asset Catalog 清单，不维护第二份文件映射。"""
    path = Path(contents_path)
    if not path.is_file():
        return [f"iOS Contents.json 不存在：{path}"]
    try:
        contents = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ["iOS Contents.json 无法解析"]

    images = contents.get("images")
    if not isinstance(images, list) or not images:
        return ["iOS Contents.json 缺少图标条目"]

    issues: list[str] = []
    seen_filenames: dict[str, tuple[int, int]] = {}
    for index, entry in enumerate(images, start=1):
        if not isinstance(entry, dict):
            issues.append(f"iOS Contents.json 第 {index} 项格式无效")
            continue
        filename = entry.get("filename")
        if not isinstance(filename, str) or not filename:
            issues.append(f"iOS Contents.json 第 {index} 项缺少 filename")
            continue
        pixel_size = _ios_pixel_size(str(entry.get("size", "")), str(entry.get("scale", "")))
        if pixel_size is None:
            issues.append(f"iOS Contents.json 尺寸或倍数无效：{filename}")
            continue
        previous_size = seen_filenames.get(filename)
        if previous_size is not None and previous_size != pixel_size:
            issues.append(
                f"iOS Contents.json 同一文件被不同像素尺寸引用：{filename}"
            )
            continue
        if previous_size is not None:
            continue
        seen_filenames[filename] = pixel_size
        file_issues = validate_png(
            path.parent / filename,
            pixel_size[0],
            pixel_size[1],
            allow_alpha=False,
            platform="ios",
        )
        for issue in file_issues:
            if issue == "iOS 图标不得包含 Alpha 通道":
                issues.append(f"{issue}：{filename}")
            else:
                issues.append(f"{filename}：{issue}")
    return issues


def select_avatar_source(size: int, manifest: dict[str, Any] | None = None) -> str:
    """按导出尺寸选择小尺寸或标准头像源稿。"""
    if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
        raise ValueError("导出尺寸必须为正整数")
    if manifest is None:
        maximum = 48
        sources = {
            "small": "trainmate-flow-brandmark-small.svg",
            "standard": "trainmate-flow-brandmark.svg",
        }
    else:
        maximum = int(manifest.get("smallSourceMaxSize", 48))
        sources = manifest.get("avatarSources", {})
    key = "small" if size <= maximum else "standard"
    source = sources.get(key)
    if not isinstance(source, str) or not source:
        raise ValueError(f"资产清单缺少 {key} 头像源稿")
    return source


def validate_platform_source_contract(manifest: dict[str, Any]) -> list[str]:
    """确保三端平台只引用用户确认的定版 PNG 母版。"""
    issues: list[str] = []
    platform_sources = manifest.get("platformSources", {})
    if not isinstance(platform_sources, dict):
        return ["资产清单的 platformSources 格式无效"]
    for platform in ("ios", "android", "web"):
        sources = platform_sources.get(platform, [])
        if not isinstance(sources, list):
            issues.append(f"{platform} 平台任务源稿清单格式无效")
            continue
        if any(MARKETING_TEXTURE.lower() in str(source).lower() for source in sources):
            issues.append(f"{platform} 平台任务不得使用营销纹理")
        if sources != [FINAL_LOGO_FILE]:
            issues.append(f"{platform} 平台任务必须且只能使用定版 Logo 母版")
    return issues


def load_manifest(path: str | Path = DEFAULT_MANIFEST_PATH) -> dict[str, Any]:
    manifest_path = Path(path)
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValueError(f"品牌资产清单不存在：{manifest_path}") from error
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError("品牌资产清单无法解析") from error
    if not isinstance(manifest, dict):
        raise ValueError("品牌资产清单根节点必须是对象")
    return manifest


def validate_manifest_contract(manifest: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    if manifest.get("schemaVersion") != 2:
        issues.append("资产清单版本必须是 2")
    if manifest.get("colors") != EXPECTED_COLORS:
        issues.append("资产清单色值与品牌契约不一致")
    if manifest.get("exportSizes") != EXPECTED_EXPORT_SIZES:
        issues.append("资产清单头像导出尺寸与品牌契约不一致")
    if manifest.get("characterExportSizes") != EXPECTED_CHARACTER_SIZES:
        issues.append("资产清单完整角色导出尺寸与品牌契约不一致")
    formal_sources = manifest.get("formalSources")
    if not isinstance(formal_sources, list):
        issues.append("资产清单 formalSources 格式无效")
    else:
        source_names = {
            item.get("file")
            for item in formal_sources
            if isinstance(item, dict) and isinstance(item.get("file"), str)
        }
        source_kinds = {
            item.get("file"): item.get("kind")
            for item in formal_sources
            if isinstance(item, dict) and isinstance(item.get("file"), str)
        }
        for missing_name in sorted(EXPECTED_FORMAL_SOURCES - source_names):
            issues.append(f"资产清单缺少正式源文件：{missing_name}")
        for extra_name in sorted(source_names - EXPECTED_FORMAL_SOURCES):
            issues.append(f"资产清单包含未声明的正式源文件：{extra_name}")
        if len(source_names) != len(formal_sources):
            issues.append("资产清单正式源文件存在重复或无效条目")
        for filename, expected_kind in EXPECTED_SOURCE_KINDS.items():
            if filename not in source_names:
                continue
            if source_kinds.get(filename) != expected_kind:
                issues.append(
                    f"资产清单源文件类型错误：{filename} 应为 {expected_kind}"
                )
    if manifest.get("marketingTexture") != MARKETING_TEXTURE:
        issues.append("资产清单营销纹理文件名与品牌契约不一致")
    try:
        for size in EXPECTED_EXPORT_SIZES:
            source = select_avatar_source(size, manifest)
            expected = (
                "trainmate-flow-brandmark-small.svg"
                if size <= 48
                else "trainmate-flow-brandmark.svg"
            )
            if source != expected:
                issues.append(f"{size}px 头像源稿选择错误")
    except (TypeError, ValueError):
        issues.append("资产清单头像源稿选择配置无效")
    issues.extend(validate_platform_source_contract(manifest))
    return issues


def validate_source(manifest: dict[str, Any], repository_root: Path) -> list[str]:
    issues = validate_manifest_contract(manifest)
    issues.extend(validate_app_icon_master(manifest, repository_root))
    source_directory = repository_root / str(
        manifest.get("sourceDirectory", "assets/branding/source")
    )
    formal_sources = manifest.get("formalSources", [])
    if isinstance(formal_sources, list):
        for item in formal_sources:
            if not isinstance(item, dict):
                continue
            filename = item.get("file")
            if not isinstance(filename, str):
                continue
            asset_kind = EXPECTED_SOURCE_KINDS.get(
                filename,
                str(item.get("kind", "formal")),
            )
            for issue in validate_svg(source_directory / filename, str(asset_kind)):
                issues.append(f"{filename}：{issue}")
            for issue in validate_motion_contract(source_directory / filename):
                issues.append(f"{filename}：{issue}")
    marketing_path = source_directory / str(
        manifest.get("marketingTexture", MARKETING_TEXTURE)
    )
    if not marketing_path.is_file():
        issues.append(f"仅营销用途纹理文件不存在：{marketing_path}")
    return issues


def validate_exports(manifest: dict[str, Any], repository_root: Path) -> list[str]:
    issues = validate_manifest_contract(manifest)
    export_config = manifest.get("exports", {})
    if not isinstance(export_config, dict):
        return issues + ["资产清单 exports 格式无效"]
    export_directory = repository_root / str(
        export_config.get("directory", "assets/branding/exports/png")
    )
    avatar_pattern = str(
        export_config.get("avatarPattern", "trainmate-flow-brandmark-{size}.png")
    )
    character_pattern = str(
        export_config.get("characterPattern", "trainmate-flow-character-{size}.png")
    )
    for size in manifest.get("exportSizes", []):
        if not isinstance(size, int):
            issues.append("头像导出尺寸必须是整数")
            continue
        path = export_directory / avatar_pattern.format(size=size)
        for issue in validate_png(path, size, size):
            issues.append(f"{path.name}：{issue}")
    for size in manifest.get("characterExportSizes", []):
        if not isinstance(size, int):
            issues.append("完整角色导出尺寸必须是整数")
            continue
        path = export_directory / character_pattern.format(size=size)
        for issue in validate_png(path, size, size):
            issues.append(f"{path.name}：{issue}")
    final_logo_name = export_config.get("finalLogoFile")
    final_lockup_name = export_config.get("finalLockupFile")
    if not isinstance(final_logo_name, str) or not final_logo_name:
        issues.append("资产清单缺少应用内定版 Logo 导出文件名")
    else:
        final_logo_path = export_directory / final_logo_name
        for issue in validate_display_logo_export(
            final_logo_path,
            manifest,
            repository_root,
        ):
            issues.append(f"{final_logo_path.name}：{issue}")
    if not isinstance(final_lockup_name, str) or not final_lockup_name:
        issues.append("资产清单缺少应用内定版组合字标文件名")
    else:
        final_lockup_path = export_directory / final_lockup_name
        for issue in validate_png(final_lockup_path, 1600, 626):
            issues.append(f"{final_lockup_path.name}：{issue}")
    return issues


def validate_ios(manifest: dict[str, Any], repository_root: Path) -> list[str]:
    issues = validate_platform_source_contract(manifest)
    contents_path = repository_root / str(
        manifest.get(
            "iosContents",
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json",
        )
    )
    issues.extend(validate_ios_catalog(contents_path))
    if contents_path.is_file():
        text = contents_path.read_text(encoding="utf-8", errors="replace")
        if MARKETING_TEXTURE.lower() in text.lower():
            issues.append("iOS 平台输出不得引用营销纹理")
        try:
            contents = json.loads(text)
            seen: set[str] = set()
            for entry in contents.get("images", []):
                if not isinstance(entry, dict) or not entry.get("filename"):
                    continue
                filename = str(entry["filename"])
                if filename in seen:
                    continue
                seen.add(filename)
                pixel_size = _ios_pixel_size(
                    str(entry.get("size", "")),
                    str(entry.get("scale", "")),
                )
                if pixel_size is None or pixel_size[0] != pixel_size[1]:
                    continue
                for issue in validate_deterministic_platform_png(
                    contents_path.parent / filename,
                    pixel_size[0],
                    manifest,
                    repository_root,
                ):
                    issues.append(f"{filename}：{issue}")
        except (AttributeError, json.JSONDecodeError):
            pass
    return issues


def _read_xml(path: Path, missing_message: str, invalid_message: str) -> tuple[ET.Element | None, list[str]]:
    if not path.is_file():
        return None, [f"{missing_message}：{path}"]
    try:
        return ET.parse(path).getroot(), []
    except (ET.ParseError, OSError):
        return None, [invalid_message]


def validate_android(manifest: dict[str, Any], repository_root: Path) -> list[str]:
    issues = validate_platform_source_contract(manifest)
    android_config = manifest.get("android", {})
    if not isinstance(android_config, dict):
        return issues + ["资产清单 android 格式无效"]
    resource_root = repository_root / str(
        android_config.get("resourceRoot", "android/app/src/main/res")
    )

    legacy = manifest.get("androidLegacy", {})
    if not isinstance(legacy, dict):
        issues.append("资产清单 androidLegacy 格式无效")
    else:
        for density, size in legacy.items():
            path = resource_root / f"mipmap-{density}" / "ic_launcher.png"
            for issue in validate_png(
                path,
                int(size),
                int(size),
                require_opaque=True,
            ):
                issues.append(f"Android {density} 图标：{issue}")
            for issue in validate_deterministic_platform_png(
                path,
                int(size),
                manifest,
                repository_root,
            ):
                issues.append(f"Android {density} 图标：{issue}")

    foreground = manifest.get("androidAdaptiveForeground", {})
    if not isinstance(foreground, dict):
        issues.append("资产清单 androidAdaptiveForeground 格式无效")
    else:
        for density, size in foreground.items():
            path = resource_root / f"drawable-{density}" / "ic_launcher_foreground.png"
            for issue in validate_png(path, int(size), int(size), require_opaque=True):
                issues.append(f"Android {density} 前景图：{issue}")
            for issue in validate_deterministic_platform_png(
                path,
                int(size),
                manifest,
                repository_root,
                maskable=True,
            ):
                issues.append(f"Android {density} 前景图：{issue}")

    adaptive_path = resource_root / str(
        android_config.get("adaptiveIcon", "mipmap-anydpi-v26/ic_launcher.xml")
    )
    adaptive_root, adaptive_issues = _read_xml(
        adaptive_path,
        "Android Adaptive Icon XML 不存在",
        "Android Adaptive Icon XML 无法解析",
    )
    issues.extend(adaptive_issues)
    if adaptive_root is not None:
        xml_text = ET.tostring(adaptive_root, encoding="unicode")
        if MARKETING_TEXTURE.lower() in xml_text.lower():
            issues.append("Android 平台输出不得引用营销纹理")
        background = adaptive_root.find("background")
        foreground_node = adaptive_root.find("foreground")
        drawable_name = f"{{{ANDROID_NAMESPACE}}}drawable"
        if (
            background is None
            or background.attrib.get(drawable_name)
            != android_config.get("backgroundResource")
        ):
            issues.append("Android Adaptive Icon 背景资源引用错误")
        if (
            foreground_node is None
            or foreground_node.attrib.get(drawable_name)
            != android_config.get("foregroundResource")
        ):
            issues.append("Android Adaptive Icon 前景资源引用错误")

    colors_path = resource_root / str(android_config.get("colors", "values/colors.xml"))
    colors_root, color_issues = _read_xml(
        colors_path,
        "Android 颜色资源文件不存在",
        "Android 颜色资源文件无法解析",
    )
    issues.extend(color_issues)
    if colors_root is not None:
        color_name = str(android_config.get("backgroundColorName", ""))
        matching = [
            node
            for node in colors_root.findall("color")
            if node.attrib.get("name") == color_name
        ]
        预期背景色 = str(
            manifest.get("appIconMaster", {}).get("maskableBackground", "")
        ).upper()
        if not matching or (matching[0].text or "").strip().upper() != 预期背景色:
            issues.append(f"Android 图标背景色必须是 {预期背景色}")
    return issues


def validate_web(manifest: dict[str, Any], repository_root: Path) -> list[str]:
    issues = validate_platform_source_contract(manifest)
    web_config = manifest.get("web", {})
    if not isinstance(web_config, dict):
        return issues + ["资产清单 web 格式无效"]
    web_root = repository_root / "web"
    for relative_path, size in web_config.items():
        is_maskable = "maskable" in relative_path.lower()
        for issue in validate_png(
            web_root / relative_path,
            int(size),
            int(size),
            require_opaque=is_maskable,
            platform="web-maskable" if is_maskable else "web",
        ):
            issues.append(f"Web {relative_path}：{issue}")
        for issue in validate_deterministic_platform_png(
            web_root / relative_path,
            int(size),
            manifest,
            repository_root,
            maskable=is_maskable,
        ):
            issues.append(f"Web {relative_path}：{issue}")

    manifest_path = web_root / "manifest.json"
    if not manifest_path.is_file():
        issues.append(f"Web manifest.json 不存在：{manifest_path}")
        return issues
    try:
        web_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        issues.append("Web manifest.json 无法解析")
        return issues
    manifest_text = json.dumps(web_manifest, ensure_ascii=False)
    if MARKETING_TEXTURE.lower() in manifest_text.lower():
        issues.append("Web 平台输出不得引用营销纹理")
    icon_entries = web_manifest.get("icons", [])
    if not isinstance(icon_entries, list):
        issues.append("Web manifest.json 的 icons 格式无效")
        return issues
    entries_by_source = {
        item.get("src"): item for item in icon_entries if isinstance(item, dict)
    }
    for relative_path, size in web_config.items():
        if relative_path == "favicon.png":
            continue
        entry = entries_by_source.get(relative_path)
        if entry is None:
            issues.append(f"Web manifest.json 缺少图标引用：{relative_path}")
            continue
        expected_size = f"{size}x{size}"
        if entry.get("sizes") != expected_size:
            issues.append(f"Web manifest.json 图标尺寸声明错误：{relative_path}")
        if "maskable" in relative_path.lower() and "maskable" not in str(
            entry.get("purpose", "")
        ).split():
            issues.append(f"Web manifest.json 缺少 maskable 用途：{relative_path}")
    return issues


class ChineseArgumentParser(argparse.ArgumentParser):
    def format_usage(self) -> str:
        return super().format_usage().replace("usage:", "用法：")

    def format_help(self) -> str:
        return (
            super()
            .format_help()
            .replace("usage:", "用法：")
            .replace("options:", "选项：")
            .replace("positional arguments:", "位置参数：")
        )

    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        self.exit(2, "错误：命令行参数无效，请使用 --help 查看支持的平台。\n")


def build_parser() -> argparse.ArgumentParser:
    parser = ChineseArgumentParser(
        prog="verify_brand_assets.py",
        add_help=False,
        description="校验智练 TrainMate 品牌源稿、导出物和平台图标。",
    )
    parser._positionals.title = "位置参数"
    parser._optionals.title = "选项"
    parser.add_argument("-h", "--help", action="help", help="显示帮助并退出")
    parser.add_argument(
        "--platform",
        required=True,
        choices=("source", "exports", "ios", "android", "web", "all"),
        metavar="{source,exports,ios,android,web,all}",
        help="选择校验范围",
    )
    return parser


def validate_platform(
    platform: str,
    manifest: dict[str, Any],
    repository_root: Path = REPOSITORY_ROOT,
) -> list[str]:
    validators = {
        "source": validate_source,
        "exports": validate_exports,
        "ios": validate_ios,
        "android": validate_android,
        "web": validate_web,
    }
    if platform == "all":
        issues: list[str] = []
        for name in ("source", "exports", "ios", "android", "web"):
            for issue in validators[name](manifest, repository_root):
                issues.append(f"{name}：{issue}")
        return issues
    return validators[platform](manifest, repository_root)


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    arguments = parser.parse_args(argv)
    if Image is None:
        print(PILLOW_ERROR, file=sys.stderr)
        return 2
    try:
        manifest = load_manifest()
    except ValueError as error:
        print(f"品牌资产校验失败：{error}", file=sys.stderr)
        return 1
    issues = validate_platform(arguments.platform, manifest)
    if issues:
        print(f"品牌资产校验失败，共 {len(issues)} 项问题：", file=sys.stderr)
        for issue in issues:
            print(f"- {issue}", file=sys.stderr)
        return 1
    print(f"品牌资产校验通过：{arguments.platform}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
