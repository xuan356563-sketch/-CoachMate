from __future__ import annotations

import base64
import json
import os
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.core.config import Settings
from app.core.errors import ApiError


@dataclass(frozen=True)
class EncryptedProfile:
    """数据库只持久化密文、随机数和密钥版本。"""

    ciphertext: bytes
    nonce: bytes
    key_version: str


class ProfileCipher:
    """使用 AES-256-GCM 加密确认后的结构化档案。"""

    def __init__(self, settings: Settings) -> None:
        self._key = self._decode_key(settings)
        self._key_version = settings.profile_encryption_key_version

    def encrypt(
        self,
        *,
        user_id: UUID,
        schema_version: int,
        payload: dict[str, Any],
    ) -> EncryptedProfile:
        nonce = os.urandom(12)
        plaintext = json.dumps(
            payload,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
        ciphertext = AESGCM(self._key).encrypt(
            nonce,
            plaintext,
            self._associated_data(user_id, schema_version),
        )
        return EncryptedProfile(ciphertext, nonce, self._key_version)

    def decrypt(
        self,
        *,
        user_id: UUID,
        schema_version: int,
        ciphertext: bytes,
        nonce: bytes,
        key_version: str,
    ) -> dict[str, Any]:
        if key_version != self._key_version:
            raise ApiError(
                503,
                "profile_key_version_unavailable",
                "云端档案暂时无法解密，请稍后重试",
            )
        try:
            plaintext = AESGCM(self._key).decrypt(
                nonce,
                ciphertext,
                self._associated_data(user_id, schema_version),
            )
            value = json.loads(plaintext.decode("utf-8"))
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ApiError(
                500,
                "profile_ciphertext_invalid",
                "云端档案完整性校验失败",
            ) from error
        if not isinstance(value, dict):
            raise ApiError(
                500,
                "profile_ciphertext_invalid",
                "云端档案完整性校验失败",
            )
        return value

    @staticmethod
    def encode_envelope(encrypted: EncryptedProfile, schema_version: int) -> dict:
        return {
            "schema_version": schema_version,
            "ciphertext": base64.b64encode(encrypted.ciphertext).decode("ascii"),
            "nonce": base64.b64encode(encrypted.nonce).decode("ascii"),
            "key_version": encrypted.key_version,
        }

    def decrypt_envelope(self, *, user_id: UUID, envelope: dict) -> dict[str, Any]:
        try:
            return self.decrypt(
                user_id=user_id,
                schema_version=int(envelope["schema_version"]),
                ciphertext=base64.b64decode(envelope["ciphertext"], validate=True),
                nonce=base64.b64decode(envelope["nonce"], validate=True),
                key_version=str(envelope["key_version"]),
            )
        except (KeyError, TypeError, ValueError) as error:
            raise ApiError(
                500,
                "profile_ciphertext_invalid",
                "云端档案完整性校验失败",
            ) from error

    @staticmethod
    def scrub_health_fields(payload: dict[str, Any]) -> dict[str, Any]:
        scrubbed = dict(payload)
        scrubbed["height_cm"] = None
        scrubbed["weight_kg"] = None
        scrubbed["injuries"] = []
        scrubbed["health_fields_included"] = False
        return scrubbed

    @staticmethod
    def _associated_data(user_id: UUID, schema_version: int) -> bytes:
        return f"{user_id}:user_profile:{schema_version}".encode("ascii")

    @staticmethod
    def _decode_key(settings: Settings) -> bytes:
        raw = settings.profile_encryption_key.get_secret_value()
        if raw.startswith("development-only-"):
            if settings.app_env == "production":
                raise ValueError("生产环境禁止使用示例档案加密密钥")
            return bytes(range(32))
        try:
            key = base64.b64decode(raw, validate=True)
        except ValueError as error:
            raise ValueError("档案加密密钥必须是 Base64 编码") from error
        if len(key) != 32:
            raise ValueError("档案加密密钥必须解码为 32 字节")
        return key
