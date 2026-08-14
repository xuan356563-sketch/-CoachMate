from __future__ import annotations

import hashlib
import json
from datetime import datetime, timedelta
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

Digest = Annotated[str, Field(pattern=r"^[a-f0-9]{64}$")]
MemoryCategory = Literal[
    "preference",
    "obstacle",
    "effective_strategy",
    "ritual",
    "boundary",
    "milestone",
]
CoachIntent = Literal[
    "today_training",
    "explain_plan",
    "recovery",
    "check_in",
    "emotional_support",
    "manage_memory",
]
CoachEmotion = Literal["neutral", "low", "anxious", "frustrated", "positive"]
ActionId = Literal["follow-existing-plan", "request-existing-adjustment"]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CoachStateProjectionInput(StrictModel):
    snapshot_id: str = Field(min_length=1, max_length=96)
    source_digest: Digest
    snapshot_digest: Digest
    contract_version: int = Field(ge=1)
    contract_hash: Digest
    rule_set_version: str = Field(min_length=1, max_length=64)
    generated_at: datetime
    valid_until: datetime
    local_date: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    planned_action_id: ActionId | None = None
    planned_duration_minutes: int | None = Field(default=None, ge=0, le=360)
    available_minutes: int | None = Field(default=None, ge=0, le=360)
    recovery_band: Literal["unknown", "green", "amber", "red"]
    completed_sessions_7d: int = Field(ge=0, le=100)
    missed_sessions_7d: int = Field(ge=0, le=100)
    safety_flags: list[
        Literal["severe_pain", "pain_requires_adjustment", "injury_red_flag"]
    ] = Field(default_factory=list, max_length=3)
    quality_codes: list[str] = Field(default_factory=list, max_length=20)
    missing_fields: list[str] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def validate_validity(self) -> "CoachStateProjectionInput":
        if self.valid_until <= self.generated_at:
            raise ValueError("训练投影有效期必须晚于生成时间")
        if self.valid_until > self.generated_at + timedelta(hours=6):
            raise ValueError("训练投影有效期不能超过六小时")
        return self


class CoachMemoryProjectionInput(StrictModel):
    memory_id: str = Field(min_length=1, max_length=96)
    category: MemoryCategory
    version: int = Field(ge=1)
    display_text: str = Field(min_length=1, max_length=240)
    confidence_bps: int = Field(ge=0, le=10000)
    valid_until: datetime | None = None
    until_revoked: bool = False
    may_mention: bool
    user_confirmed: Literal[True]
    sync_allowed: Literal[True]
    source_digests: list[Digest] = Field(min_length=1, max_length=10)

    @model_validator(mode="after")
    def validate_validity(self) -> "CoachMemoryProjectionInput":
        if self.category == "boundary":
            if not self.until_revoked:
                raise ValueError("用户边界必须持续到撤销")
        elif self.valid_until is None or self.until_revoked:
            raise ValueError("非边界记忆必须有有限有效期")
        return self


class CoachProjectionPutRequest(StrictModel):
    base_version: int | None = Field(default=None, ge=0)
    state: CoachStateProjectionInput
    memories: list[CoachMemoryProjectionInput] = Field(max_length=100)
    memory_set_digest: Digest

    @model_validator(mode="before")
    @classmethod
    def validate_memory_digest(cls, value: object) -> object:
        # 摘要必须校验客户端真正发送的规范化 JSON，避免日期经模型解析后改写格式。
        if not isinstance(value, dict):
            return value
        memories = value.get("memories")
        memory_set_digest = value.get("memory_set_digest")
        if (
            isinstance(memories, list)
            and isinstance(memory_set_digest, str)
            and canonical_digest(memories) != memory_set_digest
        ):
            raise ValueError("记忆集合摘要不一致")
        return value


class CoachEvaluationRequest(StrictModel):
    turn_id: str = Field(min_length=1, max_length=96)
    snapshot_id: str = Field(min_length=1, max_length=96)
    snapshot_digest: Digest
    memory_set_digest: Digest
    intent: CoachIntent
    emotion: CoachEmotion
    contract_version: int = Field(ge=1)
    contract_hash: Digest
    rule_set_version: str = Field(min_length=1, max_length=64)
    requested_action_ids: list[ActionId] = Field(default_factory=list, max_length=10)

    @field_validator("requested_action_ids")
    @classmethod
    def unique_actions(cls, value: list[ActionId]) -> list[ActionId]:
        if len(value) != len(set(value)):
            raise ValueError("请求动作编号不能重复")
        return value


class CoachActionOutput(StrictModel):
    action_id: ActionId
    intensity: Literal["rest", "recovery", "low", "moderate", "high"]
    duration_minutes: int = Field(ge=0, le=360)
    requires_confirmation: bool
    route: str | None = None


class CoachEvaluationResponse(StrictModel):
    turn_id: str
    snapshot_id: str
    snapshot_digest: Digest
    memory_set_digest: Digest
    contract_version: int
    contract_hash: Digest
    rule_set_version: str
    allowed: list[CoachActionOutput]
    forbidden_action_ids: list[str]
    risk_level: Literal["low", "medium", "high", "critical"]
    reason_codes: list[str]
    required_blocks: list[str]
    verification_state: Literal["remote_verified"] = "remote_verified"


def canonical_digest(value: object) -> str:
    encoded = json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()
