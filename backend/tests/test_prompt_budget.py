from __future__ import annotations

import pytest

from app.core.errors import ApiError
from app.services.prompt_budget import (
    CHAT_PROMPT_POLICY,
    PRESCRIPTION_PROMPT_POLICY,
    PromptBudgetPolicy,
    compact_chat_messages,
)


def test_prompt_budget_rejects_required_content_overflow() -> None:
    policy = PromptBudgetPolicy(
        capability="test",
        max_input_chars=12,
        max_output_tokens=10,
    )

    with pytest.raises(ApiError) as captured:
        policy.validate_required_parts("固定规则", "这段必填内容已经超过预算")

    assert captured.value.code == "ai_prompt_budget_exceeded"


def test_chat_compaction_keeps_latest_turns_within_total_budget() -> None:
    messages = [
        {"role": "user", "content": f"第{index}轮-" + ("训练" * 180)}
        for index in range(1, 9)
    ]

    compacted = compact_chat_messages(messages)

    assert len(compacted) <= 4
    assert compacted[-1]["content"].startswith("第8轮")
    assert sum(len(item["content"]) for item in compacted) <= 1200


def test_declared_token_policies_match_release_budget() -> None:
    assert CHAT_PROMPT_POLICY.max_input_chars == 1800
    assert CHAT_PROMPT_POLICY.max_output_tokens == 420
    assert PRESCRIPTION_PROMPT_POLICY.max_input_chars == 4200
    assert PRESCRIPTION_PROMPT_POLICY.max_output_tokens == 650
