#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Any

CONTRACT_VERSION = 1
CATALOG_VERSION = "2026.09.12-v1"
ALLOWED_CATALOG_STATUSES = {
    "registered",
    "pending_review",
    "approved",
    "blocked",
    "archived",
}
ALLOWED_RUNTIME_STATUSES = {"active", "catalog_only", "blocked"}
ALLOWED_DISTRIBUTION_STATUSES = {"eligible", "ineligible", "not_evaluated"}
REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CATALOG_ROOT = REPOSITORY_ROOT / "content_catalog"
EXTERNAL_PATH_ISSUE_ID = "external-exercise-manifest-absolute-paths"
EXPECTED_FLUTTER_COUNTS = {
    "exercise_count": 239,
    "exercise_with_media_count": 185,
    "exercise_media_file_count": 368,
    "exercise_paired_media_count": 183,
    "exercise_single_media_count": 2,
    "exercise_placeholder_count": 54,
    "ai_demo_slug_count": 163,
    "active_ai_media_exercise_count": 158,
}


class CatalogValidationError(ValueError):
    """业务内容资源库契约不满足时抛出的错误。"""


def canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def content_hash(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def make_resource(
    *,
    resource_type: str,
    resource_id: str,
    source_receipt: str,
    payload: dict[str, Any],
    catalog_status: str = "registered",
    runtime_status: str = "active",
    online_distribution_status: str = "not_evaluated",
    license_status: str = "not_evaluated",
    review_receipt: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "resource_key": f"{resource_type}:{resource_id}",
        "resource_type": resource_type,
        "id": resource_id,
        "schema_version": 1,
        "catalog_status": catalog_status,
        "runtime_status": runtime_status,
        "online_distribution_status": online_distribution_status,
        "source_receipts": [source_receipt],
        "license_status": license_status,
        "review_receipt": review_receipt,
        "payload": payload,
    }


def resources_from_flutter_source(source: dict[str, Any]) -> list[dict[str, Any]]:
    resources: list[dict[str, Any]] = []
    source_mappings = (
        ("exercises", "exercise", "flutter_seed"),
        ("guided_courses", "guided_course", "flutter_course_json"),
        ("training_plans", "training_plan", "flutter_seed"),
        ("starter_program_days", "starter_program_day", "flutter_seed"),
        ("motion_checks", "motion_check", "flutter_seed"),
        ("meal_guides", "meal_guide", "flutter_seed"),
        ("achievements", "achievement", "flutter_seed"),
        ("knowledge_books", "knowledge_book", "flutter_seed"),
    )
    for source_key, resource_type, source_receipt in source_mappings:
        for item in source.get(source_key, []):
            resources.append(
                make_resource(
                    resource_type=resource_type,
                    resource_id=_required_id(item, source_key),
                    source_receipt=source_receipt,
                    payload=item,
                    license_status=(
                        "internal_owned"
                        if resource_type not in {"knowledge_book"}
                        else "citation_only"
                    ),
                )
            )

    for item in source.get("sport_resources", []):
        approved = item.get("reviewStatus") == "approved"
        resources.append(make_resource(
            resource_type="sport_resource", resource_id=_required_id(item, "sport_resources"),
            source_receipt="flutter_seed", payload=item,
            catalog_status="approved" if approved else "pending_review",
            runtime_status="active" if approved else "catalog_only",
            license_status="internal_owned", online_distribution_status="ineligible",
            review_receipt={"scope": item.get("reviewNote", "")} if approved else None,
        ))

    quote_status_by_id: dict[str, str] = {}
    for quote in source.get("knowledge_quotes", []):
        quote_id = _required_id(quote, "knowledge_quotes")
        verification_status = quote.get("verificationStatus", "pending")
        quote_status_by_id[quote_id] = str(verification_status)
        verified = verification_status == "verified"
        resources.append(
            make_resource(
                resource_type="knowledge_quote",
                resource_id=quote_id,
                source_receipt="flutter_seed",
                payload=quote,
                catalog_status="approved" if verified else "pending_review",
                runtime_status="active" if verified else "catalog_only",
                online_distribution_status="eligible" if verified else "ineligible",
                license_status="citation_only",
                review_receipt=(
                    {"verification_status": "verified"} if verified else None
                ),
            )
        )

    for citation in source.get("knowledge_citation_links", []):
        citation_id = _required_id(citation, "knowledge_citation_links")
        verified = quote_status_by_id.get(citation.get("quoteId")) == "verified"
        resources.append(
            make_resource(
                resource_type="knowledge_citation_link",
                resource_id=citation_id,
                source_receipt="flutter_seed",
                payload=citation,
                catalog_status="approved" if verified else "pending_review",
                runtime_status="active" if verified else "catalog_only",
                online_distribution_status="eligible" if verified else "ineligible",
                license_status="citation_only",
                review_receipt=(
                    {"verification_status": "verified"} if verified else None
                ),
            )
        )

    fixtures = source.get("demo_fixtures", {})
    for fixture_group in ("races", "body_metrics"):
        for item in fixtures.get(fixture_group, []):
            resources.append(
                make_resource(
                    resource_type="demo_fixture",
                    resource_id=_required_id(item, fixture_group),
                    source_receipt="flutter_demo_seed",
                    payload={"fixture_group": fixture_group, **item},
                    catalog_status="registered",
                    runtime_status="blocked",
                    online_distribution_status="ineligible",
                    license_status="not_applicable",
                )
            )
    return resources


def _required_id(item: Any, source_name: str) -> str:
    if not isinstance(item, dict) or not isinstance(item.get("id"), str):
        raise CatalogValidationError(f"{source_name} 存在缺少字符串 id 的条目。")
    if not item["id"]:
        raise CatalogValidationError(f"{source_name} 存在空 id。")
    return item["id"]


def validate_cross_references(resources: list[dict[str, Any]]) -> None:
    payloads_by_type: dict[str, list[dict[str, Any]]] = {}
    for resource in resources:
        payloads_by_type.setdefault(resource["resource_type"], []).append(
            resource["payload"]
        )

    exercise_ids = {item["id"] for item in payloads_by_type.get("exercise", [])}
    for exercise in payloads_by_type.get("exercise", []):
        for relation in exercise.get("relations", []):
            target_id = relation.get("targetExerciseId")
            if target_id not in exercise_ids:
                raise CatalogValidationError(
                    f"动作关系引用不存在：{exercise['id']} -> {target_id}"
                )

    for motion_check in payloads_by_type.get("motion_check", []):
        target_id = motion_check.get("exerciseId")
        if target_id not in exercise_ids:
            raise CatalogValidationError(
                f"动作纠错引用不存在：{motion_check['id']} -> {target_id}"
            )

    for plan in payloads_by_type.get("training_plan", []):
        for workout_day in plan.get("workoutDays", []):
            for exercise_link in workout_day.get("workoutExercises", []):
                target_id = exercise_link.get("exerciseId")
                if target_id not in exercise_ids:
                    raise CatalogValidationError(
                        f"训练模板动作引用不存在：{workout_day.get('id')} -> {target_id}"
                    )

    book_ids = {item["id"] for item in payloads_by_type.get("knowledge_book", [])}
    quote_ids = {item["id"] for item in payloads_by_type.get("knowledge_quote", [])}
    for quote in payloads_by_type.get("knowledge_quote", []):
        if quote.get("bookId") not in book_ids:
            raise CatalogValidationError(
                f"知识引文引用书籍不存在：{quote['id']} -> {quote.get('bookId')}"
            )
    for citation in payloads_by_type.get("knowledge_citation_link", []):
        if citation.get("quoteId") not in quote_ids:
            raise CatalogValidationError(
                f"知识引用关系指向不存在引文：{citation['id']} -> {citation.get('quoteId')}"
            )

    workout_ids = {
        workout_day.get("id")
        for plan in payloads_by_type.get("training_plan", [])
        for workout_day in plan.get("workoutDays", [])
    }
    citation_targets = {
        "plan": {item["id"] for item in payloads_by_type.get("training_plan", [])},
        "workout": workout_ids,
        "exercise": exercise_ids,
        "meal_guide": {item["id"] for item in payloads_by_type.get("meal_guide", [])},
        "motion_check": {
            item["id"] for item in payloads_by_type.get("motion_check", [])
        },
    }
    for citation in payloads_by_type.get("knowledge_citation_link", []):
        target_type = citation.get("targetType")
        if target_type == "advice":
            continue
        valid_target_ids = citation_targets.get(target_type)
        if valid_target_ids is None or citation.get("targetId") not in valid_target_ids:
            raise CatalogValidationError(
                "知识引用目标不存在："
                f"{citation['id']} -> {target_type}:{citation.get('targetId')}"
            )

    receipt_ids = {item["id"] for item in payloads_by_type.get("source_receipt", [])}
    for resource in resources:
        if resource["resource_type"] == "source_receipt":
            continue
        for receipt_id in resource["source_receipts"]:
            if receipt_id not in receipt_ids:
                raise CatalogValidationError(
                    f"资源来源回执不存在：{resource['resource_key']} -> {receipt_id}"
                )


def build_catalog(resources: list[dict[str, Any]]) -> dict[str, Any]:
    seen_keys: set[str] = set()
    normalized_resources: list[dict[str, Any]] = []
    for resource in resources:
        normalized = _validate_resource(resource)
        resource_key = normalized["resource_key"]
        if resource_key in seen_keys:
            raise CatalogValidationError(f"发现重复资源键：{resource_key}")
        seen_keys.add(resource_key)
        normalized_resources.append(normalized)

    normalized_resources.sort(key=lambda item: item["resource_key"])
    catalog_without_hash = {
        "contract_version": CONTRACT_VERSION,
        "catalog_version": CATALOG_VERSION,
        "resource_count": len(normalized_resources),
        "resources": normalized_resources,
    }
    return {
        **catalog_without_hash,
        "content_hash": content_hash(catalog_without_hash),
    }


def _validate_resource(resource: dict[str, Any]) -> dict[str, Any]:
    required_fields = {
        "resource_key",
        "resource_type",
        "id",
        "schema_version",
        "catalog_status",
        "runtime_status",
        "online_distribution_status",
        "source_receipts",
        "license_status",
        "review_receipt",
        "payload",
    }
    missing_fields = sorted(required_fields - resource.keys())
    if missing_fields:
        raise CatalogValidationError(f"资源缺少必填字段：{', '.join(missing_fields)}")

    resource_key = resource["resource_key"]
    expected_key = f"{resource['resource_type']}:{resource['id']}"
    if resource_key != expected_key:
        raise CatalogValidationError(
            f"资源键不符合 <resource_type>:<id>：{resource_key}"
        )
    if resource["catalog_status"] not in ALLOWED_CATALOG_STATUSES:
        raise CatalogValidationError(f"资源目录状态无效：{resource_key}")
    if resource["runtime_status"] not in ALLOWED_RUNTIME_STATUSES:
        raise CatalogValidationError(f"资源运行状态无效：{resource_key}")
    if resource["online_distribution_status"] not in ALLOWED_DISTRIBUTION_STATUSES:
        raise CatalogValidationError(f"资源在线发布状态无效：{resource_key}")
    if not resource["source_receipts"]:
        raise CatalogValidationError(f"资源缺少来源回执：{resource_key}")
    if (
        resource["catalog_status"] == "pending_review"
        and resource["online_distribution_status"] == "eligible"
    ):
        raise CatalogValidationError(f"待核内容不能在线发布：{resource_key}")
    if (
        resource["catalog_status"] == "blocked"
        and resource["online_distribution_status"] == "eligible"
    ):
        raise CatalogValidationError(f"阻断内容不能在线发布：{resource_key}")
    return dict(resource)


def validate_issue_baseline(
    *,
    current_issue_ids: set[str],
    baseline: list[dict[str, Any]],
) -> None:
    baseline_ids = {str(issue.get("issue_id", "")) for issue in baseline}
    if "" in baseline_ids:
        raise CatalogValidationError("已知问题基线存在空 issue_id。")
    new_issue_ids = sorted(current_issue_ids - baseline_ids)
    if new_issue_ids:
        raise CatalogValidationError(f"发现未登记问题：{', '.join(new_issue_ids)}")
    resolved_issue_ids = sorted(baseline_ids - current_issue_ids)
    if resolved_issue_ids:
        raise CatalogValidationError(
            f"已解决问题仍在基线中：{', '.join(resolved_issue_ids)}"
        )


def collect_flutter_source(project_root: Path) -> dict[str, Any]:
    dart_command = shutil.which("dart")
    if dart_command is None:
        raise CatalogValidationError("未找到 Dart 命令，无法导出 Flutter 内容。")
    dart_wrapper = Path(dart_command).resolve()
    sdk_dart = dart_wrapper.parent.parent / "bin/cache/dart-sdk/bin/dart"
    dart = str(sdk_dart if sdk_dart.is_file() else dart_wrapper)
    result = subprocess.run(
        [dart, "run", "tool/content_catalog_export.dart"],
        cwd=project_root,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise CatalogValidationError(f"Flutter 内容导出失败：{detail}")
    try:
        source = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise CatalogValidationError(
            f"Flutter 内容导出不是有效 JSON：{error}"
        ) from error
    if not isinstance(source, dict):
        raise CatalogValidationError("Flutter 内容导出根节点必须是对象。")
    _validate_flutter_statistics(source.get("statistics", {}))
    return source


def _validate_flutter_statistics(statistics: Any) -> None:
    if not isinstance(statistics, dict):
        raise CatalogValidationError("Flutter 内容导出缺少统计信息。")
    for key, expected in EXPECTED_FLUTTER_COUNTS.items():
        actual = statistics.get(key)
        if actual != expected:
            raise CatalogValidationError(
                f"Flutter 内容数量发生意外变化：{key} 期望 {expected}，实际 {actual}。"
            )
    if statistics.get("active_exercise_demo_set") not in {"freeDb", "female", "male"}:
        raise CatalogValidationError("动作媒体当前数据集状态无效。")


def resources_from_backend_catalog(
    *,
    version: str,
    principles: list[dict[str, Any]],
    training_templates: list[dict[str, Any]],
    population_templates: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    resources: list[dict[str, Any]] = []
    mappings = (
        ("knowledge_principle", principles),
        ("backend_training_template", training_templates),
        ("population_template", population_templates),
    )
    for resource_type, items in mappings:
        for item in items:
            status = str(item.get("status", "verified"))
            approved = status == "verified"
            resources.append(
                make_resource(
                    resource_type=resource_type,
                    resource_id=_required_id(item, resource_type),
                    source_receipt="backend_knowledge_seed",
                    payload=item,
                    catalog_status="approved" if approved else "pending_review",
                    runtime_status="active" if approved else "catalog_only",
                    online_distribution_status=(
                        "eligible" if approved else "ineligible"
                    ),
                    license_status="internal_owned",
                    review_receipt={"catalog_version": version} if approved else None,
                )
            )
    return resources


def collect_backend_resources(project_root: Path) -> tuple[str, list[dict[str, Any]]]:
    backend_root = project_root / "backend"
    sys.path.insert(0, str(backend_root))
    try:
        module = importlib.import_module("app.services.knowledge_catalog")
    finally:
        sys.path.pop(0)
    version = str(module.KNOWLEDGE_CATALOG_VERSION)
    principles = [
        {
            "id": item[0],
            "status": "verified",
            "title": item[1],
            "summary": item[2],
            "tags": item[3],
            "source_label": item[4],
            "source_section": item[5],
            "content_version": version,
        }
        for item in module._PRINCIPLES
    ]
    training_templates = [
        {
            "id": item[0],
            "status": "verified",
            "title": item[1],
            "population_template_id": item[2],
            "goals": item[3],
            "primary_sports": item[4],
            "supported_days": item[5],
            "required_equipment": item[6],
            "session_pattern": item[7],
            "source_label": "TrainMate 自编结构模板",
            "content_version": version,
        }
        for item in module._TRAINING_TEMPLATES
    ]
    population_templates = [
        item.model_dump(mode="json") for item in module._POPULATION_TEMPLATES
    ]
    if (len(principles), len(training_templates), len(population_templates)) != (
        15,
        9,
        8,
    ):
        raise CatalogValidationError(
            "后端知识数量发生意外变化，期望原则/训练模板/人群模板为 15/9/8。"
        )
    return version, resources_from_backend_catalog(
        version=version,
        principles=principles,
        training_templates=training_templates,
        population_templates=population_templates,
    )


def resources_from_skill_catalog(
    manifest: dict[str, Any],
    source_catalog: dict[str, Any],
) -> list[dict[str, Any]]:
    resources = [
        make_resource(
            resource_type="ai_skill",
            resource_id=_required_id(manifest, "trainmate.skill.json"),
            source_receipt="ai_skill_manifest",
            payload=manifest,
            catalog_status="approved"
            if manifest.get("reviewed") is True
            else "pending_review",
            runtime_status="active"
            if manifest.get("reviewed") is True
            else "catalog_only",
            online_distribution_status=(
                "eligible" if manifest.get("reviewed") is True else "ineligible"
            ),
            license_status="internal_owned",
            review_receipt=(
                {"manifest_version": manifest.get("version")}
                if manifest.get("reviewed") is True
                else None
            ),
        )
    ]
    for module in source_catalog.get("modules", []):
        status = module.get("status")
        if status == "runtime_approved":
            catalog_status = "approved"
            runtime_status = "active"
        elif status == "blocked":
            catalog_status = "blocked"
            runtime_status = "blocked"
        else:
            catalog_status = "registered"
            runtime_status = "catalog_only"
        resources.append(
            make_resource(
                resource_type="ai_skill_module",
                resource_id=_required_id(module, "source-catalog.modules"),
                source_receipt="ai_skill_source_catalog",
                payload=module,
                catalog_status=catalog_status,
                runtime_status=runtime_status,
                online_distribution_status="ineligible",
                license_status=str(source_catalog.get("license_status", "unverified")),
                review_receipt=(
                    {"review_scope": source_catalog.get("review_scope")}
                    if status == "runtime_approved"
                    else None
                ),
            )
        )
    for external in source_catalog.get("external_sources", []):
        resources.append(
            make_resource(
                resource_type="ai_skill_external_source",
                resource_id=_required_id(external, "source-catalog.external_sources"),
                source_receipt="ai_skill_source_catalog",
                payload=external,
                catalog_status=(
                    "approved"
                    if external.get("status") == "runtime_approved"
                    else "registered"
                ),
                runtime_status=(
                    "active"
                    if external.get("status") == "runtime_approved"
                    else "catalog_only"
                ),
                online_distribution_status="ineligible",
                license_status=str(external.get("license_status", "unverified")),
                review_receipt={"review_scope": "contract_and_safety_only"},
            )
        )
    return resources


def collect_skill_resources(project_root: Path) -> list[dict[str, Any]]:
    skill_root = project_root / "backend/app/ai_skills/training-plan-builder"
    manifest_path = skill_root / "trainmate.skill.json"
    source_catalog_path = skill_root / "source-catalog.json"
    manifest = _load_json(manifest_path)
    source_catalog = _load_json(source_catalog_path)
    _validate_skill_hashes(skill_root, manifest)
    modules = source_catalog.get("modules", [])
    external_sources = source_catalog.get("external_sources", [])
    if len(modules) != 50 or len(external_sources) != 1:
        raise CatalogValidationError(
            "AI Skill 来源数量发生意外变化，期望 50 个模块和 1 个外部来源。"
        )
    status_counts = {
        status: sum(1 for item in modules if item.get("status") == status)
        for status in ("runtime_approved", "catalog_only", "blocked")
    }
    if status_counts != {
        "runtime_approved": 21,
        "catalog_only": 23,
        "blocked": 6,
    }:
        raise CatalogValidationError(f"AI Skill 状态数量发生意外变化：{status_counts}")
    if source_catalog.get("raw_sources_packaged") is not False:
        raise CatalogValidationError("AI Skill 原始来源不得被打包。")
    return resources_from_skill_catalog(manifest, source_catalog)


def resources_from_agent_knowledge_receipt(
    receipt: dict[str, Any],
) -> list[dict[str, Any]]:
    receipt_id = _required_id(receipt, "agent_knowledge_receipt")
    if receipt.get("instruction_handling") != "data_only":
        raise CatalogValidationError("代理知识必须按仅数据方式处理。")

    resources: list[dict[str, Any]] = []
    for document in receipt.get("documents", []):
        document_id = _required_id(document, "agent_knowledge_receipt.documents")
        relative_path = document.get("path")
        if not isinstance(relative_path, str):
            raise CatalogValidationError(f"代理知识路径无效：{document_id}")
        normalized_path = PurePosixPath(relative_path)
        if (
            normalized_path.is_absolute()
            or any(part in {"", ".", ".."} for part in normalized_path.parts)
            or normalized_path.parts[:2] != ("content_catalog", "source_documents")
        ):
            raise CatalogValidationError(f"代理知识路径不能逃逸资源库：{relative_path}")
        resources.append(
            make_resource(
                resource_type="agent_knowledge_document",
                resource_id=document_id,
                source_receipt=receipt_id,
                payload={
                    **document,
                    "instruction_handling": "data_only",
                },
                catalog_status="pending_review",
                runtime_status="catalog_only",
                online_distribution_status="ineligible",
                license_status=str(
                    receipt.get("license_status", "user_provided_internal")
                ),
            )
        )
    return resources


def collect_agent_knowledge_resources(project_root: Path) -> list[dict[str, Any]]:
    receipt = _load_json(
        project_root
        / "content_catalog/source_receipts/self_improving_20260829.json"
    )
    resources = resources_from_agent_knowledge_receipt(receipt)
    source_documents_root = (
        project_root / "content_catalog/source_documents"
    ).resolve()
    for resource in resources:
        document = resource["payload"]
        relative_path = PurePosixPath(document["path"])
        document_path = project_root.joinpath(*relative_path.parts)
        try:
            document_path.resolve().relative_to(source_documents_root)
        except ValueError as error:
            raise CatalogValidationError(
                f"代理知识实际路径不能逃逸资源库：{relative_path}"
            ) from error
        try:
            text = document_path.read_text(encoding="utf-8")
        except FileNotFoundError as error:
            raise CatalogValidationError(
                f"代理知识文件不存在：{relative_path}"
            ) from error
        except UnicodeDecodeError as error:
            raise CatalogValidationError(
                f"代理知识文件不是 UTF-8：{relative_path}"
            ) from error
        if document.get("media_type") == "application/json":
            try:
                json.loads(text)
            except json.JSONDecodeError as error:
                raise CatalogValidationError(
                    f"代理知识 JSON 无效：{relative_path}：{error}"
                ) from error
        if _sha256_file(document_path) != document.get("sha256"):
            raise CatalogValidationError(f"代理知识文件哈希不匹配：{relative_path}")
        if len(text.encode("utf-8")) != document.get("byte_count"):
            raise CatalogValidationError(f"代理知识文件大小不匹配：{relative_path}")
        if len(text.splitlines()) != document.get("line_count"):
            raise CatalogValidationError(f"代理知识文件行数不匹配：{relative_path}")
        if re.search(
            r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}",
            text,
            re.IGNORECASE,
        ):
            raise CatalogValidationError(f"代理知识仍含邮箱：{relative_path}")
        if "/Users/" in text:
            raise CatalogValidationError(f"代理知识仍含用户目录路径：{relative_path}")
        redactions = document.get("redactions", {})
        actual_redactions = {
            "email": text.count("[已脱敏邮箱]"),
            "absolute_user_path": text.count("[已脱敏本地路径]"),
        }
        if redactions != actual_redactions:
            raise CatalogValidationError(f"代理知识脱敏计数不匹配：{relative_path}")
    return resources


def _validate_skill_hashes(skill_root: Path, manifest: dict[str, Any]) -> None:
    hash_fields = {
        manifest.get("source_file"): manifest.get("source_sha256"),
        manifest.get("runtime_file"): manifest.get("runtime_sha256"),
        manifest.get("source_catalog_file"): manifest.get("source_catalog_sha256"),
    }
    fragments = manifest.get("sport_fragments", {})
    fragment_hashes = manifest.get("fragment_sha256", {})
    for sport, relative_path in fragments.items():
        hash_fields[relative_path] = fragment_hashes.get(sport)
    for relative_path, expected_hash in hash_fields.items():
        if not isinstance(relative_path, str) or not isinstance(expected_hash, str):
            raise CatalogValidationError("AI Skill 清单缺少文件路径或哈希。")
        actual_hash = _sha256_file(skill_root / relative_path)
        if actual_hash != expected_hash:
            raise CatalogValidationError(f"AI Skill 文件哈希不匹配：{relative_path}")


def collect_source_receipt_resources(project_root: Path) -> list[dict[str, Any]]:
    external_receipt = _load_json(
        project_root / "content_catalog/source_receipts/exercise_media_source.json"
    )
    agent_knowledge_receipt = _load_json(
        project_root
        / "content_catalog/source_receipts/self_improving_20260829.json"
    )
    receipt_payloads = [
        {
            "id": "flutter_seed",
            "locator_type": "repository_relative",
            "locator": "lib/data/seed",
            "description": "Flutter 可复用业务内容种子。",
        },
        {
            "id": "flutter_course_json",
            "locator_type": "repository_relative",
            "locator": "assets/training",
            "description": "引导课程 JSON。",
        },
        {
            "id": "flutter_demo_seed",
            "locator_type": "repository_relative",
            "locator": "lib/data/seed",
            "description": "仅供本地演示和测试的数据。",
        },
        {
            "id": "backend_knowledge_seed",
            "locator_type": "repository_relative",
            "locator": "backend/app/services/knowledge_catalog.py",
            "description": "后端知识原则与训练模板权威源。",
        },
        {
            "id": "ai_skill_manifest",
            "locator_type": "repository_relative",
            "locator": "backend/app/ai_skills/training-plan-builder/trainmate.skill.json",
            "description": "主 AI Skill 审核与运行时文件清单。",
        },
        {
            "id": "ai_skill_source_catalog",
            "locator_type": "repository_relative",
            "locator": "backend/app/ai_skills/training-plan-builder/source-catalog.json",
            "description": "外部 Skill 模块来源回执，不包含原始来源正文。",
        },
        external_receipt,
        agent_knowledge_receipt,
    ]
    return [
        make_resource(
            resource_type="source_receipt",
            resource_id=_required_id(payload, "source_receipts"),
            source_receipt=_required_id(payload, "source_receipts"),
            payload=payload,
            catalog_status="registered",
            runtime_status="catalog_only",
            online_distribution_status="ineligible",
            license_status=str(payload.get("license_status", "internal_owned")),
        )
        for payload in receipt_payloads
    ]


def build_live_documents(
    *,
    project_root: Path,
    verify_external: bool = False,
) -> dict[str, dict[str, Any]]:
    flutter_source = collect_flutter_source(project_root)
    flutter_resources = resources_from_flutter_source(flutter_source)
    backend_version, backend_resources = collect_backend_resources(project_root)
    skill_resources = collect_skill_resources(project_root)
    agent_knowledge_resources = collect_agent_knowledge_resources(project_root)
    receipt_resources = collect_source_receipt_resources(project_root)

    fixture_resources = [
        item for item in flutter_resources if item["resource_type"] == "demo_fixture"
    ]
    app_resources = [
        item for item in flutter_resources if item["resource_type"] != "demo_fixture"
    ]
    all_resources = [
        *app_resources,
        *fixture_resources,
        *backend_resources,
        *skill_resources,
        *agent_knowledge_resources,
        *receipt_resources,
    ]
    validate_cross_references(all_resources)

    baseline = _load_json(project_root / "content_catalog/baselines/known_issues.json")
    current_issue_ids = {EXTERNAL_PATH_ISSUE_ID}
    if verify_external:
        current_issue_ids = _verify_external_source(project_root)
    validate_issue_baseline(
        current_issue_ids=current_issue_ids,
        baseline=baseline.get("issues", []),
    )

    documents = {
        "snapshots/flutter.json": build_catalog(app_resources),
        "snapshots/fixtures.json": build_catalog(fixture_resources),
        "snapshots/backend.json": build_catalog(backend_resources),
        "snapshots/ai_skills.json": build_catalog(skill_resources),
        "snapshots/agent_knowledge.json": build_catalog(agent_knowledge_resources),
        "snapshots/source_receipts.json": build_catalog(receipt_resources),
    }
    snapshot_refs = []
    for relative_path, document in sorted(documents.items()):
        snapshot_refs.append(
            {
                "path": relative_path,
                "resource_count": document["resource_count"],
                "content_hash": document["content_hash"],
            }
        )
    index_without_hash = {
        "contract_version": CONTRACT_VERSION,
        "catalog_version": CATALOG_VERSION,
        "snapshot_count": len(snapshot_refs),
        "snapshots": snapshot_refs,
        "known_issue_baseline": "baselines/known_issues.json",
        "statistics": {
            "flutter": flutter_source["statistics"],
            "backend_catalog_version": backend_version,
            "backend_principle_count": 15,
            "backend_training_template_count": 9,
            "backend_population_template_count": 8,
            "ai_skill_count": 1,
            "ai_skill_module_count": 50,
            "ai_skill_external_source_count": 1,
            "agent_knowledge_document_count": len(agent_knowledge_resources),
            "demo_race_count": 2,
            "demo_body_metric_count": 7,
        },
    }
    documents["catalog.index.json"] = {
        **index_without_hash,
        "content_hash": content_hash(index_without_hash),
    }
    return documents


def _verify_external_source(project_root: Path) -> set[str]:
    receipt = _load_json(
        project_root / "content_catalog/source_receipts/exercise_media_source.json"
    )
    external_root = (project_root / receipt["root_relative_to_repository"]).resolve()
    if not external_root.is_dir():
        raise CatalogValidationError(f"外部动作素材目录不存在：{external_root}")
    files = sorted(
        (path for path in external_root.rglob("*") if path.is_file()),
        key=lambda path: path.relative_to(external_root).as_posix(),
    )
    rows = [
        (path.relative_to(external_root).as_posix(), path.stat().st_size)
        for path in files
    ]
    total_bytes = sum(size for _, size in rows)
    fingerprint = content_hash(rows)
    if len(files) != receipt.get("expected_file_count"):
        raise CatalogValidationError("外部动作素材文件数量与来源回执不一致。")
    if total_bytes != receipt.get("expected_total_bytes"):
        raise CatalogValidationError("外部动作素材总体积与来源回执不一致。")
    if fingerprint != receipt.get("inventory_fingerprint"):
        raise CatalogValidationError("外部动作素材清单指纹与来源回执不一致。")

    manifest_path = external_root / receipt["legacy_manifest_relative_path"]
    if not manifest_path.is_file():
        raise CatalogValidationError("外部动作素材历史任务清单不存在。")
    manifest_text = manifest_path.read_text(encoding="utf-8")
    return {EXTERNAL_PATH_ISSUE_ID} if "/Users/" in manifest_text else set()


def _load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise CatalogValidationError(f"资源库文件不存在：{path}") from error
    except json.JSONDecodeError as error:
        raise CatalogValidationError(f"资源库 JSON 无效：{path}：{error}") from error
    if not isinstance(value, dict):
        raise CatalogValidationError(f"资源库 JSON 根节点必须是对象：{path}")
    return value


def _sha256_file(path: Path) -> str:
    if not path.is_file():
        raise CatalogValidationError(f"待校验文件不存在：{path}")
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _render_json(document: dict[str, Any]) -> str:
    return (
        json.dumps(
            document,
            ensure_ascii=False,
            sort_keys=True,
            indent=2,
        )
        + "\n"
    )


def write_documents(
    documents: dict[str, dict[str, Any]],
    *,
    catalog_root: Path,
) -> None:
    for relative_path, document in documents.items():
        output_path = catalog_root / relative_path
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(_render_json(document), encoding="utf-8")


def check_documents(
    documents: dict[str, dict[str, Any]],
    *,
    catalog_root: Path,
) -> None:
    mismatches: list[str] = []
    for relative_path, document in documents.items():
        output_path = catalog_root / relative_path
        if not output_path.is_file():
            mismatches.append(f"缺少 {relative_path}")
            continue
        if output_path.read_text(encoding="utf-8") != _render_json(document):
            mismatches.append(f"内容漂移 {relative_path}")
    if mismatches:
        raise CatalogValidationError(
            "业务内容资源库与权威源不一致：" + "；".join(mismatches)
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="生成或校验 TrainMate 业务内容资源库。"
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="只校验，不修改快照。")
    mode.add_argument("--write", action="store_true", help="显式更新快照。")
    parser.add_argument(
        "--verify-external",
        action="store_true",
        help="同时校验仓库外的动作素材清单指纹。",
    )
    arguments = parser.parse_args()
    try:
        documents = build_live_documents(
            project_root=REPOSITORY_ROOT,
            verify_external=arguments.verify_external,
        )
        if arguments.write:
            write_documents(documents, catalog_root=CATALOG_ROOT)
            print(f"业务内容资源库已更新，共 {len(documents) - 1} 个分域快照。")
        else:
            check_documents(documents, catalog_root=CATALOG_ROOT)
            print(f"业务内容资源库校验通过，共 {len(documents) - 1} 个分域快照。")
        return 0
    except CatalogValidationError as error:
        print(f"业务内容资源库校验失败：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
