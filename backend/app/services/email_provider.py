from __future__ import annotations

import math
import smtplib
import ssl
from email.message import EmailMessage
from typing import Protocol

from app.core.config import Settings
from app.core.errors import ApiError

_PRODUCT_DISPLAY_NAME = "练搭 CoachMate"


class EmailProvider(Protocol):
    """邮箱验证码下发能力的最小接口。"""

    def send_verification_code(
        self,
        email: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        """发送验证码；实现不得记录邮箱或验证码。"""


class DevelopmentEmailProvider:
    """仅开发环境使用固定验证码，不发送邮件且不记录验证码。"""

    def send_verification_code(
        self,
        email: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        del email, code, expires_in_seconds


class SmtpEmailProvider:
    """使用 Python 标准库 SMTP 发送登录验证码。"""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def send_verification_code(
        self,
        email: str,
        code: str,
        expires_in_seconds: int,
    ) -> None:
        """以纯文本邮件发送验证码，供应商异常统一转换为中文错误。"""
        host = self._required_value(self._settings.smtp_host, "SMTP_HOST")
        username = self._required_value(
            self._settings.smtp_username,
            "SMTP_USERNAME",
        )
        password = self._required_secret("SMTP_PASSWORD")
        from_email = self._required_value(
            self._settings.smtp_from_email,
            "SMTP_FROM_EMAIL",
        )

        message = EmailMessage()
        message["Subject"] = f"{_PRODUCT_DISPLAY_NAME} 登录验证码"
        message["From"] = from_email
        message["To"] = email
        valid_minutes = math.ceil(expires_in_seconds / 60)
        message.set_content(
            f"你正在登录{_PRODUCT_DISPLAY_NAME}。\n\n"
            f"验证码：{code}\n"
            f"验证码将在 {valid_minutes} 分钟后失效。\n\n"
            "若非本人操作，请忽略此邮件。"
        )

        try:
            context = ssl.create_default_context()
            if self._settings.smtp_security == "ssl":
                with smtplib.SMTP_SSL(
                    host,
                    self._settings.smtp_port,
                    timeout=self._settings.smtp_timeout_seconds,
                    context=context,
                ) as client:
                    client.login(username, password)
                    client.send_message(message)
                return

            with smtplib.SMTP(
                host,
                self._settings.smtp_port,
                timeout=self._settings.smtp_timeout_seconds,
            ) as client:
                client.ehlo()
                client.starttls(context=context)
                client.ehlo()
                client.login(username, password)
                client.send_message(message)
        except (OSError, smtplib.SMTPException) as error:
            raise ApiError(
                502,
                "email_delivery_failed",
                "验证码邮件发送失败，请稍后重试",
            ) from error

    def _required_secret(self, name: str) -> str:
        value = {"SMTP_PASSWORD": self._settings.smtp_password}[name]
        if value is None or not value.get_secret_value().strip():
            raise ApiError(503, "email_not_configured", "邮件服务配置不完整")
        return value.get_secret_value()

    @staticmethod
    def _required_value(value: str, name: str) -> str:
        if not value.strip():
            raise ApiError(
                503,
                "email_not_configured",
                f"邮件服务配置不完整：{name}",
            )
        return value
