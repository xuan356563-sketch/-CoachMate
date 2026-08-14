from __future__ import annotations

import math
from typing import Protocol

from app.core.config import Settings
from app.core.errors import ApiError


class SmsProvider(Protocol):
    """验证码下发能力的最小接口。"""

    def send_verification_code(
        self,
        phone: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        """向指定手机号发送验证码，禁止记录或返回验证码。"""


class DisabledSmsProvider:
    """未配置短信服务时的显式拒绝实现。"""

    def send_verification_code(
        self,
        phone: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        del phone, code, expires_in_seconds
        raise ApiError(503, "sms_not_configured", "短信服务尚未配置")


class DevelopmentSmsProvider:
    """仅开发环境使用固定验证码，不发送短信且不记录验证码。"""

    def send_verification_code(
        self,
        phone: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        del phone, code, expires_in_seconds


class TencentCloudSmsProvider:
    """基于腾讯云 SMS SDK 3.0 的中国大陆验证码发送适配器。"""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def send_verification_code(
        self,
        phone: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        """调用腾讯云模板短信；任何供应商异常都不向客户端暴露。"""
        secret_id = self._required_secret("TENCENT_SECRET_ID")
        secret_key = self._required_secret("TENCENT_SECRET_KEY")
        sdk_app_id = self._required_value(
            self._settings.tencent_sms_sdk_app_id,
            "TENCENT_SMS_SDK_APP_ID",
        )
        sign_name = self._required_value(
            self._settings.tencent_sms_sign_name,
            "TENCENT_SMS_SIGN_NAME",
        )
        template_id = self._required_value(
            self._settings.tencent_sms_template_id,
            "TENCENT_SMS_TEMPLATE_ID",
        )

        try:
            from tencentcloud.common import credential
            from tencentcloud.common.exception.tencent_cloud_sdk_exception import (
                TencentCloudSDKException,
            )
            from tencentcloud.common.profile.client_profile import ClientProfile
            from tencentcloud.common.profile.http_profile import HttpProfile
            from tencentcloud.sms.v20210111 import models, sms_client

            http_profile = HttpProfile()
            http_profile.endpoint = "sms.tencentcloudapi.com"
            client_profile = ClientProfile()
            client_profile.httpProfile = http_profile
            client = sms_client.SmsClient(
                credential.Credential(secret_id, secret_key),
                self._settings.tencent_sms_region,
                client_profile,
            )
            request = models.SendSmsRequest()
            request.SmsSdkAppId = sdk_app_id
            request.SignName = sign_name
            request.TemplateId = template_id
            request.PhoneNumberSet = [f"+86{phone}"]
            request.TemplateParamSet = [
                code,
                str(math.ceil(expires_in_seconds / 60)),
            ]
            response = client.SendSms(request)
            status_list = response.SendStatusSet or []
            if not status_list or status_list[0].Code != "Ok":
                raise ApiError(502, "sms_delivery_failed", "验证码发送失败，请稍后重试")
        except ApiError:
            raise
        except TencentCloudSDKException as error:
            raise ApiError(
                502,
                "sms_delivery_failed",
                "验证码发送失败，请稍后重试",
            ) from error

    def _required_secret(self, name: str) -> str:
        value = {
            "TENCENT_SECRET_ID": self._settings.tencent_secret_id,
            "TENCENT_SECRET_KEY": self._settings.tencent_secret_key,
        }[name]
        if value is None or not value.get_secret_value():
            raise ApiError(503, "sms_not_configured", "短信服务配置不完整")
        return value.get_secret_value()

    @staticmethod
    def _required_value(value: str, name: str) -> str:
        if not value.strip():
            raise ApiError(503, "sms_not_configured", f"短信服务配置不完整：{name}")
        return value
