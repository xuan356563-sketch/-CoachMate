import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/training_metrics.dart';
import '../../../data/repositories/health_snapshot_repository.dart';
import '../../../data/repositories/training_metrics_repository.dart';
import '../../../data/repositories/weekly_report_repository.dart';
import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import '../../../services/growth_narrative_builder.dart';
import '../../../services/local_report_generation_coordinator.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/monthly_summary_data_source.dart';
import '../../data_center/application/body_metric_controller.dart';
import 'growth_metrics_controller.dart';
import 'training_metrics_projection_service.dart';

/// 默认使用内存实现；应用启动层可覆盖为 SQLite 仓储。
final trainingMetricsRepositoryProvider = Provider<TrainingMetricsRepository>(
  (Ref ref) => InMemoryTrainingMetricsRepository(),
);

final trainingMetricsProjectionServiceProvider =
    Provider<TrainingMetricsProjectionService>(
  (Ref ref) => const TrainingMetricsProjectionService(),
);

final growthMetricsControllerProvider = Provider<GrowthMetricsController>(
  (Ref ref) {
    final GrowthMetricsController controller = GrowthMetricsController(
      repository: ref.watch(trainingMetricsRepositoryProvider),
      narrativeBuilder: const GrowthNarrativeBuilder(),
      featureAccess: ref.watch(featureAccessProvider),
    );
    bindFeatureController(ref, 'feature.growth', 'metrics', controller);
    bindFeatureController(
      ref,
      'feature.weekly_report',
      'reportGenerator',
      controller,
    );
    return controller;
  },
);

final monthlySummaryLoaderProvider = Provider<MonthlySummaryLoader>(
  (Ref ref) {
    final LocalStorageService storage = ref.watch(localStorageServiceProvider);
    final MonthlySummaryDataSource source = MonthlySummaryDataSource(
      trainingMetricsRepository: ref.watch(trainingMetricsRepositoryProvider),
      bodyMetricRepository: ref.watch(bodyMetricRepositoryProvider),
      healthSnapshotRepository: HealthSnapshotRepository(storage),
      weeklyReportRepository: PersistedWeeklyReportRepository(storage),
    );
    return ({
      required String athleteProfileId,
      required DateTime monthStart,
    }) =>
        source.load(
          athleteProfileId: athleteProfileId,
          monthStart: monthStart,
        );
  },
);

class TrainingMetricsQuery {
  const TrainingMetricsQuery({
    required this.athleteProfileId,
    this.period,
    this.periodStart,
    this.includeInvalidated = false,
  });

  final String athleteProfileId;
  final MetricPeriod? period;
  final DateTime? periodStart;
  final bool includeInvalidated;

  @override
  bool operator ==(Object other) {
    return other is TrainingMetricsQuery &&
        other.athleteProfileId == athleteProfileId &&
        other.period == period &&
        _sameDateTime(other.periodStart, periodStart) &&
        other.includeInvalidated == includeInvalidated;
  }

  @override
  int get hashCode => Object.hash(
        athleteProfileId,
        period,
        periodStart?.toUtc().microsecondsSinceEpoch,
        includeInvalidated,
      );
}

class TrainingReportQuery {
  const TrainingReportQuery({
    required this.athleteProfileId,
    required this.period,
    required this.periodStart,
  });

  final String athleteProfileId;
  final MetricPeriod period;
  final DateTime periodStart;

  @override
  bool operator ==(Object other) {
    return other is TrainingReportQuery &&
        other.athleteProfileId == athleteProfileId &&
        other.period == period &&
        _sameDateTime(other.periodStart, periodStart);
  }

  @override
  int get hashCode => Object.hash(
        athleteProfileId,
        period,
        periodStart.toUtc().microsecondsSinceEpoch,
      );
}

final trainingMetricAggregatesProvider =
    FutureProvider.family<List<MetricAggregate>, TrainingMetricsQuery>(
  (Ref ref, TrainingMetricsQuery query) {
    return ref.watch(trainingMetricsRepositoryProvider).listAggregates(
          athleteProfileId: query.athleteProfileId,
          period: query.period,
          periodStart: query.periodStart,
          includeInvalidated: query.includeInvalidated,
        );
  },
);

final trainingReportRevisionsProvider =
    FutureProvider.family<List<ReportRevision>, TrainingReportQuery>(
  (Ref ref, TrainingReportQuery query) {
    return ref.watch(trainingMetricsRepositoryProvider).listReportRevisions(
          athleteProfileId: query.athleteProfileId,
          period: query.period,
          periodStart: query.periodStart,
        );
  },
);

bool _sameDateTime(DateTime? first, DateTime? second) {
  if (first == null || second == null) return first == second;
  return first.toUtc().microsecondsSinceEpoch ==
      second.toUtc().microsecondsSinceEpoch;
}

String resolveTrainingMetricsAthleteProfileId({
  required String growthEvidenceAthleteProfileId,
  required String profileAthleteProfileId,
}) {
  return growthEvidenceAthleteProfileId.isNotEmpty
      ? growthEvidenceAthleteProfileId
      : profileAthleteProfileId;
}
