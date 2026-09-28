import smtplib
from email.message import EmailMessage

import pytest

from app.core.config import Settings
from app.core.errors import ApiError
from app.services.email_provider import SmtpEmailProvider


class FakeSmtpClient:
    """只记录 SMTP 调用，不连接网络。"""

    def __init__(self, *args, **kwargs) -> None:
        self.args = args
        self.kwargs = kwargs
        self.started_tls = False
        self.login_credentials: tuple[str, str] | None = None
        self.sent_message: EmailMessage | None = None

    def __enter__(self) -> "FakeSmtpClient":
        return self

    def __exit__(self, *_args) -> None:
        return None

    def ehlo(self) -> None:
        return None

    def starttls(self, *, context) -> None:
        del context
        self.started_tls = True

    def login(self, username: str, password: str) -> None:
        self.login_credentials = (username, password)

    def send_message(self, message: EmailMessage) -> None:
        self.sent_message = message


def _smtp_settings(**overrides) -> Settings:
    values = {
        "email_provider": "smtp",
        "smtp_host": "smtp.example.com",
        "smtp_port": 587,
        "smtp_username": "smtp-user",
        "smtp_password": "smtp-password",
        "smtp_from_email": "noreply@example.com",
        "smtp_security": "starttls",
    }
    values.update(overrides)
    return Settings(**values)


def test_smtp_provider_uses_starttls_and_sends_plain_text_code(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    clients: list[FakeSmtpClient] = []

    def create_client(*args, **kwargs) -> FakeSmtpClient:
        client = FakeSmtpClient(*args, **kwargs)
        clients.append(client)
        return client

    monkeypatch.setattr(smtplib, "SMTP", create_client)
    provider = SmtpEmailProvider(_smtp_settings())

    provider.send_verification_code("runner@example.com", "246810", 300)

    assert len(clients) == 1
    client = clients[0]
    assert client.started_tls is True
    assert client.login_credentials == ("smtp-user", "smtp-password")
    assert client.sent_message is not None
    assert client.sent_message["To"] == "runner@example.com"
    assert client.sent_message["Subject"] == "练搭 CoachMate 登录验证码"
    content = client.sent_message.get_content()
    assert "你正在登录练搭 CoachMate。" in content
    assert "智练 TrainMate" not in content
    assert "246810" in content


def test_smtp_provider_hides_supplier_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fail_to_connect(*_args, **_kwargs):
        raise OSError("测试连接失败")

    monkeypatch.setattr(smtplib, "SMTP", fail_to_connect)
    provider = SmtpEmailProvider(_smtp_settings())

    with pytest.raises(ApiError) as captured:
        provider.send_verification_code("runner@example.com", "246810", 300)

    assert captured.value.code == "email_delivery_failed"
    assert "smtp.example.com" not in captured.value.detail
    assert "runner@example.com" not in captured.value.detail
