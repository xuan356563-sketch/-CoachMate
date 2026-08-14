from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


脚本路径 = Path(__file__).resolve().parents[1] / "normalize_action_character_assets.py"
模块规格 = importlib.util.spec_from_file_location("normalize_action_characters", 脚本路径)
if 模块规格 is None or 模块规格.loader is None:
    raise RuntimeError("无法加载人物资产规范化脚本")
人物资产 = importlib.util.module_from_spec(模块规格)
模块规格.loader.exec_module(人物资产)


class 人物资产规范测试(unittest.TestCase):
    def test_两套运行时人物数量尺寸透明通道和安全区正确(self) -> None:
        文件名组 = 人物资产.动作文件名()
        报告 = 人物资产.校验输出(文件名组)

        self.assertEqual(20, len(文件名组))
        self.assertEqual(40, 报告["files"])
        self.assertLessEqual(报告["maxCenterOffset"], 2)
        self.assertLessEqual(
            报告["maxSubjectEdge"],
            人物资产.主体最大边长 + 2,
        )

    def test_原稿和运行时目录完全分离(self) -> None:
        for 目录 in 人物资产.原稿目录.values():
            self.assertNotEqual(目录.resolve(), 人物资产.输出根目录.resolve())
            self.assertEqual(20, len([路径 for 路径 in 目录.glob("*.png") if not 路径.name.startswith(".")]))


if __name__ == "__main__":
    unittest.main()
