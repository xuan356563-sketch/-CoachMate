from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.core.config import Settings
from app.services.coach.contracts import (
    CoachEvaluationRequest,
    CoachStateProjectionInput,
    canonical_digest,
)
from app.services.coach.projection_service import CoachProjectionService

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "contracts" / "coach" / "v1" / "fixtures"


def _read(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


@pytest.mark.parametrize(
    "case",
    _read("canonical-digest-cases.json")["cases"],
    ids=lambda case: case["case_id"],
)
def test_canonical_digest_matches_shared_fixture(case: dict) -> None:
    assert canonical_digest(case["value"]) == case["expected_sha256"]


@pytest.mark.parametrize(
    ("case", "intent"),
    [
        (case, intent)
        for case in _read("decision-cases.json")["cases"]
        for intent in ("today_training", "explain_plan", "recovery", "manage_memory")
    ],
    ids=lambda value: value["case_id"] if isinstance(value, dict) else value,
)
def test_decision_fixture_has_stable_cross_runtime_semantics(
    case: dict,
    intent: str,
) -> None:
    settings = Settings()
    service = CoachProjectionService.__new__(CoachProjectionService)
    service._settings = settings
    state = CoachStateProjectionInput(
        snapshot_id=f"snapshot-{case['case_id']}",
        source_digest="a" * 64,
        snapshot_digest="b" * 64,
        contract_version=1,
        contract_hash=settings.coach_contract_hash,
        rule_set_version=settings.coach_rule_set_version,
        generated_at="2026-08-12T08:00:00Z",
        valid_until="2026-08-12T13:00:00Z",
        local_date="2026-08-12",
        planned_action_id=(
            "follow-existing-plan" if case["planned"] is not None else None
        ),
        planned_duration_minutes=case["planned"],
        available_minutes=case["available"],
        recovery_band=case["recovery"],
        completed_sessions_7d=3,
        missed_sessions_7d=0,
        safety_flags=case["flags"],
        quality_codes=[],
        missing_fields=case["missing"],
    )
    request = CoachEvaluationRequest(
        turn_id=f"turn-{case['case_id']}-{intent}",
        snapshot_id=state.snapshot_id,
        snapshot_digest=state.snapshot_digest,
        memory_set_digest=canonical_digest([]),
        intent=intent,
        emotion="neutral",
        contract_version=1,
        contract_hash=settings.coach_contract_hash,
        rule_set_version=settings.coach_rule_set_version,
        requested_action_ids=[],
    )

    result = service._decision(request, state)

    if intent == "manage_memory":
        assert result.allowed == []
        assert result.risk_level == "low"
        assert result.reason_codes == ["non_training_intent"]
        return
    assert result.risk_level == case["expect_risk"]
    assert case["expect_reason"] in result.reason_codes
    action = result.allowed[0] if len(result.allowed) == 1 else None
    assert (action.action_id if action else None) == case["expect_action"]
    assert (action.intensity if action else None) == case["expect_intensity"]
    assert (action.duration_minutes if action else None) == case["expect_duration"]
