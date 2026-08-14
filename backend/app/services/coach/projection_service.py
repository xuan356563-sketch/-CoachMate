from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import ApiError
from app.core.security import utc_now
from app.models import (
    CoachMemoryProjection,
    CoachRuleAudit,
    CoachStateProjection,
    UserConsent,
)
from app.services.coach.contracts import (
    CoachActionOutput,
    CoachEvaluationRequest,
    CoachEvaluationResponse,
    CoachProjectionPutRequest,
    CoachStateProjectionInput,
    canonical_digest,
)
from app.services.coach.projection_cipher import CoachProjectionCipher


class CoachProjectionService:
    """服务端只从登录用户的加密投影读取事实，再执行同构确定性规则。"""

    def __init__(self, session: Session, settings: Settings) -> None:
        self._session = session
        self._settings = settings
        self._cipher = CoachProjectionCipher(settings)

    def replace_current(
        self,
        user_id: UUID,
        request: CoachProjectionPutRequest,
    ) -> dict[str, object]:
        self._require_access(user_id)
        self._validate_contract(
            request.state.contract_version,
            request.state.contract_hash,
            request.state.rule_set_version,
        )
        if _as_utc(request.state.valid_until) <= utc_now():
            raise ApiError(
                422,
                "coach_snapshot_expired",
                "训练投影已经过期，请在本机重新生成",
            )
        state_row = self._session.scalar(
            select(CoachStateProjection).where(
                CoachStateProjection.user_id == user_id
            )
        )
        memory_row = self._session.scalar(
            select(CoachMemoryProjection).where(
                CoachMemoryProjection.user_id == user_id
            )
        )
        current_version = state_row.version if state_row is not None else 0
        supplied_version = request.base_version or 0
        if supplied_version != current_version:
            raise ApiError(
                409,
                "coach_projection_version_conflict",
                "Coach 云投影版本已变化，请重新读取后覆盖",
            )
        next_version = current_version + 1
        state_payload = request.state.model_dump(mode="json", exclude_none=False)
        memory_payload = {
            "memories": [
                item.model_dump(mode="json", exclude_none=False)
                for item in request.memories
            ],
            "memory_set_digest": request.memory_set_digest,
        }
        encrypted_state = self._cipher.encrypt(
            user_id=user_id,
            kind="state",
            version=next_version,
            payload=state_payload,
        )
        encrypted_memories = self._cipher.encrypt(
            user_id=user_id,
            kind="memories",
            version=next_version,
            payload=memory_payload,
        )
        now = utc_now()
        if state_row is None:
            state_row = CoachStateProjection(user_id=user_id)
            self._session.add(state_row)
        state_row.version = next_version
        state_row.snapshot_id = request.state.snapshot_id
        state_row.source_digest = request.state.source_digest
        state_row.snapshot_digest = request.state.snapshot_digest
        state_row.contract_version = request.state.contract_version
        state_row.contract_hash = request.state.contract_hash
        state_row.rule_set_version = request.state.rule_set_version
        state_row.ciphertext = encrypted_state.ciphertext
        state_row.nonce = encrypted_state.nonce
        state_row.key_version = encrypted_state.key_version
        state_row.generated_at = request.state.generated_at
        state_row.expires_at = request.state.valid_until
        state_row.updated_at = now
        if memory_row is None:
            memory_row = CoachMemoryProjection(user_id=user_id)
            self._session.add(memory_row)
        memory_row.version = next_version
        memory_row.memory_set_digest = request.memory_set_digest
        memory_row.memory_count = len(request.memories)
        memory_row.ciphertext = encrypted_memories.ciphertext
        memory_row.nonce = encrypted_memories.nonce
        memory_row.key_version = encrypted_memories.key_version
        memory_row.updated_at = now
        self._session.commit()
        return {
            "version": next_version,
            "snapshot_id": request.state.snapshot_id,
            "snapshot_digest": request.state.snapshot_digest,
            "memory_set_digest": request.memory_set_digest,
            "expires_at": request.state.valid_until,
        }

    def delete_current(self, user_id: UUID) -> None:
        self._session.execute(
            delete(CoachMemoryProjection).where(
                CoachMemoryProjection.user_id == user_id
            )
        )
        self._session.execute(
            delete(CoachStateProjection).where(
                CoachStateProjection.user_id == user_id
            )
        )
        self._session.commit()

    def evaluate(
        self,
        user_id: UUID,
        request: CoachEvaluationRequest,
    ) -> CoachEvaluationResponse:
        self._require_access(user_id)
        self._validate_contract(
            request.contract_version,
            request.contract_hash,
            request.rule_set_version,
        )
        state_row = self._session.scalar(
            select(CoachStateProjection).where(
                CoachStateProjection.user_id == user_id
            )
        )
        memory_row = self._session.scalar(
            select(CoachMemoryProjection).where(
                CoachMemoryProjection.user_id == user_id
            )
        )
        if state_row is None or memory_row is None:
            raise ApiError(
                409,
                "coach_projection_missing",
                "Coach 云投影不存在，请先从本机上传已授权投影",
            )
        if state_row.version != memory_row.version:
            raise ApiError(
                409,
                "coach_projection_version_mismatch",
                "Coach 状态与记忆投影版本不一致",
            )
        if _as_utc(state_row.expires_at) <= utc_now():
            raise ApiError(
                409,
                "coach_snapshot_expired",
                "Coach 云端训练快照已过期",
            )
        if (
            request.snapshot_id != state_row.snapshot_id
            or request.snapshot_digest != state_row.snapshot_digest
        ):
            raise ApiError(
                409,
                "coach_snapshot_mismatch",
                "本机与云端训练快照摘要不一致",
            )
        if request.memory_set_digest != memory_row.memory_set_digest:
            raise ApiError(
                409,
                "coach_memory_mismatch",
                "本机与云端记忆集合摘要不一致",
            )
        state_payload = self._cipher.decrypt(
            user_id=user_id,
            kind="state",
            version=state_row.version,
            ciphertext=state_row.ciphertext,
            nonce=state_row.nonce,
            key_version=state_row.key_version,
        )
        memory_payload = self._cipher.decrypt(
            user_id=user_id,
            kind="memories",
            version=memory_row.version,
            ciphertext=memory_row.ciphertext,
            nonce=memory_row.nonce,
            key_version=memory_row.key_version,
        )
        if memory_payload.get("memory_set_digest") != request.memory_set_digest:
            raise ApiError(
                409,
                "coach_memory_mismatch",
                "加密记忆集合与请求摘要不一致",
            )
        state = CoachStateProjectionInput.model_validate(state_payload)
        response = self._decision(request, state)
        request_digest = canonical_digest(request.model_dump(mode="json"))
        decision_digest = canonical_digest(response.model_dump(mode="json"))
        self._session.add(
            CoachRuleAudit(
                user_id=user_id,
                turn_id=request.turn_id,
                snapshot_id=request.snapshot_id,
                snapshot_digest=request.snapshot_digest,
                memory_set_digest=request.memory_set_digest,
                request_digest=request_digest,
                decision_digest=decision_digest,
                verification_state="remote_verified",
                reason_codes=response.reason_codes,
            )
        )
        self._session.commit()
        return response

    def _decision(
        self,
        request: CoachEvaluationRequest,
        state: CoachStateProjectionInput,
    ) -> CoachEvaluationResponse:
        allowed: list[CoachActionOutput] = []
        forbidden: list[str] = []
        required_blocks: list[str] = []
        risk: str = "low"
        reasons: list[str]
        if request.intent in {"emotional_support", "manage_memory"}:
            reasons = ["non_training_intent"]
        elif state.missing_fields:
            risk = "high"
            forbidden = ["all_training_actions"]
            reasons = ["snapshot_critical_fact_missing"]
        elif {"severe_pain", "injury_red_flag"}.intersection(state.safety_flags):
            risk = "critical"
            forbidden = ["all_training_actions"]
            required_blocks = ["pain_redline_guidance"]
            reasons = ["pain_redline"]
        elif state.planned_action_id is None or state.planned_duration_minutes is None:
            risk = "medium"
            reasons = ["existing_plan_missing"]
        elif (
            "pain_requires_adjustment" in state.safety_flags
            or state.recovery_band == "red"
        ):
            risk = "medium"
            reasons = ["existing_adjustment_required"]
            allowed = [
                CoachActionOutput(
                    action_id="request-existing-adjustment",
                    intensity="recovery",
                    duration_minutes=0,
                    requires_confirmation=True,
                    route="/daily-adjustment",
                )
            ]
        else:
            duration = min(
                state.planned_duration_minutes,
                (
                    state.available_minutes
                    if state.available_minutes is not None
                    else state.planned_duration_minutes
                ),
            )
            reasons = ["existing_plan_available"]
            allowed = [
                CoachActionOutput(
                    action_id="follow-existing-plan",
                    intensity=(
                        "low" if state.recovery_band == "amber" else "moderate"
                    ),
                    duration_minutes=duration,
                    requires_confirmation=False,
                    route="/plans",
                )
            ]
        if request.requested_action_ids:
            requested = set(request.requested_action_ids)
            allowed = [item for item in allowed if item.action_id in requested]
        return CoachEvaluationResponse(
            turn_id=request.turn_id,
            snapshot_id=request.snapshot_id,
            snapshot_digest=request.snapshot_digest,
            memory_set_digest=request.memory_set_digest,
            contract_version=self._settings.coach_contract_version,
            contract_hash=self._settings.coach_contract_hash,
            rule_set_version=self._settings.coach_rule_set_version,
            allowed=allowed,
            forbidden_action_ids=forbidden,
            risk_level=risk,
            reason_codes=reasons,
            required_blocks=required_blocks,
        )

    def _require_access(self, user_id: UUID) -> None:
        if not self._settings.coach_cloud_projection_enabled:
            raise ApiError(
                503,
                "coach_cloud_projection_disabled",
                "Coach 云投影当前未启用",
            )
        consent = self._session.scalar(
            select(UserConsent).where(
                UserConsent.user_id == user_id,
                UserConsent.consent_type == "coach_cloud_projection",
                UserConsent.document_version
                == self._settings.coach_cloud_projection_consent_version,
                UserConsent.revoked_at.is_(None),
            )
        )
        if consent is None:
            raise ApiError(
                403,
                "coach_cloud_projection_consent_required",
                "使用 Coach 云投影前需要单独授权",
            )

    def _validate_contract(
        self,
        contract_version: int,
        contract_hash: str,
        rule_set_version: str,
    ) -> None:
        if (
            contract_version != self._settings.coach_contract_version
            or contract_hash != self._settings.coach_contract_hash
            or rule_set_version != self._settings.coach_rule_set_version
        ):
            raise ApiError(
                409,
                "coach_contract_mismatch",
                "本机与云端 Coach 契约或规则版本不一致",
            )


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)
