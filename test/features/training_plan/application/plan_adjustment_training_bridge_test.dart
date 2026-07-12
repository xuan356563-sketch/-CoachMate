import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_rule_audit.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/plan_adjustment_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('计划调整控制器同步旧训练状态并保留跟练会话与知识查询', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    final TrainingMvpController trainingController =
        container.read(trainingMvpProvider.notifier);
    trainingController.startWorkoutPlayer(workoutDayId: 'workout-week1-day2');
    trainingController.completeWorkoutPlayerStep();
    trainingController.setKnowledgeSearchQuery('跑步');
    final TrainingMvpState before = container.read(trainingMvpProvider);
    final TrainingRuleAuditReport beforeAudit =
        before.activePlanRuleAuditReport;
    final WorkoutDay workout = before.todayWorkout;

    container
        .read(planAdjustmentControllerProvider.notifier)
        .saveManualAdjustment(
          workout: workout,
          adjustedMinutes: 20,
          adjustedIntensity: '恢复',
          reason: '今日疲劳',
        );
    await Future<void>.delayed(Duration.zero);

    TrainingMvpState updated = container.read(trainingMvpProvider);
    expect(updated.todayWorkout.estimatedMinutes, 20);
    expect(updated.todayWorkout.intensity, '恢复');
    expect(updated.latestPlanAdjustmentFor(workout.id)?.isActive, isTrue);
    expect(updated.activeWorkoutPlayerDayId, before.activeWorkoutPlayerDayId);
    expect(updated.workoutPlayerStepIndex, before.workoutPlayerStepIndex);
    expect(updated.workoutPlayerEvents, before.workoutPlayerEvents);
    expect(updated.logs, before.logs);
    expect(updated.knowledgeSearchQuery, before.knowledgeSearchQuery);
    _expectSameRuleAudit(updated.activePlanRuleAuditReport, beforeAudit);

    container
        .read(planAdjustmentControllerProvider.notifier)
        .restoreOriginalPlan(updated.todayWorkout);
    await Future<void>.delayed(Duration.zero);

    updated = container.read(trainingMvpProvider);
    expect(updated.todayWorkout.estimatedMinutes, workout.estimatedMinutes);
    expect(updated.todayWorkout.intensity, workout.intensity);
    expect(updated.latestPlanAdjustmentFor(workout.id)?.isActive, isFalse);
    expect(updated.activeWorkoutPlayerDayId, before.activeWorkoutPlayerDayId);
    expect(updated.workoutPlayerStepIndex, before.workoutPlayerStepIndex);
    expect(updated.workoutPlayerEvents, before.workoutPlayerEvents);
    expect(updated.logs, before.logs);
    expect(updated.knowledgeSearchQuery, before.knowledgeSearchQuery);
    _expectSameRuleAudit(updated.activePlanRuleAuditReport, beforeAudit);
  });

  test('重启后训练状态会投影已持久化的计划调整', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer firstContainer = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    final TrainingMvpState initial = firstContainer.read(trainingMvpProvider);
    final WorkoutDay workout = initial.todayWorkout;

    firstContainer
        .read(planAdjustmentControllerProvider.notifier)
        .saveManualAdjustment(
          workout: workout,
          adjustedMinutes: 20,
          adjustedIntensity: '恢复',
          reason: '今日疲劳',
        );
    await Future<void>.delayed(Duration.zero);
    firstContainer.dispose();

    final ProviderContainer secondContainer = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(secondContainer.dispose);

    final TrainingMvpState restored = secondContainer.read(trainingMvpProvider);
    expect(restored.todayWorkout.id, workout.id);
    expect(restored.todayWorkout.estimatedMinutes, 20);
    expect(restored.todayWorkout.intensity, '恢复');
    expect(restored.latestPlanAdjustmentFor(workout.id)?.isActive, isTrue);
  });
}

void _expectSameRuleAudit(
  TrainingRuleAuditReport actual,
  TrainingRuleAuditReport expected,
) {
  expect(actual.planId, expected.planId);
  expect(actual.checkedWorkoutCount, expected.checkedWorkoutCount);
  expect(actual.citationCount, expected.citationCount);
  expect(actual.runningModuleCount, expected.runningModuleCount);
  expect(actual.maxEstimatedMinutes, expected.maxEstimatedMinutes);
  expect(actual.passCount, expected.passCount);
  expect(actual.warningCount, expected.warningCount);
  expect(actual.failCount, expected.failCount);
  expect(actual.statusLabel, expected.statusLabel);
}
