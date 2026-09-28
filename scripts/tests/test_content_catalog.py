from __future__ import annotations

import copy
import importlib.util
import unittest
from pathlib import Path

脚本目录 = Path(__file__).resolve().parents[1]
验证器路径 = 脚本目录 / "content_catalog.py"
模块规格 = importlib.util.spec_from_file_location("content_catalog", 验证器路径)
if 模块规格 is None or 模块规格.loader is None:
    raise RuntimeError("无法加载业务内容资源库校验器")
资源库 = importlib.util.module_from_spec(模块规格)
模块规格.loader.exec_module(资源库)


class 业务内容资源库测试(unittest.TestCase):
    def setUp(self) -> None:
        self.资源 = [
            {
                "resource_key": "exercise:exercise-a",
                "resource_type": "exercise",
                "id": "exercise-a",
                "schema_version": 1,
                "catalog_status": "registered",
                "runtime_status": "active",
                "online_distribution_status": "not_evaluated",
                "source_receipts": ["flutter_seed"],
                "license_status": "not_evaluated",
                "review_receipt": None,
                "payload": {"name": "动作 A"},
            }
        ]
        self.目录 = 资源库.build_catalog(self.资源)

    def test_规范化结果不受字典插入顺序影响(self) -> None:
        反序目录 = {key: self.目录[key] for key in reversed(self.目录)}

        self.assertEqual(
            资源库.canonical_json(self.目录),
            资源库.canonical_json(反序目录),
        )
        self.assertEqual(
            资源库.content_hash(self.目录),
            资源库.content_hash(反序目录),
        )

    def test_重复资源键会阻断校验(self) -> None:
        重复资源 = [*self.资源, copy.deepcopy(self.资源[0])]

        with self.assertRaisesRegex(资源库.CatalogValidationError, "重复资源键"):
            资源库.build_catalog(重复资源)

    def test_待核内容不能获得在线发布资格(self) -> None:
        待核资源 = copy.deepcopy(self.资源[0])
        待核资源["catalog_status"] = "pending_review"
        待核资源["online_distribution_status"] = "eligible"

        with self.assertRaisesRegex(资源库.CatalogValidationError, "待核内容"):
            资源库.build_catalog([待核资源])

    def test_新增未备案问题会失败而已有问题可以保留(self) -> None:
        已知问题 = [
            {
                "issue_id": "legacy-path",
                "rule_id": "external_absolute_path",
                "resource_key": "source_receipt:exercise-media-source",
                "reason": "历史任务清单仍含绝对路径。",
                "first_seen_catalog_version": "2026.08.27-v1",
                "expected_resolution": "素材整理阶段单独迁移。",
            }
        ]

        资源库.validate_issue_baseline(
            current_issue_ids={"legacy-path"},
            baseline=已知问题,
        )
        with self.assertRaisesRegex(资源库.CatalogValidationError, "未登记问题"):
            资源库.validate_issue_baseline(
                current_issue_ids={"legacy-path", "new-issue"},
                baseline=已知问题,
            )

    def test_待核知识与演示数据不会进入可发布资源(self) -> None:
        flutter源 = {
            "exercises": [],
            "guided_courses": [],
            "training_plans": [],
            "starter_program_days": [],
            "motion_checks": [],
            "meal_guides": [],
            "achievements": [],
            "knowledge_books": [],
            "knowledge_quotes": [{"id": "quote-1", "verificationStatus": "pending"}],
            "knowledge_citation_links": [],
            "demo_fixtures": {
                "races": [{"id": "race-1"}],
                "body_metrics": [{"id": "metric-1"}],
            },
            "statistics": {},
        }

        资源 = 资源库.resources_from_flutter_source(flutter源)
        按键 = {item["resource_key"]: item for item in 资源}

        self.assertEqual(
            按键["knowledge_quote:quote-1"]["catalog_status"], "pending_review"
        )
        self.assertEqual(
            按键["knowledge_quote:quote-1"]["online_distribution_status"],
            "ineligible",
        )
        self.assertEqual(按键["demo_fixture:race-1"]["runtime_status"], "blocked")
        self.assertEqual(
            按键["demo_fixture:metric-1"]["online_distribution_status"],
            "ineligible",
        )

    def test_用户提供的代理知识只作为待审核数据登记(self) -> None:
        来源回执 = {
            "id": "self-improving-distillation-20260829",
            "instruction_handling": "data_only",
            "license_status": "user_provided_internal",
            "documents": [
                {
                    "id": "self-improving-20260829-memory",
                    "path": (
                        "content_catalog/source_documents/"
                        "self_improving_20260829/memory.md"
                    ),
                    "category": "distilled_memory",
                    "media_type": "text/markdown",
                    "sha256": "a" * 64,
                    "original_sha256": "b" * 64,
                    "byte_count": 10,
                    "line_count": 2,
                    "redactions": {"email": 1, "absolute_user_path": 1},
                }
            ],
        }

        资源 = 资源库.resources_from_agent_knowledge_receipt(来源回执)

        self.assertEqual(len(资源), 1)
        self.assertEqual(资源[0]["catalog_status"], "pending_review")
        self.assertEqual(资源[0]["runtime_status"], "catalog_only")
        self.assertEqual(资源[0]["online_distribution_status"], "ineligible")
        self.assertEqual(资源[0]["payload"]["instruction_handling"], "data_only")

    def test_代理知识来源路径不能逃逸资源库(self) -> None:
        来源回执 = {
            "id": "self-improving-distillation-20260829",
            "instruction_handling": "data_only",
            "documents": [
                {
                    "id": "unsafe-document",
                    "path": "../outside.md",
                    "category": "unknown",
                    "media_type": "text/markdown",
                    "sha256": "a" * 64,
                    "original_sha256": "b" * 64,
                    "byte_count": 1,
                    "line_count": 1,
                    "redactions": {},
                }
            ],
        }

        with self.assertRaisesRegex(资源库.CatalogValidationError, "代理知识路径"):
            资源库.resources_from_agent_knowledge_receipt(来源回执)

    def test_断裂动作关系会阻断校验(self) -> None:
        动作资源 = [
            资源库.make_resource(
                resource_type="exercise",
                resource_id="exercise-a",
                source_receipt="flutter_seed",
                payload={
                    "id": "exercise-a",
                    "relations": [
                        {"targetExerciseId": "exercise-missing", "type": "regression"}
                    ],
                },
            )
        ]

        with self.assertRaisesRegex(
            资源库.CatalogValidationError, "动作关系引用不存在"
        ):
            资源库.validate_cross_references(动作资源)

    def test_断裂知识引用目标会阻断校验(self) -> None:
        资源 = [
            资源库.make_resource(
                resource_type="source_receipt",
                resource_id="flutter_seed",
                source_receipt="flutter_seed",
                payload={"id": "flutter_seed"},
                runtime_status="catalog_only",
                online_distribution_status="ineligible",
            ),
            资源库.make_resource(
                resource_type="knowledge_book",
                resource_id="book-1",
                source_receipt="flutter_seed",
                payload={"id": "book-1"},
            ),
            资源库.make_resource(
                resource_type="knowledge_quote",
                resource_id="quote-1",
                source_receipt="flutter_seed",
                payload={"id": "quote-1", "bookId": "book-1"},
            ),
            资源库.make_resource(
                resource_type="knowledge_citation_link",
                resource_id="citation-1",
                source_receipt="flutter_seed",
                payload={
                    "id": "citation-1",
                    "quoteId": "quote-1",
                    "targetType": "plan",
                    "targetId": "plan-missing",
                },
            ),
        ]

        with self.assertRaisesRegex(
            资源库.CatalogValidationError, "知识引用目标不存在"
        ):
            资源库.validate_cross_references(资源)


if __name__ == "__main__":
    unittest.main()
