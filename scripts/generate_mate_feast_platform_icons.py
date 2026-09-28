#!/usr/bin/env python3
"""从 MATE C-08 小尺寸品牌标生成 iOS、Android 与 Web 图标。"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
import tempfile
from pathlib import Path

from PIL import Image


项目根目录 = Path(__file__).resolve().parents[1]
源图 = (
    项目根目录
    / "assets/branding/mate-feast-bag-v2/exports/png/mate-feast-compact-mark-1024.png"
)
IOS图标集 = 项目根目录 / "ios/Runner/Assets.xcassets/MateFeastIcon.appiconset"
背景色 = "#F5EBD8"

IOS槽位 = (
    ("iphone", "20x20", "2x", 40),
    ("iphone", "20x20", "3x", 60),
    ("iphone", "29x29", "1x", 29),
    ("iphone", "29x29", "2x", 58),
    ("iphone", "29x29", "3x", 87),
    ("iphone", "40x40", "2x", 80),
    ("iphone", "40x40", "3x", 120),
    ("iphone", "60x60", "2x", 120),
    ("iphone", "60x60", "3x", 180),
    ("ipad", "20x20", "1x", 20),
    ("ipad", "20x20", "2x", 40),
    ("ipad", "29x29", "1x", 29),
    ("ipad", "29x29", "2x", 58),
    ("ipad", "40x40", "1x", 40),
    ("ipad", "40x40", "2x", 80),
    ("ipad", "76x76", "1x", 76),
    ("ipad", "76x76", "2x", 152),
    ("ipad", "83.5x83.5", "2x", 167),
    ("ios-marketing", "1024x1024", "1x", 1024),
)
安卓尺寸 = {
    "mipmap-mdpi/ic_trainmate_mate_feast.png": 48,
    "mipmap-hdpi/ic_trainmate_mate_feast.png": 72,
    "mipmap-xhdpi/ic_trainmate_mate_feast.png": 96,
    "mipmap-xxhdpi/ic_trainmate_mate_feast.png": 144,
    "mipmap-xxxhdpi/ic_trainmate_mate_feast.png": 192,
}
网页尺寸 = {
    "web/icons/mate-feast/Icon-192.png": (192, False),
    "web/icons/mate-feast/Icon-512.png": (512, False),
    "web/icons/mate-feast/Icon-maskable-192.png": (192, True),
    "web/icons/mate-feast/Icon-maskable-512.png": (512, True),
    "web/mate-feast-favicon.png": (64, False),
}


def _哈希(内容: bytes) -> str:
    return hashlib.sha256(内容).hexdigest()


def _读取主体() -> Image.Image:
    with Image.open(源图) as 图片:
        if 图片.size != (1024, 1024) or 图片.mode != "RGBA":
            raise ValueError("MATE C-08 小尺寸品牌标必须为 1024×1024 RGBA PNG")
        边界 = 图片.getchannel("A").getbbox()
        if 边界 is None:
            raise ValueError("MATE C-08 小尺寸品牌标没有可见像素")
        return 图片.crop(边界).copy()


def _母版(主体: Image.Image, *, 安全区: bool) -> Image.Image:
    画布 = Image.new("RGB", (1024, 1024), 背景色)
    占比 = 0.60 if 安全区 else 0.78
    最大边 = round(1024 * 占比)
    比例 = min(最大边 / 主体.width, 最大边 / 主体.height)
    尺寸 = (round(主体.width * 比例), round(主体.height * 比例))
    缩放图 = 主体.resize(尺寸, Image.Resampling.LANCZOS)
    画布.paste(
        缩放图,
        ((1024 - 尺寸[0]) // 2, (1024 - 尺寸[1]) // 2),
        缩放图,
    )
    return 画布


def _PNG(图片: Image.Image, 尺寸: int) -> bytes:
    输出 = io.BytesIO()
    图片.resize((尺寸, 尺寸), Image.Resampling.LANCZOS).save(
        输出,
        format="PNG",
        optimize=False,
        compress_level=9,
    )
    return 输出.getvalue()


def _文件名(idiom: str, 尺寸: str, 倍率: str) -> str:
    return f"MateFeast-{idiom}-{尺寸.replace('.', '-')}@{倍率}.png"


def _预期文件() -> dict[Path, bytes]:
    主体 = _读取主体()
    标准母版 = _母版(主体, 安全区=False)
    安全母版 = _母版(主体, 安全区=True)
    文件: dict[Path, bytes] = {}
    内容项: list[dict[str, str]] = []
    for idiom, 尺寸, 倍率, 像素 in IOS槽位:
        文件名 = _文件名(idiom, 尺寸, 倍率)
        内容项.append(
            {"size": 尺寸, "idiom": idiom, "filename": 文件名, "scale": 倍率}
        )
        文件[IOS图标集 / 文件名] = _PNG(标准母版, 像素)
    文件[IOS图标集 / "Contents.json"] = (
        json.dumps(
            {"images": 内容项, "info": {"version": 1, "author": "xcode"}},
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    ).encode()
    for 相对路径, 像素 in 安卓尺寸.items():
        文件[项目根目录 / "android/app/src/main/res" / 相对路径] = _PNG(
            标准母版, 像素
        )
    for 相对路径, (像素, 使用安全区) in 网页尺寸.items():
        文件[项目根目录 / 相对路径] = _PNG(
            安全母版 if 使用安全区 else 标准母版, 像素
        )
    return 文件


def _写入(路径: Path, 内容: bytes) -> None:
    路径.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=路径.parent, delete=False) as 临时文件:
        临时文件.write(内容)
        临时路径 = Path(临时文件.name)
    临时路径.replace(路径)


def _验证配置() -> None:
    工程 = (项目根目录 / "ios/Runner.xcodeproj/project.pbxproj").read_text()
    if 工程.count("ASSETCATALOG_COMPILER_APPICON_NAME = MateFeastIcon;") != 3:
        raise ValueError("iOS 三个构建配置必须共同指向 MateFeastIcon")
    安卓配置 = (项目根目录 / "android/app/src/main/AndroidManifest.xml").read_text()
    if 'android:icon="@mipmap/ic_trainmate_mate_feast"' not in 安卓配置:
        raise ValueError("AndroidManifest.xml 尚未指向 MATE C-08 图标")
    网页配置 = json.loads((项目根目录 / "web/manifest.json").read_text())
    预期 = [
        "icons/mate-feast/Icon-192.png",
        "icons/mate-feast/Icon-512.png",
        "icons/mate-feast/Icon-maskable-192.png",
        "icons/mate-feast/Icon-maskable-512.png",
    ]
    if [项目["src"] for 项目 in 网页配置["icons"]] != 预期:
        raise ValueError("Web manifest 尚未精确指向 MATE C-08 图标")
    首页 = (项目根目录 / "web/index.html").read_text()
    if (
        'href="icons/mate-feast/Icon-192.png"' not in 首页
        or 'href="mate-feast-favicon.png"' not in 首页
    ):
        raise ValueError("Web index 尚未指向 MATE C-08 图标")


def _检查() -> dict[str, object]:
    预期文件 = _预期文件()
    for 路径, 内容 in 预期文件.items():
        if not 路径.is_file() or _哈希(路径.read_bytes()) != _哈希(内容):
            raise ValueError(f"MATE C-08 图标内容不一致：{路径.relative_to(项目根目录)}")
        if 路径.suffix == ".png":
            with Image.open(路径) as 图片:
                if 图片.mode != "RGB":
                    raise ValueError(
                        f"MATE C-08 图标必须完全不透明：{路径.relative_to(项目根目录)}"
                    )
    return {
        "status": "ok",
        "activeConfiguration": False,
        "ios": len(IOS槽位),
        "android": len(安卓尺寸),
        "web": len(网页尺寸),
    }


def main() -> int:
    解析器 = argparse.ArgumentParser(description=__doc__)
    解析器.add_argument("--check", action="store_true", help="只读复算图标、尺寸与三端配置")
    参数 = 解析器.parse_args()
    try:
        if 参数.check:
            结果 = _检查()
        else:
            for 路径, 内容 in _预期文件().items():
                _写入(路径, 内容)
            结果 = {
                "status": "generated",
                "ios": len(IOS槽位),
                "android": len(安卓尺寸),
                "web": len(网页尺寸),
            }
        print(json.dumps(结果, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as 错误:
        print(f"MATE C-08 平台图标处理失败：{错误}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
