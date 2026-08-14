import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';

void main() {
  final Map<String, Object?> digestFixture = _fixture(
    'contracts/coach/v1/fixtures/canonical-digest-cases.json',
  );
  final Map<String, Object?> decisionFixture = _fixture(
    'contracts/coach/v1/fixtures/decision-cases.json',
  );

  for (final Object? raw in digestFixture['cases']! as List<Object?>) {
    final Map<String, Object?> item = Map<String, Object?>.from(raw! as Map);
    test('跨端规范摘要一致：${item['case_id']}', () {
      expect(CoachDigest.sha256(item['value']), item['expected_sha256']);
    });
  }

  for (final Object? raw in decisionFixture['cases']! as List<Object?>) {
    final Map<String, Object?> item = Map<String, Object?>.from(raw! as Map);
    final String caseId = item['case_id']! as String;
    final DateTime now = DateTime.utc(2026, 8, 12, 8);
    final TrainingStateSnapshotV1 snapshot = _snapshot(item, now);
    final TrainingDecisionV1 decision = const CoachKernel().evaluate(
      snapshot: snapshot,
      intent: CoachIntent.todayTraining,
      now: now,
    );
    final CoachDecisionEnvelopeV1 envelope = const CoachSafetyGate().apply(
      snapshot: snapshot,
      training: decision,
      turnId: 'turn-$caseId',
      memorySetDigest: CoachDigest.emptySet,
    );

    test('$caseId：训练引擎输出与共享夹具一致', () {
      expect(decision.riskLevel.name, item['expect_risk']);
      expect(decision.reasonCodes, contains(item['expect_reason']));
      expect(decision.allowed.singleOrNull?.actionId, item['expect_action']);
      expect(decision.allowed.singleOrNull?.intensity.name,
          item['expect_intensity']);
      expect(decision.allowed.singleOrNull?.durationMinutes,
          item['expect_duration']);
    });

    test('$caseId：安全层不扩大训练允许集合', () {
      expect(
        envelope.allowed.map((CoachActionOptionV1 action) => action.actionId),
        everyElement(
          isIn(decision.allowed
              .map((CoachActionOptionV1 action) => action.actionId)
              .toList()),
        ),
      );
      expect(envelope.riskLevel.index,
          greaterThanOrEqualTo(decision.riskLevel.index));
    });

    test('$caseId：双端相同结果仲裁后不放宽', () {
      final CoachMergeResult merged = const CoachDecisionMerger().intersect(
        local: envelope,
        remote: envelope,
      );
      expect(merged.verificationState, CoachVerificationState.dualVerified);
      expect(merged.envelope.allowed.length, envelope.allowed.length);
      expect(merged.envelope.riskLevel, envelope.riskLevel);
    });

    test('$caseId：静态渲染不生成允许集合外的行动', () {
      final CoachRenderedReply rendered =
          const DeterministicCompanionRenderer().render(
        envelope: envelope,
        communication: CommunicationPlanV1(
          chosenActionId: envelope.allowed.singleOrNull?.actionId,
          tone: CoachTone.warm,
        ),
        memories: const <CoachMemoryV1>[],
        verificationState: CoachVerificationState.localOnly,
      );
      expect(
        rendered.actions.map((CoachRenderedAction action) => action.actionId),
        everyElement(
          isIn(envelope.allowed
              .map((CoachActionOptionV1 action) => action.actionId)
              .toList()),
        ),
      );
    });
  }
}

TrainingStateSnapshotV1 _snapshot(
  Map<String, Object?> item,
  DateTime now,
) {
  final int? planned = item['planned'] as int?;
  return TrainingStateSnapshotV1.create(
    snapshotId: 'snapshot-${item['case_id']}',
    athleteProfileId: 'athlete-fixture',
    generatedAt: now,
    validUntil: now.add(const Duration(hours: 5)),
    localDate: '2026-08-12',
    timeZoneName: 'Asia/Shanghai',
    sourceRefs: <CoachSourceRef>[
      CoachSourceRef(
        sourceKind: 'fixture',
        sourceLocalId: 'source-${item['case_id']}',
        sourceDigest: CoachDigest.sha256(item),
        observedAt: now,
        summaryKey: '共享测试夹具',
      ),
    ],
    plannedActionId: planned == null ? null : 'follow-existing-plan',
    plannedDurationMinutes: planned,
    availableMinutes: item['available'] as int?,
    recoveryBand: CoachRecoveryBand.values.byName(item['recovery']! as String),
    completedSessions7d: 3,
    missedSessions7d: 0,
    severePain: (item['flags']! as List<Object?>).contains('severe_pain'),
    safetyFlags: List<String>.from(item['flags']! as List<Object?>),
    missingFields: List<String>.from(item['missing']! as List<Object?>),
  );
}

Map<String, Object?> _fixture(String path) => Map<String, Object?>.from(
      jsonDecode(File(path).readAsStringSync())! as Map,
    );

extension<T> on Iterable<T> {
  T? get singleOrNull => length == 1 ? single : null;
}
