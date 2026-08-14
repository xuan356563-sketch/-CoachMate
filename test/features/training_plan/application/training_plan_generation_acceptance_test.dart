import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/ai_artifact.dart';
import 'package:trainflow_ai/data/models/ai_training_prescription.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/features/training_plan/application/training_plan_generation_controller.dart';

void main() {
  test('确认响应仅缓存标记变化时仍可通过一致性校验', () {
    final AiTrainingPrescription expected = _prescription(cacheHit: true);
    final AiArtifact original = _artifact(
      id: 'artifact-1',
      decision: AiArtifactDecision.pending,
      prescription: expected,
    );
    final AiArtifact accepted = _artifact(
      id: 'artifact-1',
      decision: AiArtifactDecision.accepted,
      prescription: _prescription(cacheHit: false),
    );

    expect(
      trainingPrescriptionAcceptanceBlocker(
        original: original,
        accepted: accepted,
        expectedPrescription: expected,
      ),
      isNull,
    );
  });

  test('错误 ID、pending、Skill 哈希或蓝图漂移均阻断本地激活', () {
    final AiTrainingPrescription expected = _prescription(cacheHit: false);
    final AiArtifact original = _artifact(
      id: 'artifact-1',
      decision: AiArtifactDecision.pending,
      prescription: expected,
    );
    final List<AiArtifact> invalid = <AiArtifact>[
      _artifact(
        id: 'artifact-other',
        decision: AiArtifactDecision.accepted,
        prescription: expected,
      ),
      _artifact(
        id: 'artifact-1',
        decision: AiArtifactDecision.pending,
        prescription: expected,
      ),
      _artifact(
        id: 'artifact-1',
        decision: AiArtifactDecision.accepted,
        prescription: _prescription(
          cacheHit: false,
          runtimeHash:
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        ),
      ),
      _artifact(
        id: 'artifact-1',
        decision: AiArtifactDecision.accepted,
        prescription: _prescription(cacheHit: false, durationMinutes: 60),
      ),
    ];

    for (final AiArtifact response in invalid) {
      expect(
        trainingPrescriptionAcceptanceBlocker(
          original: original,
          accepted: response,
          expectedPrescription: expected,
        ),
        contains('不会改变'),
      );
    }
  });
}

AiTrainingPrescription _prescription({
  required bool cacheHit,
  int durationMinutes = 45,
  String runtimeHash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) {
  const String digest =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  return AiTrainingPrescription(
    cycleFocus: 'base',
    progressionMode: AiProgressionMode.conservative,
    weeklySessions: <AiSessionBlueprint>[
      AiSessionBlueprint(
        trainingType: TrainingType.strength,
        durationMinutes: durationMinutes,
        intensityBand: AiIntensityBand.moderate,
        focusCodes: const <String>['full_body_strength'],
      ),
    ],
    skill: AiSkillRef(
      id: 'training-plan-builder',
      version: '1.0.0',
      displayName: '训练计划生成器',
      sourceSha256: digest,
      runtimeSha256: runtimeHash,
      coverage: 'general_fitness',
      selectionReason: '通用周期化规则',
    ),
    generationMeta: AiGenerationMeta(
      contractVersion: '1',
      clientContextDigest: digest,
      model: 'deepseek-chat',
      cacheHit: cacheHit,
      promptContractVersion: 'training-prescription-v1',
      inputTokens: 10,
      outputTokens: 20,
    ),
    selectionReasonCode: 'generic_periodization_fallback',
  );
}

AiArtifact _artifact({
  required String id,
  required AiArtifactDecision decision,
  required AiTrainingPrescription prescription,
}) =>
    AiArtifact(
      id: id,
      capability: AiCapability.trainer,
      artifactType: 'training_prescription_v1',
      schemaVersion: 1,
      decision: decision,
      contextDigest:
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      payload: prescription.toJson(),
      warnings: const <String>[],
      provider: 'deepseek',
      model: 'deepseek-chat',
      generatedAt: DateTime(2026, 7, 17),
    );
