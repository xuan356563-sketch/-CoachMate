import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/ai_training_prescription.dart';
import 'package:trainflow_ai/data/models/ai_knowledge_citation.dart';
import 'package:trainflow_ai/data/models/plan_generation_preferences.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';

void main() {
  test('仅 strength 且带审核片段的处方启用 ABC 本地编译', () {
    final PlanGenerationPreferences preferences =
        PlanGenerationPreferences.fromPrescription(
      prescription: _prescription(
        coverage: 'strength',
        fragmentSha256: _hash,
      ),
      generationId: 'artifact-strength',
    );

    expect(
      preferences.generationMethod,
      PlanGenerationMethod.abcStrengthCycle,
    );
    expect(preferences.usesAbcStrengthCycle, isTrue);
    expect(preferences.knowledgeCitations.single.id, 'periodization');
  });

  test('通用覆盖或缺少专项片段时保持原本地编译行为', () {
    final PlanGenerationPreferences general =
        PlanGenerationPreferences.fromPrescription(
      prescription: _prescription(
        coverage: 'general_fitness',
        fragmentSha256: _hash,
      ),
      generationId: 'artifact-general',
    );
    final PlanGenerationPreferences missingFragment =
        PlanGenerationPreferences.fromPrescription(
      prescription: _prescription(
        coverage: 'strength',
        fragmentSha256: null,
      ),
      generationId: 'artifact-no-fragment',
    );

    expect(general.generationMethod, PlanGenerationMethod.standard);
    expect(missingFragment.generationMethod, PlanGenerationMethod.standard);
    expect(general.usesAbcStrengthCycle, isFalse);
    expect(missingFragment.usesAbcStrengthCycle, isFalse);
  });
}

AiTrainingPrescription _prescription({
  required String coverage,
  required String? fragmentSha256,
}) {
  return AiTrainingPrescription(
    cycleFocus: 'base',
    progressionMode: AiProgressionMode.balanced,
    weeklySessions: const <AiSessionBlueprint>[
      AiSessionBlueprint(
        trainingType: TrainingType.strength,
        durationMinutes: 45,
        intensityBand: AiIntensityBand.moderate,
        focusCodes: <String>['full_body_strength'],
      ),
    ],
    skill: AiSkillRef(
      id: 'training-plan-builder',
      version: '1.2.0',
      displayName: '训练计划制定助手',
      sourceSha256: _hash,
      runtimeSha256: _hash,
      fragmentSha256: fragmentSha256,
      coverage: coverage,
      selectionReason: '测试来源',
    ),
    generationMeta: const AiGenerationMeta(
      contractVersion: '1',
      clientContextDigest: _hash,
      model: 'deepseek-chat',
      cacheHit: false,
      promptContractVersion: 'training-prescription-v1',
    ),
    knowledgeCitations: const <AiKnowledgeCitation>[
      AiKnowledgeCitation(
        id: 'periodization',
        type: AiKnowledgeCitationType.principle,
        title: '周期化',
        sourceLabel: 'TrainMate 内部训练原则',
        sourceSection: '周期结构',
        contentVersion: '2026.08.02-v2',
      ),
    ],
    selectionReasonCode: 'generic_periodization_fallback',
  );
}

const String _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
