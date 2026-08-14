from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import UTC, datetime

import httpx

from app.core.config import Settings
from app.core.errors import ApiError
from app.services.ai_generation import (
    AiGenerationContext,
    AiTextGenerationRequest,
    HttpDeepSeekClient,
)


@dataclass(frozen=True)
class DeepSeekRotationReceipt:
    """不包含密钥、请求正文或供应商原始响应的轮换验收回执。"""

    verified_at: str
    configured: bool
    minimal_client_verified: bool
    business_api_verified: bool
    old_key_revoked_attested: bool
    result_code: str
    detail: str

    @property
    def complete(self) -> bool:
        return (
            self.configured
            and self.minimal_client_verified
            and self.business_api_verified
            and self.old_key_revoked_attested
        )

    def to_public_dict(self) -> dict[str, object]:
        return {**asdict(self), "complete": self.complete}


def minimal_verification_request() -> AiTextGenerationRequest:
    """只包含合成训练条件，不读取姓名、健康数据或训练日志。"""

    return AiTextGenerationRequest(
        capability="trainer",
        prompt="生成一张用于连通性验收的低风险训练卡。",
        context=AiGenerationContext(
            goal="保持稳定训练",
            sports=["跑步"],
            available_minutes=20,
            scheduled_minutes=20,
            scheduled_period="晚上",
        ),
    )


async def verify_minimal_deepseek_client(
    settings: Settings,
    *,
    transport: httpx.AsyncBaseTransport | None = None,
) -> tuple[bool, str, str]:
    """运行真实客户端与本地 Schema 校验，只返回稳定状态。"""

    configured = settings.deepseek_api_key is not None and bool(
        settings.deepseek_api_key.get_secret_value().strip()
    )
    if not configured:
        return False, "deepseek_not_configured", "DeepSeek Key 未配置"
    try:
        artifact = await HttpDeepSeekClient(
            settings,
            transport=transport,
        ).generate(minimal_verification_request())
    except ApiError as error:
        return False, error.code, error.detail
    except Exception:
        return False, "deepseek_verification_failed", "DeepSeek 验收失败"
    if artifact.provider != "deepseek" or artifact.artifact_type != "trainer_plan_v1":
        return False, "deepseek_artifact_mismatch", "AI 产物类型不符合验收契约"
    return True, "deepseek_client_verified", "DeepSeek 客户端与产物 Schema 验证通过"


def build_rotation_receipt(
    *,
    configured: bool,
    minimal_client_verified: bool,
    business_api_verified: bool,
    old_key_revoked_attested: bool,
    result_code: str,
    detail: str,
    now: datetime | None = None,
) -> DeepSeekRotationReceipt:
    verified_at = (now or datetime.now(UTC)).astimezone(UTC).isoformat()
    return DeepSeekRotationReceipt(
        verified_at=verified_at,
        configured=configured,
        minimal_client_verified=minimal_client_verified,
        business_api_verified=business_api_verified,
        old_key_revoked_attested=old_key_revoked_attested,
        result_code=result_code,
        detail=detail,
    )
