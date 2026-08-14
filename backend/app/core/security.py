from __future__ import annotations

import hashlib
import hmac
import re
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import jwt
from email_validator import EmailNotValidError, validate_email
from pydantic import SecretStr

from app.core.config import Settings
from app.core.errors import ApiError

_CHINA_MAINLAND_PHONE_PATTERN = re.compile(r"^1[3-9]\d{9}$")


@dataclass(frozen=True)
class AccessTokenClaims:
    """已校验访问令牌中的主体与会话信息。"""

    user_id: UUID
    session_id: UUID


def utc_now() -> datetime:
    """生成带 UTC 时区的当前时间。"""
    return datetime.now(UTC)


def normalize_china_mainland_phone(value: str) -> str:
    """仅接受中国大陆手机号，统一移除 +86 前缀和空白。"""
    normalized = value.strip().replace(" ", "").replace("-", "")
    if normalized.startswith("+86"):
        normalized = normalized[3:]
    elif normalized.startswith("0086"):
        normalized = normalized[4:]

    if not _CHINA_MAINLAND_PHONE_PATTERN.fullmatch(normalized):
        raise ApiError(422, "phone_invalid", "请输入有效的中国大陆手机号")
    return normalized


def keyed_hash(value: str, secret: SecretStr) -> str:
    """使用服务端密钥生成不可逆 HMAC 摘要。"""
    return hmac.new(
        secret.get_secret_value().encode("utf-8"),
        value.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def phone_hash(phone: str, settings: Settings) -> str:
    """生成手机号检索摘要，数据库不保存明文手机号。"""
    return keyed_hash(phone, settings.phone_hash_key)


def normalize_email(value: str) -> str:
    """校验并规范化邮箱；不执行 DNS 查询，避免暴露登录意图。"""
    try:
        result = validate_email(
            value.strip(),
            check_deliverability=False,
            allow_smtputf8=False,
        )
    except EmailNotValidError as error:
        raise ApiError(422, "email_invalid", "请输入有效的邮箱地址") from error
    normalized = result.ascii_email or result.normalized
    return normalized.casefold()


def email_hash(email: str, settings: Settings) -> str:
    """生成邮箱检索摘要，数据库不保存邮箱明文。"""
    return keyed_hash(email, settings.email_hash_key)


def mask_email(email: str) -> str:
    """生成只用于账号提示的邮箱脱敏文本。"""
    local_part, domain = email.rsplit("@", maxsplit=1)
    return f"{local_part[0]}***@{domain}"


def generate_sms_code() -> str:
    """生成六位数字验证码。"""
    return "".join(secrets.choice("0123456789") for _ in range(6))


def sms_code_hash(
    challenge_id: UUID,
    target_phone_hash: str,
    code: str,
    settings: Settings,
) -> str:
    """绑定挑战、手机号摘要和验证码，防止跨挑战复用。"""
    return keyed_hash(
        f"{challenge_id}:{target_phone_hash}:{code}",
        settings.sms_code_signing_key,
    )


def email_code_hash(
    challenge_id: UUID,
    target_email_hash: str,
    code: str,
    settings: Settings,
) -> str:
    """绑定挑战、邮箱摘要和验证码，防止跨挑战复用。"""
    return keyed_hash(
        f"{challenge_id}:{target_email_hash}:{code}",
        settings.email_code_signing_key,
    )


def generate_refresh_token() -> str:
    """生成仅向客户端返回一次的高熵刷新令牌。"""
    return secrets.token_urlsafe(48)


def refresh_token_hash(token: str, settings: Settings) -> str:
    """保存刷新令牌摘要，不保存明文令牌。"""
    return keyed_hash(token, settings.refresh_token_signing_key)


def create_access_token(
    user_id: UUID,
    session_id: UUID,
    settings: Settings,
) -> str:
    """签发短时访问令牌。"""
    now = utc_now()
    payload: dict[str, Any] = {
        "sub": str(user_id),
        "sid": str(session_id),
        "typ": "access",
        "aud": "trainflow-api",
        "iat": now,
        "exp": now + timedelta(minutes=settings.session_access_ttl_minutes),
    }
    return jwt.encode(
        payload,
        settings.jwt_signing_key.get_secret_value(),
        algorithm="HS256",
    )


def decode_access_token(token: str, settings: Settings) -> AccessTokenClaims:
    """验证访问令牌签名、用途、受众和过期时间。"""
    try:
        payload = jwt.decode(
            token,
            settings.jwt_signing_key.get_secret_value(),
            algorithms=["HS256"],
            audience="trainflow-api",
        )
        if payload.get("typ") != "access":
            raise ApiError(401, "access_token_invalid", "访问令牌无效")
        return AccessTokenClaims(
            user_id=UUID(str(payload["sub"])),
            session_id=UUID(str(payload["sid"])),
        )
    except ApiError:
        raise
    except (jwt.PyJWTError, KeyError, ValueError) as error:
        raise ApiError(401, "access_token_invalid", "访问令牌无效或已过期") from error
