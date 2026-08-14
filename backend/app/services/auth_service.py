from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta
from uuid import UUID, uuid4

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import ApiError
from app.core.security import (
    create_access_token,
    email_code_hash,
    email_hash,
    generate_refresh_token,
    generate_sms_code,
    mask_email,
    normalize_china_mainland_phone,
    normalize_email,
    phone_hash,
    refresh_token_hash,
    sms_code_hash,
    utc_now,
)
from app.models import (
    AuthSession,
    Device,
    EmailChallenge,
    SmsChallenge,
    User,
    UserConsent,
)
from app.services.email_provider import EmailProvider
from app.services.sms_provider import SmsProvider


@dataclass(frozen=True)
class DeviceInput:
    """创建会话时需要记录的应用安装实例。"""

    installation_id: UUID
    platform: str
    device_name: str | None


@dataclass(frozen=True)
class ConsentInput:
    """首次登录必须接受的文档版本。"""

    terms_version: str
    privacy_version: str


@dataclass(frozen=True)
class IssuedTokens:
    """只在响应中返回一次的令牌对。"""

    access_token: str
    refresh_token: str
    session_id: UUID


class AuthService:
    """协调验证码挑战、账号创建、会话和刷新令牌轮换。"""

    def __init__(
        self,
        session: Session,
        settings: Settings,
        sms_provider: SmsProvider | None = None,
    ) -> None:
        self._session = session
        self._settings = settings
        self._sms_provider = sms_provider

    def request_sms_challenge(
        self,
        phone_value: str,
        sms_provider: SmsProvider | None = None,
    ) -> UUID:
        """在速率限制内创建挑战并下发验证码。"""
        provider = sms_provider or self._sms_provider
        if provider is None:
            raise ApiError(503, "sms_not_configured", "短信服务尚未配置")
        phone = normalize_china_mainland_phone(phone_value)
        target_phone_hash = phone_hash(phone, self._settings)
        now = utc_now()
        window_start = now - timedelta(
            seconds=self._settings.sms_challenge_window_seconds,
        )
        recent_count = self._session.scalar(
            select(func.count())
            .select_from(SmsChallenge)
            .where(
                SmsChallenge.phone_hash == target_phone_hash,
                SmsChallenge.created_at >= window_start,
            ),
        )
        if recent_count is not None and (
            recent_count >= self._settings.sms_challenge_limit_per_window
        ):
            raise ApiError(
                429,
                "sms_rate_limited",
                "验证码请求过于频繁，请稍后再试",
            )

        challenge_id = uuid4()
        code = (
            self._settings.development_sms_code
            if self._settings.sms_provider == "development"
            else generate_sms_code()
        )
        challenge = SmsChallenge(
            id=challenge_id,
            phone_hash=target_phone_hash,
            code_hash=sms_code_hash(
                challenge_id,
                target_phone_hash,
                code,
                self._settings,
            ),
            expires_at=now + timedelta(seconds=self._settings.sms_code_ttl_seconds),
        )
        self._session.add(challenge)
        self._session.flush()
        try:
            provider.send_verification_code(
                phone,
                code,
                self._settings.sms_code_ttl_seconds,
            )
        except Exception:
            self._session.rollback()
            raise
        self._session.commit()
        return challenge_id

    def request_email_challenge(
        self,
        email_value: str,
        email_provider: EmailProvider,
    ) -> UUID:
        """在速率限制内创建邮箱挑战并下发验证码。"""
        email = normalize_email(email_value)
        target_email_hash = email_hash(email, self._settings)
        now = utc_now()
        window_start = now - timedelta(
            seconds=self._settings.email_challenge_window_seconds,
        )
        recent_count = self._session.scalar(
            select(func.count())
            .select_from(EmailChallenge)
            .where(
                EmailChallenge.email_hash == target_email_hash,
                EmailChallenge.created_at >= window_start,
            ),
        )
        if recent_count is not None and (
            recent_count >= self._settings.email_challenge_limit_per_window
        ):
            raise ApiError(
                429,
                "email_rate_limited",
                "验证码请求过于频繁，请稍后再试",
            )

        challenge_id = uuid4()
        code = (
            self._settings.development_email_code
            if self._settings.email_provider == "development"
            else generate_sms_code()
        )
        challenge = EmailChallenge(
            id=challenge_id,
            email_hash=target_email_hash,
            code_hash=email_code_hash(
                challenge_id,
                target_email_hash,
                code,
                self._settings,
            ),
            expires_at=now + timedelta(seconds=self._settings.email_code_ttl_seconds),
        )
        self._session.add(challenge)
        self._session.flush()
        try:
            email_provider.send_verification_code(
                email,
                code,
                self._settings.email_code_ttl_seconds,
            )
        except Exception:
            self._session.rollback()
            raise
        self._session.commit()
        return challenge_id

    def create_session_from_sms(
        self,
        phone_value: str,
        challenge_id: UUID,
        code: str,
        device_input: DeviceInput,
        consents: ConsentInput | None,
    ) -> IssuedTokens:
        """验证挑战并创建账号或已登录设备会话。"""
        phone = normalize_china_mainland_phone(phone_value)
        target_phone_hash = phone_hash(phone, self._settings)
        challenge = self._session.scalar(
            select(SmsChallenge)
            .where(SmsChallenge.id == challenge_id)
            .with_for_update(),
        )
        now = utc_now()
        if challenge is None or challenge.phone_hash != target_phone_hash:
            raise ApiError(401, "sms_challenge_invalid", "验证码无效或已过期")
        if challenge.consumed_at is not None or self._is_expired(
            challenge.expires_at, now
        ):
            raise ApiError(401, "sms_challenge_invalid", "验证码无效或已过期")
        if challenge.attempt_count >= self._settings.sms_code_max_attempts:
            raise ApiError(
                401,
                "sms_challenge_locked",
                "验证码尝试次数过多，请重新获取",
            )

        expected_hash = sms_code_hash(
            challenge.id,
            target_phone_hash,
            code,
            self._settings,
        )
        if expected_hash != challenge.code_hash:
            challenge.attempt_count += 1
            self._session.commit()
            if challenge.attempt_count >= self._settings.sms_code_max_attempts:
                raise ApiError(
                    401, "sms_challenge_locked", "验证码尝试次数过多，请重新获取"
                )
            raise ApiError(401, "sms_code_invalid", "验证码错误")

        user = self._session.scalar(
            select(User).where(User.phone_hash == target_phone_hash),
        )
        requires_current_consents = user is None or not self._has_current_consents(
            user.id
        )
        if requires_current_consents:
            self._validate_current_consents(consents)

        if user is None:
            user = User(
                id=uuid4(),
                phone_hash=target_phone_hash,
                phone_last4=phone[-4:],
            )
            self._session.add(user)
            self._session.flush()
        if requires_current_consents:
            assert consents is not None
            self._record_consents(user.id, consents)

        device = self._upsert_device(user.id, device_input, now)
        challenge.consumed_at = now
        tokens = self._create_session(user.id, device.id)
        self._session.commit()
        return tokens

    def create_session_from_email(
        self,
        email_value: str,
        challenge_id: UUID,
        code: str,
        device_input: DeviceInput,
        consents: ConsentInput | None,
    ) -> IssuedTokens:
        """验证邮箱挑战并创建账号或已登录设备会话。"""
        email = normalize_email(email_value)
        target_email_hash = email_hash(email, self._settings)
        challenge = self._session.scalar(
            select(EmailChallenge)
            .where(EmailChallenge.id == challenge_id)
            .with_for_update(),
        )
        now = utc_now()
        if challenge is None or challenge.email_hash != target_email_hash:
            raise ApiError(401, "email_challenge_invalid", "验证码无效或已过期")
        if challenge.consumed_at is not None or self._is_expired(
            challenge.expires_at, now
        ):
            raise ApiError(401, "email_challenge_invalid", "验证码无效或已过期")
        if challenge.attempt_count >= self._settings.email_code_max_attempts:
            raise ApiError(
                401,
                "email_challenge_locked",
                "验证码尝试次数过多，请重新获取",
            )

        expected_hash = email_code_hash(
            challenge.id,
            target_email_hash,
            code,
            self._settings,
        )
        if expected_hash != challenge.code_hash:
            challenge.attempt_count += 1
            self._session.commit()
            if challenge.attempt_count >= self._settings.email_code_max_attempts:
                raise ApiError(
                    401,
                    "email_challenge_locked",
                    "验证码尝试次数过多，请重新获取",
                )
            raise ApiError(401, "email_code_invalid", "验证码错误")

        user = self._session.scalar(
            select(User).where(User.email_hash == target_email_hash),
        )
        requires_current_consents = user is None or not self._has_current_consents(
            user.id
        )
        if requires_current_consents:
            self._validate_current_consents(consents)

        if user is None:
            user = User(
                id=uuid4(),
                email_hash=target_email_hash,
                masked_email=mask_email(email),
            )
            self._session.add(user)
            self._session.flush()
        if requires_current_consents:
            assert consents is not None
            self._record_consents(user.id, consents)

        device = self._upsert_device(user.id, device_input, now)
        challenge.consumed_at = now
        tokens = self._create_session(user.id, device.id)
        self._session.commit()
        return tokens

    def refresh_session(self, refresh_token: str) -> IssuedTokens:
        """轮换刷新令牌；旧令牌重放将撤销整条会话族。"""
        token_hash = refresh_token_hash(refresh_token, self._settings)
        current_session = self._session.scalar(
            select(AuthSession).where(AuthSession.refresh_token_hash == token_hash),
        )
        now = utc_now()
        if current_session is None:
            raise ApiError(401, "refresh_token_invalid", "刷新令牌无效或已过期")
        if current_session.revoked_at is not None:
            if current_session.revocation_reason == "rotated":
                self._revoke_session_family(current_session.family_id, now, "replayed")
                self._session.commit()
                raise ApiError(
                    401,
                    "refresh_token_replayed",
                    "检测到刷新令牌重复使用，请重新登录",
                )
            raise ApiError(401, "refresh_token_invalid", "刷新令牌无效或已过期")
        if self._is_expired(current_session.expires_at, now):
            current_session.revoked_at = now
            current_session.revocation_reason = "expired"
            self._session.commit()
            raise ApiError(401, "refresh_token_invalid", "刷新令牌无效或已过期")

        rotated_session = self._create_session(
            current_session.user_id,
            current_session.device_id,
            family_id=current_session.family_id,
            parent_session_id=current_session.id,
        )
        current_session.revoked_at = now
        current_session.revocation_reason = "rotated"
        current_session.replaced_by_session_id = rotated_session.session_id
        self._session.commit()
        return rotated_session

    def revoke_session(self, session_id: UUID, user_id: UUID) -> None:
        """撤销当前用户自己的一个会话。"""
        auth_session = self._session.get(AuthSession, session_id)
        if auth_session is None or auth_session.user_id != user_id:
            raise ApiError(404, "session_not_found", "会话不存在")
        if auth_session.revoked_at is None:
            auth_session.revoked_at = utc_now()
            auth_session.revocation_reason = "logout"
            self._session.commit()

    def _has_current_consents(self, user_id: UUID) -> bool:
        rows = self._session.execute(
            select(UserConsent.consent_type, UserConsent.document_version).where(
                UserConsent.user_id == user_id,
                UserConsent.revoked_at.is_(None),
            ),
        ).all()
        current = {
            ("terms", self._settings.terms_version),
            ("privacy", self._settings.privacy_version),
        }
        return current.issubset(set(rows))

    def _validate_current_consents(self, consents: ConsentInput | None) -> None:
        if consents is None:
            raise ApiError(
                422,
                "consent_required",
                "登录前需同意当前服务协议与隐私政策",
            )
        if (
            consents.terms_version != self._settings.terms_version
            or consents.privacy_version != self._settings.privacy_version
        ):
            raise ApiError(
                422,
                "consent_version_invalid",
                "协议版本已更新，请重新阅读并同意",
            )

    def _record_consents(self, user_id: UUID, consents: ConsentInput) -> None:
        existing = set(
            self._session.execute(
                select(UserConsent.consent_type, UserConsent.document_version).where(
                    UserConsent.user_id == user_id,
                ),
            ).all(),
        )
        pending = [
            ("terms", consents.terms_version),
            ("privacy", consents.privacy_version),
        ]
        self._session.add_all(
            [
                UserConsent(
                    id=uuid4(),
                    user_id=user_id,
                    consent_type=consent_type,
                    document_version=document_version,
                )
                for consent_type, document_version in pending
                if (consent_type, document_version) not in existing
            ],
        )

    def _upsert_device(
        self,
        user_id: UUID,
        device_input: DeviceInput,
        now,
    ) -> Device:
        device = self._session.scalar(
            select(Device).where(
                Device.user_id == user_id,
                Device.installation_id == device_input.installation_id,
            ),
        )
        if device is None:
            device = Device(
                id=uuid4(),
                user_id=user_id,
                installation_id=device_input.installation_id,
                platform=device_input.platform,
                device_name=device_input.device_name,
                last_seen_at=now,
            )
            self._session.add(device)
            self._session.flush()
            return device

        device.platform = device_input.platform
        device.device_name = device_input.device_name
        device.last_seen_at = now
        return device

    def _create_session(
        self,
        user_id: UUID,
        device_id: UUID | None,
        family_id: UUID | None = None,
        parent_session_id: UUID | None = None,
    ) -> IssuedTokens:
        session_id = uuid4()
        refresh_token = generate_refresh_token()
        auth_session = AuthSession(
            id=session_id,
            user_id=user_id,
            device_id=device_id,
            family_id=family_id or uuid4(),
            parent_session_id=parent_session_id,
            refresh_token_hash=refresh_token_hash(refresh_token, self._settings),
            expires_at=utc_now()
            + timedelta(days=self._settings.session_refresh_ttl_days),
        )
        self._session.add(auth_session)
        self._session.flush()
        return IssuedTokens(
            access_token=create_access_token(user_id, session_id, self._settings),
            refresh_token=refresh_token,
            session_id=session_id,
        )

    def _revoke_session_family(
        self,
        family_id: UUID,
        now,
        reason: str,
    ) -> None:
        self._session.execute(
            update(AuthSession)
            .where(
                AuthSession.family_id == family_id,
                AuthSession.revoked_at.is_(None),
            )
            .values(revoked_at=now, revocation_reason=reason),
        )

    @staticmethod
    def _is_expired(expires_at, now) -> bool:
        """兼容 SQLite 测试环境返回的无时区时间。"""
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=now.tzinfo)
        return expires_at <= now
