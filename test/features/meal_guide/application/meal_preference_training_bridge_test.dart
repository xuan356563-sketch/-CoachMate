import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/meal_guide.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/meal_guide/application/meal_preference_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('照吃偏好控制器同步照吃卡和建议并保留跟练会话', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final TrainingMvpController training =
        container.read(trainingMvpProvider.notifier);
    training.startWorkoutPlayer(workoutDayId: 'workout-week1-day2');
    training.completeWorkoutPlayerStep();
    final TrainingMvpState before = container.read(trainingMvpProvider);

    container
        .read(mealPreferenceControllerProvider.notifier)
        .saveScenario(MealScenario.homeCooking);
    await Future<void>.delayed(Duration.zero);

    final TrainingMvpState after = container.read(trainingMvpProvider);
    expect(after.mealScenario, MealScenario.homeCooking);
    expect(after.activeMealGuide.scenario, MealScenario.homeCooking);
    expect(after.coachAdvices, contains(contains('按自炊场景执行')));
    expect(after.activeWorkoutPlayerDayId, before.activeWorkoutPlayerDayId);
    expect(after.workoutPlayerStepIndex, before.workoutPlayerStepIndex);
    expect(after.logs, before.logs);
  });
}
