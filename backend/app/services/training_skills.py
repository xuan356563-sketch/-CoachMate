from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    ValidationError,
    field_validator,
    model_validator,
)

TrainingSportCode = Literal[
    "general_fitness",
    "strength",
    "fat_loss",
    "marathon",
    "trail_running",
    "hyrox",
]

_HASH_PATTERN = re.compile(r"^[0-9a-f]{64}$")
_MAX_SOURCE_BYTES = 64 * 1024
_MAX_RUNTIME_BYTES = 12 * 1024
_MAX_FRAGMENT_BYTES = 8 * 1024
_MAX_SELECTED_RUNTIME_BYTES = 20 * 1024
_MAX_SOURCE_CATALOG_BYTES = 64 * 1024
_RUNTIME_FILE_PATTERN = re.compile(r"^RUNTIME(?:-[A-Z0-9-]+)?\.md$")
_KNOWLEDGE_MODULE_MARKER = re.compile(
    r"<!--\s*knowledge_modules:([a-z0-9,-]+)\s*-->",
)
_RUNTIME_FORBIDDEN_PATTERNS = (
    re.compile(r"https?://|file://", re.IGNORECASE),
    re.compile(
        r"(?m)^\s*```(?:bash|sh|zsh|shell|python|javascript|typescript)\b",
        re.IGNORECASE,
    ),
    re.compile(r"(?:^|\s)(?:/Users/|/home/|~/|\.\./)"),
    re.compile(
        r"\b(?:curl|wget|WebSearch|tool_call|function_call)\b",
        re.IGNORECASE,
    ),
    re.compile(r"(?im)^\s*(?:system|assistant|user)\s*:"),
    re.compile(r"忽略.{0,20}(?:系统|先前|以上).{0,10}指令|覆盖.{0,12}系统提示"),
)
_SOURCE_CATALOG_BINDING = "<!-- source_catalog_sha256:{digest} -->"

KnowledgeRuntimeTarget = Literal[
    "base",
    "strength",
    "marathon",
    "trail_running",
]
KnowledgeModuleStatus = Literal["runtime_approved", "catalog_only", "blocked"]
KnowledgeAuditLevel = Literal[
    "author_self_tested",
    "self_declared",
    "unverified",
]


class SkillBundleError(RuntimeError):
    """Skill 包不完整或未通过完整性校验。"""


class TrainingSkillManifest(BaseModel):
    """开发者审核后随服务发布的 Skill 清单。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    schema_version: Literal[1, 2]
    id: str = Field(pattern=r"^[a-z0-9][a-z0-9-]{1,62}$")
    version: str = Field(pattern=r"^\d+\.\d+\.\d+$")
    display_name: str = Field(min_length=1, max_length=80)
    capability: Literal["trainer_plan"]
    sports: list[TrainingSportCode] = Field(min_length=1, max_length=8)
    priority: int = Field(ge=0, le=1000)
    reviewed: bool
    source_file: str = Field(min_length=1, max_length=120)
    runtime_file: str = Field(min_length=1, max_length=120)
    sport_fragments: dict[TrainingSportCode, str] = Field(default_factory=dict)
    source_sha256: str
    runtime_sha256: str
    fragment_sha256: dict[TrainingSportCode, str] = Field(default_factory=dict)
    source_catalog_file: str | None = Field(default=None, min_length=1, max_length=120)
    source_catalog_sha256: str | None = None

    @field_validator("sports")
    @classmethod
    def reject_duplicate_sports(
        cls,
        values: list[TrainingSportCode],
    ) -> list[TrainingSportCode]:
        if len(values) != len(set(values)):
            raise ValueError("Skill 覆盖运动不能重复")
        return values

    @field_validator("source_sha256", "runtime_sha256")
    @classmethod
    def validate_hash(cls, value: str) -> str:
        if not _HASH_PATTERN.fullmatch(value):
            raise ValueError("Skill 哈希必须是 SHA-256")
        return value

    @field_validator("fragment_sha256")
    @classmethod
    def validate_fragment_hashes(
        cls,
        values: dict[TrainingSportCode, str],
    ) -> dict[TrainingSportCode, str]:
        if any(not _HASH_PATTERN.fullmatch(value) for value in values.values()):
            raise ValueError("Skill 片段哈希必须是 SHA-256")
        return values

    @field_validator("source_catalog_sha256")
    @classmethod
    def validate_optional_catalog_hash(cls, value: str | None) -> str | None:
        if value is not None and not _HASH_PATTERN.fullmatch(value):
            raise ValueError("Skill 来源目录哈希必须是 SHA-256")
        return value

    @model_validator(mode="after")
    def validate_schema_contract(self) -> "TrainingSkillManifest":
        has_catalog_file = self.source_catalog_file is not None
        has_catalog_hash = self.source_catalog_sha256 is not None
        if has_catalog_file != has_catalog_hash:
            raise ValueError("Skill 来源目录文件和哈希必须同时声明")
        if self.schema_version == 1 and has_catalog_file:
            raise ValueError("Skill v1 清单不能声明来源目录")
        if self.schema_version == 2 and not has_catalog_file:
            raise ValueError("Skill v2 清单必须声明来源目录")
        return self


class TrainingKnowledgeModuleManifest(BaseModel):
    """外部技能只读来源条目，不允许直接进入模型。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    id: str = Field(pattern=r"^[a-z0-9][a-z0-9-]{1,62}$")
    group: str = Field(pattern=r"^[a-z0-9][a-z0-9-]{1,62}$")
    archive_path: str = Field(min_length=1, max_length=180)
    source_sha256: str
    audit_level: KnowledgeAuditLevel
    status: KnowledgeModuleStatus
    reason_code: str = Field(pattern=r"^[a-z0-9][a-z0-9_]{1,79}$")
    runtime_targets: list[KnowledgeRuntimeTarget] = Field(
        default_factory=list,
        max_length=3,
    )

    @field_validator("source_sha256")
    @classmethod
    def validate_source_hash(cls, value: str) -> str:
        if not _HASH_PATTERN.fullmatch(value):
            raise ValueError("来源模块哈希必须是 SHA-256")
        return value

    @field_validator("archive_path")
    @classmethod
    def validate_archive_path(cls, value: str) -> str:
        if "\\" in value:
            raise ValueError("来源模块归档路径无效")
        path = PurePosixPath(value)
        if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
            raise ValueError("来源模块归档路径无效")
        if path.name != "SKILL.md":
            raise ValueError("来源模块必须指向 SKILL.md")
        return value

    @field_validator("runtime_targets")
    @classmethod
    def reject_duplicate_targets(
        cls,
        values: list[KnowledgeRuntimeTarget],
    ) -> list[KnowledgeRuntimeTarget]:
        if len(values) != len(set(values)):
            raise ValueError("来源模块运行时目标不能重复")
        return values

    @model_validator(mode="after")
    def validate_runtime_status(self) -> "TrainingKnowledgeModuleManifest":
        if self.status == "runtime_approved" and not self.runtime_targets:
            raise ValueError("已审核来源模块必须声明运行时目标")
        if self.status != "runtime_approved" and self.runtime_targets:
            raise ValueError("未启用来源模块不能声明运行时目标")
        return self


class TrainingExternalKnowledgeSourceManifest(BaseModel):
    """不随应用打包的外部 Skill 来源收据。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    id: str = Field(pattern=r"^[a-z0-9][a-z0-9-]{1,62}$")
    source_filename: str = Field(min_length=1, max_length=120)
    source_sha256: str
    audit_level: KnowledgeAuditLevel
    status: KnowledgeModuleStatus
    reason_code: str = Field(pattern=r"^[a-z0-9][a-z0-9_]{1,79}$")
    runtime_targets: list[KnowledgeRuntimeTarget] = Field(
        default_factory=list,
        max_length=4,
    )
    license_status: Literal["unverified"]
    raw_source_packaged: Literal[False]

    @field_validator("source_filename")
    @classmethod
    def validate_source_filename(cls, value: str) -> str:
        if (
            "\\" in value
            or PurePosixPath(value).name != value
            or not value.lower().endswith(".md")
        ):
            raise ValueError("外部来源文件名无效")
        return value

    @field_validator("source_sha256")
    @classmethod
    def validate_source_hash(cls, value: str) -> str:
        if not _HASH_PATTERN.fullmatch(value):
            raise ValueError("外部来源哈希必须是 SHA-256")
        return value

    @field_validator("runtime_targets")
    @classmethod
    def reject_duplicate_targets(
        cls,
        values: list[KnowledgeRuntimeTarget],
    ) -> list[KnowledgeRuntimeTarget]:
        if len(values) != len(set(values)):
            raise ValueError("外部来源运行时目标不能重复")
        return values

    @model_validator(mode="after")
    def validate_runtime_status(self) -> "TrainingExternalKnowledgeSourceManifest":
        if self.status == "runtime_approved" and not self.runtime_targets:
            raise ValueError("已审核外部来源必须声明运行时目标")
        if self.status != "runtime_approved" and self.runtime_targets:
            raise ValueError("未启用外部来源不能声明运行时目标")
        return self


class TrainingKnowledgeSourceCatalog(BaseModel):
    """用户提供技能包的不可执行来源收据。"""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    schema_version: Literal[1, 2]
    bundle_id: str = Field(pattern=r"^[a-z0-9][a-z0-9-]{1,62}$")
    bundle_filename: str = Field(min_length=1, max_length=120)
    bundle_sha256: str
    archive_entry_count: int = Field(ge=1, le=512)
    skill_count: int = Field(ge=1, le=100)
    license_status: Literal["unverified"]
    raw_sources_packaged: Literal[False]
    review_scope: Literal["contract_and_safety_only"]
    modules: list[TrainingKnowledgeModuleManifest] = Field(
        min_length=1,
        max_length=100,
    )
    external_sources: list[TrainingExternalKnowledgeSourceManifest] = Field(
        default_factory=list,
        max_length=20,
    )

    @field_validator("bundle_sha256")
    @classmethod
    def validate_bundle_hash(cls, value: str) -> str:
        if not _HASH_PATTERN.fullmatch(value):
            raise ValueError("来源压缩包哈希必须是 SHA-256")
        return value

    @field_validator("bundle_filename")
    @classmethod
    def validate_bundle_filename(cls, value: str) -> str:
        if (
            "\\" in value
            or PurePosixPath(value).name != value
            or not value.lower().endswith(".zip")
        ):
            raise ValueError("来源压缩包文件名无效")
        return value

    @model_validator(mode="after")
    def validate_counts(self) -> "TrainingKnowledgeSourceCatalog":
        if self.skill_count != len(self.modules):
            raise ValueError("来源目录 Skill 数量不一致")
        if self.archive_entry_count < self.skill_count:
            raise ValueError("来源目录归档条目数量不一致")
        if self.schema_version == 1 and self.external_sources:
            raise ValueError("来源目录 v1 不能声明外部来源")
        return self


@dataclass(frozen=True)
class LoadedTrainingSkill:
    manifest: TrainingSkillManifest
    source_sha256: str
    runtime_sha256: str
    runtime_text: str
    fragment_texts: dict[str, str]
    fragment_hashes: dict[str, str]
    source_catalog_sha256: str | None
    knowledge_modules: tuple[TrainingKnowledgeModuleManifest, ...]
    external_sources: tuple[TrainingExternalKnowledgeSourceManifest, ...]


@dataclass(frozen=True)
class SkillSelection:
    manifest: TrainingSkillManifest
    source_sha256: str
    runtime_sha256: str
    runtime_text: str
    fragment_text: str
    fragment_sha256: str | None
    coverage: TrainingSportCode
    selection_reason: str
    selection_reason_code: str
    source_catalog_sha256: str | None
    knowledge_module_ids: tuple[str, ...]

    @property
    def combined_runtime(self) -> str:
        if not self.fragment_text:
            return self.runtime_text
        return f"{self.runtime_text}\n\n{self.fragment_text}"


class TrainingSkillRegistry:
    """只加载应用包内通过清单和哈希校验的训练 Skill。"""

    def __init__(self, root: Path) -> None:
        self._root = root
        self._loaded: tuple[LoadedTrainingSkill, ...] | None = None

    @classmethod
    def default(cls) -> "TrainingSkillRegistry":
        return cls(Path(__file__).resolve().parents[1] / "ai_skills")

    def load(self) -> tuple[LoadedTrainingSkill, ...]:
        if self._loaded is not None:
            return self._loaded
        try:
            manifests = sorted(self._root.glob("*/trainmate.skill.json"))
            if not manifests:
                raise SkillBundleError("没有可用的内置训练 Skill")
            root = self._root.resolve()
            resolved_manifests: list[Path] = []
            for path in manifests:
                if self._contains_symlink(path, self._root):
                    raise SkillBundleError("训练 Skill 禁止使用符号链接")
                resolved = path.resolve()
                try:
                    resolved.relative_to(root)
                except ValueError as error:
                    raise SkillBundleError("训练 Skill 清单禁止越过内置目录") from error
                if not resolved.is_file():
                    raise SkillBundleError("训练 Skill 清单文件缺失")
                resolved_manifests.append(resolved)
            loaded = tuple(
                self._load_bundle(path.parent, path) for path in resolved_manifests
            )
            ids = [item.manifest.id for item in loaded]
            if len(ids) != len(set(ids)):
                raise SkillBundleError("内置训练 Skill ID 重复")
            if len(loaded) != 1:
                raise SkillBundleError("V1 只能发布一个主 Skill")
            self._loaded = loaded
            return loaded
        except SkillBundleError:
            raise
        except (OSError, UnicodeError, json.JSONDecodeError, ValidationError) as error:
            raise SkillBundleError("内置训练 Skill 校验失败") from error

    def resolve(self, primary_sport: TrainingSportCode) -> SkillSelection:
        exact_candidates = [
            item for item in self.load() if primary_sport in item.manifest.sports
        ]
        candidates = exact_candidates
        selected_coverage: TrainingSportCode = primary_sport
        selection_reason = "主运动与 Skill 覆盖标签精确匹配"
        selection_reason_code = "primary_sport_exact_match"
        if not candidates:
            candidates = [
                item
                for item in self.load()
                if "general_fitness" in item.manifest.sports
            ]
            selected_coverage = "general_fitness"
            selection_reason = "当前运动使用通用训练 Skill 覆盖"
            selection_reason_code = "generic_fallback"
        if not candidates:
            raise SkillBundleError("没有覆盖当前运动的内置训练 Skill")
        selected = sorted(
            candidates,
            key=lambda item: (-item.manifest.priority, item.manifest.id),
        )[0]
        fragment = selected.fragment_texts.get(selected_coverage, "")
        fragment_hash = selected.fragment_hashes.get(selected_coverage)
        module_ids = tuple(
            item.id
            for item in (*selected.knowledge_modules, *selected.external_sources)
            if item.status == "runtime_approved"
            and (
                "base" in item.runtime_targets
                or selected_coverage in item.runtime_targets
            )
        )
        if exact_candidates:
            if fragment and selected_coverage == "hyrox":
                selection_reason = "HYROX 主运动精确匹配已审核专项片段"
                selection_reason_code = "hyrox_fragment_exact_match"
            elif fragment:
                selection_reason = "主运动使用通用周期化规则，并叠加已审核专项片段"
                selection_reason_code = "generic_periodization_fallback"
            else:
                selection_reason = "主运动使用通用周期化规则和 TrainMate 本地模板"
                selection_reason_code = "generic_periodization_fallback"
        separator = "\n\n" if fragment else ""
        if len((selected.runtime_text + separator + fragment).encode("utf-8")) > (
            _MAX_SELECTED_RUNTIME_BYTES
        ):
            raise SkillBundleError("训练 Skill 运行时内容超过上限")
        return SkillSelection(
            manifest=selected.manifest,
            source_sha256=selected.source_sha256,
            runtime_sha256=selected.runtime_sha256,
            runtime_text=selected.runtime_text,
            fragment_text=fragment,
            fragment_sha256=fragment_hash,
            coverage=primary_sport,
            selection_reason=selection_reason,
            selection_reason_code=selection_reason_code,
            source_catalog_sha256=selected.source_catalog_sha256,
            knowledge_module_ids=module_ids,
        )

    def capability_metadata(self) -> list[dict[str, object]]:
        return [
            {
                "id": item.manifest.id,
                "version": item.manifest.version,
                "display_name": item.manifest.display_name,
                "sports": list(item.manifest.sports),
                "source_sha256": item.source_sha256,
                "runtime_sha256": item.runtime_sha256,
                "fragment_sha256": dict(item.fragment_hashes),
            }
            for item in sorted(self.load(), key=lambda item: item.manifest.id)
        ]

    def _load_bundle(
        self,
        bundle: Path,
        manifest_path: Path,
    ) -> LoadedTrainingSkill:
        raw_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest = TrainingSkillManifest.model_validate(raw_manifest)
        if not manifest.reviewed:
            raise SkillBundleError("训练 Skill 尚未完成审核")
        if not set(manifest.sport_fragments).issubset(set(manifest.sports)):
            raise SkillBundleError("训练 Skill 专项片段超出覆盖范围")
        if set(manifest.sport_fragments) != set(manifest.fragment_sha256):
            raise SkillBundleError("训练 Skill 片段与哈希清单不一致")
        declared_runtime_files = [
            manifest.runtime_file,
            *manifest.sport_fragments.values(),
        ]
        if manifest.source_file in declared_runtime_files:
            raise SkillBundleError("训练 Skill 源文件和运行时必须隔离")
        if len(declared_runtime_files) != len(set(declared_runtime_files)):
            raise SkillBundleError("训练 Skill 运行时文件不能重复")
        declared_files = [
            manifest.source_file,
            *declared_runtime_files,
            *(
                [manifest.source_catalog_file]
                if manifest.source_catalog_file is not None
                else []
            ),
        ]
        if len(declared_files) != len(set(declared_files)):
            raise SkillBundleError("训练 Skill 源文件、目录和运行时必须隔离")

        source_path = self._safe_bundle_file(bundle, manifest.source_file)
        runtime_path = self._safe_bundle_file(bundle, manifest.runtime_file)
        fragment_paths = {
            sport: self._safe_bundle_file(bundle, relative)
            for sport, relative in manifest.sport_fragments.items()
        }
        resolved_runtime_paths = [runtime_path, *fragment_paths.values()]
        if source_path in resolved_runtime_paths:
            raise SkillBundleError("训练 Skill 源文件和运行时必须隔离")
        if len(resolved_runtime_paths) != len(set(resolved_runtime_paths)):
            raise SkillBundleError("训练 Skill 运行时文件不能重复")
        self._validate_runtime_filename(manifest.runtime_file)
        for relative in manifest.sport_fragments.values():
            self._validate_runtime_filename(relative)
        catalog_path = (
            self._safe_bundle_file(bundle, manifest.source_catalog_file)
            if manifest.source_catalog_file is not None
            else None
        )
        resolved_declared_paths = [
            source_path,
            *resolved_runtime_paths,
            *([catalog_path] if catalog_path is not None else []),
        ]
        if len(resolved_declared_paths) != len(set(resolved_declared_paths)):
            raise SkillBundleError("训练 Skill 源文件、目录和运行时必须隔离")
        source = self._read_bytes(source_path, _MAX_SOURCE_BYTES)
        runtime = self._read_bytes(runtime_path, _MAX_RUNTIME_BYTES)
        fragments = {
            sport: self._read_bytes(path, _MAX_FRAGMENT_BYTES)
            for sport, path in fragment_paths.items()
        }
        source_hash = _sha256(source)
        runtime_hash = _sha256(runtime)
        fragment_hashes = {
            sport: _sha256(content) for sport, content in fragments.items()
        }
        if source_hash != manifest.source_sha256:
            raise SkillBundleError("训练 Skill 原始源文件哈希不匹配")
        if runtime_hash != manifest.runtime_sha256:
            raise SkillBundleError("训练 Skill 运行时哈希不匹配")
        if fragment_hashes != dict(manifest.fragment_sha256):
            raise SkillBundleError("训练 Skill 专项片段哈希不匹配")
        catalog_hash: str | None = None
        catalog: TrainingKnowledgeSourceCatalog | None = None
        knowledge_modules: tuple[TrainingKnowledgeModuleManifest, ...] = ()
        external_sources: tuple[TrainingExternalKnowledgeSourceManifest, ...] = ()
        if catalog_path is not None:
            catalog_bytes = self._read_bytes(
                catalog_path,
                _MAX_SOURCE_CATALOG_BYTES,
            )
            catalog_hash = _sha256(catalog_bytes)
            if catalog_hash != manifest.source_catalog_sha256:
                raise SkillBundleError("训练 Skill 来源目录哈希不匹配")
            try:
                catalog = TrainingKnowledgeSourceCatalog.model_validate_json(
                    catalog_bytes,
                )
            except ValidationError as error:
                raise SkillBundleError("训练 Skill 来源目录格式无效") from error
            self._validate_source_catalog(manifest, catalog)
            knowledge_modules = tuple(catalog.modules)
            external_sources = tuple(catalog.external_sources)
        try:
            runtime_text = runtime.decode("utf-8")
            fragment_texts = {
                sport: content.decode("utf-8") for sport, content in fragments.items()
            }
        except UnicodeDecodeError as error:
            raise SkillBundleError("训练 Skill 运行时必须使用 UTF-8") from error
        self._validate_runtime_text(runtime_text)
        for fragment_text in fragment_texts.values():
            self._validate_runtime_text(fragment_text)
        if catalog_hash is not None:
            binding = _SOURCE_CATALOG_BINDING.format(digest=catalog_hash)
            if binding not in runtime_text:
                raise SkillBundleError("训练 Skill 运行时未绑定来源目录")
        if catalog is not None:
            self._validate_runtime_module_mapping(
                catalog,
                runtime_text,
                fragment_texts,
            )
        return LoadedTrainingSkill(
            manifest=manifest,
            source_sha256=source_hash,
            runtime_sha256=runtime_hash,
            runtime_text=runtime_text,
            fragment_texts=fragment_texts,
            fragment_hashes=fragment_hashes,
            source_catalog_sha256=catalog_hash,
            knowledge_modules=knowledge_modules,
            external_sources=external_sources,
        )

    @staticmethod
    def _safe_bundle_file(bundle: Path, relative: str) -> Path:
        candidate = Path(relative)
        if candidate.is_absolute() or not relative.strip():
            raise SkillBundleError("训练 Skill 文件路径无效")
        bundle_root = bundle.resolve()
        unresolved = bundle / candidate
        if TrainingSkillRegistry._contains_symlink(unresolved, bundle):
            raise SkillBundleError("训练 Skill 禁止使用符号链接")
        resolved = unresolved.resolve()
        try:
            resolved.relative_to(bundle_root)
        except ValueError as error:
            raise SkillBundleError("训练 Skill 文件禁止越过包目录") from error
        if not resolved.is_file():
            raise SkillBundleError("训练 Skill 文件缺失")
        return resolved

    @staticmethod
    def _contains_symlink(path: Path, root: Path) -> bool:
        absolute_root = root.absolute()
        absolute_path = path.absolute()
        try:
            relative = absolute_path.relative_to(absolute_root)
        except ValueError:
            return False
        current = absolute_root
        if current.is_symlink():
            return True
        for part in relative.parts:
            current /= part
            if current.is_symlink():
                return True
        return False

    @staticmethod
    def _validate_runtime_filename(relative: str) -> None:
        if not _RUNTIME_FILE_PATTERN.fullmatch(PurePosixPath(relative).name):
            raise SkillBundleError("训练 Skill 运行时文件名无效")

    @staticmethod
    def _validate_runtime_text(content: str) -> None:
        if content.lstrip().startswith("---") or any(
            pattern.search(content) for pattern in _RUNTIME_FORBIDDEN_PATTERNS
        ):
            raise SkillBundleError("训练 Skill 运行时包含禁止内容")

    @staticmethod
    def _validate_source_catalog(
        manifest: TrainingSkillManifest,
        catalog: TrainingKnowledgeSourceCatalog,
    ) -> None:
        module_ids = [item.id for item in catalog.modules]
        if len(module_ids) != len(set(module_ids)):
            raise SkillBundleError("训练 Skill 来源模块 ID 重复")
        ids = [*module_ids, *(item.id for item in catalog.external_sources)]
        if len(ids) != len(set(ids)):
            raise SkillBundleError("训练 Skill 来源 ID 重复")
        paths = [item.archive_path for item in catalog.modules]
        normalized_paths = {
            unicodedata.normalize("NFKC", path).casefold() for path in paths
        }
        if len(paths) != len(normalized_paths):
            raise SkillBundleError("训练 Skill 来源模块路径重复")
        available_targets = {
            "base",
            *manifest.sport_fragments.keys(),
        }
        for item in (*catalog.modules, *catalog.external_sources):
            if not set(item.runtime_targets).issubset(available_targets):
                raise SkillBundleError("训练 Skill 来源模块缺少审核后运行时")

    @staticmethod
    def _validate_runtime_module_mapping(
        catalog: TrainingKnowledgeSourceCatalog,
        runtime_text: str,
        fragment_texts: dict[str, str],
    ) -> None:
        """确保每个启用来源只映射到声明目标的审核规则。"""

        target_texts = {"base": runtime_text, **fragment_texts}
        expected_by_target: dict[str, set[str]] = {
            target: {
                module.id
                for module in (*catalog.modules, *catalog.external_sources)
                if module.status == "runtime_approved"
                and target in module.runtime_targets
            }
            for target in target_texts
        }
        for target, content in target_texts.items():
            marker_ids: list[str] = []
            for match in _KNOWLEDGE_MODULE_MARKER.finditer(content):
                marker_ids.extend(match.group(1).split(","))
            unmatched_content = _KNOWLEDGE_MODULE_MARKER.sub("", content)
            if "knowledge_modules:" in unmatched_content:
                raise SkillBundleError("训练 Skill 来源模块标记格式无效")
            if len(marker_ids) != len(set(marker_ids)):
                raise SkillBundleError("训练 Skill 运行时来源模块标记重复")
            if set(marker_ids) != expected_by_target[target]:
                raise SkillBundleError("训练 Skill 运行时与来源模块映射不一致")

    @staticmethod
    def _read_bytes(path: Path, limit: int) -> bytes:
        content = path.read_bytes()
        if len(content) > limit:
            raise SkillBundleError("训练 Skill 文件超过大小上限")
        return content


def _sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()
