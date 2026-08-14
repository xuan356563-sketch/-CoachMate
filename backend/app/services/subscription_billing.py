from __future__ import annotations

import hashlib
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Literal, Protocol
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import ApiError
from app.core.security import utc_now
from app.models import AppleSubscriptionEvent, SubscriptionEntitlement, User

EntitlementStatus = Literal[
    "none",
    "trial",
    "active",
    "grace_period",
    "billing_retry",
    "expired",
    "revoked",
]


@dataclass(frozen=True)
class VerifiedAppleTransaction:
    """完成苹果签名和证书链校验后的最小交易投影。"""

    transaction_id: str
    original_transaction_id: str
    product_id: str
    app_account_token: UUID
    environment: Literal["sandbox", "production"]
    purchased_at: datetime
    expires_at: datetime | None
    revoked_at: datetime | None
    is_trial: bool
    bundle_id: str = "com.zhilian.trainmate"


@dataclass(frozen=True)
class VerifiedAppleNotification:
    """完成苹果签名验证后的通知摘要。"""

    notification_uuid: str
    notification_type: str
    subtype: str | None
    transaction: VerifiedAppleTransaction | None


class AppleTransactionVerifier(Protocol):
    def verify_transaction(
        self,
        verification_data: str,
    ) -> VerifiedAppleTransaction: ...

    def verify_notification(
        self,
        signed_payload: str,
    ) -> VerifiedAppleNotification: ...


class OfficialAppleTransactionVerifier:
    """使用苹果官方服务端库验证 JWS、证书链、环境和应用标识。"""

    def __init__(self, settings: Settings) -> None:
        try:
            from appstoreserverlibrary.models.Environment import Environment
            from appstoreserverlibrary.signed_data_verifier import (
                SignedDataVerifier,
            )
        except ImportError as error:
            raise RuntimeError("缺少苹果服务端校验依赖") from error

        certificates = []
        for item in settings.apple_root_certificates.split(","):
            path = item.strip()
            if path:
                certificates.append(Path(path).read_bytes())
        if not certificates:
            raise RuntimeError("未配置苹果根证书")
        environment = (
            Environment.SANDBOX
            if settings.apple_subscription_environment == "sandbox"
            else Environment.PRODUCTION
        )
        self._verifier = SignedDataVerifier(
            certificates,
            True,
            environment,
            settings.apple_bundle_id,
            settings.apple_app_id,
        )

    def verify_transaction(self, verification_data: str) -> VerifiedAppleTransaction:
        try:
            value = self._verifier.verify_and_decode_signed_transaction(
                verification_data
            )
            return self._transaction(value)
        except Exception as error:
            raise ApiError(
                422,
                "apple_transaction_invalid",
                "苹果交易签名验证失败",
            ) from error

    def verify_notification(self, signed_payload: str) -> VerifiedAppleNotification:
        try:
            value = self._verifier.verify_and_decode_notification(signed_payload)
            data = getattr(value, "data", None)
            signed_transaction = getattr(data, "signedTransactionInfo", None)
            transaction = (
                self.verify_transaction(signed_transaction)
                if signed_transaction
                else None
            )
            notification_type = getattr(
                value.notificationType,
                "value",
                value.notificationType,
            )
            subtype = getattr(value.subtype, "value", value.subtype)
            return VerifiedAppleNotification(
                notification_uuid=str(value.notificationUUID),
                notification_type=str(notification_type),
                subtype=(str(subtype) if subtype is not None else None),
                transaction=transaction,
            )
        except ApiError:
            raise
        except Exception as error:
            raise ApiError(
                422,
                "apple_notification_invalid",
                "苹果订阅通知签名验证失败",
            ) from error

    @staticmethod
    def _transaction(value) -> VerifiedAppleTransaction:
        def timestamp(name: str) -> datetime | None:
            raw = getattr(value, name, None)
            if raw is None:
                return None
            return datetime.fromtimestamp(int(raw) / 1000, tz=UTC)

        environment_value = getattr(value.environment, "value", value.environment)
        environment = str(environment_value).lower()
        if "sandbox" in environment:
            environment = "sandbox"
        else:
            environment = "production"
        offer_type = getattr(value, "offerType", None)
        offer_type = getattr(offer_type, "value", offer_type)
        return VerifiedAppleTransaction(
            transaction_id=str(value.transactionId),
            original_transaction_id=str(value.originalTransactionId),
            product_id=str(value.productId),
            app_account_token=UUID(str(value.appAccountToken)),
            environment=environment,
            purchased_at=timestamp("purchaseDate") or utc_now(),
            expires_at=timestamp("expiresDate"),
            revoked_at=timestamp("revocationDate"),
            is_trial=(str(offer_type) == "1"),
            bundle_id=str(value.bundleId),
        )


class SubscriptionBillingService:
    """以服务端验签结果为唯一来源维护订阅权益。"""

    def __init__(self, session: Session, settings: Settings) -> None:
        self._session = session
        self._settings = settings

    def entitlement(self, user_id: UUID) -> dict[str, object]:
        row = self._session.scalar(
            select(SubscriptionEntitlement).where(
                SubscriptionEntitlement.user_id == user_id,
                SubscriptionEntitlement.platform == "ios",
            ),
        )
        if row is None:
            return self._response(None, "none")
        status = self._effective_status(row)
        if status != row.status:
            row.status = status
            self._session.commit()
        return self._response(row, status)

    def verify_transaction(
        self,
        *,
        user_id: UUID,
        submitted_app_account_token: UUID,
        verification_data: str,
        verifier: AppleTransactionVerifier,
    ) -> dict[str, object]:
        if submitted_app_account_token != user_id:
            raise ApiError(
                422,
                "apple_transaction_account_mismatch",
                "交易账号令牌与当前账号不一致",
            )
        verified = verifier.verify_transaction(verification_data)
        self._validate_transaction(user_id, verified)
        row = self._upsert(user_id, verified)
        self._session.commit()
        self._session.refresh(row)
        return self._response(row, self._effective_status(row))

    def process_notification(
        self,
        *,
        signed_payload: str,
        verifier: AppleTransactionVerifier,
    ) -> None:
        verified = verifier.verify_notification(signed_payload)
        existing = self._session.scalar(
            select(AppleSubscriptionEvent.id).where(
                AppleSubscriptionEvent.notification_uuid
                == verified.notification_uuid,
            ),
        )
        if existing is not None:
            return
        user_id: UUID | None = None
        if verified.transaction is not None:
            transaction = verified.transaction
            self._validate_common(transaction)
            user = self._session.get(User, transaction.app_account_token)
            if user is not None:
                user_id = user.id
                row = self._upsert(user.id, transaction)
                row.status = self._notification_status(
                    verified.notification_type,
                    verified.subtype,
                    self._effective_status(row),
                )
        self._session.add(
            AppleSubscriptionEvent(
                notification_uuid=verified.notification_uuid,
                user_id=user_id,
                notification_type=verified.notification_type,
                subtype=verified.subtype,
                payload_hash=hashlib.sha256(
                    signed_payload.encode("utf-8")
                ).hexdigest(),
            ),
        )
        try:
            self._session.commit()
        except IntegrityError:
            self._session.rollback()
            duplicate = self._session.scalar(
                select(AppleSubscriptionEvent.id).where(
                    AppleSubscriptionEvent.notification_uuid
                    == verified.notification_uuid,
                ),
            )
            if duplicate is None:
                raise

    def ensure_can_generate(self, user_id: UUID) -> None:
        if not self._settings.paid_plan_generation_gate_enabled:
            return
        entitlement = self.entitlement(user_id)
        if not entitlement["can_generate_plan"]:
            raise ApiError(
                402,
                "membership_required",
                "生成或重排新计划需要有效会员",
            )

    def _validate_transaction(
        self,
        user_id: UUID,
        transaction: VerifiedAppleTransaction,
    ) -> None:
        self._validate_common(transaction)
        if transaction.app_account_token != user_id:
            raise ApiError(
                422,
                "apple_transaction_account_mismatch",
                "已验证交易不属于当前账号",
            )

    def _validate_common(self, transaction: VerifiedAppleTransaction) -> None:
        if transaction.bundle_id != self._settings.apple_bundle_id:
            raise ApiError(422, "apple_bundle_mismatch", "苹果交易应用标识不匹配")
        if transaction.product_id != self._settings.apple_subscription_product_id:
            raise ApiError(422, "apple_product_mismatch", "苹果交易产品标识不匹配")
        if transaction.environment != self._settings.apple_subscription_environment:
            raise ApiError(422, "apple_environment_mismatch", "苹果交易环境不匹配")

    def _upsert(
        self,
        user_id: UUID,
        transaction: VerifiedAppleTransaction,
    ) -> SubscriptionEntitlement:
        original = self._session.scalar(
            select(SubscriptionEntitlement).where(
                SubscriptionEntitlement.original_transaction_id
                == transaction.original_transaction_id,
            ),
        )
        if original is not None and original.user_id != user_id:
            raise ApiError(
                409,
                "apple_transaction_already_bound",
                "该苹果订阅已绑定其他账号",
            )
        row = original or self._session.scalar(
            select(SubscriptionEntitlement).where(
                SubscriptionEntitlement.user_id == user_id,
                SubscriptionEntitlement.platform == "ios",
            ),
        )
        status = self._status_from_transaction(transaction)
        if row is None:
            row = SubscriptionEntitlement(user_id=user_id, platform="ios")
            self._session.add(row)
        row.product_id = transaction.product_id
        row.transaction_id = transaction.transaction_id
        row.original_transaction_id = transaction.original_transaction_id
        row.environment = transaction.environment
        row.status = status
        row.purchased_at = transaction.purchased_at
        row.expires_at = transaction.expires_at
        row.revoked_at = transaction.revoked_at
        row.last_verified_at = utc_now()
        self._session.flush()
        return row

    @staticmethod
    def _status_from_transaction(
        transaction: VerifiedAppleTransaction,
    ) -> EntitlementStatus:
        if transaction.revoked_at is not None:
            return "revoked"
        if transaction.expires_at is not None and transaction.expires_at <= utc_now():
            return "expired"
        return "trial" if transaction.is_trial else "active"

    @staticmethod
    def _effective_status(row: SubscriptionEntitlement) -> EntitlementStatus:
        if row.status in {"revoked", "expired"}:
            return row.status
        expires_at = row.expires_at
        if expires_at is not None:
            if expires_at.tzinfo is None:
                expires_at = expires_at.replace(tzinfo=UTC)
            if expires_at <= utc_now():
                return "expired"
        return row.status

    @staticmethod
    def _notification_status(
        notification_type: str,
        subtype: str | None,
        fallback: EntitlementStatus,
    ) -> EntitlementStatus:
        kind = notification_type.upper()
        detail = (subtype or "").upper()
        if kind in {"REFUND", "REVOKE"}:
            return "revoked"
        if kind == "EXPIRED":
            return "expired"
        if kind == "DID_FAIL_TO_RENEW":
            return "grace_period" if "GRACE" in detail else "billing_retry"
        if kind in {"DID_RENEW", "SUBSCRIBED"}:
            return "active"
        return fallback

    @staticmethod
    def _response(
        row: SubscriptionEntitlement | None,
        status: EntitlementStatus,
    ) -> dict[str, object]:
        return {
            "status": status,
            "can_generate_plan": status
            in {"trial", "active", "grace_period"},
            "product_id": row.product_id if row is not None else None,
            "trial_ends_at": (
                row.expires_at if row is not None and status == "trial" else None
            ),
            "expires_at": row.expires_at if row is not None else None,
        }
