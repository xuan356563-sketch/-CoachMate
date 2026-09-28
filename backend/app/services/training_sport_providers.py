from __future__ import annotations

from collections.abc import Collection, Iterable
from dataclasses import dataclass
from typing import Literal

TrainingSportCode = Literal[
    "general_fitness",
    "strength",
    "fat_loss",
    "marathon",
    "trail_running",
    "hyrox",
]
TrainingTypeCode = Literal[
    "easy_run",
    "tempo_run",
    "interval_run",
    "long_run",
    "strength",
    "hyrox",
    "mobility",
    "cross_training",
]


class ProviderRegistryError(RuntimeError):
    """运动提供方注册或解析失败。"""


@dataclass(frozen=True)
class ProviderSkillPolicy:
    """主 Skill 为当前运动选择专项片段时使用的等价策略。"""

    fragment_coverage: TrainingSportCode
    selection_reason: str
    selection_reason_code: str


@dataclass(frozen=True)
class TrainingSportProvider:
    """一项内置云端运动的稳定身份和处方策略。"""

    id: str
    sport_code: TrainingSportCode
    allowed_training_types: frozenset[TrainingTypeCode]
    safe_fallback_pattern: tuple[TrainingTypeCode, ...]

    def select_skill_policy(
        self,
        *,
        covered_sports: Collection[str],
        fragment_sports: Collection[str],
    ) -> ProviderSkillPolicy:
        exact_match = self.sport_code in covered_sports
        coverage: TrainingSportCode = (
            self.sport_code if exact_match else "general_fitness"
        )
        if coverage not in covered_sports:
            raise ProviderRegistryError("主 Skill 没有覆盖当前运动或通用训练")
        if not exact_match:
            return ProviderSkillPolicy(
                fragment_coverage=coverage,
                selection_reason="当前运动使用通用训练 Skill 覆盖",
                selection_reason_code="generic_fallback",
            )
        if self.sport_code == "hyrox" and coverage in fragment_sports:
            return ProviderSkillPolicy(
                fragment_coverage=coverage,
                selection_reason="HYROX 主运动精确匹配已审核专项片段",
                selection_reason_code="hyrox_fragment_exact_match",
            )
        return ProviderSkillPolicy(
            fragment_coverage=coverage,
            selection_reason="主运动使用通用周期化规则，并叠加已审核专项片段"
            if coverage in fragment_sports
            else "主运动使用通用周期化规则和 TrainMate 本地模板",
            selection_reason_code="generic_periodization_fallback",
        )


class ProviderRegistry:
    """注册内置运动提供方，并拒绝身份或运动代码冲突。"""

    def __init__(self, providers: Iterable[TrainingSportProvider]) -> None:
        loaded = tuple(providers)
        ids = [provider.id for provider in loaded]
        if len(ids) != len(set(ids)):
            raise ProviderRegistryError("运动提供方 ID 重复")
        sport_codes = [provider.sport_code for provider in loaded]
        if len(sport_codes) != len(set(sport_codes)):
            raise ProviderRegistryError("运动提供方运动代码重复")
        self._providers = loaded
        self._by_sport_code = {
            provider.sport_code: provider for provider in self._providers
        }

    @classmethod
    def default(cls) -> "ProviderRegistry":
        return cls(_BUILTIN_PROVIDERS)

    @property
    def providers(self) -> tuple[TrainingSportProvider, ...]:
        return self._providers

    def resolve(self, sport_code: str) -> TrainingSportProvider:
        try:
            return self._by_sport_code[sport_code]
        except KeyError as error:
            raise ProviderRegistryError(
                f"不支持的训练运动代码：{sport_code}",
            ) from error


_RUNNING_ALLOWED: frozenset[TrainingTypeCode] = frozenset(
    {
        "easy_run",
        "tempo_run",
        "interval_run",
        "long_run",
        "strength",
        "mobility",
        "cross_training",
    },
)
_GENERAL_ALLOWED: frozenset[TrainingTypeCode] = frozenset(
    {"strength", "mobility", "cross_training", "easy_run"},
)

_BUILTIN_PROVIDERS = (
    TrainingSportProvider(
        id="sport.marathon",
        sport_code="marathon",
        allowed_training_types=_RUNNING_ALLOWED,
        safe_fallback_pattern=("easy_run", "strength", "long_run", "mobility"),
    ),
    TrainingSportProvider(
        id="sport.trail_running",
        sport_code="trail_running",
        allowed_training_types=_RUNNING_ALLOWED,
        safe_fallback_pattern=("easy_run", "strength", "long_run", "mobility"),
    ),
    TrainingSportProvider(
        id="sport.strength",
        sport_code="strength",
        allowed_training_types=frozenset(
            {"strength", "mobility", "cross_training"},
        ),
        safe_fallback_pattern=("strength", "mobility", "cross_training"),
    ),
    TrainingSportProvider(
        id="sport.hyrox",
        sport_code="hyrox",
        allowed_training_types=frozenset(
            {
                "easy_run",
                "tempo_run",
                "interval_run",
                "long_run",
                "strength",
                "hyrox",
                "mobility",
            },
        ),
        safe_fallback_pattern=("easy_run", "strength", "hyrox", "mobility"),
    ),
    TrainingSportProvider(
        id="goal.fat_loss",
        sport_code="fat_loss",
        allowed_training_types=_GENERAL_ALLOWED,
        safe_fallback_pattern=(
            "strength",
            "easy_run",
            "cross_training",
            "mobility",
        ),
    ),
    TrainingSportProvider(
        id="goal.general_fitness",
        sport_code="general_fitness",
        allowed_training_types=_GENERAL_ALLOWED,
        safe_fallback_pattern=(
            "strength",
            "easy_run",
            "mobility",
            "cross_training",
        ),
    ),
)
