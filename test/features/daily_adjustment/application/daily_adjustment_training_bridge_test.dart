import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/daily_adjustment.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/daily_adjustment/application/daily_adjustment_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('每日调整控制器同步旧训练状态并保留跟练会话', () async {
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
    final TrainingMvpState sessionState = container.read(trainingMvpProvider);
    final DailyAdjustmentController dailyController =
        container.read(dailyAdjustmentControllerProvider.notifier);

    dailyController.setDailyAvailableMinutes(20);
    dailyController.setDailyWorkStress(WorkStressLevel.high);
    dailyController.setDailyTrainingEnvironment(TrainingEnvironment.home);
    dailyController.setDailyWeather(WeatherCondition.rain);
    await Future<void>.delayed(Duration.zero);

    TrainingMvpState state = container.read(trainingMvpProvider);
    expect(state.dailyAvailableMinutesOverride, 20);
    expect(state.dailyWorkStress, WorkStressLevel.high);
    expect(state.dailyTrainingEnvironment, TrainingEnvironment.home);
    expect(state.dailyWeather, WeatherCondition.rain);
    expect(state.dailyAdjustmentDecision.availableMinutes, 20);
    expect(state.dailyAdjustmentDecision.workStress, WorkStressLevel.high);
    expect(state.dailyAdjustmentDecision.environment, TrainingEnvironment.home);
    expect(state.dailyAdjustmentDecision.weather, WeatherCondition.rain);

    dailyController.applyDailyAdjustmentDecision(state.dailyAdjustmentDecision);
    await Future<void>.delayed(Duration.zero);

    state = container.read(trainingMvpProvider);
    expect(
      state.dailyAdjustmentStatusMessage,
      container.read(dailyAdjustmentControllerProvider).statusMessage,
    );
    expect(state.dailyAdjustmentDecision.availableMinutes, 20);
    expect(state.dailyAdjustmentDecision.workStress, WorkStressLevel.high);
    expect(
        state.activeWorkoutPlayerDayId, sessionState.activeWorkoutPlayerDayId);
    expect(state.workoutPlayerStepIndex, sessionState.workoutPlayerStepIndex);
    expect(state.workoutPlayerEvents, sessionState.workoutPlayerEvents);
    expect(state.logs, sessionState.logs);
    expect(state.knowledgeSearchQuery, sessionState.knowledgeSearchQuery);
  });
}
