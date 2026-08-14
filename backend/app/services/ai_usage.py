from __future__ import annotations

import re

from sqlalchemy.orm import Session

from app.models import AiUsageEvent

_SAFE_REQUEST_ID = re.compile(r"^[A-Za-z0-9._-]{1,80}$")


class AiUsageRecorder:
    """只持久化供应商用量维度，不接收请求正文或用户标识。"""

    def __init__(self, session: Session) -> None:
        self._session = session

    def record(
        self,
        *,
        provider: str,
        model: str,
        input_tokens: int | None,
        output_tokens: int | None,
        latency_ms: int,
        result_code: str,
        request_id: str | None,
        capability: str | None = None,
        prompt_contract_version: str | None = None,
        prompt_cache_hit_tokens: int | None = None,
        prompt_cache_miss_tokens: int | None = None,
    ) -> AiUsageEvent:
        safe_request_id = (
            request_id
            if request_id is not None and _SAFE_REQUEST_ID.fullmatch(request_id)
            else None
        )
        event = AiUsageEvent(
            provider=provider[:32],
            model=model[:80],
            capability=capability[:32] if capability else None,
            prompt_contract_version=(
                prompt_contract_version[:64]
                if prompt_contract_version
                else None
            ),
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            prompt_cache_hit_tokens=prompt_cache_hit_tokens,
            prompt_cache_miss_tokens=prompt_cache_miss_tokens,
            latency_ms=max(0, latency_ms),
            result_code=result_code[:64],
            request_id=safe_request_id,
        )
        self._session.add(event)
        self._session.commit()
        self._session.refresh(event)
        return event
