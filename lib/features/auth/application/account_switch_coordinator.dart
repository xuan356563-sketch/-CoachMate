import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_center/application/ai_artifact_controller.dart';
import '../../data_center/application/body_metric_controller.dart';
import '../../data_center/application/body_metric_export_controller.dart';
import '../../dashboard/training_mvp_controller.dart';
import '../../daily_adjustment/application/daily_adjustment_controller.dart';
import '../../growth/application/growth_evidence_controller.dart';
import '../../growth/application/run_context_controller.dart';
import '../../growth/application/strength_primary_exercise_controller.dart';
import '../../growth/application/training_metrics_provider.dart';
import '../../meal_guide/application/meal_preference_controller.dart';
import '../../profile/application/achievement_controller.dart';
import '../../profile/application/health_sync_controller.dart';
import '../../profile/application/training_schedule_controller.dart';
import '../../profile/application/user_profile_controller.dart';
import '../../reminders/application/reminder_settings_controller.dart';
import '../../training_log/application/training_log_controller.dart';
import '../../training_plan/application/adjustment_proposal_controller.dart';
import '../../training_plan/application/four_week_plan_controller.dart';
import '../../training_plan/application/plan_adjustment_controller.dart';
import '../../training_plan/application/plan_revision_controller.dart';
import '../../training_plan/application/training_plan_generation_controller.dart';
import '../../workout_player/application/workout_player_assist_controller.dart';
import 'auth_controller.dart';

final accountSwitchCoordinatorProvider = Provider<AccountSwitchCoordinator>(
  (Ref ref) => AccountSwitchCoordinator(
    clearPendingHealthQueue: () =>
        ref.read(healthDataGatewayProvider).clearPendingBatches(
              athleteId: ref.read(userProfileControllerProvider).profile.id,
            ),
    confirmDatabaseAccountSwitch: () =>
        ref.read(authControllerProvider.notifier).confirmAccountSwitch(),
    isScopeAlreadyReplaced: () => switch (ref.read(authControllerProvider)) {
      AsyncData<AuthState>(:final value) => value.accountScopeReplaced,
      _ => false,
    },
    resetInMemoryState: () {
      ref.invalidate(healthSyncControllerProvider);
      ref.invalidate(bodyMetricRepositoryProvider);
      ref.invalidate(dailyCheckInRepositoryProvider);
      ref.invalidate(bodyMetricControllerProvider);
      ref.invalidate(bodyMetricExportRepositoryProvider);
      ref.invalidate(bodyMetricExportControllerProvider);
      ref.invalidate(bodyMetricExportTextProvider);
      ref.invalidate(bodyMetricExportPackageStatusProvider);
      ref.invalidate(growthEvidenceControllerProvider);
      ref.invalidate(growthMetricsControllerProvider);
      ref.invalidate(trainingMetricAggregatesProvider);
      ref.invalidate(trainingReportRevisionsProvider);
      ref.invalidate(pendingRunContextReviewsProvider);
      ref.invalidate(strengthExerciseOptionsProvider);
      ref.invalidate(achievementRecordRepositoryProvider);
      ref.invalidate(achievementControllerProvider);
      ref.invalidate(userProfileControllerProvider);
      ref.invalidate(trainingLogRepositoryProvider);
      ref.invalidate(trainingLogControllerProvider);
      ref.invalidate(planAdjustmentControllerProvider);
      ref.invalidate(acwrAdjustmentProposalControllerProvider);
      // 先丢弃 AI 产物和生成页恢复状态，避免旧账号处方在新账号同步时被合并。
      ref.invalidate(trainingPlanGenerationControllerProvider);
      ref.invalidate(planRevisionControllerProvider);
      ref.invalidate(aiArtifactControllerProvider);
      ref.invalidate(fourWeekPlanControllerProvider);
      ref.invalidate(trainingScheduleControllerProvider);
      ref.invalidate(dailyAdjustmentControllerProvider);
      ref.invalidate(reminderSettingsControllerProvider);
      ref.invalidate(mealPreferenceControllerProvider);
      ref.invalidate(workoutPlayerAssistControllerProvider);
      // 依赖控制器全部失效后再重建聚合主状态，避免短暂回显旧账号数据。
      ref.invalidate(trainingMvpProvider);
    },
  ),
);

/// 协调跨 SQLite 与 Swift 队列的账号切换清理顺序。
///
/// Swift 队列无法加入 SQLite 事务，因此先清理可安全重建的待处理队列，
/// 再执行数据库原子清理与换绑。任一步失败都会阻止后续步骤。
class AccountSwitchCoordinator {
  const AccountSwitchCoordinator({
    required this.clearPendingHealthQueue,
    required this.confirmDatabaseAccountSwitch,
    required this.isScopeAlreadyReplaced,
    required this.resetInMemoryState,
  });

  final Future<void> Function() clearPendingHealthQueue;
  final Future<bool> Function() confirmDatabaseAccountSwitch;
  final bool Function() isScopeAlreadyReplaced;
  final void Function() resetInMemoryState;

  Future<void> confirm() async {
    final bool scopeAlreadyReplaced = isScopeAlreadyReplaced();
    if (!scopeAlreadyReplaced) {
      // Swift 队列可从 HealthKit 重建，先清队列可避免旧账号批次在换绑后重放。
      await clearPendingHealthQueue();
    }
    final bool switched = await confirmDatabaseAccountSwitch();
    if (!switched) {
      if (isScopeAlreadyReplaced()) {
        throw StateError('本地账号数据已切换，新账号功能装配待恢复。重试不会再次清理数据。');
      }
      throw StateError('本地业务数据原子清理失败，账号尚未切换。');
    }
    resetInMemoryState();
  }
}
