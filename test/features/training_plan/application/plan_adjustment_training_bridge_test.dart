import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(updated.knowledgeSearchQuery, before.knowledgeSearchQuery);

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
    expect(updated.knowledgeSearchQuery, before.knowledgeSearchQuery);
  });
}
