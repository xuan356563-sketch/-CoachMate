from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.core.config import Settings


@pytest.mark.parametrize("raw_value", ["", "   "])
def test_blank_optional_apple_app_id_is_treated_as_unset(raw_value: str) -> None:
    settings = Settings(_env_file=None, apple_app_id=raw_value)

    assert settings.apple_app_id is None


def test_non_blank_apple_app_id_keeps_integer_validation() -> None:
    settings = Settings(_env_file=None, apple_app_id="123456789")

    assert settings.apple_app_id == 123456789

    with pytest.raises(ValidationError, match="apple_app_id"):
        Settings(_env_file=None, apple_app_id="不是数字")
