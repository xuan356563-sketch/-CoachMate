#!/usr/bin/env python3
"""生成或只读校验 MATE C-08 素材清单。"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image


项目根目录 = Path(__file__).resolve().parents[1]
素材根目录 = 项目根目录 / "assets/branding/mate-feast-bag-v2"
清单路径 = 素材根目录 / "manifest.json"
动作名称 = (
    "01-pointing-guide",
    "02-running",
    "03-side-lunge-stretch",
    "04-seated-meditation",
    "05-jumping-jack",
    "06-high-knees",
    "07-sprint",
    "08-jump-rope",
    "09-burpee",
    "10-squat",
    "11-forward-lunge",
    "12-push-up",
    "13-plank",
    "14-mountain-climber",
    "15-sit-up-crunch",
    "16-dumbbell-curl",
    "17-dumbbell-overhead-press",
    "18-standing-side-stretch",
    "19-seated-forward-fold",
    "20-tree-pose-balance",
)
成长阶段 = ("pattern_egg", "sprout", "junior", "advanced", "champion")
伙伴心情 = ("excited", "happy", "curious", "calm", "waiting")


def 解析参数() -> argparse.Namespace:
    解析器 = argparse.ArgumentParser(description=__doc__)
    解析器.add_argument(
        "--check",
        action="store_true",
        help="只读复算清单并校验，不改写文件",
    )
    return 解析器.parse_args()


def 相对路径(路径: Path) -> str:
    return 路径.relative_to(项目根目录).as_posix()


def 计算哈希(路径: Path) -> str:
    摘要 = hashlib.sha256()
    with 路径.open("rb") as 文件:
        for 数据块 in iter(lambda: 文件.read(65536), b""):
            摘要.update(数据块)
    return 摘要.hexdigest()


def 图片信息(路径: Path) -> dict[str, Any]:
    if not 路径.is_file():
        raise RuntimeError(f"缺少 MATE C-08 素材：{相对路径(路径)}")
    with Image.open(路径) as 图片:
        图片.load()
        if 图片.format != "PNG" or 图片.mode != "RGBA":
            raise RuntimeError(f"素材必须是 RGBA PNG：{相对路径(路径)}")
        if 图片.getchannel("A").getextrema()[0] == 255:
            raise RuntimeError(f"素材缺少透明区域：{相对路径(路径)}")
        宽度, 高度 = 图片.size
    return {
        "path": 相对路径(路径),
        "width": 宽度,
        "height": 高度,
        "sha256": 计算哈希(路径),
    }


def 审核总览信息(路径: Path) -> dict[str, Any]:
    if not 路径.is_file():
        raise RuntimeError(f"缺少 MATE C-08 审核总览：{相对路径(路径)}")
    with Image.open(路径) as 图片:
        图片.load()
        if 图片.format != "PNG" or 图片.mode != "RGB":
            raise RuntimeError("MATE C-08 审核总览必须是 RGB PNG")
        if 图片.size != (1600, 2200):
            raise RuntimeError("MATE C-08 审核总览必须是 1600×2200")
        宽度, 高度 = 图片.size
    return {
        "path": 相对路径(路径),
        "width": 宽度,
        "height": 高度,
        "sha256": 计算哈希(路径),
    }


def 生成清单() -> dict[str, Any]:
    参考路径 = 素材根目录 / "source/mate-character-sheet-user-provided-v2.png"
    if not 参考路径.is_file():
        raise RuntimeError("缺少用户提供的 C-08 角色设定图")
    with Image.open(参考路径) as 参考图:
        参考图.load()
        参考宽度, 参考高度 = 参考图.size

    动作: dict[str, Any] = {}
    for 名称 in 动作名称:
        母图 = 图片信息(素材根目录 / f"source/action-masters/{名称}.png")
        动作[名称] = {
            "masterPath": 母图["path"],
            "masterSha256": 母图["sha256"],
            "variants": {
                "navy": 图片信息(
                    素材根目录 / f"action-characters/navy/{名称}.png"
                ),
                "peach-light": 图片信息(
                    素材根目录 / f"action-characters/peach-light/{名称}.png"
                ),
            },
        }

    伙伴状态: dict[str, Any] = {}
    for 阶段 in 成长阶段:
        for 心情 in 伙伴心情:
            标识 = f"{阶段}-{心情}"
            伙伴状态[标识] = 图片信息(
                素材根目录 / f"companion-states/{标识}.png"
            )

    品牌资产 = {
        "character": 图片信息(
            素材根目录 / "exports/png/mate-feast-character-1024.png"
        ),
        "brandmark": 图片信息(
            素材根目录 / "exports/png/mate-feast-brandmark-1024.png"
        ),
        "compactMark": 图片信息(
            素材根目录 / "exports/png/mate-feast-compact-mark-1024.png"
        ),
    }

    return {
        "version": "mate-feast-bag-v2",
        "status": "pending-human-visual-review",
        "generatedBy": "OpenAI image generation + deterministic runtime export",
        "promptVersion": "mate-feast-c08-v2.0",
        "palette": [
            "#C1512E",
            "#D6B489",
            "#F5EBD8",
            "#E8467F",
            "#1A1512",
            "#2438CE",
        ],
        "reference": {
            "path": 相对路径(参考路径),
            "width": 参考宽度,
            "height": 参考高度,
            "sha256": 计算哈希(参考路径),
        },
        "actions": 动作,
        "companionStates": 伙伴状态,
        "brandAssets": 品牌资产,
        "reviewOverview": 审核总览信息(
            素材根目录 / "review/action-overview.png"
        ),
        "runtimeEligibility": {
            "c08": "eligible-after-contract-checks",
            "c07": "archive-only",
        },
    }


def main() -> int:
    参数 = 解析参数()
    期望清单 = 生成清单()
    if 参数.check:
        try:
            实际清单 = json.loads(清单路径.read_text(encoding="utf-8"))
        except FileNotFoundError as 错误:
            raise RuntimeError("MATE C-08 素材清单不存在") from 错误
        except (OSError, json.JSONDecodeError) as 错误:
            raise RuntimeError("MATE C-08 素材清单无法解析") from 错误
        if 实际清单 != 期望清单:
            raise RuntimeError("MATE C-08 素材清单与实际文件不一致")
        print("MATE C-08 素材清单校验通过：20 动作、25 伙伴状态、3 品牌资产")
        return 0

    清单路径.write_text(
        json.dumps(期望清单, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"已生成 MATE C-08 素材清单：{清单路径}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
