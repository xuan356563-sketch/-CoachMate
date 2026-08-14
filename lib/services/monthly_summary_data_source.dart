import '../data/models/monthly_summary.dart';
import '../data/repositories/body_metric_repository.dart';
import '../data/repositories/health_snapshot_repository.dart';
import '../data/repositories/training_metrics_repository.dart';
import '../data/repositories/weekly_report_repository.dart';
import 'monthly_summary_builder.dart';

/// 汇集月报所需的设备内数据，不执行网络请求，也不修改任何训练记录。
class MonthlySummaryDataSource {
  const MonthlySummaryDataSource({
    required TrainingMetricsRepository trainingMetricsRepository,
    required BodyMetricRepository bodyMetricRepository,
    required HealthSnapshotRepository healthSnapshotRepository,
    required WeeklyReportRepository weeklyReportRepository,
    MonthlySummaryBuilder builder = const MonthlySummaryBuilder(),
  })  : _trainingMetricsRepository = trainingMetricsRepository,
        _bodyMetricRepository = bodyMetricRepository,
        _healthSnapshotRepository = healthSnapshotRepository,
        _weeklyReportRepository = weeklyReportRepository,
        _builder = builder;

  final TrainingMetricsRepository _trainingMetricsRepository;
  final BodyMetricRepository _bodyMetricRepository;
  final HealthSnapshotRepository _healthSnapshotRepository;
  final WeeklyReportRepository _weeklyReportRepository;
  final MonthlySummaryBuilder _builder;

  Future<MonthlySummary> load({
    required String athleteProfileId,
    required DateTime monthStart,
  }) async {
    final metrics = await _trainingMetricsRepository.listAggregates(
      athleteProfileId: athleteProfileId,
    );
    return _builder.build(
      athleteProfileId: athleteProfileId,
      monthStart: monthStart,
      metricHistory: metrics,
      bodyMetrics: _bodyMetricRepository.listMetrics(),
      healthSnapshots: _healthSnapshotRepository.listSnapshots(
        athleteId: athleteProfileId,
      ),
      weeklyReports: _weeklyReportRepository.listReports(),
    );
  }
}
