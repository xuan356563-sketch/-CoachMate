import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';

void main() {
  test('按指标 ID 幂等保存，并隔离不同运动员的数据', () async {
    final InMemoryTrainingMetricsRepository repository =
        InMemoryTrainingMetricsRepository();
    await repository.saveAggregate(_aggregate(value: 0.5));
    await repository.saveAggregate(_aggregate(value: 0.8));
    await repository.saveAggregate(
      _aggregate(
        id: 'metric-other',
        athleteProfileId: 'athlete-2',
        value: 1,
      ),
    );

    final List<MetricAggregate> metrics = await repository.listAggregates(
      athleteProfileId: 'athlete-1',
      period: MetricPeriod.week,
      periodStart: DateTime(2026, 7, 13),
    );

    expect(metrics, hasLength(1));
    expect(metrics.single.value, 0.8);
  });

  test('按来源失效血缘和关联指标，并返回受影响指标 ID', () async {
    final InMemoryTrainingMetricsRepository repository =
        InMemoryTrainingMetricsRepository();
    await repository.saveAggregate(_aggregate(value: 0.8));
    await repository.saveLineage(
      MetricLineage(
        metricId: 'metric-1',
        sourceType: 'workout',
        sourceId: 'workout-1',
        relationship: 'input',
        createdAt: DateTime(2026, 7, 15),
      ),
    );
    final DateTime invalidatedAt = DateTime(2026, 7, 16, 8);

    final List<String> affected = await repository.invalidateBySource(
      athleteProfileId: 'athlete-1',
      sourceType: 'workout',
      sourceId: 'workout-1',
      invalidatedAt: invalidatedAt,
    );

    expect(affected, <String>['metric-1']);
    final List<MetricAggregate> metrics = await repository.listAggregates(
      athleteProfileId: 'athlete-1',
      includeInvalidated: true,
    );
    expect(metrics.single.status, MetricStatus.invalidated);
    expect(metrics.single.invalidatedAt, invalidatedAt);
    final List<MetricLineage> lineage =
        await repository.listLineage(metricId: 'metric-1');
    expect(lineage.single.invalidatedAt, invalidatedAt);
  });

  test('报告只新增修订，调整建议按 ID 更新状态', () async {
    final InMemoryTrainingMetricsRepository repository =
        InMemoryTrainingMetricsRepository();
    await repository.saveReportRevision(_revision(1));
    await repository.saveReportRevision(_revision(2));
    await repository.saveAdjustmentProposal(_proposal());
    await repository.saveAdjustmentProposal(
      _proposal().copyWith(
        status: AdjustmentProposalStatus.confirmed,
        confirmedAt: DateTime(2026, 7, 16),
      ),
    );

    final List<ReportRevision> revisions = await repository.listReportRevisions(
      athleteProfileId: 'athlete-1',
      period: MetricPeriod.week,
      periodStart: DateTime(2026, 7, 13),
    );
    expect(revisions.map((ReportRevision item) => item.revision), <int>[2, 1]);
    final List<AdjustmentProposal> proposals =
        await repository.listAdjustmentProposals(
      athleteProfileId: 'athlete-1',
    );
    expect(proposals, hasLength(1));
    expect(proposals.single.status, AdjustmentProposalStatus.confirmed);
  });
}

MetricAggregate _aggregate({
  String id = 'metric-1',
  String athleteProfileId = 'athlete-1',
  required double value,
}) {
  return MetricAggregate(
    id: id,
    athleteProfileId: athleteProfileId,
    metricCode: 'weekly_consistency',
    period: MetricPeriod.week,
    periodStart: DateTime(2026, 7, 13),
    value: value,
    unit: 'ratio',
    sampleCount: 3,
    sampleDurationSeconds: 0,
    coverage: 1,
    status: MetricStatus.ready,
    algorithmVersion: 'test-v1',
    inputFingerprint: 'fingerprint-1',
    computedAt: DateTime(2026, 7, 15),
  );
}

ReportRevision _revision(int revision) {
  return ReportRevision(
    id: 'report-$revision',
    athleteProfileId: 'athlete-1',
    period: MetricPeriod.week,
    periodStart: DateTime(2026, 7, 13),
    revision: revision,
    generatedAt: DateTime(2026, 7, 15, revision),
    metricIds: const <String>['metric-1'],
    narrative: '第 $revision 版报告',
    algorithmVersion: 'narrative-v1',
    previousRevisionId: revision == 1 ? null : 'report-${revision - 1}',
  );
}

AdjustmentProposal _proposal() {
  return AdjustmentProposal(
    id: 'proposal-1',
    athleteProfileId: 'athlete-1',
    planId: 'plan-1',
    workoutDayId: 'day-1',
    workoutTitle: '间歇跑',
    triggerMetricCode: 'acwr.session_rpe',
    triggerAlgorithmVersion: 'acwr-v1',
    explanation: '等待确认。',
    originalMinutes: 60,
    adjustedMinutes: 60,
    originalIntensity: '高强度',
    adjustedIntensity: '降低一级',
    status: AdjustmentProposalStatus.proposed,
    createdAt: DateTime(2026, 7, 15),
  );
}
