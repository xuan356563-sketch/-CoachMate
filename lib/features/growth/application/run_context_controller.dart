import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/trainmate_structured_database_gateway.dart';
import '../../../data/models/training_metrics.dart';
import '../../../services/local_report_generation_coordinator.dart';
import '../../../services/training_metrics_pipeline.dart';
import '../../profile/application/health_sync_controller.dart';
import 'training_metrics_provider.dart';

/// 一条仍需用户确认公路/越野场景的 HealthKit `.running` 事实。
class RunContextReviewItem {
  const RunContextReviewItem({
    required this.workoutId,
    required this.startedAt,
    required this.localDate,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.sourceBundleId,
    required this.sourceProductType,
  });

  factory RunContextReviewItem.fromRow(Map<String, Object?> row) {
    final String workoutId = row['id'] as String? ?? '';
    final DateTime? startedAt = DateTime.tryParse(
      row['started_at_utc'] as String? ?? '',
    );
    final DateTime? localDate = DateTime.tryParse(
      row['local_date'] as String? ?? '',
    );
    if (workoutId.isEmpty || startedAt == null || localDate == null) {
      throw const FormatException('待确认跑步事实缺少训练标识或日期。');
    }
    return RunContextReviewItem(
      workoutId: workoutId,
      startedAt: startedAt,
      localDate: DateTime(localDate.year, localDate.month, localDate.day),
      distanceMeters: _nonNegativeNumber(row['distance_meters']),
      durationSeconds: _nonNegativeNumber(
        row['active_duration_seconds'],
      ).round(),
      sourceBundleId: row['source_bundle_id'] as String? ?? '',
      sourceProductType: row['source_product_type'] as String? ?? '',
    );
  }

  final String workoutId;
  final DateTime startedAt;
  final DateTime localDate;
  final double distanceMeters;
  final int durationSeconds;
  final String sourceBundleId;
  final String sourceProductType;
}

final pendingRunContextReviewsProvider =
    FutureProvider.family<List<RunContextReviewItem>, String>(
  (Ref ref, String athleteProfileId) async {
    if (athleteProfileId.trim().isEmpty) return const <RunContextReviewItem>[];
    final TrainMateStructuredDatabaseGateway? structured =
        ref.watch(healthSyncStructuredDatabaseGatewayProvider);
    if (structured is! RunContextDatabaseGateway) {
      // Web 存储桩不会伪造 HealthKit 跑步分类能力。
      return const <RunContextReviewItem>[];
    }
    final RunContextDatabaseGateway database =
        structured as RunContextDatabaseGateway;
    final List<Map<String, Object?>> rows =
        await database.listRunningWorkoutsNeedingContext(
      athleteProfileId: athleteProfileId,
    );
    return List<RunContextReviewItem>.unmodifiable(
      rows.map(RunContextReviewItem.fromRow),
    );
  },
);

final runContextConfirmationServiceProvider =
    Provider<RunContextConfirmationService>(
  (Ref ref) => RunContextConfirmationService(
    database: ref.watch(healthSyncStructuredDatabaseGatewayProvider)
            is RunContextDatabaseGateway
        ? ref.watch(healthSyncStructuredDatabaseGatewayProvider)
            as RunContextDatabaseGateway
        : null,
    metricsPipeline: ref.watch(healthSyncMetricsPipelineProvider),
    reportCoordinator: LocalReportGenerationCoordinator(
      repository: ref.watch(trainingMetricsRepositoryProvider),
      metricsPipeline: ref.watch(healthSyncMetricsPipelineProvider),
      monthlySummaryLoader: ref.watch(monthlySummaryLoaderProvider),
    ),
  ),
);

/// 保存用户确认，并让受影响的训练、周/月指标和已结束周期报告重新计算。
class RunContextConfirmationService {
  const RunContextConfirmationService({
    required RunContextDatabaseGateway? database,
    required TrainingMetricsPipeline? metricsPipeline,
    required LocalReportGenerationCoordinator reportCoordinator,
    DateTime Function()? clock,
  })  : _database = database,
        _metricsPipeline = metricsPipeline,
        _reportCoordinator = reportCoordinator,
        _clock = clock ?? DateTime.now;

  final RunContextDatabaseGateway? _database;
  final TrainingMetricsPipeline? _metricsPipeline;
  final LocalReportGenerationCoordinator _reportCoordinator;
  final DateTime Function() _clock;

  Future<void> confirm({
    required String athleteProfileId,
    required String workoutId,
    required String runContext,
  }) async {
    final RunContextDatabaseGateway? structured = _database;
    if (structured == null) {
      throw StateError('当前设备不支持 HealthKit 跑步项目确认。');
    }
    await structured.confirmRunningWorkoutContext(
      athleteProfileId: athleteProfileId,
      workoutId: workoutId,
      runContext: runContext,
      confirmedAt: _clock(),
    );

    final TrainingMetricsPipeline? pipeline = _metricsPipeline;
    if (pipeline == null) return;
    try {
      final WorkoutAnalysisOutcome outcome = await pipeline.analyzeWorkout(
        athleteProfileId: athleteProfileId,
        workoutId: workoutId,
      );
      final DateTime weekStart = outcome.occurredOn.subtract(
        Duration(days: outcome.occurredOn.weekday - DateTime.monday),
      );
      final DateTime monthStart = DateTime(
        outcome.occurredOn.year,
        outcome.occurredOn.month,
      );
      for (final ({MetricPeriod period, DateTime start}) target in <({
        MetricPeriod period,
        DateTime start,
      })>[
        (period: MetricPeriod.week, start: weekStart),
        (period: MetricPeriod.month, start: monthStart),
      ]) {
        await pipeline.aggregatePeriod(
          athleteProfileId: athleteProfileId,
          period: target.period,
          periodStart: target.start,
        );
        await _reportCoordinator.ensureClosedPeriod(
          athleteProfileId: athleteProfileId,
          period: target.period,
          periodStart: target.start,
        );
      }
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        const RunContextRecalculationException(),
        stackTrace,
      );
    }
  }
}

/// 场景事实已经安全保存，但派生指标尚未完成重算。
class RunContextRecalculationException implements Exception {
  const RunContextRecalculationException();

  String get message => '跑步项目已保存，但指标重算失败；旧指标保持失效状态，请稍后重试同步。';

  @override
  String toString() => message;
}

double _nonNegativeNumber(Object? value) {
  if (value is! num || !value.isFinite || value < 0) return 0;
  return value.toDouble();
}
