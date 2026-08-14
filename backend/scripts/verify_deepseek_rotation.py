from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path
from typing import Any

import httpx

from app.core.config import Settings
from app.services.deepseek_rotation_verifier import (
    build_rotation_receipt,
    minimal_verification_request,
    verify_minimal_deepseek_client,
)


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="脱敏验证 DeepSeek Key 轮换、最小客户端和真实业务接口。",
    )
    parser.add_argument(
        "--api-base-url",
        default="http://127.0.0.1:8000",
        help="正在运行的 TrainMate API 地址。",
    )
    parser.add_argument(
        "--receipt",
        type=Path,
        help="可选：把不含密钥的 JSON 回执写到指定路径。",
    )
    return parser.parse_args()


async def _verify_business_api(base_url: str) -> tuple[bool, str, str]:
    access_token = os.getenv("TRAINMATE_ACCESS_TOKEN", "").strip()
    if not access_token:
        return False, "business_access_token_missing", "未提供业务验收访问令牌"
    request = minimal_verification_request().model_dump(mode="json")
    try:
        async with httpx.AsyncClient(timeout=45) as client:
            response = await client.post(
                f"{base_url.rstrip('/')}/v1/ai/generations",
                headers={"Authorization": f"Bearer {access_token}"},
                json=request,
            )
    except (httpx.HTTPError, TimeoutError):
        return False, "business_api_unreachable", "真实 AI 业务接口不可达"
    if response.status_code != 201:
        try:
            payload: Any = response.json()
        except ValueError:
            payload = None
        code = payload.get("code") if isinstance(payload, dict) else None
        return False, str(code or "business_api_rejected"), "真实 AI 业务接口验收未通过"
    try:
        payload = response.json()
    except ValueError:
        return False, "business_api_invalid_json", "真实 AI 业务接口返回格式无效"
    if not isinstance(payload, dict) or payload.get("provider") != "deepseek":
        return False, "business_api_provider_mismatch", "真实 AI 业务接口供应商不符"
    return True, "business_api_verified", "真实 AI 生成链路验证通过"


async def _run() -> int:
    args = _arguments()
    settings = Settings()
    configured = settings.deepseek_api_key is not None and bool(
        settings.deepseek_api_key.get_secret_value().strip()
    )
    minimal_ok, minimal_code, minimal_detail = await verify_minimal_deepseek_client(
        settings,
    )
    business_ok, business_code, business_detail = await _verify_business_api(
        args.api_base_url,
    )
    revoked = os.getenv("DEEPSEEK_OLD_KEY_REVOKED", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }
    result_code = business_code if minimal_ok else minimal_code
    detail = business_detail if minimal_ok else minimal_detail
    receipt = build_rotation_receipt(
        configured=configured,
        minimal_client_verified=minimal_ok,
        business_api_verified=business_ok,
        old_key_revoked_attested=revoked,
        result_code=result_code,
        detail=detail,
    )
    public_document = receipt.to_public_dict()
    output = json.dumps(public_document, ensure_ascii=False, indent=2)
    print(output)
    if args.receipt is not None:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(f"{output}\n", encoding="utf-8")
    return 0 if receipt.complete else 2


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_run()))
