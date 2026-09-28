"""Android 本地数据备份与迁移规则合同测试。"""

from __future__ import annotations

import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


项目根目录 = Path(__file__).resolve().parents[2]
安卓目录 = 项目根目录 / "android/app/src/main"
全部持久化域 = {
    "root",
    "file",
    "database",
    "sharedpref",
    "external",
    "device_root",
    "device_file",
    "device_database",
    "device_sharedpref",
}
安卓命名空间 = "http://schemas.android.com/apk/res/android"


def 排除域集合(节点: ET.Element) -> set[str]:
    return {
        排除.attrib["domain"]
        for 排除 in 节点.findall("exclude")
        if 排除.attrib.get("path") == "."
    }


class Android备份规则测试(unittest.TestCase):
    def test_manifest关闭备份并同时引用新旧规则(self) -> None:
        根节点 = ET.parse(安卓目录 / "AndroidManifest.xml").getroot()
        应用 = 根节点.find("application")
        self.assertIsNotNone(应用)
        assert 应用 is not None
        self.assertEqual(应用.attrib[f"{{{安卓命名空间}}}allowBackup"], "false")
        self.assertEqual(
            应用.attrib[f"{{{安卓命名空间}}}fullBackupContent"],
            "@xml/backup_rules",
        )
        self.assertEqual(
            应用.attrib[f"{{{安卓命名空间}}}dataExtractionRules"],
            "@xml/data_extraction_rules",
        )

    def test_android十一及以下排除全部持久化域(self) -> None:
        根节点 = ET.parse(安卓目录 / "res/xml/backup_rules.xml").getroot()
        self.assertEqual(根节点.tag, "full-backup-content")
        self.assertEqual(排除域集合(根节点), 全部持久化域)

    def test_android十二及以上云备份和设备迁移均排除全部域(self) -> None:
        根节点 = ET.parse(
            安卓目录 / "res/xml/data_extraction_rules.xml"
        ).getroot()
        for 标签 in ("cloud-backup", "device-transfer"):
            节点 = 根节点.find(标签)
            self.assertIsNotNone(节点, f"缺少 {标签} 规则")
            assert 节点 is not None
            self.assertEqual(排除域集合(节点), 全部持久化域)


if __name__ == "__main__":
    unittest.main()
