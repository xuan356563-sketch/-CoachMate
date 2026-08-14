import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/monthly_summary.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/features/growth/application/growth_metrics_controller.dart';
import 'package:trainflow_ai/services/growth_narrative_builder.dart';

void main() {
  test('当前指标投影被覆盖后，旧周报仍保留生成时的指标快照', () async {
    final InMemoryTrainingMetricsRepository repository =
        InMemoryTrainingMetricsRepository();
    final DateTime weekStart = DateTime(2026, 7, 13);
    await repository.saveAggregate(
      _aggregate(
        id: 'metric-1',
        periodStart: weekStart,
        value: 0.75,
      ),
    );
    final GrowthMetricsController controller = GrowthMetricsController(
      repository: repository,
      narrativeBuilder: const GrowthNarrativeBuilder(),
      clock: () => DateTime(2026, 7, 20, 8),
    );

    await controller.loadPeriod(
      athleteProfileId: 'athlete-1',
      period: MetricPeriod.week,
      periodStart: weekStart,
    );
    final ReportRevision first = await controller.generateWeeklyReport();
    await repository.saveAggregate(
      _aggregate(
        id: 'metric-1',
        periodStart: weekStart,
        value: 0.9,
      ),
    );
    await controller.loadPeriod(
      athleteProfileId: 'athlete-1',
      period: MetricPeriod.week,
      periodStart: weekStart,
    );
    final ReportRevision second = await controller.generateWeeklyReport();
    final List<ReportRevision> stored = await repository.listReportRevisions(
      athleteProfileId: 'athlete-1',
      period: MetricPeriod.week,
      periodStart: weekStart,
    );

    expect(controller.state.status, MetricStatus.ready);
    expect(controller.state.metrics, hasLength(1));
    expect(first.revision, 1);
    expect(second.revision, 2);
    expect(second.previousRevisionId, first.id);
    expect(first.metricSnapshots.single.value, 0.75);
    expect(first.metricSnapshots.single.baselineValue, 0.6);
    expect(first.metricSnapshots.single.sampleCount, 3);
    expect(first.metricSnapshots.single.coverage, 1);
    expect(first.metricSnapshots.single.metadata['explanation'], '测试指标');
    expect(second.metricSnapshots.single.value, 0.9);
    expect(second.narrative, contains('本周训练执行率为 90%'));
    expect(stored.last.metricSnapshots.single.value, 0.75);
    expect(controller.state.reports, hasLength(2));
  });

  test('来源失效后刷新当前周期，不再把失效指标作为可用结果', () async {
    final InMemoryTrainingMetricsRepository repository =
        InMemoryTrainingMetricsRepository();
    final DateTime weekStart = DateTime(2026, 7, 13);
    await repository.saveAggregate(
      _aggregate(
        id: 'metric-1',
        periodStart: weekStart,
        value: 0.75,
      ),
    );
    await repository.saveLineage(
      MetricLineage(
        metricId: 'metric-1',
        sourceType: 'workout',
        sourceId: 'workout-1',
        relationship: 'input',
        createdAt: DateTime(2026, 7, 15),
      ),
    );
    final GrowthMetricsController controller = GrowthMetricsController(
      repository: repository,
      narrativeBuilder: const GrowthNarrativeBuilder(),
      clock: () => DateTime(2026, 7, 20, 8),
    );
    await controller.loadPeriod(
      athleteProfileId: 'athlete-1',
      period: MetricPeriod.week,
      periodStart: weekStart,
    );

    final List<String> affected = await controller.invalidateBySource(
      sourceType: 'workout',
      sourceId: 'workout-1',
    );

    expect(affected, <String>['metric-1']);
    expect(controller.state.metrics, isEmpty);
    expect(controller.state.status, MetricStatus.unavailable);
  });

  test('指标为空时拒绝写入看似有效的报告修订', () async {
    final InMemoryTrainingMetricsRepository repository =
        InMemoryTrainingMetricsRepository();
    final GrowthMetricsController controller = GrowthMetricsController(
      repository: repository,
      narrativeBuilder: const GrowthNarrativeBuilder(),
      clock: () => DateTime(2026, 7, 20, 8),
    );
    await controller.loadPeriod(
      athleteProfileId: 'athlete-1',
      period: MetricPeriod.week,
      periodStart: DateTime(2026, 7, 13),
    );

    await expectLater(
      controller.generateWeeklyReport(),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          '中文错误',
          contains('指标仍在积累'),
        ),
      ),
    );
    expect(
      await repository.listReportRevisions(
        athleteProfileId: 'athlete-1',
        period: MetricPeriod.week,
        periodStart: DateTime(2026, 7, 13),
      ),
      isEmpty,
    );
  });

  test('生成月报时把结构化月度总结固定到报告修订中', () async {
    final InMemoryTrainingMetricsRepository repository =
        InMemoryTrainingMetricsRepository();
    final DateTime monthStart = DateTime(2026, 6);
    await repository.saveAggregate(
      _aggregate(
        id: 'metric-month',
        periodStart: monthStart,
        value: 70,
        period: MetricPeriod.month,
      ),
    );
    final GrowthMetricsController controller = GrowthMetricsController(
      repository: repository,
      narrativeBuilder: const GrowthNarrativeBuilder(),
      clock: () => DateTime(2026, 7, 1),
    );
    await controller.loadPeriod(
      athleteProfileId: 'athlete-1',
      period: MetricPeriod.month,
      periodStart: monthStart,
    );
    final MonthlySummary summary = MonthlySummary(
      monthStart: monthStart,
      previousMonthStart: DateTime(2026, 5),
      inputFingerprint: 'summary-a',
      dimensions: <MonthlyDimensionSummary>[
        MonthlyDimensionSummary(
          dimension: MonthlySummaryDimension.trainingExecution,
          state: MonthlyChangeState.accumulating,
          metrics: const <MonthlyMetricChange>[],
        ),
      ],
      bodyChanges: const <MonthlyMetricChange>[],
    );

    final ReportRevision report =
        await controller.generateMonthlyReport(monthlySummary: summary);

    expect(report.monthlySummarySnapshot?.inputFingerprint, 'summary-a');
    expect(report.narrative, contains('训练执行'));
  });
}

MetricAggregate _aggregate({
  required String id,
  required DateTime periodStart,
  required double value,
  MetricPeriod period = MetricPeriod.week,
}) {
  return MetricAggregate(
    id: id,
    athleteProfileId: 'athlete-1',
    metricCode: 'weekly_consistency',
    period: period,
    periodStart: periodStart,
    value: value,
    unit: 'ratio',
    sampleCount: 3,
    sampleDurationSeconds: 0,
    coverage: 1,
    status: MetricStatus.ready,
    algorithmVersion: 'test-v1',
    inputFingerprint: 'fingerprint-1',
    computedAt: DateTime(2026, 7, 15),
    baselineValue: 0.6,
    metadata: const <String, Object?>{'explanation': '测试指标'},
  );
}
