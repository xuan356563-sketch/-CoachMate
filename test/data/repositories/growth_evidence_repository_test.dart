import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/growth_evidence.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('降级仓储按来源事件 ID 幂等保存，并撤销而非物理删除', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final PersistedGrowthEvidenceRepository repository =
        PersistedGrowthEvidenceRepository(storage);
    final DateTime occurredAt = DateTime(2026, 7, 14, 8);

    await repository.saveEvent(_event(occurredAt, title: '首次保存'));
    await repository.saveEvent(_event(occurredAt, title: '修订后的训练记录'));

    final List<GrowthEvidenceEvent> active = await repository.listEvents(
      athleteProfileId: 'athlete-1',
    );
    expect(active, hasLength(1));
    expect(active.single.title, '修订后的训练记录');

    await repository.revokeSource(
      athleteProfileId: 'athlete-1',
      sourceTable: 'training_logs',
      sourceId: 'log-1',
      revokedAt: DateTime(2026, 7, 14, 10),
    );
    expect(
      await repository.listEvents(athleteProfileId: 'athlete-1'),
      isEmpty,
    );

    final List<GrowthEvidenceEvent> auditRows = await repository.listEvents(
      athleteProfileId: 'athlete-1',
      includeRevoked: true,
    );
    expect(auditRows, hasLength(1));
    expect(auditRows.single.isRevoked, isTrue);

    final PersistedGrowthEvidenceRepository restored =
        PersistedGrowthEvidenceRepository(storage);
    final List<GrowthEvidenceEvent> restoredRows = await restored.listEvents(
      athleteProfileId: 'athlete-1',
      includeRevoked: true,
    );
    expect(restoredRows.single.isRevoked, isTrue);
  });

  test('同一用户与周键的周成长报告会原位更新', () async {
    final PersistedGrowthEvidenceRepository repository =
        PersistedGrowthEvidenceRepository(InMemoryLocalStorageService());
    final WeeklyGrowthReport first = _weeklyReport(
      generatedAt: DateTime(2026, 7, 14, 8),
      completionRate: 0.5,
    );
    final WeeklyGrowthReport updated = first.copyWith(
      generatedAt: DateTime(2026, 7, 14, 10),
      completionRate: 0.75,
      regeneratedAt: DateTime(2026, 7, 14, 10),
    );

    await repository.saveWeeklyReport(first);
    await repository.saveWeeklyReport(updated);

    final List<WeeklyGrowthReport> reports =
        await repository.listWeeklyReports(athleteProfileId: 'athlete-1');
    expect(reports, hasLength(1));
    expect(reports.single.completionRate, 0.75);
    expect(reports.single.regeneratedAt, DateTime(2026, 7, 14, 10));
  });

  test('清理运动员成长数据会删除证据等级峰值和报告且不影响其他账号', () async {
    final PersistedGrowthEvidenceRepository repository =
        PersistedGrowthEvidenceRepository(InMemoryLocalStorageService());
    final DateTime now = DateTime(2026, 7, 14, 8);
    await repository.saveEvent(_event(now, title: '待清理证据'));
    await repository.saveLevelState(
      athleteProfileId: 'athlete-1',
      state: const GrowthLevelState(peakXp: 240, peakLevel: 3),
      updatedAt: now,
    );
    await repository.saveWeeklyReport(
      _weeklyReport(generatedAt: now, completionRate: 0.8),
    );
    await repository.saveEvent(
      _event(
        now,
        title: '其他账号证据',
        eventId: 'training_logs:other-log',
        athleteProfileId: 'athlete-2',
        sourceId: 'other-log',
      ),
    );

    await repository.clearAthleteData('athlete-1');

    expect(
      await repository.listEvents(
        athleteProfileId: 'athlete-1',
        includeRevoked: true,
      ),
      isEmpty,
    );
    expect(
      await repository.readLevelState('athlete-1'),
      const GrowthLevelState(peakXp: 0, peakLevel: 1),
    );
    expect(
      await repository.listWeeklyReports(athleteProfileId: 'athlete-1'),
      isEmpty,
    );
    expect(
      await repository.listEvents(athleteProfileId: 'athlete-2'),
      hasLength(1),
    );
  });
}

GrowthEvidenceEvent _event(
  DateTime occurredAt, {
  required String title,
  String eventId = 'training_logs:log-1',
  String athleteProfileId = 'athlete-1',
  String sourceId = 'log-1',
}) {
  return GrowthEvidenceEvent(
    eventId: eventId,
    athleteProfileId: athleteProfileId,
    eventType: GrowthEventType.training,
    title: title,
    description: '用于验证持久化和撤销规则。',
    occurredAt: occurredAt,
    occurredOn: DateTime(2026, 7, 14),
    timeZoneOffsetMinutes: -420,
    timeZoneName: 'PDT',
    sourceTable: 'training_logs',
    sourceId: sourceId,
    xpComponents: const <GrowthXpComponent>[
      GrowthXpComponent(
        type: GrowthXpComponentType.completion,
        amount: 30,
        reason: '完成训练',
      ),
    ],
    impacts: const <GrowthImpact>[],
    confidence: GrowthConfidence.high,
    missingData: const <String>[],
    inputSnapshot: const <String, dynamic>{},
    modelVersion: 1,
    createdAt: occurredAt,
    updatedAt: occurredAt,
  );
}

WeeklyGrowthReport _weeklyReport({
  required DateTime generatedAt,
  required double completionRate,
}) {
  return WeeklyGrowthReport(
    id: 'weekly-growth:athlete-1:2026-07-13',
    athleteProfileId: 'athlete-1',
    weekKey: '2026-07-13',
    weekStartsOn: DateTime(2026, 7, 13),
    weekEndsOn: DateTime(2026, 7, 19),
    generatedAt: generatedAt,
    lockedAt: null,
    regeneratedAt: null,
    consecutiveTrainingDays: 2,
    runningDistanceKm: 10,
    strengthSessionCount: 1,
    completionRate: completionRate,
    trainingLoad: 320,
    growthIndex: 72,
    availableIndexDimensions: 3,
    recoverySummary: '恢复数据充足。',
    evidenceEventIds: const <String>['training_logs:log-1'],
    modelVersion: 1,
  );
}
