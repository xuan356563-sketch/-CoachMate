from __future__ import annotations

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import ApiError
from app.core.security import AccessTokenClaims, decode_access_token, utc_now
from app.db.session import get_session
from app.models import AuthSession, User, UserConsent
from app.services.auth_redis_gate import AuthRedisGate
from app.services.auth_service import (
    AuthService,
    ConsentInput,
    DeviceInput,
    IssuedTokens,
)
from app.services.email_provider import (
    DevelopmentEmailProvider,
    EmailProvider,
    SmtpEmailProvider,
)
from app.services.sms_provider import (
    DevelopmentSmsProvider,
    SmsProvider,
    TencentCloudSmsProvider,
)

router = APIRouter(prefix="/v1/auth", tags=["账号与会话"])
_bearer_scheme = HTTPBearer(auto_error=False)


class SmsChallengeRequest(BaseModel):
    """申请短信验证码。"""

    phone: str = Field(max_length=24)


class SmsChallengeResponse(BaseModel):
    """不包含验证码的挑战响应。"""

    challenge_id: UUID
    expires_in_seconds: int


class EmailChallengeRequest(BaseModel):
    """申请邮箱验证码。"""

    email: str = Field(max_length=320)


class EmailChallengeResponse(BaseModel):
    """不包含验证码和邮箱明文的挑战响应。"""

    challenge_id: UUID
    expires_in_seconds: int


class DeviceRequest(BaseModel):
    """客户端安装实例声明。"""

    installation_id: UUID
    platform: Literal["android", "ios", "web", "macos", "windows", "linux"]
    device_name: str | None = Field(default=None, max_length=80)


class ConsentRequest(BaseModel):
    """首次注册时提交的协议版本。"""

    terms_version: str = Field(min_length=1, max_length=64)
    privacy_version: str = Field(min_length=1, max_length=64)


class CreateSessionRequest(BaseModel):
    """验证码登录请求，邮箱和手机号必须且只能提交一个。"""

    email: str | None = Field(default=None, max_length=320)
    phone: str | None = Field(default=None, max_length=24)
    challenge_id: UUID
    code: str = Field(min_length=6, max_length=6)
    device: DeviceRequest
    consents: ConsentRequest | None = None

    @model_validator(mode="after")
    def validate_identity(self):
        """拒绝同时提交或完全不提交登录标识。"""
        if (self.email is None) == (self.phone is None):
            raise ValueError("邮箱和手机号必须且只能填写一个")
        return self

    @field_validator("code")
    @classmethod
    def validate_code(cls, value: str) -> str:
        """拒绝非六位数字验证码。"""
        if not value.isdigit():
            raise ValueError("验证码必须是六位数字")
        return value


class RefreshTokenRequest(BaseModel):
    """使用不透明刷新令牌获取新令牌对。"""

    refresh_token: str = Field(min_length=32, max_length=512)


class TokenResponse(BaseModel):
    """令牌对响应。"""

    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in_seconds: int
    session_id: UUID


class CurrentUserResponse(BaseModel):
    """当前账号的最小非敏感资料。"""

    user_id: UUID
    session_id: UUID
    account_type: Literal["email", "phone"]
    masked_email: str | None
    phone_last4: str | None
    has_required_consents: bool


class PublicAuthConfigResponse(BaseModel):
    """客户端登录前可以读取的非敏感配置。"""

    terms_version: str
    privacy_version: str
    sms_mode: Literal["development", "tencent", "disabled"]
    email_mode: Literal["development", "smtp", "disabled"]


def get_sms_provider(
    settings: Annotated[Settings, Depends(get_settings)],
) -> SmsProvider:
    """按部署配置选择短信供应商。"""
    if settings.sms_provider == "development":
        if settings.app_env != "development":
            raise ApiError(503, "sms_not_configured", "开发短信模式不可用")
        return DevelopmentSmsProvider()
    if settings.sms_provider == "tencent":
        return TencentCloudSmsProvider(settings)
    raise ApiError(503, "sms_not_configured", "短信服务尚未配置")


def get_email_provider(
    settings: Annotated[Settings, Depends(get_settings)],
) -> EmailProvider:
    """按部署配置选择邮件供应商。"""
    if settings.email_provider == "development":
        if settings.app_env != "development":
            raise ApiError(503, "email_not_configured", "开发邮件模式不可用")
        return DevelopmentEmailProvider()
    if settings.email_provider == "smtp":
        return SmtpEmailProvider(settings)
    raise ApiError(503, "email_not_configured", "邮件服务尚未配置")


def get_auth_service(
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AuthService:
    """构造单请求认证服务。"""
    return AuthService(session, settings)


def get_auth_redis_gate(
    settings: Annotated[Settings, Depends(get_settings)],
) -> AuthRedisGate:
    """构造验证码与令牌写入的生产 Redis 门禁。"""
    return AuthRedisGate(settings)


@router.get(
    "/public-config",
    response_model=PublicAuthConfigResponse,
    summary="读取登录公开配置",
)
def get_public_auth_config(
    settings: Annotated[Settings, Depends(get_settings)],
) -> PublicAuthConfigResponse:
    """返回协议版本和验证码通道模式，不返回验证码或服务端密钥。"""
    return PublicAuthConfigResponse(
        terms_version=settings.terms_version,
        privacy_version=settings.privacy_version,
        sms_mode=settings.sms_provider,
        email_mode=settings.email_provider,
    )


def get_current_access_claims(
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(_bearer_scheme),
    ],
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AccessTokenClaims:
    """验证 Bearer 令牌并确认对应会话仍有效。"""
    if credentials is None:
        raise ApiError(401, "access_token_required", "请先登录")
    claims = decode_access_token(credentials.credentials, settings)
    auth_session = session.get(AuthSession, claims.session_id)
    if auth_session is None or auth_session.user_id != claims.user_id:
        raise ApiError(401, "access_token_invalid", "访问令牌无效或已过期")
    if auth_session.revoked_at is not None or _session_expired(auth_session.expires_at):
        raise ApiError(401, "access_token_invalid", "访问令牌无效或已过期")
    return claims


@router.post(
    "/sms-challenges",
    response_model=SmsChallengeResponse,
    status_code=status.HTTP_201_CREATED,
    summary="发送短信验证码",
)
def request_sms_challenge(
    request: SmsChallengeRequest,
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
    sms_provider: Annotated[SmsProvider, Depends(get_sms_provider)],
    settings: Annotated[Settings, Depends(get_settings)],
    gate: Annotated[AuthRedisGate, Depends(get_auth_redis_gate)],
) -> SmsChallengeResponse:
    """创建一次性挑战；响应和日志均不包含验证码。"""
    gate.check()
    challenge_id = auth_service.request_sms_challenge(request.phone, sms_provider)
    return SmsChallengeResponse(
        challenge_id=challenge_id,
        expires_in_seconds=settings.sms_code_ttl_seconds,
    )


@router.post(
    "/email-challenges",
    response_model=EmailChallengeResponse,
    status_code=status.HTTP_201_CREATED,
    summary="发送邮箱验证码",
)
def request_email_challenge(
    request: EmailChallengeRequest,
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
    email_provider: Annotated[EmailProvider, Depends(get_email_provider)],
    settings: Annotated[Settings, Depends(get_settings)],
    gate: Annotated[AuthRedisGate, Depends(get_auth_redis_gate)],
) -> EmailChallengeResponse:
    """创建邮箱一次性挑战；响应和日志均不包含邮箱或验证码。"""
    gate.check()
    challenge_id = auth_service.request_email_challenge(
        request.email,
        email_provider,
    )
    return EmailChallengeResponse(
        challenge_id=challenge_id,
        expires_in_seconds=settings.email_code_ttl_seconds,
    )


@router.post(
    "/sessions",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
    summary="通过验证码创建会话",
)
def create_session(
    request: CreateSessionRequest,
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
    settings: Annotated[Settings, Depends(get_settings)],
    gate: Annotated[AuthRedisGate, Depends(get_auth_redis_gate)],
) -> TokenResponse:
    """完成首次同意记录、设备登记与令牌签发。"""
    gate.check()
    consents = (
        ConsentInput(
            terms_version=request.consents.terms_version,
            privacy_version=request.consents.privacy_version,
        )
        if request.consents is not None
        else None
    )
    device_input = DeviceInput(
        installation_id=request.device.installation_id,
        platform=request.device.platform,
        device_name=request.device.device_name,
    )
    if request.email is not None:
        tokens = auth_service.create_session_from_email(
            request.email,
            request.challenge_id,
            request.code,
            device_input,
            consents,
        )
    else:
        assert request.phone is not None
        tokens = auth_service.create_session_from_sms(
            request.phone,
            request.challenge_id,
            request.code,
            device_input,
            consents,
        )
    return _token_response(tokens, settings)


@router.post(
    "/tokens/refresh",
    response_model=TokenResponse,
    summary="轮换刷新令牌",
)
def refresh_token(
    request: RefreshTokenRequest,
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
    settings: Annotated[Settings, Depends(get_settings)],
    gate: Annotated[AuthRedisGate, Depends(get_auth_redis_gate)],
) -> TokenResponse:
    """轮换刷新令牌，不允许旧令牌重放。"""
    gate.check()
    return _token_response(
        auth_service.refresh_session(request.refresh_token), settings
    )


@router.get("/me", response_model=CurrentUserResponse, summary="读取当前账号")
def get_current_user(
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> CurrentUserResponse:
    """返回不含登录标识明文的当前账号信息。"""
    user = session.get(User, claims.user_id)
    if user is None:
        raise ApiError(401, "access_token_invalid", "访问令牌无效或已过期")
    active_consents = set(
        session.execute(
            select(UserConsent.consent_type, UserConsent.document_version).where(
                UserConsent.user_id == user.id,
                UserConsent.revoked_at.is_(None),
            ),
        ).all(),
    )
    return CurrentUserResponse(
        user_id=user.id,
        session_id=claims.session_id,
        account_type="email" if user.email_hash is not None else "phone",
        masked_email=user.masked_email,
        phone_last4=user.phone_last4,
        has_required_consents={
            ("terms", settings.terms_version),
            ("privacy", settings.privacy_version),
        }.issubset(active_consents),
    )


@router.delete(
    "/sessions/current",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="退出当前会话",
)
def logout_current_session(
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
) -> Response:
    """撤销当前会话，使访问和刷新令牌均不可继续使用。"""
    auth_service.revoke_session(claims.session_id, claims.user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def _token_response(tokens: IssuedTokens, settings: Settings) -> TokenResponse:
    """统一构造令牌响应，不持久化或记录令牌明文。"""
    return TokenResponse(
        access_token=tokens.access_token,
        refresh_token=tokens.refresh_token,
        expires_in_seconds=settings.session_access_ttl_minutes * 60,
        session_id=tokens.session_id,
    )


def _session_expired(expires_at) -> bool:
    """兼容 SQLite 测试环境返回的无时区时间。"""
    now = utc_now()
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=now.tzinfo)
    return expires_at <= now
