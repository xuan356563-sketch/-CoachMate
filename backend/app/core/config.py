from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """仅从服务端环境变量读取的运行配置。"""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "TrainFlow API"
    app_version: str = "development"
    app_env: Literal["development", "test", "production"] = "development"
    database_url: str = (
        "postgresql+psycopg://trainflow:trainflow@postgres:5432/trainflow"
    )
    redis_url: str = "redis://redis:6379/0"
    cors_origins: str = (
        "http://localhost:3000,http://localhost:3980,http://localhost:8000,"
        "http://localhost:8083,http://127.0.0.1:8083"
    )
    deepseek_base_url: str = "https://api.deepseek.com"
    deepseek_model: str = "deepseek-v4-flash"
    deepseek_api_key: SecretStr | None = None
    ai_generation_timeout_seconds: float = Field(default=30, ge=5, le=60)
    ai_generation_limit: int = Field(default=20, ge=1, le=100)
    ai_generation_window_seconds: int = Field(default=600, ge=60, le=3600)
    training_plan_kill_switch: bool = False
    knowledge_catalog_enabled: bool = True
    profile_proposal_enabled: bool = True
    training_prescription_v2_enabled: bool = True
    training_structure_v1_enabled: bool = False
    plan_revision_enabled: bool = True
    sync_enabled: bool = False
    health_profile_cloud_enabled: bool = False
    health_profile_consent_version: str = (
        "health-profile-cloud-2026-07-31.1"
    )
    coach_cloud_projection_enabled: bool = False
    coach_cloud_projection_consent_version: str = (
        "coach-cloud-projection-2026-08-12.1"
    )
    coach_contract_version: int = 1
    coach_contract_hash: str = (
        "8970f0e215ddc5b54709eb5febeef2ca506b823e4095f54be9b9d31956e078e0"
    )
    coach_rule_set_version: str = "coach-rules-1.0.0"
    profile_encryption_key: SecretStr = SecretStr(
        "development-only-profile-encryption-key"
    )
    profile_encryption_key_version: str = "development-v1"
    ios_subscription_enabled: bool = False
    paid_plan_generation_gate_enabled: bool = False
    apple_subscription_product_id: str = (
        "com.zhilian.trainmate.membership.monthly"
    )
    apple_bundle_id: str = "com.zhilian.trainmate"
    apple_subscription_environment: Literal["sandbox", "production"] = (
        "sandbox"
    )
    apple_app_id: int | None = None
    apple_root_certificates: str = ""
    sync_batch_limit: int = Field(default=100, ge=1, le=100)
    account_deletion_grace_days: int = Field(default=7, ge=1, le=30)
    ops_enabled: bool = False
    jwt_signing_key: SecretStr = SecretStr(
        "development-only-replace-before-production",
    )
    phone_hash_key: SecretStr = SecretStr(
        "development-only-replace-before-production",
    )
    email_hash_key: SecretStr = SecretStr(
        "development-only-replace-before-production",
    )
    sms_code_signing_key: SecretStr = SecretStr(
        "development-only-replace-before-production",
    )
    email_code_signing_key: SecretStr = SecretStr(
        "development-only-replace-before-production",
    )
    refresh_token_signing_key: SecretStr = SecretStr(
        "development-only-replace-before-production",
    )
    sms_provider: Literal["disabled", "development", "tencent"] = "development"
    development_sms_code: str = Field(default="246810", pattern=r"^\d{6}$")
    email_provider: Literal["disabled", "development", "smtp"] = "development"
    development_email_code: str = Field(default="246810", pattern=r"^\d{6}$")
    terms_version: str = "internal-test-2026-07-13.1"
    privacy_version: str = "internal-test-2026-07-13.1"
    sms_code_ttl_seconds: int = Field(default=300, ge=60, le=600)
    sms_code_max_attempts: int = Field(default=5, ge=3, le=10)
    sms_challenge_limit_per_window: int = Field(default=3, ge=1, le=10)
    sms_challenge_window_seconds: int = Field(default=600, ge=60, le=3600)
    email_code_ttl_seconds: int = Field(default=300, ge=60, le=600)
    email_code_max_attempts: int = Field(default=5, ge=3, le=10)
    email_challenge_limit_per_window: int = Field(default=3, ge=1, le=10)
    email_challenge_window_seconds: int = Field(default=600, ge=60, le=3600)
    session_access_ttl_minutes: int = Field(default=15, ge=5, le=60)
    session_refresh_ttl_days: int = Field(default=30, ge=1, le=90)
    tencent_secret_id: SecretStr | None = None
    tencent_secret_key: SecretStr | None = None
    tencent_sms_sdk_app_id: str = ""
    tencent_sms_sign_name: str = ""
    tencent_sms_template_id: str = ""
    tencent_sms_region: str = "ap-guangzhou"
    smtp_host: str = ""
    smtp_port: int = Field(default=587, ge=1, le=65535)
    smtp_username: str = ""
    smtp_password: SecretStr | None = None
    smtp_from_email: str = ""
    smtp_security: Literal["starttls", "ssl"] = "starttls"
    smtp_timeout_seconds: float = Field(default=10, ge=1, le=60)
    minimax_base_url: str = "https://api.minimaxi.com"
    minimax_model: str = "MiniMax-M3"
    minimax_api_key: SecretStr | None = None
    minimax_timeout_seconds: float = Field(default=30, ge=5, le=60)
    race_image_max_bytes: int = Field(default=10 * 1024 * 1024, ge=1024)
    race_recognition_limit: int = Field(default=10, ge=1, le=100)
    race_recognition_window_seconds: int = Field(default=600, ge=60, le=3600)

    @field_validator("apple_app_id", mode="before")
    @classmethod
    def normalize_optional_apple_app_id(cls, value: object) -> object | None:
        """将空白的可选 Apple App ID 解释为未配置。"""
        if isinstance(value, str) and not value.strip():
            return None
        return value

    @property
    def cors_origin_list(self) -> list[str]:
        """将环境变量中的逗号分隔域名转换为 CORS 列表。"""
        return [
            origin.strip() for origin in self.cors_origins.split(",") if origin.strip()
        ]

    @model_validator(mode="after")
    def validate_production_secrets(self) -> "Settings":
        """拒绝生产环境使用示例密钥或不完整的验证码通道配置。"""
        if self.app_env != "production":
            return self

        secret_values = {
            "JWT_SIGNING_KEY": self.jwt_signing_key,
            "PHONE_HASH_KEY": self.phone_hash_key,
            "EMAIL_HASH_KEY": self.email_hash_key,
            "SMS_CODE_SIGNING_KEY": self.sms_code_signing_key,
            "EMAIL_CODE_SIGNING_KEY": self.email_code_signing_key,
            "REFRESH_TOKEN_SIGNING_KEY": self.refresh_token_signing_key,
        }
        insecure = [
            name
            for name, secret in secret_values.items()
            if secret.get_secret_value().startswith("development-only-")
        ]
        if insecure:
            raise ValueError(f"生产环境必须配置安全密钥：{', '.join(insecure)}")

        if self.sms_provider == "development":
            raise ValueError("生产环境禁止使用 development 短信模式")
        if self.email_provider == "development":
            raise ValueError("生产环境禁止使用 development 邮件模式")
        if self.terms_version.startswith("internal-test-") or (
            self.privacy_version.startswith("internal-test-")
        ):
            raise ValueError("生产环境禁止使用内部测试协议版本")
        if self.sms_provider == "tencent":
            missing = [
                name
                for name, value in {
                    "TENCENT_SECRET_ID": self.tencent_secret_id,
                    "TENCENT_SECRET_KEY": self.tencent_secret_key,
                    "TENCENT_SMS_SDK_APP_ID": self.tencent_sms_sdk_app_id,
                    "TENCENT_SMS_SIGN_NAME": self.tencent_sms_sign_name,
                    "TENCENT_SMS_TEMPLATE_ID": self.tencent_sms_template_id,
                }.items()
                if value is None or (isinstance(value, str) and not value.strip())
            ]
            if missing:
                raise ValueError(f"腾讯云短信配置不完整：{', '.join(missing)}")

        if self.email_provider != "smtp":
            raise ValueError("生产环境必须使用 SMTP 邮件服务")
        missing_smtp = [
            name
            for name, value in {
                "SMTP_HOST": self.smtp_host,
                "SMTP_USERNAME": self.smtp_username,
                "SMTP_PASSWORD": self.smtp_password,
                "SMTP_FROM_EMAIL": self.smtp_from_email,
            }.items()
            if value is None
            or (isinstance(value, SecretStr) and not value.get_secret_value().strip())
            or (isinstance(value, str) and not value.strip())
        ]
        if missing_smtp:
            raise ValueError(f"SMTP 邮件配置不完整：{', '.join(missing_smtp)}")

        if self.minimax_api_key is None:
            raise ValueError("生产环境必须配置 MINIMAX_API_KEY")
        if not self.minimax_model.strip():
            raise ValueError("生产环境必须配置 MINIMAX_MODEL")
        if self.deepseek_api_key is None:
            raise ValueError("生产环境必须配置 DEEPSEEK_API_KEY")
        if not self.deepseek_model.strip():
            raise ValueError("生产环境必须配置 DEEPSEEK_MODEL")

        if self.health_profile_cloud_enabled:
            if self.profile_encryption_key.get_secret_value().startswith(
                "development-only-"
            ):
                raise ValueError("生产环境必须配置安全档案加密密钥")
            if not self.profile_encryption_key_version.strip():
                raise ValueError("生产环境必须配置档案加密密钥版本")
            if not self.health_profile_consent_version.strip():
                raise ValueError("生产环境必须配置健康档案同意版本")

        if self.coach_cloud_projection_enabled:
            if self.profile_encryption_key.get_secret_value().startswith(
                "development-only-"
            ):
                raise ValueError("生产环境必须配置安全的 Coach 投影加密密钥")
            if not self.coach_cloud_projection_consent_version.strip():
                raise ValueError("生产环境必须配置 Coach 云投影同意版本")

        if self.ios_subscription_enabled:
            missing_apple = [
                name
                for name, value in {
                    "APPLE_APP_ID": self.apple_app_id,
                    "APPLE_ROOT_CERTIFICATES": self.apple_root_certificates,
                }.items()
                if value is None or (isinstance(value, str) and not value.strip())
            ]
            if missing_apple:
                raise ValueError(
                    f"苹果订阅校验配置不完整：{', '.join(missing_apple)}"
                )

        return self


@lru_cache
def get_settings() -> Settings:
    """缓存配置，避免在每个请求中重复读取环境变量。"""
    return Settings()
