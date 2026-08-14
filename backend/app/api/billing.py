from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from app.api.auth import get_current_access_claims
from app.core.config import Settings, get_settings
from app.core.errors import ApiError
from app.core.security import AccessTokenClaims
from app.db.session import get_session
from app.services.subscription_billing import (
    AppleTransactionVerifier,
    OfficialAppleTransactionVerifier,
    SubscriptionBillingService,
)

router = APIRouter(prefix="/v1/billing", tags=["订阅与权益"])


class EntitlementResponse(BaseModel):
    status: Literal[
        "none",
        "trial",
        "active",
        "grace_period",
        "billing_retry",
        "expired",
        "revoked",
    ]
    can_generate_plan: bool
    product_id: str | None = None
    trial_ends_at: datetime | None = None
    expires_at: datetime | None = None


class AppleTransactionVerificationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    verification_data: str = Field(min_length=1, max_length=20000)
    app_account_token: UUID


class AppleNotificationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    signedPayload: str = Field(min_length=1, max_length=100000)


def get_subscription_billing_service(
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> SubscriptionBillingService:
    return SubscriptionBillingService(session, settings)


def get_apple_transaction_verifier(
    settings: Annotated[Settings, Depends(get_settings)],
) -> AppleTransactionVerifier:
    return OfficialAppleTransactionVerifier(settings)


def _ensure_subscription_enabled(settings: Settings) -> None:
    if not settings.ios_subscription_enabled:
        raise ApiError(503, "ios_subscription_disabled", "iOS 订阅当前未启用")


@router.get(
    "/entitlement",
    response_model=EntitlementResponse,
    summary="获取当前账号的服务端会员权益",
)
def get_entitlement(
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        SubscriptionBillingService,
        Depends(get_subscription_billing_service),
    ],
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, object]:
    _ensure_subscription_enabled(settings)
    return service.entitlement(claims.user_id)


@router.post(
    "/apple/transactions/verify",
    response_model=EntitlementResponse,
    summary="验证苹果交易并刷新会员权益",
)
def verify_apple_transaction(
    request: AppleTransactionVerificationRequest,
    claims: Annotated[AccessTokenClaims, Depends(get_current_access_claims)],
    service: Annotated[
        SubscriptionBillingService,
        Depends(get_subscription_billing_service),
    ],
    verifier: Annotated[
        AppleTransactionVerifier,
        Depends(get_apple_transaction_verifier),
    ],
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, object]:
    _ensure_subscription_enabled(settings)
    return service.verify_transaction(
        user_id=claims.user_id,
        submitted_app_account_token=request.app_account_token,
        verification_data=request.verification_data,
        verifier=verifier,
    )


@router.post(
    "/apple/notifications",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="接收苹果服务器订阅通知 V2",
)
def receive_apple_notification(
    request: AppleNotificationRequest,
    service: Annotated[
        SubscriptionBillingService,
        Depends(get_subscription_billing_service),
    ],
    verifier: Annotated[
        AppleTransactionVerifier,
        Depends(get_apple_transaction_verifier),
    ],
    settings: Annotated[Settings, Depends(get_settings)],
) -> Response:
    _ensure_subscription_enabled(settings)
    service.process_notification(
        signed_payload=request.signedPayload,
        verifier=verifier,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
