import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 8, 12, 12);

  TrainingStateSnapshotV1 snapshot({
    int? pain,
    bool severePain = false,
    DateTime? validUntil,
    String actionId = 'follow-existing-plan',
    int duration = 45,
  }) {
    return TrainingStateSnapshotV1.create(
      snapshotId: 'snapshot-1',
      athleteProfileId: 'athlete-1',
      generatedAt: now.subtract(const Duration(minutes: 5)),
      validUntil: validUntil ?? now.add(const Duration(hours: 5)),
      localDate: '2026-08-12',
      timeZoneName: 'Asia/Shanghai',
      sourceRefs: <CoachSourceRef>[
        CoachSourceRef(
          sourceKind: 'scheduled_workout',
          sourceLocalId: 'workout-1',
          sourceDigest:
              CoachDigest.sha256(<String, Object?>{'id': 'workout-1'}),
          observedAt: now,
          summaryKey: '今日计划',
        ),
      ],
      plannedActionId: actionId,
      plannedDurationMinutes: duration,
      availableMinutes: duration,
      maxPainScore: pain,
      severePain: severePain,
      recoveryBand: CoachRecoveryBand.green,
      completedSessions7d: 3,
      missedSessions7d: 0,
    );
  }

  test('训练快照使用规范 JSON 生成稳定 SHA-256 摘要', () {
    final TrainingStateSnapshotV1 value = snapshot();
    final Map<String, Object?> reversed = <String, Object?>{
      for (final MapEntry<String, Object?> entry
          in value.toJson().entries.toList().reversed)
        entry.key: entry.value,
    };

    expect(CoachDigest.sha256(value.toJson()), CoachDigest.sha256(reversed));
    expect(value.contractHash, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(value.sourceDigest, matches(RegExp(r'^[a-f0-9]{64}$')));
  });

  test('训练意图遇到过期快照时安全失败且不返回动作', () {
    final TrainingDecisionV1 decision = const CoachKernel().evaluate(
      snapshot: snapshot(validUntil: now.subtract(const Duration(seconds: 1))),
      intent: CoachIntent.todayTraining,
      now: now,
    );

    expect(decision.allowed, isEmpty);
    expect(decision.riskLevel, CoachRiskLevel.high);
    expect(decision.reasonCodes, contains('snapshot_expired'));
  });

  test('训练快照内容被改写但摘要未更新时安全失败', () {
    final TrainingStateSnapshotV1 original = snapshot();
    final Map<String, Object?> alteredJson = Map<String, Object?>.from(
      original.toJson(),
    )..['available_minutes'] = 120;
    final TrainingStateSnapshotV1 altered =
        TrainingStateSnapshotV1.fromJson(alteredJson);

    final TrainingDecisionV1 decision = const CoachKernel().evaluate(
      snapshot: altered,
      intent: CoachIntent.todayTraining,
      now: now,
    );

    expect(decision.allowed, isEmpty);
    expect(decision.reasonCodes, contains('snapshot_source_digest_mismatch'));
  });

  test('疼痛达到七分时安全层移除所有训练入口', () {
    final TrainingStateSnapshotV1 value = snapshot(pain: 7);
    final TrainingDecisionV1 training = const CoachKernel().evaluate(
      snapshot: value,
      intent: CoachIntent.todayTraining,
      now: now,
    );
    final CoachDecisionEnvelopeV1 envelope = const CoachSafetyGate().apply(
      snapshot: value,
      training: training,
      turnId: 'turn-1',
      memorySetDigest: CoachDigest.emptySet,
    );

    expect(envelope.allowed, isEmpty);
    expect(envelope.riskLevel, CoachRiskLevel.critical);
    expect(envelope.requiredBlocks, contains('pain_redline_guidance'));
  });

  test('双端仲裁只保留动作交集并取更低强度与时长', () {
    final TrainingStateSnapshotV1 value = snapshot();
    final String snapshotDigest = CoachDigest.sha256(value.toJson());
    CoachDecisionEnvelopeV1 envelope({
      required CoachIntensity intensity,
      required int duration,
      List<String> extra = const <String>[],
    }) {
      return CoachDecisionEnvelopeV1(
        turnId: 'turn-1',
        snapshotId: value.snapshotId,
        snapshotDigest: snapshotDigest,
        memorySetDigest: CoachDigest.emptySet,
        allowed: <CoachActionOptionV1>[
          CoachActionOptionV1(
            actionId: 'follow-existing-plan',
            intensity: intensity,
            durationMinutes: duration,
            requiresConfirmation: false,
          ),
          for (final String id in extra)
            CoachActionOptionV1(
              actionId: id,
              intensity: CoachIntensity.low,
              durationMinutes: 15,
              requiresConfirmation: false,
            ),
        ],
        riskLevel: CoachRiskLevel.low,
      );
    }

    final CoachMergeResult result = const CoachDecisionMerger().intersect(
      local: envelope(
        intensity: CoachIntensity.moderate,
        duration: 45,
        extra: const <String>['local-only'],
      ),
      remote: envelope(
        intensity: CoachIntensity.low,
        duration: 30,
        extra: const <String>['remote-only'],
      ),
    );

    expect(result.envelope.allowed, hasLength(1));
    expect(result.envelope.allowed.single.actionId, 'follow-existing-plan');
    expect(result.envelope.allowed.single.intensity, CoachIntensity.low);
    expect(result.envelope.allowed.single.durationMinutes, 30);
  });

  test('契约摘要不一致时不混合结果并回退固定安全口径', () {
    final TrainingStateSnapshotV1 value = snapshot();
    final CoachDecisionEnvelopeV1 local = CoachDecisionEnvelopeV1(
      turnId: 'turn-1',
      snapshotId: value.snapshotId,
      snapshotDigest: CoachDigest.sha256(value.toJson()),
      memorySetDigest: CoachDigest.emptySet,
      allowed: const <CoachActionOptionV1>[],
      riskLevel: CoachRiskLevel.low,
    );
    final CoachDecisionEnvelopeV1 remote = local.copyWith(
      contractHash: List<String>.filled(64, '0').join(),
    );

    final CoachMergeResult result =
        const CoachDecisionMerger().intersect(local: local, remote: remote);

    expect(result.verificationState, CoachVerificationState.contractMismatch);
    expect(result.envelope.allowed, isEmpty);
    expect(result.fixedFallbackText, isNotEmpty);
  });

  test('渲染器不能输出允许集合之外的动作', () {
    final TrainingStateSnapshotV1 value = snapshot();
    final CoachDecisionEnvelopeV1 envelope = CoachDecisionEnvelopeV1(
      turnId: 'turn-1',
      snapshotId: value.snapshotId,
      snapshotDigest: CoachDigest.sha256(value.toJson()),
      memorySetDigest: CoachDigest.emptySet,
      allowed: const <CoachActionOptionV1>[
        CoachActionOptionV1(
          actionId: 'follow-existing-plan',
          intensity: CoachIntensity.low,
          durationMinutes: 30,
          requiresConfirmation: false,
        ),
      ],
      riskLevel: CoachRiskLevel.low,
    );

    expect(
      () => const DeterministicCompanionRenderer().render(
        envelope: envelope,
        communication: const CommunicationPlanV1(
          chosenActionId: 'invented-action',
          tone: CoachTone.warm,
        ),
        memories: const <CoachMemoryV1>[],
        verificationState: CoachVerificationState.localOnly,
      ),
      throwsA(isA<CoachContractException>()),
    );
  });
}
