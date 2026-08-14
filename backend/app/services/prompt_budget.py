from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass

from app.core.errors import ApiError


@dataclass(frozen=True)
class PromptBudgetPolicy:
    """用字符硬上限和输出 Token 上限约束一次模型调用。"""

    capability: str
    max_input_chars: int
    max_output_tokens: int

    def validate_required_parts(self, *parts: str) -> None:
        """必填内容不得静默截断，超限时交给上层走本地降级。"""
        if sum(len(part) for part in parts) <= self.max_input_chars:
            return
        raise ApiError(
            422,
            "ai_prompt_budget_exceeded",
            "AI 请求超过安全预算，已停止云端生成，请使用本地方案。",
        )


PROFILE_PROMPT_POLICY = PromptBudgetPolicy(
    capability="profile_proposal",
    max_input_chars=1800,
    max_output_tokens=320,
)
CHAT_PROMPT_POLICY = PromptBudgetPolicy(
    capability="chat",
    max_input_chars=1800,
    max_output_tokens=420,
)
PRESCRIPTION_PROMPT_POLICY = PromptBudgetPolicy(
    capability="training_prescription",
    max_input_chars=4200,
    max_output_tokens=650,
)
PLAN_REVISION_PROMPT_POLICY = PromptBudgetPolicy(
    capability="plan_revision",
    max_input_chars=2200,
    max_output_tokens=650,
)
GENERIC_TEXT_PROMPT_POLICY = PromptBudgetPolicy(
    capability="generic_text",
    max_input_chars=2400,
    max_output_tokens=650,
)


def compact_chat_messages(
    messages: Sequence[Mapping[str, str]],
    *,
    max_messages: int = 4,
    max_content_chars: int = 1200,
) -> list[dict[str, str]]:
    """保留最近消息，优先删除最旧上下文，不修改单条消息正文。"""
    compacted = [
        {
            "role": str(message.get("role", "")),
            "content": str(message.get("content", "")),
        }
        for message in messages[-max_messages:]
    ]
    while (
        len(compacted) > 1
        and sum(len(item["content"]) for item in compacted) > max_content_chars
    ):
        compacted.pop(0)
    if sum(len(item["content"]) for item in compacted) > max_content_chars:
        raise ApiError(
            422,
            "ai_prompt_budget_exceeded",
            "当前问题超过 AI 对话预算，请缩短后重试。",
        )
    return compacted
