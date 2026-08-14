import '../../../data/models/monthly_summary.dart';
import '../../../data/models/training_metrics.dart';
import '../../../data/repositories/training_metrics_repository.dart';
import '../../../services/growth_narrative_builder.dart';

class GrowthMetricsState {
  const GrowthMetricsState({
    required this.status,
    required this.metrics,
    required this.reports,
    required this.athleteProfileId,
    required this.period,
    required this.periodStart,
    required this.message,
  });

  const GrowthMetricsState.initial()
      : status = MetricStatus.unavailable,
        metrics = const <MetricAggregate>[],
        reports = const <ReportRevision>[],
        athleteProfileId = null,
        period = null,
        periodStart = null,
        message = '尚未加载成长指标。';

  final MetricStatus status;
  final List<MetricAggregate> metrics;
  final List<ReportRevision> reports;
  final String? athleteProfileId;
  final MetricPeriod? period;
  final DateTime? periodStart;
  final String message;
}

/// 成长指标应用层边界，不直接访问 SQLite，也不修改训练计划。
class GrowthMetricsController {
  GrowthMetricsController({
    required TrainingMetricsRepository repository,
    required GrowthNarrativeBuilder narrativeBuilder,
    DateTime Function()? clock,
  })  : _repository = repository,
        _narrativeBuilder = narrativeBuilder,
        _clock = clock ?? DateTime.now;

  static const String narrativeAlgorithmVersion =
      'trainmate-local-narrative-v1';

  final TrainingMetricsRepository _repository;
  final GrowthNarrativeBuilder _narrativeBuilder;
  final DateTime Function() _clock;
  GrowthMetricsState _state = const GrowthMetricsState.initial();

  GrowthMetricsState get state => _state;

  Future<void> loadPeriod({
    required String athleteProfileId,
    required MetricPeriod period,
    required DateTime periodStart,
  }) async {
    try {
      final List<MetricAggregate> metrics = await _repository.listAggregates(
        athleteProfileId: athleteProfileId,
        period: period,
        periodStart: periodStart,
      );
      final List<ReportRevision> reports =
          await _repository.listReportRevisions(
        athleteProfileId: athleteProfileId,
        period: period,
        periodStart: periodStart,
      );
      _state = GrowthMetricsState(
        status: metrics.isEmpty ? MetricStatus.unavailable : MetricStatus.ready,
        metrics: metrics,
        reports: reports,
        athleteProfileId: athleteProfileId,
        period: period,
        periodStart: periodStart,
        message: metrics.isEmpty ? '当前周期暂无可用指标。' : '成长指标已更新。',
      );
    } on Object catch (error) {
      _state = GrowthMetricsState(
        status: MetricStatus.failed,
        metrics: const <MetricAggregate>[],
        reports: const <ReportRevision>[],
        athleteProfileId: athleteProfileId,
        period: period,
        periodStart: periodStart,
        message: '成长指标加载失败：$error',
      );
      rethrow;
    }
  }

  Future<List<String>> invalidateBySource({
    required String sourceType,
    required String sourceId,
  }) async {
    final String? athleteProfileId = _state.athleteProfileId;
    if (athleteProfileId == null) {
      throw StateError('请先加载运动员的成长指标。');
    }
    final List<String> affected = await _repository.invalidateBySource(
      athleteProfileId: athleteProfileId,
      sourceType: sourceType,
      sourceId: sourceId,
      invalidatedAt: _clock(),
    );
    final MetricPeriod? period = _state.period;
    final DateTime? periodStart = _state.periodStart;
    if (period != null && periodStart != null) {
      await loadPeriod(
        athleteProfileId: athleteProfileId,
        period: period,
        periodStart: periodStart,
      );
    }
    return affected;
  }

  Future<ReportRevision> generateWeeklyReport({
    AcwrResult? acwr,
    AdjustmentProposal? proposal,
  }) {
    return _generateReport(
      expectedPeriod: MetricPeriod.week,
      buildNarrative: (List<MetricAggregate> metrics) =>
          _narrativeBuilder.buildWeeklyReport(
        metrics: metrics,
        acwr: acwr,
        proposal: proposal,
      ),
    );
  }

  Future<ReportRevision> generateMonthlyReport({
    SevenDayBodyAverageResult? bodyAverage,
    DeviceBestSegment? bestSegment,
    MonthlySummary? monthlySummary,
  }) {
    return _generateReport(
      expectedPeriod: MetricPeriod.month,
      monthlySummarySnapshot: monthlySummary,
      buildNarrative: (List<MetricAggregate> metrics) =>
          _narrativeBuilder.buildMonthlyReport(
        metrics: metrics,
        bodyAverage: bodyAverage,
        bestSegment: bestSegment,
        monthlySummary: monthlySummary,
      ),
    );
  }

  Future<ReportRevision> _generateReport({
    required MetricPeriod expectedPeriod,
    required String Function(List<MetricAggregate> metrics) buildNarrative,
    MonthlySummary? monthlySummarySnapshot,
  }) async {
    final String? athleteProfileId = _state.athleteProfileId;
    final MetricPeriod? period = _state.period;
    final DateTime? periodStart = _state.periodStart;
    if (athleteProfileId == null || period == null || periodStart == null) {
      throw StateError('请先加载需要生成报告的指标周期。');
    }
    if (period != expectedPeriod) {
      throw StateError('当前加载周期与要生成的报告类型不一致。');
    }
    final List<MetricAggregate> usableMetrics = _state.metrics
        .where(
          (MetricAggregate item) => item.status != MetricStatus.invalidated,
        )
        .toList();
    if (usableMetrics.isEmpty) {
      throw StateError('指标仍在积累，不能生成空报告修订。');
    }
    final List<ReportRevision> existing = await _repository.listReportRevisions(
      athleteProfileId: athleteProfileId,
      period: period,
      periodStart: periodStart,
    );
    final int revision = existing.isEmpty ? 1 : existing.first.revision + 1;
    final ReportRevision? previous = existing.isEmpty ? null : existing.first;
    final ReportRevision report = ReportRevision(
      id: 'report:$athleteProfileId:${period.name}:${_dateKey(periodStart)}:r$revision',
      athleteProfileId: athleteProfileId,
      period: period,
      periodStart: periodStart,
      revision: revision,
      generatedAt: _clock(),
      metricIds: List<String>.unmodifiable(
        usableMetrics.map((MetricAggregate item) => item.id),
      ),
      metricSnapshots: List<ReportMetricSnapshot>.unmodifiable(
        usableMetrics.map(ReportMetricSnapshot.fromAggregate),
      ),
      narrative: buildNarrative(usableMetrics),
      algorithmVersion: narrativeAlgorithmVersion,
      previousRevisionId: previous?.id,
      monthlySummarySnapshot: monthlySummarySnapshot,
    );
    await _repository.saveReportRevision(report);
    final List<ReportRevision> updated = <ReportRevision>[report, ...existing];
    _state = GrowthMetricsState(
      status: _state.status,
      metrics: _state.metrics,
      reports: List<ReportRevision>.unmodifiable(updated),
      athleteProfileId: athleteProfileId,
      period: period,
      periodStart: periodStart,
      message: '已生成第 $revision 版本地确定性报告。',
    );
    return report;
  }
}

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
