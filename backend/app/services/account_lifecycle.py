from __future__ import annotations

import hmac
from datetime import timedelta
from uuid import UUID, uuid4

from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import ApiError
from app.core.security import (
    email_code_hash,
    email_hash,
    generate_sms_code,
    normalize_email,
    utc_now,
)
from app.models import (
    AccountDeletionChallenge,
    AccountDeletionReceipt,
    AccountDeletionRequest,
    AccountExportRecord,
    AuthSession,
    CloudUserProfile,
    CoachMemoryProjection,
    CoachStateProjection,
    SubscriptionEntitlement,
    User,
    UserConsent,
)
from app.services.email_provider import EmailProvider
from app.services.profile_cipher import ProfileCipher
from app.services.sync_service import SyncService


class AccountLifecycleService:
    """处理可审计导出、邮箱复核、会话撤销和延迟删除。"""

    def __init__(self, session: Session, settings: Settings) -> None:
        self._session = session
        self._settings = settings

    def export(self, user_id: UUID) -> dict[str, object]:
        user = self._session.get(User, user_id)
        if user is None:
            raise ApiError(404, "account_not_found", "账号不存在")
        now = utc_now()
        record = AccountExportRecord(
            user_id=user_id,
            export_format="json",
            state="completed",
            completed_at=now,
        )
        self._session.add(record)
        self._session.flush()
        sync = SyncService(self._session, self._settings).snapshot(
            user_id,
            enforce_access=False,
        )
        membership = self._session.scalar(
            select(SubscriptionEntitlement).where(
                SubscriptionEntitlement.user_id == user_id,
                SubscriptionEntitlement.platform == "ios",
            ),
        )
        payload: dict[str, object] = {
            "export_id": str(record.id),
            "generated_at": now,
            "account": {
                "user_id": str(user.id),
                "account_type": (
                    "email" if user.email_hash is not None else "phone"
                ),
                "created_at": user.created_at,
            },
            "sync": sync,
            "membership": (
                {
                    "platform": membership.platform,
                    "product_id": membership.product_id,
                    "status": membership.status,
                    "expires_at": membership.expires_at,
                    "revoked_at": membership.revoked_at,
                }
                if membership is not None
                else None
            ),
        }
        self._session.commit()
        return payload

    def set_health_profile_cloud_consent(
        self,
        user_id: UUID,
        *,
        granted: bool,
        document_version: str,
    ) -> UserConsent:
        """记录独立健康云同步授权；撤回时同步擦除云端健康字段。"""
        if granted and not self._settings.health_profile_cloud_enabled:
            raise ApiError(
                503,
                "health_profile_cloud_disabled",
                "健康资料云同步当前未启用",
            )
        if document_version != self._settings.health_profile_consent_version:
            raise ApiError(
                422,
                "health_profile_consent_version_invalid",
                "健康资料授权版本已更新，请重新阅读",
            )
        user = self._session.get(User, user_id)
        if user is None:
            raise ApiError(404, "account_not_found", "账号不存在")
        consent = self._session.scalar(
            select(UserConsent).where(
                UserConsent.user_id == user_id,
                UserConsent.consent_type == "health_profile_cloud",
                UserConsent.document_version == document_version,
            ),
        )
        now = utc_now()
        if consent is None:
            consent = UserConsent(
                user_id=user_id,
                consent_type="health_profile_cloud",
                document_version=document_version,
                granted_at=now,
            )
            self._session.add(consent)
        elif granted:
            consent.granted_at = now
        consent.revoked_at = None if granted else now
        if not granted:
            self._scrub_cloud_profile_health(user_id)
        self._session.commit()
        self._session.refresh(consent)
        return consent

    def _scrub_cloud_profile_health(self, user_id: UUID) -> None:
        profile = self._session.scalar(
            select(CloudUserProfile).where(CloudUserProfile.user_id == user_id),
        )
        if profile is None or not profile.health_fields_included:
            return
        cipher = ProfileCipher(self._settings)
        payload = cipher.decrypt(
            user_id=user_id,
            schema_version=profile.schema_version,
            ciphertext=profile.ciphertext,
            nonce=profile.nonce,
            key_version=profile.key_version,
        )
        scrubbed = cipher.scrub_health_fields(payload)
        encrypted = cipher.encrypt(
            user_id=user_id,
            schema_version=profile.schema_version,
            payload=scrubbed,
        )
        profile.ciphertext = encrypted.ciphertext
        profile.nonce = encrypted.nonce
        profile.key_version = encrypted.key_version
        profile.health_fields_included = False
        profile.version += 1

    def set_coach_cloud_projection_consent(
        self,
        user_id: UUID,
        *,
        granted: bool,
        document_version: str,
    ) -> UserConsent:
        """记录 Coach 独立授权；撤回时立即删除全部云投影。"""
        if granted and not self._settings.coach_cloud_projection_enabled:
            raise ApiError(
                503,
                "coach_cloud_projection_disabled",
                "Coach 云投影当前未启用",
            )
        if document_version != self._settings.coach_cloud_projection_consent_version:
            raise ApiError(
                422,
                "coach_cloud_projection_consent_version_invalid",
                "Coach 云投影授权版本已更新，请重新阅读",
            )
        if self._session.get(User, user_id) is None:
            raise ApiError(404, "account_not_found", "账号不存在")
        consent = self._session.scalar(
            select(UserConsent).where(
                UserConsent.user_id == user_id,
                UserConsent.consent_type == "coach_cloud_projection",
                UserConsent.document_version == document_version,
            )
        )
        now = utc_now()
        if consent is None:
            consent = UserConsent(
                user_id=user_id,
                consent_type="coach_cloud_projection",
                document_version=document_version,
                granted_at=now,
            )
            self._session.add(consent)
        elif granted:
            consent.granted_at = now
        consent.revoked_at = None if granted else now
        if not granted:
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
        self._session.refresh(consent)
        return consent

    def request_deletion_challenge(
        self,
        user_id: UUID,
        email_value: str,
        provider: EmailProvider,
    ) -> UUID:
        user, email, target_hash = self._email_identity(user_id, email_value)
        if user.email_hash is None or not hmac.compare_digest(
            user.email_hash,
            target_hash,
        ):
            raise ApiError(
                401,
                "account_email_mismatch",
                "邮箱与当前账号不匹配",
            )
        now = utc_now()
        window_start = now - timedelta(
            seconds=self._settings.email_challenge_window_seconds,
        )
        recent_count = self._session.scalar(
            select(func.count())
            .select_from(AccountDeletionChallenge)
            .where(
                AccountDeletionChallenge.user_id == user_id,
                AccountDeletionChallenge.created_at >= window_start,
            ),
        )
        if recent_count is not None and (
            recent_count >= self._settings.email_challenge_limit_per_window
        ):
            raise ApiError(
                429,
                "account_deletion_rate_limited",
                "删除复核验证码请求过于频繁，请稍后再试",
            )

        challenge_id = uuid4()
        code = (
            self._settings.development_email_code
            if self._settings.email_provider == "development"
            else generate_sms_code()
        )
        challenge = AccountDeletionChallenge(
            id=challenge_id,
            user_id=user_id,
            email_hash=target_hash,
            code_hash=email_code_hash(
                challenge_id,
                target_hash,
                code,
                self._settings,
            ),
            expires_at=now
            + timedelta(seconds=self._settings.email_code_ttl_seconds),
        )
        self._session.add(challenge)
        self._session.flush()
        try:
            provider.send_verification_code(
                email,
                code,
                self._settings.email_code_ttl_seconds,
            )
        except Exception:
            self._session.rollback()
            raise
        self._session.commit()
        return challenge_id

    def request_deletion(
        self,
        user_id: UUID,
        *,
        email_value: str,
        challenge_id: UUID,
        code: str,
    ) -> AccountDeletionRequest:
        _, _, target_hash = self._email_identity(user_id, email_value)
        challenge = self._session.scalar(
            select(AccountDeletionChallenge)
            .where(
                AccountDeletionChallenge.id == challenge_id,
                AccountDeletionChallenge.user_id == user_id,
            )
            .with_for_update(),
        )
        now = utc_now()
        if (
            challenge is None
            or not hmac.compare_digest(challenge.email_hash, target_hash)
            or challenge.consumed_at is not None
            or self._is_expired(challenge.expires_at, now)
        ):
            raise ApiError(
                401,
                "account_deletion_challenge_invalid",
                "删除复核验证码无效或已过期",
            )
        if challenge.attempt_count >= self._settings.email_code_max_attempts:
            raise ApiError(
                401,
                "account_deletion_challenge_locked",
                "验证码尝试次数过多，请重新获取",
            )
        expected_hash = email_code_hash(
            challenge.id,
            target_hash,
            code,
            self._settings,
        )
        if not hmac.compare_digest(expected_hash, challenge.code_hash):
            challenge.attempt_count += 1
            self._session.commit()
            raise ApiError(401, "account_deletion_code_invalid", "验证码错误")

        active_request = self._active_request(user_id)
        if active_request is not None:
            raise ApiError(
                409,
                "account_deletion_already_pending",
                "账号删除申请已存在",
            )
        challenge.consumed_at = now
        deletion_request = AccountDeletionRequest(
            user_id=user_id,
            status="pending",
            requested_at=now,
            purge_after=now
            + timedelta(days=self._settings.account_deletion_grace_days),
        )
        self._session.add(deletion_request)
        self._session.execute(
            update(AuthSession)
            .where(
                AuthSession.user_id == user_id,
                AuthSession.revoked_at.is_(None),
            )
            .values(
                revoked_at=now,
                revocation_reason="account_deletion",
            ),
        )
        self._session.commit()
        self._session.refresh(deletion_request)
        return deletion_request

    def cancel_deletion(self, user_id: UUID) -> AccountDeletionRequest:
        deletion_request = self._active_request(user_id)
        if deletion_request is None:
            raise ApiError(
                404,
                "account_deletion_not_pending",
                "当前没有可撤销的账号删除申请",
            )
        now = utc_now()
        if self._is_expired(deletion_request.purge_after, now):
            raise ApiError(
                409,
                "account_deletion_grace_expired",
                "账号删除撤销期已结束",
            )
        deletion_request.status = "cancelled"
        deletion_request.cancelled_at = now
        self._session.commit()
        self._session.refresh(deletion_request)
        return deletion_request

    def deletion_status(
        self,
        user_id: UUID,
    ) -> AccountDeletionRequest | None:
        return self._session.scalar(
            select(AccountDeletionRequest)
            .where(AccountDeletionRequest.user_id == user_id)
            .order_by(AccountDeletionRequest.requested_at.desc())
            .limit(1),
        )

    def purge_due_deletions(self) -> int:
        """供私网定时任务调用；删除用户后只保留匿名回执。"""
        now = utc_now()
        requests = self._session.scalars(
            select(AccountDeletionRequest)
            .where(
                AccountDeletionRequest.status == "pending",
                AccountDeletionRequest.purge_after <= now,
            )
            .with_for_update(),
        ).all()
        purged = 0
        for deletion_request in requests:
            user = self._session.get(User, deletion_request.user_id)
            self._session.add(
                AccountDeletionReceipt(
                    deletion_request_id=deletion_request.id,
                    completed_at=now,
                ),
            )
            if user is not None:
                self._session.delete(user)
            purged += 1
        self._session.commit()
        return purged

    def _active_request(self, user_id: UUID) -> AccountDeletionRequest | None:
        return self._session.scalar(
            select(AccountDeletionRequest)
            .where(
                AccountDeletionRequest.user_id == user_id,
                AccountDeletionRequest.status == "pending",
            )
            .order_by(AccountDeletionRequest.requested_at.desc())
            .limit(1),
        )

    def _email_identity(
        self,
        user_id: UUID,
        email_value: str,
    ) -> tuple[User, str, str]:
        user = self._session.get(User, user_id)
        if user is None:
            raise ApiError(404, "account_not_found", "账号不存在")
        if user.email_hash is None:
            raise ApiError(
                409,
                "account_email_required",
                "当前账号未绑定邮箱，无法在线申请删除",
            )
        email = normalize_email(email_value)
        return user, email, email_hash(email, self._settings)

    @staticmethod
    def _is_expired(expires_at, now) -> bool:
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=now.tzinfo)
        return expires_at <= now
