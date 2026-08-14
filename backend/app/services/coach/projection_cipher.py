from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Any, Literal
from uuid import UUID

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.core.config import Settings
from app.core.errors import ApiError
from app.services.profile_cipher import ProfileCipher

ProjectionKind = Literal["state", "memories"]


@dataclass(frozen=True)
class EncryptedCoachProjection:
    ciphertext: bytes
    nonce: bytes
    key_version: str


class CoachProjectionCipher:
    """复用已配置密钥，但用独立关联数据隔离 Coach 投影。"""

    def __init__(self, settings: Settings) -> None:
        self._key = ProfileCipher._decode_key(settings)
        self._key_version = settings.profile_encryption_key_version

    def encrypt(
        self,
        *,
        user_id: UUID,
        kind: ProjectionKind,
        version: int,
        payload: dict[str, Any],
    ) -> EncryptedCoachProjection:
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
            self._associated_data(user_id, kind, version),
        )
        return EncryptedCoachProjection(ciphertext, nonce, self._key_version)

    def decrypt(
        self,
        *,
        user_id: UUID,
        kind: ProjectionKind,
        version: int,
        ciphertext: bytes,
        nonce: bytes,
        key_version: str,
    ) -> dict[str, Any]:
        if key_version != self._key_version:
            raise ApiError(
                503,
                "coach_key_version_unavailable",
                "Coach 云投影暂时无法解密，请稍后重试",
            )
        try:
            plaintext = AESGCM(self._key).decrypt(
                nonce,
                ciphertext,
                self._associated_data(user_id, kind, version),
            )
            value = json.loads(plaintext.decode("utf-8"))
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ApiError(
                500,
                "coach_ciphertext_invalid",
                "Coach 云投影完整性校验失败",
            ) from error
        if not isinstance(value, dict):
            raise ApiError(
                500,
                "coach_ciphertext_invalid",
                "Coach 云投影完整性校验失败",
            )
        return value

    @staticmethod
    def _associated_data(
        user_id: UUID,
        kind: ProjectionKind,
        version: int,
    ) -> bytes:
        return f"{user_id}:coach_{kind}:{version}".encode("ascii")
