import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/local_storage_service.dart';
import '../../../data/repositories/weekly_report_repository.dart';
import '../../dashboard/training_mvp_controller.dart';
import '../../data_center/application/body_metric_controller.dart';
import '../../growth/application/growth_evidence_controller.dart';
import '../../growth/application/run_context_controller.dart';
import '../../growth/application/strength_primary_exercise_controller.dart';
import '../../growth/application/training_metrics_provider.dart';
import '../../training_plan/application/adjustment_proposal_controller.dart';
import '../../training_plan/application/plan_adjustment_controller.dart';
import 'achievement_controller.dart';
import 'health_sync_controller.dart';
import 'user_profile_controller.dart';

final healthDataDeletionCoordinatorProvider =
    Provider<HealthDataDeletionCoordinator>(
  (Ref ref) => HealthDataDeletionCoordinator(
    currentAthleteId: () => ref.read(userProfileControllerProvider).profile.id,
    clearHealthFactsAndQueue: () async {
      await ref.read(healthSyncControllerProvider.future);
      await ref.read(healthSyncControllerProvider.notifier).clearAthleteData();
    },
    clearBodyMetrics: () =>
        ref.read(bodyMetricControllerProvider.notifier).clear(),
    clearGrowthData: (String athleteProfileId) =>
        ref.read(growthEvidenceControllerProvider.notifier).clearAthleteData(
              athleteProfileId: athleteProfileId,
              persistenceAlreadyCleared:
                  ref.read(healthSyncStructuredDatabaseGatewayProvider) != null,
            ),
    clearHealthDerivedPlanAdjustments: () => ref
        .read(planAdjustmentControllerProvider.notifier)
        .clearHealthDerivedAdjustments(),
    clearCompatibilityReportsAndBadges: () {
      PersistedWeeklyReportRepository(
        ref.read(localStorageServiceProvider),
      ).clearReports();
      ref.read(achievementRecordRepositoryProvider).clearRecords();
    },
    flushStorage: () => ref.read(localStorageServiceProvider).flush(),
    resetDerivedState: () {
      ref.invalidate(trainingMetricAggregatesProvider);
      ref.invalidate(trainingReportRevisionsProvider);
      ref.invalidate(pendingRunContextReviewsProvider);
      ref.invalidate(strengthExerciseOptionsProvider);
      ref.invalidate(acwrAdjustmentProposalControllerProvider);
      ref.invalidate(planAdjustmentControllerProvider);
      ref.invalidate(growthMetricsControllerProvider);
      ref.invalidate(achievementRecordRepositoryProvider);
      ref.invalidate(achievementControllerProvider);
      ref.invalidate(trainingMvpProvider);
    },
  ),
);

/// 统一清理本机健康数据及其派生状态。
///
/// SQLite 内的事实、指标、报告、成长证据、锚点和调整记录由健康同步控制器
/// 在一个结构化事务中清理；随后清空仍驻留内存的兼容身体与成长状态。
class HealthDataDeletionCoordinator {
  const HealthDataDeletionCoordinator({
    required this.currentAthleteId,
    required this.clearHealthFactsAndQueue,
    required this.clearBodyMetrics,
    required this.clearGrowthData,
    required this.clearHealthDerivedPlanAdjustments,
    required this.clearCompatibilityReportsAndBadges,
    required this.flushStorage,
    required this.resetDerivedState,
  });

  final String Function() currentAthleteId;
  final Future<void> Function() clearHealthFactsAndQueue;
  final Future<void> Function() clearBodyMetrics;
  final Future<void> Function(String athleteProfileId) clearGrowthData;
  final void Function() clearHealthDerivedPlanAdjustments;
  final void Function() clearCompatibilityReportsAndBadges;
  final Future<void> Function() flushStorage;
  final void Function() resetDerivedState;

  Future<void> clearCurrentAthleteData() async {
    final String athleteProfileId = currentAthleteId();
    if (athleteProfileId.isEmpty) {
      throw StateError('当前运动员标识为空，无法安全清理本地健康数据。');
    }
    await clearHealthFactsAndQueue();
    await clearBodyMetrics();
    await clearGrowthData(athleteProfileId);
    clearHealthDerivedPlanAdjustments();
    clearCompatibilityReportsAndBadges();
    await flushStorage();
    resetDerivedState();
  }
}
