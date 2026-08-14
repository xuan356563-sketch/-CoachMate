import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/monthly_summary.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/services/local_report_generation_coordinator.dart';

void main() {
  const String athleteProfileId = 'athlete-1';
  final DateTime previousWeekStart = DateTime(2026, 7, 6);
  final DateTime previousMonthStart = DateTime(2026, 6);

  late InMemoryTrainingMetricsRepository repository;
  late DateTime now;
  late LocalReportGenerationCoordinator coordinator;

  setUp(() {
    repository = InMemoryTrainingMetricsRepository();
    now = DateTime(2026, 7, 15, 9);
    coordinator = LocalReportGenerationCoordinator(
      repository: repository,
      clock: () => now,
    );
  });

  Future<void> seedRecentlyClosedPeriodMetrics() async {
    await repository.saveAggregate(
      _aggregate(
        id: 'metric-weekly-consistency',
        period: MetricPeriod.week,
        periodStart: previousWeekStart,
        computedAt: DateTime(2026, 7, 12, 23),
        metricCode: 'weekly_consistency',
        value: 0.8,
        unit: 'ratio',
      ),
    );
    await repository.saveAggregate(
      _aggregate(
        id: 'metric-monthly-body-weight',
        period: MetricPeriod.month,
        periodStart: previousMonthStart,
        computedAt: DateTime(2026, 6, 30, 23),
        metricCode: 'body.weight_7d_average',
        value: 70,
        unit: 'kg',
      ),
    );
  }

  test('首次运行会为上一完整周和上一完整月各生成一份本地报告', () async {
    await seedRecentlyClosedPeriodMetrics();

    final int generated = await coordinator.ensureRecentlyClosedPeriods(
      athleteProfileId: athleteProfileId,
    );

    expect(generated, 2);
    final List<ReportRevision> weeklyReports =
        await repository.listReportRevisions(
      athleteProfileId: athleteProfileId,
      period: MetricPeriod.week,
      periodStart: previousWeekStart,
    );
    final List<ReportRevision> monthlyReports =
        await repository.listReportRevisions(
      athleteProfileId: athleteProfileId,
      period: MetricPeriod.month,
      periodStart: previousMonthStart,
    );

    expect(weeklyReports, hasLength(1));
    expect(weeklyReports.single.revision, 1);
    expect(
      weeklyReports.single.metricIds,
      <String>['metric-weekly-consistency'],
    );
    expect(monthlyReports, hasLength(1));
    expect(monthlyReports.single.revision, 1);
    expect(
      monthlyReports.single.metricIds,
      <String>['metric-monthly-body-weight'],
    );
  });

  test('指标未变化时重复运行不会新增报告修订', () async {
    await seedRecentlyClosedPeriodMetrics();
    await coordinator.ensureRecentlyClosedPeriods(
      athleteProfileId: athleteProfileId,
    );

    final int generated = await coordinator.ensureRecentlyClosedPeriods(
      athleteProfileId: athleteProfileId,
    );

    expect(generated, 0);
    expect(
      await repository.listReportRevisions(
        athleteProfileId: athleteProfileId,
        period: MetricPeriod.week,
        periodStart: previousWeekStart,
      ),
      hasLength(1),
    );
    expect(
      await repository.listReportRevisions(
        athleteProfileId: athleteProfileId,
        period: MetricPeriod.month,
        periodStart: previousMonthStart,
      ),
      hasLength(1),
    );
  });

  test('指标计算时间变新后新增修订，并保留上一版报告', () async {
    await seedRecentlyClosedPeriodMetrics();
    await coordinator.ensureRecentlyClosedPeriods(
      athleteProfileId: athleteProfileId,
    );
    final ReportRevision original = (await repository.listReportRevisions(
      athleteProfileId: athleteProfileId,
      period: MetricPeriod.week,
      periodStart: previousWeekStart,
    ))
        .single;

    now = DateTime(2026, 7, 15, 11);
    await repository.saveAggregate(
      _aggregate(
        id: 'metric-weekly-consistency',
        period: MetricPeriod.week,
        periodStart: previousWeekStart,
        computedAt: DateTime(2026, 7, 15, 10),
        metricCode: 'weekly_consistency',
        value: 0.9,
        unit: 'ratio',
      ),
    );

    final int generated = await coordinator.ensureRecentlyClosedPeriods(
      athleteProfileId: athleteProfileId,
    );

    expect(generated, 1);
    final List<ReportRevision> weeklyReports =
        await repository.listReportRevisions(
      athleteProfileId: athleteProfileId,
      period: MetricPeriod.week,
      periodStart: previousWeekStart,
    );
    expect(weeklyReports, hasLength(2));
    expect(weeklyReports.first.revision, 2);
    expect(weeklyReports.first.previousRevisionId, original.id);
    expect(weeklyReports.last.id, original.id);
    expect(weeklyReports.last.revision, 1);
    expect(weeklyReports.last.narrative, original.narrative);
    expect(
      await repository.listReportRevisions(
        athleteProfileId: athleteProfileId,
        period: MetricPeriod.month,
        periodStart: previousMonthStart,
      ),
      hasLength(1),
    );
  });

  test('月度原始输入指纹变化时新增月报修订，未变化时保持幂等', () async {
    await seedRecentlyClosedPeriodMetrics();
    String fingerprint = 'summary-a';
    final LocalReportGenerationCoordinator summaryCoordinator =
        LocalReportGenerationCoordinator(
      repository: repository,
      clock: () => now,
      monthlySummaryLoader: ({
        required String athleteProfileId,
        required DateTime monthStart,
      }) async =>
          MonthlySummary(
        monthStart: monthStart,
        previousMonthStart: DateTime(monthStart.year, monthStart.month - 1),
        inputFingerprint: fingerprint,
        dimensions: const <MonthlyDimensionSummary>[],
        bodyChanges: const <MonthlyMetricChange>[],
      ),
    );

    expect(
      await summaryCoordinator.ensureRecentlyClosedPeriods(
        athleteProfileId: athleteProfileId,
      ),
      2,
    );
    expect(
      await summaryCoordinator.ensureRecentlyClosedPeriods(
        athleteProfileId: athleteProfileId,
      ),
      0,
    );
    fingerprint = 'summary-b';
    now = DateTime(2026, 7, 15, 11);
    expect(
      await summaryCoordinator.ensureRecentlyClosedPeriods(
        athleteProfileId: athleteProfileId,
      ),
      1,
    );
    final List<ReportRevision> monthlyReports =
        await repository.listReportRevisions(
      athleteProfileId: athleteProfileId,
      period: MetricPeriod.month,
      periodStart: previousMonthStart,
    );
    expect(monthlyReports, hasLength(2));
    expect(
      monthlyReports.first.monthlySummarySnapshot?.inputFingerprint,
      'summary-b',
    );
  });
}

MetricAggregate _aggregate({
  required String id,
  required MetricPeriod period,
  required DateTime periodStart,
  required DateTime computedAt,
  required String metricCode,
  required double value,
  required String unit,
}) {
  return MetricAggregate(
    id: id,
    athleteProfileId: 'athlete-1',
    metricCode: metricCode,
    period: period,
    periodStart: periodStart,
    value: value,
    unit: unit,
    sampleCount: 4,
    sampleDurationSeconds: 3600,
    coverage: 1,
    status: MetricStatus.ready,
    algorithmVersion: 'test-metric-v1',
    inputFingerprint: 'fingerprint:$id:${computedAt.toIso8601String()}',
    computedAt: computedAt,
  );
}
