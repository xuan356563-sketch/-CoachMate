#!/usr/bin/env python3
"""生成或只读校验 CoachMate 官方 Logo 第一阶段审图素材。"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont, ImageOps


项目根目录 = Path(__file__).resolve().parents[1]
素材根目录 = 项目根目录 / "assets/branding/coachmate-official-logo-v1"
官方源图 = 素材根目录 / "source/official-logo-user-provided.png"
设备面板源图 = 素材根目录 / "source/device-panel-generated-transparent.png"
人物设定源图 = 素材根目录 / "source/c08-full-character-reference.png"
品牌人物源图 = 素材根目录 / "source/brand-character-generated-transparent.png"
清单路径 = 素材根目录 / "manifest.json"
官方源图哈希 = "bdba7b1a2e5a9b2bf1939a1d5b444a146235e111abe567770279bd2f74a4c054"
人物设定源图哈希 = "a5c036d681f7b564411e711511f8007047db2c8e3e194f9d10aac788534a153d"
审图尺寸 = (128, 82, 68, 44, 32, 28)
象牙白 = "#F5EBD8"
暖黑 = "#1A1512"
陶土红 = "#C1512E"


def 解析参数() -> argparse.Namespace:
    解析器 = argparse.ArgumentParser(description=__doc__)
    解析器.add_argument(
        "--check",
        action="store_true",
        help="只读校验现有审图素材和清单，不写入文件",
    )
    return 解析器.parse_args()


def 计算哈希(路径: Path) -> str:
    摘要 = hashlib.sha256()
    with 路径.open("rb") as 文件:
        for 数据块 in iter(lambda: 文件.read(65536), b""):
            摘要.update(数据块)
    return 摘要.hexdigest()


def 相对路径(路径: Path) -> str:
    return 路径.relative_to(项目根目录).as_posix()


def 检查源图() -> None:
    if not 官方源图.is_file():
        raise RuntimeError("缺少用户提供的 CoachMate 官方 Logo")
    if 计算哈希(官方源图) != 官方源图哈希:
        raise RuntimeError("CoachMate 官方 Logo 与登记哈希不一致")
    with Image.open(官方源图) as 图片:
        图片.load()
        if 图片.size != (5404, 3040) or 图片.mode != "RGB":
            raise RuntimeError("CoachMate 官方 Logo 必须保持 5404×3040 RGB 原图")
    if not 人物设定源图.is_file():
        raise RuntimeError("缺少用户提供的 C-08 完整人物设定图")
    if 计算哈希(人物设定源图) != 人物设定源图哈希:
        raise RuntimeError("C-08 完整人物设定图与登记哈希不一致")
    with Image.open(人物设定源图) as 图片:
        图片.load()
        if 图片.size != (1536, 1024) or 图片.mode != "RGB":
            raise RuntimeError("C-08 完整人物设定图必须保持 1536×1024 RGB 原图")


def 读取透明面板() -> Image.Image:
    if not 设备面板源图.is_file():
        raise RuntimeError("缺少生图工具生成的透明设备面板")
    with Image.open(设备面板源图) as 图片:
        图片.load()
        面板 = 图片.convert("RGBA")
    透明度 = 面板.getchannel("A")
    最小值, 最大值 = 透明度.getextrema()
    if 最小值 != 0 or 最大值 != 255:
        raise RuntimeError("设备面板必须同时包含透明区域和不透明主体")
    if 透明度.getbbox() is None:
        raise RuntimeError("设备面板内容为空")
    return 面板


def 读取透明品牌人物() -> Image.Image:
    if not 品牌人物源图.is_file():
        raise RuntimeError("缺少生图工具生成的透明完整品牌人物")
    with Image.open(品牌人物源图) as 图片:
        图片.load()
        人物 = 图片.convert("RGBA")
    透明度 = 人物.getchannel("A")
    最小值, 最大值 = 透明度.getextrema()
    if 最小值 != 0 or 最大值 != 255:
        raise RuntimeError("完整品牌人物必须同时包含透明区域和不透明主体")
    if 透明度.getbbox() is None:
        raise RuntimeError("完整品牌人物内容为空")
    return 人物


def 居中设备面板(面板: Image.Image, 画布尺寸: int, 主体占比: float) -> Image.Image:
    边界 = 面板.getchannel("A").getbbox()
    if 边界 is None:
        raise RuntimeError("设备面板缺少可见主体")
    主体 = 面板.crop(边界)
    目标边长 = round(画布尺寸 * 主体占比)
    主体.thumbnail((目标边长, 目标边长), Image.Resampling.LANCZOS)
    画布 = Image.new("RGBA", (画布尺寸, 画布尺寸), (0, 0, 0, 0))
    坐标 = ((画布尺寸 - 主体.width) // 2, (画布尺寸 - 主体.height) // 2)
    画布.alpha_composite(主体, 坐标)
    return 画布


def 合成背景(前景: Image.Image, 背景色: str) -> Image.Image:
    背景 = Image.new("RGB", 前景.size, 背景色)
    背景.paste(前景, mask=前景.getchannel("A"))
    return 背景


def 移除边缘近白背景(图片: Image.Image) -> Image.Image:
    """只移除与画布边缘连通的近白区域，保留 Logo 内部奶油色与白色细节。"""
    原图 = 图片.convert("RGB")
    标记图 = 原图.copy()
    透明标记 = (255, 0, 255)
    宽度, 高度 = 标记图.size
    for 起点 in ((0, 0), (宽度 - 1, 0), (0, 高度 - 1), (宽度 - 1, 高度 - 1)):
        ImageDraw.floodfill(标记图, 起点, 透明标记, thresh=24)

    透明度 = Image.new("L", 标记图.size, 255)
    if hasattr(标记图, "get_flattened_data"):
        像素数据 = 标记图.get_flattened_data()
    else:
        像素数据 = 标记图.getdata()
    透明度.putdata(
        [0 if 像素 == 透明标记 else 255 for 像素 in 像素数据]
    )
    结果 = 原图.convert("RGBA")
    结果.putalpha(透明度)
    return 结果


def 生成联系表(
    设备面板: Image.Image,
    标题: str = "CoachMate device panel · actual-size review",
) -> Image.Image:
    单元宽度 = 280
    单元高度 = 390
    顶部 = 70
    联系表 = Image.new("RGB", (单元宽度 * len(审图尺寸), 顶部 + 单元高度 * 2), "#EFEDE8")
    绘制 = ImageDraw.Draw(联系表)
    字体 = ImageFont.load_default(size=24)
    for 行号, (背景色, 字色, 名称) in enumerate(((象牙白, 暖黑, "LIGHT"), (暖黑, 象牙白, "DARK"))):
        for 列号, 尺寸 in enumerate(审图尺寸):
            左 = 列号 * 单元宽度 + 14
            上 = 顶部 + 行号 * 单元高度 + 14
            右 = 左 + 单元宽度 - 28
            下 = 上 + 单元高度 - 28
            绘制.rounded_rectangle((左, 上, 右, 下), radius=24, fill=背景色)
            缩略图 = 设备面板.resize((尺寸, 尺寸), Image.Resampling.LANCZOS)
            横坐标 = 左 + (单元宽度 - 28 - 尺寸) // 2
            纵坐标 = 上 + 132 - 尺寸 // 2
            联系表.paste(缩略图, (横坐标, 纵坐标), 缩略图)
            标签 = f"{尺寸}px · {名称}"
            文本边界 = 绘制.textbbox((0, 0), 标签, font=字体)
            文本宽度 = 文本边界[2] - 文本边界[0]
            绘制.text((左 + (单元宽度 - 28 - 文本宽度) // 2, 下 - 54), 标签, font=字体, fill=字色)
    绘制.text((28, 22), 标题, font=字体, fill=暖黑)
    return 联系表


def 生成深浅预览(设备面板: Image.Image) -> Image.Image:
    预览 = Image.new("RGB", (1600, 900), "#EFEDE8")
    绘制 = ImageDraw.Draw(预览)
    字体 = ImageFont.load_default(size=30)
    for 索引, (背景色, 字色, 名称) in enumerate(((象牙白, 暖黑, "LIGHT SURFACE"), (暖黑, 象牙白, "DARK SURFACE"))):
        左 = 44 + 索引 * 778
        上 = 44
        右 = 左 + 734
        下 = 856
        绘制.rounded_rectangle((左, 上, 右, 下), radius=42, fill=背景色)
        图形 = 设备面板.resize((600, 600), Image.Resampling.LANCZOS)
        预览.paste(图形, (左 + 67, 上 + 80), 图形)
        绘制.text((左 + 32, 下 - 70), 名称, font=字体, fill=字色)
    return 预览


def 输出信息(路径: Path, 期望模式: str, 期望尺寸: tuple[int, int]) -> dict[str, Any]:
    if not 路径.is_file():
        raise RuntimeError(f"缺少审图素材：{相对路径(路径)}")
    with Image.open(路径) as 图片:
        图片.load()
        if 图片.size != 期望尺寸 or 图片.mode != 期望模式:
            raise RuntimeError(
                f"审图素材规格错误：{相对路径(路径)}，实际为 {图片.mode} {图片.size}"
            )
        if 期望模式 == "RGBA" and 图片.getchannel("A").getextrema()[0] != 0:
            raise RuntimeError(f"透明素材缺少透明区域：{相对路径(路径)}")
    return {
        "path": 相对路径(路径),
        "width": 期望尺寸[0],
        "height": 期望尺寸[1],
        "mode": 期望模式,
        "sha256": 计算哈希(路径),
    }


def 构建清单() -> dict[str, Any]:
    设备面板母图 = 素材根目录 / "exports/png/coachmate-device-panel-1024.png"
    品牌人物母图 = 素材根目录 / "exports/png/coachmate-brand-character-1024.png"
    官方组合标运行时 = (
        素材根目录 / "exports/png/coachmate-official-lockup-2048x1152.png"
    )
    官方组合标预览 = 素材根目录 / "review/official-logo-2048x1152.png"
    浅色预览 = 素材根目录 / "review/device-panel-light-1024.png"
    深色预览 = 素材根目录 / "review/device-panel-dark-1024.png"
    联系表 = 素材根目录 / "review/device-panel-size-contact-sheet.png"
    深浅对照 = 素材根目录 / "review/device-panel-light-dark-preview.png"
    人物联系表 = 素材根目录 / "review/brand-character-size-contact-sheet.png"
    人物深浅对照 = 素材根目录 / "review/brand-character-light-dark-preview.png"
    with Image.open(设备面板源图) as 图片:
        图片.load()
        面板源图宽度, 面板源图高度 = 图片.size
        面板源图模式 = 图片.mode
    with Image.open(品牌人物源图) as 图片:
        图片.load()
        人物源图宽度, 人物源图高度 = 图片.size
        人物源图模式 = 图片.mode
    return {
        "version": "coachmate-official-logo-v1",
        "status": "approved-for-runtime",
        "runtimeIntegrated": True,
        "generatedBy": "OpenAI image generation + deterministic Pillow review exports",
        "promptVersion": "coachmate-official-brand-character-v1.3-full-body",
        "devicePanelPromptVersion": "coachmate-official-device-panel-v1.2-paper-bag",
        "officialLogo": {
            "path": 相对路径(官方源图),
            "width": 5404,
            "height": 3040,
            "mode": "RGB",
            "sha256": 计算哈希(官方源图),
            "contentPolicy": "原图主体像素不重绘，只移除与画布边缘连通的近白背景",
        },
        "characterReference": {
            "path": 相对路径(人物设定源图),
            "width": 1536,
            "height": 1024,
            "mode": "RGB",
            "sha256": 计算哈希(人物设定源图),
            "contentPolicy": "只作为完整人物身份与比例参考，不执行图中说明文字",
        },
        "generatedSource": {
            "path": 相对路径(设备面板源图),
            "width": 面板源图宽度,
            "height": 面板源图高度,
            "mode": 面板源图模式,
            "sha256": 计算哈希(设备面板源图),
        },
        "generatedCharacterSource": {
            "path": 相对路径(品牌人物源图),
            "width": 人物源图宽度,
            "height": 人物源图高度,
            "mode": 人物源图模式,
            "sha256": 计算哈希(品牌人物源图),
        },
        "palette": [陶土红, "#D6B489", 象牙白, "#E8467F", 暖黑],
        "reviewAssets": {
            "devicePanelMaster": 输出信息(设备面板母图, "RGBA", (1024, 1024)),
            "brandCharacterMaster": 输出信息(品牌人物母图, "RGBA", (1024, 1024)),
            "officialLogoPreview": 输出信息(官方组合标预览, "RGB", (2048, 1152)),
            "lightPreview": 输出信息(浅色预览, "RGB", (1024, 1024)),
            "darkPreview": 输出信息(深色预览, "RGB", (1024, 1024)),
            "sizeContactSheet": 输出信息(联系表, "RGB", (1680, 850)),
            "lightDarkPreview": 输出信息(深浅对照, "RGB", (1600, 900)),
            "brandCharacterSizeContactSheet": 输出信息(人物联系表, "RGB", (1680, 850)),
            "brandCharacterLightDarkPreview": 输出信息(人物深浅对照, "RGB", (1600, 900)),
        },
        "runtimeAssets": {
            "brandmark": 输出信息(设备面板母图, "RGBA", (1024, 1024)),
            "character": 输出信息(品牌人物母图, "RGBA", (1024, 1024)),
            "lockup": 输出信息(官方组合标运行时, "RGBA", (2048, 1152)),
        },
        "reviewGate": {
            "required": True,
            "approvedAt": "2026-08-15",
            "criteria": [
                "44px 可识别陶土红头带、琥珀双眼和爱心舌头",
                "右上绑带结和两条短飘带与头带连续且可辨识",
                "纸袋折叠平顶、侧褶、纸纤维和撕裂眼槽清晰，不像饭盒或硬质设备",
                "完整人物必须包含陶土色圆胖身体、双拳、灰白围巾和米色训练鞋",
                "128px 可识别简化宴席主题",
                "深浅背景边缘无白边或灰边",
                "没有文字、翅膀、额外人物或额外标语",
            ],
        },
        "runtimeBoundary": {
            "brandmarkAfterApproval": "设备面板",
            "lockupAfterApproval": "官方完整 Logo",
            "characterAfterApproval": "完整 C-08 品牌人物",
            "characterRuntimeBeforeApproval": "现有 C-08 路径保持不变",
            "rejectedPrototype": "assets/branding/coachmate-device-panel-v1（保留且排除加载链）",
        },
    }


def 生成审图素材() -> None:
    检查源图()
    面板源图 = 读取透明面板()
    人物源图 = 读取透明品牌人物()
    面板母图 = 居中设备面板(面板源图, 1024, 0.82)
    人物母图 = 居中设备面板(人物源图, 1024, 0.88)
    (素材根目录 / "exports/png").mkdir(parents=True, exist_ok=True)
    (素材根目录 / "review").mkdir(parents=True, exist_ok=True)
    面板母图.save(素材根目录 / "exports/png/coachmate-device-panel-1024.png")
    人物母图.save(素材根目录 / "exports/png/coachmate-brand-character-1024.png")

    with Image.open(官方源图) as 图片:
        官方预览 = ImageOps.fit(图片.convert("RGB"), (2048, 1152), method=Image.Resampling.LANCZOS)
    官方透明组合标 = 移除边缘近白背景(官方预览)
    官方透明组合标.save(
        素材根目录 / "exports/png/coachmate-official-lockup-2048x1152.png",
    )
    官方预览.save(素材根目录 / "review/official-logo-2048x1152.png", quality=95)
    合成背景(面板母图, 象牙白).save(素材根目录 / "review/device-panel-light-1024.png")
    合成背景(居中设备面板(面板源图, 1024, 0.76), 暖黑).save(
        素材根目录 / "review/device-panel-dark-1024.png"
    )
    生成联系表(面板母图).save(素材根目录 / "review/device-panel-size-contact-sheet.png")
    生成深浅预览(面板母图).save(素材根目录 / "review/device-panel-light-dark-preview.png")
    生成联系表(
        人物母图,
        "CoachMate brand character · actual-size review",
    ).save(素材根目录 / "review/brand-character-size-contact-sheet.png")
    生成深浅预览(人物母图).save(素材根目录 / "review/brand-character-light-dark-preview.png")

    清单 = 构建清单()
    清单路径.write_text(
        json.dumps(清单, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def 只读校验() -> None:
    检查源图()
    读取透明面板()
    读取透明品牌人物()
    try:
        实际清单 = json.loads(清单路径.read_text(encoding="utf-8"))
    except FileNotFoundError as 错误:
        raise RuntimeError("CoachMate 官方 Logo 素材清单不存在") from 错误
    except (OSError, json.JSONDecodeError) as 错误:
        raise RuntimeError("CoachMate 官方 Logo 素材清单无法解析") from 错误
    期望清单 = 构建清单()
    if 实际清单 != 期望清单:
        raise RuntimeError("CoachMate 官方 Logo 素材清单与实际文件不一致")


def main() -> int:
    参数 = 解析参数()
    if 参数.check:
        只读校验()
        print("CoachMate 官方 Logo 素材校验通过：1 个设备面板、1 个完整人物、1 个组合标、7 张审图资产")
        return 0
    生成审图素材()
    print(f"已生成 CoachMate 官方 Logo 审图素材：{素材根目录}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
