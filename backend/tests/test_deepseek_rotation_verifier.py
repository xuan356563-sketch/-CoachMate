import asyncio
from datetime import UTC, datetime

import httpx

from app.core.config import Settings
from app.services.deepseek_rotation_verifier import (
    build_rotation_receipt,
    verify_minimal_deepseek_client,
)


def test_missing_key_reports_only_safe_status() -> None:
    settings = Settings(deepseek_api_key=None)

    verified, code, detail = asyncio.run(
        verify_minimal_deepseek_client(settings),
    )

    assert verified is False
    assert code == "deepseek_not_configured"
    assert detail == "DeepSeek Key 未配置"


def test_live_client_receipt_never_contains_key() -> None:
    secret = "test-secret-that-must-not-appear"

    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["Authorization"] == f"Bearer {secret}"
        return httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "message": {
                            "content": (
                                '{"payload":{"cycle_label":"连通性验收",'
                                '"weekly_structure":"每周三次低风险训练。",'
                                '"workout_cards":[{"title":"轻松跑",'
                                '"duration_minutes":20,"intensity":"轻松",'
                                '"focus":["稳定完成"],'
                                '"safety_note":"不适时停止。"}],'
                                '"safety_notes":["不以疼痛换进度。"]},'
                                '"warnings":[]}'
                            )
                        }
                    }
                ]
            },
        )

    settings = Settings(deepseek_api_key=secret)
    verified, code, detail = asyncio.run(
        verify_minimal_deepseek_client(
            settings,
            transport=httpx.MockTransport(handler),
        ),
    )
    receipt = build_rotation_receipt(
        configured=True,
        minimal_client_verified=verified,
        business_api_verified=True,
        old_key_revoked_attested=True,
        result_code=code,
        detail=detail,
        now=datetime(2026, 7, 18, tzinfo=UTC),
    ).to_public_dict()

    assert receipt["complete"] is True
    assert secret not in str(receipt)
    assert "Authorization" not in str(receipt)
