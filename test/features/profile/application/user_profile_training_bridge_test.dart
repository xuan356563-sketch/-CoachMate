import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/daily_adjustment.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/profile/application/user_profile_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('保存资料时同步训练资料和建议并保留跟练会话', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    final TrainingMvpController controller =
        container.read(trainingMvpProvider.notifier);
    final TrainingMvpState initialState = container.read(trainingMvpProvider);
    controller.startWorkoutPlayer(workoutDayId: 'workout-week1-day2');
    controller.completeWorkoutPlayerStep();
    final TrainingMvpState sessionState = container.read(trainingMvpProvider);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              name: '桥接训练者',
              weeklyTrainingDays: 5,
              equipmentAccessType: EquipmentAccessType.none,
            );

    container.read(userProfileControllerProvider.notifier).save(profile);

    final TrainingMvpState state = container.read(trainingMvpProvider);
    expect(state.profileCompleted, isTrue);
    expect(state.profile.name, '桥接训练者');
    expect(state.coachAdvices, isNot(initialState.coachAdvices));
    expect(state.coachAdvices, contains('你每周计划训练 5 天，建议至少保留 1 天完全恢复。'));
    expect(
      state.dailyAdjustmentDecision.environment,
      TrainingEnvironment.noEquipment,
    );
    expect(
        state.activeWorkoutPlayerDayId, sessionState.activeWorkoutPlayerDayId);
    expect(state.workoutPlayerStepIndex, sessionState.workoutPlayerStepIndex);
    expect(state.workoutPlayerEvents, sessionState.workoutPlayerEvents);
  });
}
