import '../data/models/monthly_summary.dart';
import '../data/models/training_metrics.dart';
import '../data/repositories/training_metrics_repository.dart';
import '../features/growth/application/growth_metrics_controller.dart';
import 'growth_narrative_builder.dart';
import 'training_metrics_pipeline.dart';

typedef MonthlySummaryLoader = Future<MonthlySummary?> Function({
  required String athleteProfileId,
  required DateTime monthStart,
});

/// 在应用启动时幂等补齐最近结束周期的本地报告。
///
/// 只读取设备内结构化指标；相同指标版本已有报告时不会重复生成修订。
class LocalReportGenerationCoordinator {
  LocalReportGenerationCoordinator({
    required TrainingMetricsRepository repository,
    TrainingMetricsPipeline? metricsPipeline,
    MonthlySummaryLoader? monthlySummaryLoader,
    DateTime Function()? clock,
  })  : _repository = repository,
        _metricsPipeline = metricsPipeline,
        _monthlySummaryLoader = monthlySummaryLoader,
        _clock = clock ?? DateTime.now;

  final TrainingMetricsRepository _repository;
  final TrainingMetricsPipeline? _metricsPipeline;
  final MonthlySummaryLoader? _monthlySummaryLoader;
  final DateTime Function() _clock;

  Future<int> ensureRecentlyClosedPeriods({
    required String athleteProfileId,
  }) async {
    if (athleteProfileId.isEmpty) {
      throw ArgumentError.value(
          athleteProfileId, 'athleteProfileId', '运动员标识不能为空。');
    }
    final DateTime now = _localDate(_clock());
    final DateTime currentWeekStart = now.subtract(
      Duration(days: now.weekday - DateTime.monday),
    );
    final DateTime previousWeekStart = currentWeekStart.subtract(
      const Duration(days: 7),
    );
    final DateTime currentMonthStart = DateTime(now.year, now.month);
    final DateTime previousMonthLastDay = currentMonthStart.subtract(
      const Duration(days: 1),
    );
    final DateTime previousMonthStart = DateTime(
      previousMonthLastDay.year,
      previousMonthLastDay.month,
    );

    int generated = 0;
    if (await _ensurePeriod(
      athleteProfileId: athleteProfileId,
      period: MetricPeriod.week,
      periodStart: previousWeekStart,
    )) {
      generated += 1;
    }
    if (await _ensurePeriod(
      athleteProfileId: athleteProfileId,
      period: MetricPeriod.month,
      periodStart: previousMonthStart,
    )) {
      generated += 1;
    }
    return generated;
  }

  /// 为已经结束的指定周期补齐报告；活动中的周期不会提前生成。
  Future<bool> ensureClosedPeriod({
    required String athleteProfileId,
    required MetricPeriod period,
    required DateTime periodStart,
  }) {
    final DateTime normalizedStart = period == MetricPeriod.week
        ? _localDate(periodStart).subtract(
            Duration(days: periodStart.weekday - DateTime.monday),
          )
        : DateTime(periodStart.year, periodStart.month);
    final DateTime endExclusive = period == MetricPeriod.week
        ? normalizedStart.add(const Duration(days: 7))
        : DateTime(normalizedStart.year, normalizedStart.month + 1);
    if (endExclusive.isAfter(_clock())) return Future<bool>.value(false);
    return _ensurePeriod(
      athleteProfileId: athleteProfileId,
      period: period,
      periodStart: normalizedStart,
    );
  }

  Future<bool> _ensurePeriod({
    required String athleteProfileId,
    required MetricPeriod period,
    required DateTime periodStart,
  }) async {
    List<MetricAggregate> metrics = await _repository.listAggregates(
      athleteProfileId: athleteProfileId,
      period: period,
      periodStart: periodStart,
    );
    final TrainingMetricsPipeline? metricsPipeline = _metricsPipeline;
    if (metrics.isEmpty && metricsPipeline != null) {
      await metricsPipeline.aggregatePeriod(
        athleteProfileId: athleteProfileId,
        period: period,
        periodStart: periodStart,
      );
      metrics = await _repository.listAggregates(
        athleteProfileId: athleteProfileId,
        period: period,
        periodStart: periodStart,
      );
    }
    final List<MetricAggregate> usable = metrics
        .where(
            (MetricAggregate item) => item.status != MetricStatus.invalidated)
        .toList(growable: false);
    if (usable.isEmpty) return false;

    final List<ReportRevision> reports = await _repository.listReportRevisions(
      athleteProfileId: athleteProfileId,
      period: period,
      periodStart: periodStart,
    );
    final MonthlySummary? monthlySummary =
        period == MetricPeriod.month && _monthlySummaryLoader != null
            ? await _monthlySummaryLoader!(
                athleteProfileId: athleteProfileId,
                monthStart: periodStart,
              )
            : null;
    if (_latestReportStillMatches(reports, usable, monthlySummary)) {
      return false;
    }

    final GrowthMetricsController controller = GrowthMetricsController(
      repository: _repository,
      narrativeBuilder: const GrowthNarrativeBuilder(),
      clock: _clock,
    );
    await controller.loadPeriod(
      athleteProfileId: athleteProfileId,
      period: period,
      periodStart: periodStart,
    );
    if (period == MetricPeriod.week) {
      await controller.generateWeeklyReport();
    } else {
      await controller.generateMonthlyReport(monthlySummary: monthlySummary);
    }
    return true;
  }

  bool _latestReportStillMatches(
    List<ReportRevision> reports,
    List<MetricAggregate> metrics,
    MonthlySummary? monthlySummary,
  ) {
    if (reports.isEmpty) return false;
    final ReportRevision latest = reports.first;
    DateTime latestMetricTime = metrics.first.computedAt;
    for (final MetricAggregate metric in metrics.skip(1)) {
      if (metric.computedAt.isAfter(latestMetricTime)) {
        latestMetricTime = metric.computedAt;
      }
    }
    final Set<String> currentIds =
        metrics.map((MetricAggregate item) => item.id).toSet();
    final bool sameMonthlyInput = monthlySummary == null ||
        latest.monthlySummarySnapshot?.inputFingerprint ==
            monthlySummary.inputFingerprint;
    return sameMonthlyInput &&
        !latest.generatedAt.isBefore(latestMetricTime) &&
        latest.metricIds.toSet().containsAll(currentIds) &&
        currentIds.containsAll(latest.metricIds);
  }

  DateTime _localDate(DateTime value) => DateTime(
        value.year,
        value.month,
        value.day,
      );
}
