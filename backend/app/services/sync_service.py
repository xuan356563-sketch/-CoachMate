from __future__ import annotations

import base64
from datetime import date, datetime
from typing import Any, Literal
from uuid import UUID

import redis
from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import ApiError
from app.models import (
    AccountDeletionRequest,
    CloudPlanVersion,
    CloudScheduledWorkout,
    CloudUserProfile,
    CompletionSummary,
    SyncChange,
    SyncMutation,
    TrainingPreference,
    UserAppSetting,
    UserConsent,
)
from app.services.profile_cipher import ProfileCipher

SyncEntityType = Literal[
    "user_profile",
    "training_preferences",
    "plan_versions",
    "scheduled_workouts",
    "completion_summaries",
    "app_settings",
]


class _StrictPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")


class TrainingPreferencesPayload(_StrictPayload):
    """允许上传的训练偏好字段。"""

    goal: str = Field(min_length=1, max_length=80)
    sport_types: list[str] = Field(min_length=1, max_length=8)
    experience_level: str = Field(min_length=1, max_length=32)
    weekly_availability: list[int] = Field(min_length=1, max_length=7)
    equipment: list[str] = Field(max_length=32)


class StructuredInjuryPayload(_StrictPayload):
    """用户确认后的伤病限制，不包含诊断结论。"""

    body_region: str = Field(min_length=1, max_length=48)
    state: Literal[
        "recovered",
        "occasional_discomfort",
        "currently_limited",
        "uncertain",
    ]
    limiting_activity: Literal[
        "run",
        "jump",
        "squat",
        "push",
        "pull",
        "other",
    ]
    confirmed_note: str = Field(default="", max_length=40)


class UserProfilePayload(_StrictPayload):
    """确认后的首次建档白名单；原始文本和转写稿不属于契约。"""

    schema_version: Literal[1] = 1
    nickname: str = Field(min_length=1, max_length=40)
    gender: Literal["male", "female", "other", "unknown"]
    declared_age: int = Field(ge=18, le=120)
    height_cm: float | None = Field(default=None, ge=100, le=250)
    weight_kg: float | None = Field(default=None, ge=30, le=350)
    worker_profile_type: str = Field(min_length=1, max_length=48)
    work_schedule_type: str = Field(min_length=1, max_length=48)
    training_goal: str = Field(min_length=1, max_length=80)
    main_sports: list[str] = Field(default_factory=list, max_length=8)
    training_experience_level: str = Field(min_length=1, max_length=32)
    training_environment: Literal[
        "bodyweight_home",
        "home_equipment",
        "gym",
        "outdoor",
        "mixed",
    ]
    weekly_training_days: int = Field(ge=1, le=7)
    daily_available_minutes: int = Field(ge=15, le=180)
    core_self_report: Literal[
        "under_20_seconds",
        "seconds_20_45",
        "seconds_46_90",
        "over_90_seconds",
        "uncertain",
    ]
    aerobic_talk_test: Literal[
        "under_10_minutes",
        "minutes_10_20",
        "minutes_21_40",
        "over_40_minutes",
        "uncertain",
    ]
    cardio_recovery: Literal[
        "over_5_minutes",
        "minutes_3_5",
        "minutes_1_3",
        "under_1_minute",
        "uncertain",
    ]
    injuries: list[StructuredInjuryPayload] = Field(
        default_factory=list,
        max_length=10,
    )
    health_fields_included: bool = False

    @model_validator(mode="after")
    def validate_health_boundary(self) -> "UserProfilePayload":
        if not self.health_fields_included and (
            self.height_cm is not None
            or self.weight_kg is not None
            or self.injuries
        ):
            raise ValueError("未授权健康资料云同步时不得包含健康字段")
        return self


class PlanVersionPayload(_StrictPayload):
    """计划版本的非敏感云端投影。"""

    title: str = Field(min_length=1, max_length=120)
    starts_on: date
    ends_on: date | None = None
    state: Literal["draft", "active", "completed", "archived"]


class ScheduledWorkoutPayload(_StrictPayload):
    """计划课次的非敏感云端投影。"""

    plan_version_id: UUID
    scheduled_date: date
    sport_type: str = Field(min_length=1, max_length=32)
    title: str = Field(min_length=1, max_length=120)
    duration_minutes: int = Field(ge=1, le=600)
    state: Literal["scheduled", "completed", "skipped", "cancelled"]


class CompletionSummaryPayload(_StrictPayload):
    """训练完成摘要，不接受主观和健康数据。"""

    plan_version_id: UUID
    scheduled_workout_id: UUID
    started_at: datetime
    ended_at: datetime
    duration_seconds: int = Field(ge=0, le=172800)
    completion_percentage: int = Field(ge=0, le=100)
    revoked: bool = False


class AppSettingsPayload(_StrictPayload):
    """跨设备应用设置白名单。"""

    locale: str = Field(min_length=2, max_length=16)
    week_starts_on: int = Field(ge=1, le=7)
    notifications_enabled: bool


_PAYLOAD_MODELS: dict[str, type[_StrictPayload]] = {
    "user_profile": UserProfilePayload,
    "training_preferences": TrainingPreferencesPayload,
    "plan_versions": PlanVersionPayload,
    "scheduled_workouts": ScheduledWorkoutPayload,
    "completion_summaries": CompletionSummaryPayload,
    "app_settings": AppSettingsPayload,
}


class IncomingMutation(BaseModel):
    """服务层使用的已解析同步操作。"""

    model_config = ConfigDict(extra="forbid")

    mutation_id: UUID
    entity_type: SyncEntityType
    entity_id: UUID
    operation: Literal["upsert"]
    base_version: int | None = Field(default=None, ge=0)
    payload: dict[str, Any]


class SyncWriteGate:
    """生产环境依赖 Redis 确认写入协调能力可用。"""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._redis = redis.Redis.from_url(
            settings.redis_url,
            socket_connect_timeout=1,
            socket_timeout=1,
            decode_responses=True,
        )

    def check(self) -> None:
        if self._settings.app_env != "production":
            return
        try:
            self._redis.ping()
        except redis.RedisError as error:
            raise ApiError(
                503,
                "sync_write_unavailable",
                "云同步暂时不可用，本地训练不受影响",
            ) from error


class SyncService:
    """执行白名单校验、乐观锁、幂等记录和增量游标写入。"""

    def __init__(self, session: Session, settings: Settings) -> None:
        self._session = session
        self._settings = settings
        self._profile_cipher = ProfileCipher(settings)

    def ensure_enabled(self) -> None:
        if not self._settings.sync_enabled:
            raise ApiError(503, "sync_disabled", "云同步功能当前未启用")

    def apply_mutations(
        self,
        user_id: UUID,
        mutations: list[IncomingMutation],
    ) -> list[dict[str, Any]]:
        self.ensure_enabled()
        self._ensure_account_sync_allowed(user_id)
        validated = [
            (mutation, self._validate_payload(mutation))
            for mutation in mutations
        ]
        for mutation, payload in validated:
            if mutation.entity_type == "user_profile":
                self._ensure_profile_upload_allowed(user_id, payload)
        results: list[dict[str, Any]] = []
        for mutation, payload in validated:
            saved = self._session.scalar(
                select(SyncMutation).where(
                    SyncMutation.user_id == user_id,
                    SyncMutation.mutation_id == mutation.mutation_id,
                ),
            )
            if saved is not None:
                results.append(dict(saved.result_payload))
                continue

            result = self._apply_one(user_id, mutation, payload)
            self._session.add(
                SyncMutation(
                    user_id=user_id,
                    mutation_id=mutation.mutation_id,
                    entity_type=mutation.entity_type,
                    entity_id=mutation.entity_id,
                    outcome=result["status"],
                    result_payload=result,
                ),
            )
            results.append(result)
        self._session.commit()
        return results

    def snapshot(
        self,
        user_id: UUID,
        *,
        enforce_access: bool = True,
    ) -> dict[str, Any]:
        if enforce_access:
            self.ensure_enabled()
            self._ensure_account_sync_allowed(user_id)
        entities = {
            "user_profile": self._snapshot_rows(
                self._session.scalars(
                    select(CloudUserProfile).where(
                        CloudUserProfile.user_id == user_id,
                    ),
                ).all(),
                "user_profile",
            ),
            "training_preferences": self._snapshot_rows(
                self._session.scalars(
                    select(TrainingPreference).where(
                        TrainingPreference.user_id == user_id,
                    ),
                ).all(),
                "training_preferences",
            ),
            "plan_versions": self._snapshot_rows(
                self._session.scalars(
                    select(CloudPlanVersion).where(
                        CloudPlanVersion.user_id == user_id,
                    ),
                ).all(),
                "plan_versions",
            ),
            "scheduled_workouts": self._snapshot_rows(
                self._session.scalars(
                    select(CloudScheduledWorkout).where(
                        CloudScheduledWorkout.user_id == user_id,
                    ),
                ).all(),
                "scheduled_workouts",
            ),
            "completion_summaries": self._snapshot_rows(
                self._session.scalars(
                    select(CompletionSummary).where(
                        CompletionSummary.user_id == user_id,
                    ),
                ).all(),
                "completion_summaries",
            ),
            "app_settings": self._snapshot_rows(
                self._session.scalars(
                    select(UserAppSetting).where(
                        UserAppSetting.user_id == user_id,
                    ),
                ).all(),
                "app_settings",
            ),
        }
        cursor = self._session.scalar(
            select(func.max(SyncChange.cursor)).where(
                SyncChange.user_id == user_id,
            ),
        )
        return {"cursor": cursor or 0, "entities": entities}

    def changes(
        self,
        user_id: UUID,
        *,
        after: int,
        limit: int,
    ) -> dict[str, Any]:
        self.ensure_enabled()
        self._ensure_account_sync_allowed(user_id)
        rows = self._session.scalars(
            select(SyncChange)
            .where(
                SyncChange.user_id == user_id,
                SyncChange.cursor > after,
            )
            .order_by(SyncChange.cursor)
            .limit(limit + 1),
        ).all()
        has_more = len(rows) > limit
        selected = rows[:limit]
        changes = [
            {
                "cursor": row.cursor,
                "mutation_id": str(row.mutation_id),
                "entity_type": row.entity_type,
                "entity_id": str(row.entity_id),
                "operation": row.operation,
                "version": row.version,
                "payload": self._change_payload(user_id, row),
            }
            for row in selected
        ]
        return {
            "changes": changes,
            "next_cursor": selected[-1].cursor if selected else after,
            "has_more": has_more,
        }

    def _ensure_account_sync_allowed(self, user_id: UUID) -> None:
        pending = self._session.scalar(
            select(AccountDeletionRequest.id).where(
                AccountDeletionRequest.user_id == user_id,
                AccountDeletionRequest.status == "pending",
            ),
        )
        if pending is not None:
            raise ApiError(
                423,
                "account_deletion_pending",
                "账号正在删除撤销期内，云同步已停止",
            )

    def _ensure_profile_upload_allowed(
        self,
        user_id: UUID,
        payload: _StrictPayload,
    ) -> None:
        if not isinstance(payload, UserProfilePayload):
            return
        if not payload.health_fields_included:
            return
        if not self._settings.health_profile_cloud_enabled:
            raise ApiError(
                503,
                "health_profile_cloud_disabled",
                "健康资料云同步当前未启用",
            )
        consent = self._session.scalar(
            select(UserConsent.id).where(
                UserConsent.user_id == user_id,
                UserConsent.consent_type == "health_profile_cloud",
                UserConsent.document_version
                == self._settings.health_profile_consent_version,
                UserConsent.revoked_at.is_(None),
            ),
        )
        if consent is None:
            raise ApiError(
                403,
                "health_profile_cloud_consent_required",
                "上传身高、体重或伤病前需单独授权健康资料云同步",
            )

    def _validate_payload(
        self,
        mutation: IncomingMutation,
    ) -> _StrictPayload:
        payload_model = _PAYLOAD_MODELS[mutation.entity_type]
        try:
            return payload_model.model_validate(mutation.payload)
        except ValidationError as error:
            raise ApiError(
                422,
                "sync_payload_invalid",
                "同步请求包含未声明或不允许的字段。",
            ) from error

    def _apply_one(
        self,
        user_id: UUID,
        mutation: IncomingMutation,
        payload: _StrictPayload,
    ) -> dict[str, Any]:
        existing = self._find_entity(user_id, mutation)
        current_version = 0 if existing is None else self._version(existing)
        if (
            existing is not None
            and mutation.base_version != current_version
        ) or (
            existing is None
            and mutation.base_version not in (None, 0)
        ):
            return self._conflict_result(mutation, existing, current_version)

        version = current_version + 1
        entity = self._upsert_entity(
            user_id,
            mutation,
            payload,
            existing,
            version,
        )
        if mutation.entity_type == "user_profile":
            safe_payload = {
                "schema_version": entity.schema_version,
                "ciphertext": base64.b64encode(entity.ciphertext).decode("ascii"),
                "nonce": base64.b64encode(entity.nonce).decode("ascii"),
                "key_version": entity.key_version,
            }
        else:
            safe_payload = self._entity_payload(mutation.entity_type, entity)
        change = SyncChange(
            user_id=user_id,
            mutation_id=mutation.mutation_id,
            entity_type=mutation.entity_type,
            entity_id=entity.id,
            operation=mutation.operation,
            version=version,
            payload=safe_payload,
        )
        self._session.add(change)
        self._session.flush()
        return {
            "mutation_id": str(mutation.mutation_id),
            "entity_type": mutation.entity_type,
            "entity_id": str(entity.id),
            "status": "applied",
            "version": version,
            "cursor": change.cursor,
        }

    def _find_entity(
        self,
        user_id: UUID,
        mutation: IncomingMutation,
    ) -> Any | None:
        if mutation.entity_type == "user_profile":
            return self._session.scalar(
                select(CloudUserProfile).where(
                    CloudUserProfile.user_id == user_id,
                ),
            )
        if mutation.entity_type == "training_preferences":
            return self._session.scalar(
                select(TrainingPreference).where(
                    TrainingPreference.user_id == user_id,
                ),
            )
        if mutation.entity_type == "app_settings":
            return self._session.scalar(
                select(UserAppSetting).where(UserAppSetting.user_id == user_id),
            )
        model = {
            "plan_versions": CloudPlanVersion,
            "scheduled_workouts": CloudScheduledWorkout,
            "completion_summaries": CompletionSummary,
        }[mutation.entity_type]
        return self._session.scalar(
            select(model).where(
                model.id == mutation.entity_id,
                model.user_id == user_id,
            ),
        )

    @staticmethod
    def _version(entity: Any) -> int:
        return entity.version if hasattr(entity, "version") else 1

    def _conflict_result(
        self,
        mutation: IncomingMutation,
        existing: Any | None,
        current_version: int,
    ) -> dict[str, Any]:
        result: dict[str, Any] = {
            "mutation_id": str(mutation.mutation_id),
            "entity_type": mutation.entity_type,
            "entity_id": str(
                existing.id if existing is not None else mutation.entity_id
            ),
            "status": "conflict",
            "version": current_version,
        }
        if existing is not None:
            if mutation.entity_type != "user_profile":
                result["cloud_payload"] = self._entity_payload(
                    mutation.entity_type,
                    existing,
                )
        return result

    def _upsert_entity(
        self,
        user_id: UUID,
        mutation: IncomingMutation,
        payload: _StrictPayload,
        existing: Any | None,
        version: int,
    ) -> Any:
        values = payload.model_dump(mode="json")
        if mutation.entity_type == "user_profile":
            encrypted = self._profile_cipher.encrypt(
                user_id=user_id,
                schema_version=int(values["schema_version"]),
                payload=values,
            )
            entity = existing or CloudUserProfile(
                id=mutation.entity_id,
                user_id=user_id,
            )
            entity.schema_version = int(values["schema_version"])
            entity.ciphertext = encrypted.ciphertext
            entity.nonce = encrypted.nonce
            entity.key_version = encrypted.key_version
            entity.health_fields_included = bool(
                values["health_fields_included"]
            )
            values = {}
        elif mutation.entity_type == "training_preferences":
            entity = existing or TrainingPreference(
                id=mutation.entity_id,
                user_id=user_id,
            )
        elif mutation.entity_type == "plan_versions":
            entity = existing or CloudPlanVersion(
                id=mutation.entity_id,
                user_id=user_id,
            )
        elif mutation.entity_type == "scheduled_workouts":
            entity = existing or CloudScheduledWorkout(
                id=mutation.entity_id,
                user_id=user_id,
            )
        elif mutation.entity_type == "completion_summaries":
            entity = existing or CompletionSummary(
                id=mutation.entity_id,
                user_id=user_id,
            )
        else:
            entity = existing or UserAppSetting(
                id=mutation.entity_id,
                user_id=user_id,
            )
        for key, value in values.items():
            setattr(entity, key, value)
        if hasattr(entity, "version"):
            entity.version = version
        if existing is None:
            self._session.add(entity)
        self._session.flush()
        return entity

    def _snapshot_rows(self, rows: list[Any], entity_type: str) -> list[dict[str, Any]]:
        return [
            {
                "entity_id": str(row.id),
                "version": self._version(row),
                "payload": self._entity_payload(entity_type, row),
            }
            for row in rows
        ]

    def _entity_payload(self, entity_type: str, entity: Any) -> dict[str, Any]:
        if entity_type == "user_profile":
            return self._profile_cipher.decrypt(
                user_id=entity.user_id,
                schema_version=entity.schema_version,
                ciphertext=entity.ciphertext,
                nonce=entity.nonce,
                key_version=entity.key_version,
            )
        fields = _PAYLOAD_MODELS[entity_type].model_fields
        raw = {field: getattr(entity, field) for field in fields}
        return _PAYLOAD_MODELS[entity_type](**raw).model_dump(mode="json")

    def _change_payload(
        self,
        user_id: UUID,
        change: SyncChange,
    ) -> dict[str, Any]:
        if change.entity_type != "user_profile":
            return dict(change.payload)
        return self._profile_cipher.decrypt_envelope(
            user_id=user_id,
            envelope=dict(change.payload),
        )
