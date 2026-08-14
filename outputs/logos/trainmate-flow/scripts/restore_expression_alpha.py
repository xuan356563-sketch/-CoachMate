#!/usr/bin/env python3
"""保留原动作主体，只合成生成图中的表情与语义符号。"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="合成 TrainMate 表情并恢复真实 Alpha")
    parser.add_argument("--source", type=Path, required=True, help="带 Alpha 的原动作图")
    parser.add_argument("--generated", type=Path, required=True, help="生成后的 RGB/RGBA 图")
    parser.add_argument("--output", type=Path, required=True, help="透明 PNG 输出路径")
    parser.add_argument(
        "--variant",
        choices=("navy", "peach-light"),
        help="配色版本；不传时根据源文件路径判断",
    )
    return parser.parse_args()


def largest_component(mask: np.ndarray) -> np.ndarray:
    """返回二值图中面积最大的四连通区域。"""

    height, width = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    best: list[tuple[int, int]] = []
    for y, x in zip(*np.where(mask & ~visited), strict=False):
        if visited[y, x]:
            continue
        queue: deque[tuple[int, int]] = deque([(int(y), int(x))])
        visited[y, x] = True
        current: list[tuple[int, int]] = []
        while queue:
            cy, cx = queue.popleft()
            current.append((cy, cx))
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    queue.append((ny, nx))
        if len(current) > len(best):
            best = current

    output = np.zeros_like(mask, dtype=bool)
    if best:
        ys, xs = zip(*best, strict=False)
        output[np.asarray(ys), np.asarray(xs)] = True
    return output


def best_eye_component(mask: np.ndarray, target_width: int, target_height: int) -> np.ndarray:
    """从棋盘格和眼罩白色区域中选出尺寸最接近原眼罩的连通区。"""

    height, width = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    best: list[tuple[int, int]] = []
    best_score = float("inf")
    for y, x in zip(*np.where(mask & ~visited), strict=False):
        if visited[y, x]:
            continue
        queue: deque[tuple[int, int]] = deque([(int(y), int(x))])
        visited[y, x] = True
        current: list[tuple[int, int]] = []
        min_x = max_x = int(x)
        min_y = max_y = int(y)
        while queue:
            cy, cx = queue.popleft()
            current.append((cy, cx))
            min_x, max_x = min(min_x, cx), max(max_x, cx)
            min_y, max_y = min(min_y, cy), max(max_y, cy)
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    queue.append((ny, nx))

        component_width = max_x - min_x + 1
        component_height = max_y - min_y + 1
        aspect = component_width / max(1, component_height)
        if (
            len(current) < 800
            or component_width < target_width * 0.55
            or component_width > target_width * 1.75
            or component_height < target_height * 0.45
            or component_height > target_height * 1.9
            or not 1.35 <= aspect <= 7.0
        ):
            continue
        score = abs(component_width / target_width - 1.0) + abs(component_height / target_height - 1.0)
        if score < best_score:
            best_score = score
            best = current

    output = np.zeros_like(mask, dtype=bool)
    if best:
        ys, xs = zip(*best, strict=False)
        output[np.asarray(ys), np.asarray(xs)] = True
    return output


def enclosed_transparent_region(alpha: np.ndarray) -> np.ndarray:
    """找出人物内部最大的透明封闭区，兼容旧素材的透明眼罩。"""

    transparent = alpha < 48
    exterior = np.zeros_like(transparent, dtype=bool)
    queue: deque[tuple[int, int]] = deque()
    height, width = transparent.shape
    for x in range(width):
        if transparent[0, x]:
            queue.append((0, x))
        if transparent[height - 1, x]:
            queue.append((height - 1, x))
    for y in range(height):
        if transparent[y, 0]:
            queue.append((y, 0))
        if transparent[y, width - 1]:
            queue.append((y, width - 1))

    while queue:
        y, x = queue.popleft()
        if exterior[y, x] or not transparent[y, x]:
            continue
        exterior[y, x] = True
        if y > 0:
            queue.append((y - 1, x))
        if y + 1 < height:
            queue.append((y + 1, x))
        if x > 0:
            queue.append((y, x - 1))
        if x + 1 < width:
            queue.append((y, x + 1))

    return largest_component(transparent & ~exterior)


def close_mask(mask: np.ndarray, size: int = 21) -> np.ndarray:
    """闭合眼罩内的旧瞳孔小孔，并保留胶囊外轮廓。"""

    if size % 2 == 0:
        size += 1
    image = Image.fromarray((mask.astype(np.uint8) * 255), mode="L")
    image = image.filter(ImageFilter.MaxFilter(size)).filter(ImageFilter.MinFilter(size))
    return np.asarray(image) > 127


def dilate_mask(mask: np.ndarray, radius: int) -> np.ndarray:
    """在低分辨率上膨胀大范围遮罩，避免大核滤镜拖慢批处理。"""

    image = Image.fromarray((mask.astype(np.uint8) * 255), mode="L")
    factor = 8 if radius >= 48 else 4
    small_size = (max(1, image.width // factor), max(1, image.height // factor))
    small = image.resize(small_size, Image.Resampling.NEAREST)
    small_radius = max(1, int(round(radius / factor)))
    kernel = small_radius * 2 + 1
    expanded = small.filter(ImageFilter.MaxFilter(kernel))
    return np.asarray(expanded.resize(image.size, Image.Resampling.NEAREST)) > 0


def interior_components(mask: np.ndarray, bounds: tuple[int, int, int, int]) -> np.ndarray:
    """返回指定边界内不接触边界的连通区，用于补回旧瞳孔岛。"""

    x0, y0, x1, y1 = bounds
    local = mask[y0:y1, x0:x1]
    height, width = local.shape
    visited = np.zeros_like(local, dtype=bool)
    kept = np.zeros_like(local, dtype=bool)
    for y, x in zip(*np.where(local & ~visited), strict=False):
        if visited[y, x]:
            continue
        queue: deque[tuple[int, int]] = deque([(int(y), int(x))])
        visited[y, x] = True
        current: list[tuple[int, int]] = []
        touches_edge = False
        while queue:
            cy, cx = queue.popleft()
            current.append((cy, cx))
            touches_edge |= cy == 0 or cx == 0 or cy == height - 1 or cx == width - 1
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < height and 0 <= nx < width and local[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    queue.append((ny, nx))
        if not touches_edge:
            ys, xs = zip(*current, strict=False)
            kept[np.asarray(ys), np.asarray(xs)] = True

    output = np.zeros_like(mask, dtype=bool)
    output[y0:y1, x0:x1] = kept
    return output


def find_eye_mask(source_rgba: np.ndarray) -> np.ndarray:
    rgb = source_rgba[..., :3].astype(np.int16)
    alpha = source_rgba[..., 3]
    color_range = rgb.max(axis=2) - rgb.min(axis=2)
    white = (alpha > 96) & (rgb.min(axis=2) > 205) & (color_range < 14)
    opaque_candidate = largest_component(white)
    enclosed_candidate = enclosed_transparent_region(alpha)

    def plausible(mask: np.ndarray) -> bool:
        if mask.sum() < 800:
            return False
        ys, xs = np.where(mask)
        width = int(xs.max() - xs.min() + 1)
        height = int(ys.max() - ys.min() + 1)
        aspect = width / max(1, height)
        return width >= source_rgba.shape[1] * 0.14 and height <= source_rgba.shape[0] * 0.27 and 1.35 <= aspect <= 7.0

    # 跳绳等器械也会形成封闭区，只有符合胶囊比例的候选才可作为眼罩。
    if plausible(enclosed_candidate) and not plausible(opaque_candidate):
        candidate = enclosed_candidate
    elif plausible(opaque_candidate) and not plausible(enclosed_candidate):
        candidate = opaque_candidate
    else:
        candidate = enclosed_candidate if enclosed_candidate.sum() > opaque_candidate.sum() else opaque_candidate
    if candidate.sum() < 800:
        raise SystemExit("无法定位眼罩区域，已停止输出")
    ys, xs = np.where(candidate)
    bounds = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    dark = (source_rgba[..., 3] > 48) & (source_rgba[..., :3].mean(axis=2) < 120)
    old_eye_islands = interior_components(dark, bounds)
    expanded_islands = np.asarray(
        Image.fromarray((old_eye_islands.astype(np.uint8) * 255), mode="L").filter(ImageFilter.MaxFilter(9))
    ) > 127
    return close_mask(candidate | expanded_islands, 9)


def find_generated_eye_bounds(
    generated_rgb: np.ndarray,
    bounds: tuple[int, int, int, int],
) -> tuple[int, int, int, int] | None:
    """定位生成图眼罩，供表情和语义符号使用同一套对齐参数。"""

    x0, y0, x1, y1 = bounds
    width = x1 - x0
    height = y1 - y0
    search_x0 = max(0, x0 - width // 2)
    search_x1 = min(generated_rgb.shape[1], x1 + width // 2)
    search_y0 = max(0, y0 - height)
    search_y1 = min(generated_rgb.shape[0], y1 + height)
    crop = generated_rgb[search_y0:search_y1, search_x0:search_x1]
    crop16 = crop.astype(np.int16)
    white = (crop16.min(axis=2) > 225) & ((crop16.max(axis=2) - crop16.min(axis=2)) < 24)
    component = best_eye_component(white, width, height)
    if component.sum() < 800:
        return None

    ys, xs = np.where(component)
    gx0 = search_x0 + int(xs.min())
    gx1 = search_x0 + int(xs.max()) + 1
    gy0 = search_y0 + int(ys.min())
    gy1 = search_y0 + int(ys.max()) + 1
    return gx0, gy0, gx1, gy1


def align_generated_face(generated_rgb: np.ndarray, bounds: tuple[int, int, int, int]) -> np.ndarray:
    """按生成图眼罩与原图眼罩的边界对齐表情和嘴部。"""

    generated_bounds = find_generated_eye_bounds(generated_rgb, bounds)
    if generated_bounds is None:
        return generated_rgb

    x0, y0, x1, y1 = bounds
    width = x1 - x0
    height = y1 - y0
    gx0, gy0, gx1, gy1 = generated_bounds
    generated_eye_height = gy1 - gy0
    extra_source = max(46, int(height * 0.72))
    extra_generated = max(46, int(generated_eye_height * 0.72))
    face_crop = Image.fromarray(
        generated_rgb[gy0:min(generated_rgb.shape[0], gy1 + extra_generated), gx0:gx1],
        mode="RGB",
    )
    face_crop = face_crop.resize((width, height + extra_source), Image.Resampling.LANCZOS)
    aligned = generated_rgb.copy()
    aligned[y0:min(generated_rgb.shape[0], y1 + extra_source), x0:x1] = np.asarray(face_crop)[
        : min(generated_rgb.shape[0], y1 + extra_source) - y0
    ]
    return aligned


def align_generated_canvas(generated_rgb: np.ndarray, bounds: tuple[int, int, int, int]) -> np.ndarray:
    """按眼罩仿射对齐整张生成图，用于提取汗滴和灵感线。"""

    generated_bounds = find_generated_eye_bounds(generated_rgb, bounds)
    if generated_bounds is None:
        return generated_rgb

    x0, y0, x1, y1 = bounds
    gx0, gy0, gx1, gy1 = generated_bounds
    scale_x = (x1 - x0) / max(1, gx1 - gx0)
    scale_y = (y1 - y0) / max(1, gy1 - gy0)
    inverse = (
        1.0 / scale_x,
        0.0,
        gx0 - x0 / scale_x,
        0.0,
        1.0 / scale_y,
        gy0 - y0 / scale_y,
    )
    aligned = Image.fromarray(generated_rgb, mode="RGB").transform(
        (generated_rgb.shape[1], generated_rgb.shape[0]),
        Image.Transform.AFFINE,
        inverse,
        resample=Image.Resampling.BICUBIC,
    )
    return np.asarray(aligned, dtype=np.uint8)


def composite_color(base: np.ndarray, color: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    strength = alpha.astype(np.float32)[..., None] / 255.0
    return np.clip(base * (1.0 - strength) + color * strength, 0, 255).astype(np.uint8)


def main() -> None:
    args = parse_args()
    variant = args.variant or ("peach-light" if "peach-light" in str(args.source) else "navy")
    source = Image.open(args.source).convert("RGBA")
    generated = Image.open(args.generated).convert("RGB")
    if generated.size != source.size:
        generated = generated.resize(source.size, Image.Resampling.LANCZOS)

    source_rgba = np.asarray(source, dtype=np.uint8).copy()
    generated_rgb = np.asarray(generated, dtype=np.uint8)
    source_rgb = source_rgba[..., :3]
    source_alpha = source_rgba[..., 3]

    # 只增强原有头带和飘带的桃橙色，不重绘任何结构。
    rgb16 = source_rgb.astype(np.int16)
    orange_source = (
        (source_alpha > 24)
        & (rgb16[..., 0] > 205)
        & (rgb16[..., 0] - rgb16[..., 1] > 55)
        & (rgb16[..., 1] > 65)
        & (rgb16[..., 1] < 195)
        & (rgb16[..., 2] < 155)
    )
    stronger_orange = source_rgb.copy()
    stronger_orange[..., 0] = np.maximum(stronger_orange[..., 0], 245)
    stronger_orange[..., 1] = np.clip(stronger_orange[..., 1] * 0.92, 92, 178)
    stronger_orange[..., 2] = np.clip(stronger_orange[..., 2] * 0.72, 28, 125)
    source_rgb[orange_source] = stronger_orange[orange_source]

    eye_mask = find_eye_mask(source_rgba)
    ys, xs = np.where(eye_mask)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    eye_height = y1 - y0
    eye_width = x1 - x0

    # 使用纸白重置眼罩，清除旧圆点眼；外轮廓严格沿用原素材。
    source_rgb[eye_mask] = np.array([255, 253, 252], dtype=np.uint8)
    source_alpha[eye_mask] = 255

    aligned_face_rgb = align_generated_face(generated_rgb, (x0, y0, x1, y1))
    aligned_canvas_rgb = align_generated_canvas(generated_rgb, (x0, y0, x1, y1))
    generated_luma = (
        aligned_face_rgb[..., 0].astype(np.float32) * 0.2126
        + aligned_face_rgb[..., 1].astype(np.float32) * 0.7152
        + aligned_face_rgb[..., 2].astype(np.float32) * 0.0722
    )
    generated_range = aligned_face_rgb.max(axis=2).astype(np.int16) - aligned_face_rgb.min(axis=2).astype(np.int16)

    # 只从生成图提取眼罩内的墨兰表情笔画，白色高光自然保留为纸白。
    dark_strength = np.clip((165.0 - generated_luma) * 2.2, 0, 255).astype(np.uint8)
    expression_region = np.asarray(
        Image.fromarray((eye_mask.astype(np.uint8) * 255), mode="L").filter(ImageFilter.MinFilter(13))
    ) > 127
    eye_expression_alpha = np.where(expression_region, dark_strength, 0).astype(np.uint8)
    source_rgb[:] = composite_color(source_rgb, aligned_face_rgb, eye_expression_alpha)

    # 清除旧嘴并仅在眼罩下方的安全区域合成新嘴。
    mouth_y0 = max(0, y1 - 4)
    mouth_y1 = min(source.height, y1 + max(46, int(eye_height * 0.72)))
    mouth_x0 = max(0, x0 + int(eye_width * 0.18))
    mouth_x1 = min(source.width, x1 - int(eye_width * 0.18))
    mouth_roi = np.zeros_like(source_alpha, dtype=bool)
    mouth_roi[mouth_y0:mouth_y1, mouth_x0:mouth_x1] = True
    body_here = source_alpha > 80

    if variant == "navy":
        old_mouth = mouth_roi & orange_source
        mouth_generated = (
            mouth_roi
            & (aligned_face_rgb[..., 0] > 180)
            & (aligned_face_rgb[..., 0].astype(np.int16) - aligned_face_rgb[..., 2].astype(np.int16) > 55)
            & (aligned_face_rgb[..., 1] < 210)
        )
        mouth_color = np.array([255, 138, 76], dtype=np.uint8)
    else:
        old_mouth = mouth_roi & body_here & (source_rgb.mean(axis=2) < 105)
        mouth_generated = mouth_roi & (generated_luma < 105) & (generated_range < 80)
        mouth_color = np.array([17, 16, 31], dtype=np.uint8)
    sample_mask = mouth_roi & body_here & ~old_mouth
    if sample_mask.any():
        body_fill = np.median(source_rgb[sample_mask], axis=0).astype(np.uint8)
    else:
        body_fill = np.array([25, 23, 44] if variant == "navy" else [255, 226, 184], dtype=np.uint8)

    erase_image = Image.fromarray((old_mouth.astype(np.uint8) * 255), mode="L")
    erase_alpha = np.asarray(erase_image.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(2.0)))
    erase_color = np.broadcast_to(body_fill, source_rgb.shape)
    source_rgb[:] = composite_color(source_rgb, erase_color, erase_alpha)

    mouth_alpha = np.asarray(
        Image.fromarray((mouth_generated.astype(np.uint8) * 255), mode="L").filter(ImageFilter.GaussianBlur(0.8))
    )
    mouth_layer = np.broadcast_to(mouth_color, source_rgb.shape)
    source_rgb[:] = composite_color(source_rgb, mouth_layer, mouth_alpha)

    # 新增符号只取高饱和桃橙或青绿；避免把棋盘格及重绘偏移带回成品。
    cyan = (
        (aligned_canvas_rgb[..., 1] > 145)
        & (aligned_canvas_rgb[..., 2] > 120)
        & (aligned_canvas_rgb[..., 1].astype(np.int16) - aligned_canvas_rgb[..., 0].astype(np.int16) > 35)
    )
    orange = (
        (aligned_canvas_rgb[..., 0] > 210)
        & (aligned_canvas_rgb[..., 0].astype(np.int16) - aligned_canvas_rgb[..., 2].astype(np.int16) > 75)
        & (aligned_canvas_rgb[..., 1] < 205)
    )
    near_subject = dilate_mask(source_alpha > 24, 20)
    near_cyan = dilate_mask(cyan, 60)
    # 青绿只可能来自获准的情绪符号，可覆盖身体；橙色外部符号仍需位于主体外且邻近青绿标记。
    extra_mask = cyan | ((source_alpha < 24) & orange & ~near_subject & near_cyan)
    extra_alpha = np.asarray(
        Image.fromarray((extra_mask.astype(np.uint8) * 255), mode="L").filter(ImageFilter.GaussianBlur(0.8))
    )
    source_rgb[:] = composite_color(source_rgb, aligned_canvas_rgb, extra_alpha)
    source_alpha[:] = np.maximum(source_alpha, extra_alpha)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(source_rgba, mode="RGBA").save(args.output, format="PNG", optimize=True)
    print(args.output.resolve())


if __name__ == "__main__":
    main()
