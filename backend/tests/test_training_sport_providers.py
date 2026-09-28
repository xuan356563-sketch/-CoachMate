from __future__ import annotations

import pytest

from app.services.training_prescription_v2 import (
    TrainingPrescriptionV2Request,
    _compile_safe_fallback,
)
from app.services.training_skills import TrainingSkillRegistry
from app.services.training_sport_providers import (
    ProviderRegistry,
    ProviderRegistryError,
    TrainingSportCode,
    TrainingSportProvider,
)

EXPECTED_PROVIDERS = {
    "marathon": {
        "id": "sport.marathon",
        "allowed": {
            "easy_run",
            "tempo_run",
            "interval_run",
            "long_run",
            "strength",
            "mobility",
            "cross_training",
        },
        "fallback": ("easy_run", "strength", "long_run", "mobility"),
        "fragment_title": "马拉松专项运行时",
        "reason_code": "generic_periodization_fallback",
    },
    "trail_running": {
        "id": "sport.trail_running",
        "allowed": {
            "easy_run",
            "tempo_run",
            "interval_run",
            "long_run",
            "strength",
            "mobility",
            "cross_training",
        },
        "fallback": ("easy_run", "strength", "long_run", "mobility"),
        "fragment_title": "越野跑专项运行时",
        "reason_code": "generic_periodization_fallback",
    },
    "strength": {
        "id": "sport.strength",
        "allowed": {"strength", "mobility", "cross_training"},
        "fallback": ("strength", "mobility", "cross_training"),
        "fragment_title": "ABC 力量专项运行时",
        "reason_code": "generic_periodization_fallback",
    },
    "hyrox": {
        "id": "sport.hyrox",
        "allowed": {
            "easy_run",
            "tempo_run",
            "interval_run",
            "long_run",
            "strength",
            "hyrox",
            "mobility",
        },
        "fallback": ("easy_run", "strength", "hyrox", "mobility"),
        "fragment_title": "HYROX 专项运行时",
        "reason_code": "hyrox_fragment_exact_match",
    },
    "fat_loss": {
        "id": "goal.fat_loss",
        "allowed": {"strength", "mobility", "cross_training", "easy_run"},
        "fallback": ("strength", "easy_run", "cross_training", "mobility"),
        "fragment_title": None,
        "reason_code": "generic_periodization_fallback",
    },
    "general_fitness": {
        "id": "goal.general_fitness",
        "allowed": {"strength", "mobility", "cross_training", "easy_run"},
        "fallback": ("strength", "easy_run", "mobility", "cross_training"),
        "fragment_title": None,
        "reason_code": "generic_periodization_fallback",
    },
}


def _provider(
    *,
    provider_id: str,
    sport_code: TrainingSportCode,
) -> TrainingSportProvider:
    return TrainingSportProvider(
        id=provider_id,
        sport_code=sport_code,
        allowed_training_types=frozenset({"mobility"}),
        safe_fallback_pattern=("mobility",),
    )


def _v2_request(sport_code: str) -> TrainingPrescriptionV2Request:
    return TrainingPrescriptionV2Request.model_validate(
        {
            "contract_version": 2,
            "client_context_digest": "a" * 64,
            "population_template_id": "shift_worker_flexible",
            "knowledge_snapshot_version": "knowledge-catalog-v1",
            "context": {
                "goal": "general_fitness",
                "primary_sport": sport_code,
                "experience_level": "intermediate",
                "weekly_training_days": 6,
                "available_minutes": 45,
                "equipment_access": ["bodyweight"],
            },
        },
    )


def test_provider_registry_rejects_duplicate_ids() -> None:
    with pytest.raises(ProviderRegistryError, match="运动提供方 ID 重复"):
        ProviderRegistry(
            (
                _provider(provider_id="sport.same", sport_code="marathon"),
                _provider(provider_id="sport.same", sport_code="strength"),
            ),
        )


def test_provider_registry_rejects_duplicate_sport_codes() -> None:
    with pytest.raises(ProviderRegistryError, match="运动代码重复"):
        ProviderRegistry(
            (
                _provider(provider_id="sport.first", sport_code="marathon"),
                _provider(provider_id="sport.second", sport_code="marathon"),
            ),
        )


def test_default_registry_contains_exactly_six_cloud_sports() -> None:
    providers = ProviderRegistry.default().providers

    assert {provider.sport_code for provider in providers} == set(EXPECTED_PROVIDERS)
    assert {provider.id for provider in providers} == {
        expected["id"] for expected in EXPECTED_PROVIDERS.values()
    }


@pytest.mark.parametrize("unsupported", ["rehab", "unknown"])
def test_provider_registry_rejects_unsupported_sports(unsupported: str) -> None:
    with pytest.raises(ProviderRegistryError, match="不支持的训练运动代码"):
        ProviderRegistry.default().resolve(unsupported)


@pytest.mark.parametrize("sport_code", EXPECTED_PROVIDERS)
def test_builtin_provider_allowlist_and_v2_fallback_are_equivalent(
    sport_code: str,
) -> None:
    expected = EXPECTED_PROVIDERS[sport_code]
    provider = ProviderRegistry.default().resolve(sport_code)

    assert provider.id == expected["id"]
    assert provider.sport_code == sport_code
    assert set(provider.allowed_training_types) == expected["allowed"]
    assert provider.safe_fallback_pattern == expected["fallback"]

    prescription = _compile_safe_fallback(_v2_request(sport_code))
    actual_pattern = tuple(
        session.training_type for session in prescription.weekly_sessions
    )
    repeated = expected["fallback"] * 2
    assert actual_pattern == repeated[:6]


@pytest.mark.parametrize("sport_code", EXPECTED_PROVIDERS)
def test_builtin_provider_keeps_reviewed_fragment_selection_evidence(
    sport_code: str,
) -> None:
    expected = EXPECTED_PROVIDERS[sport_code]
    selection = TrainingSkillRegistry.default().resolve(sport_code)

    assert selection.coverage == sport_code
    assert selection.selection_reason_code == expected["reason_code"]
    fragment_title = expected["fragment_title"]
    if fragment_title is None:
        assert selection.fragment_text == ""
        assert selection.fragment_sha256 is None
    else:
        assert fragment_title in selection.fragment_text
        assert selection.fragment_sha256 == (
            selection.manifest.fragment_sha256[sport_code]
        )
