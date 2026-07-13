import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/workout_player/application/workout_player_assist_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('播放器辅助状态同步旧训练状态并保留步骤和日志行为', () async {
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
    final String workoutId =
        container.read(trainingMvpProvider).todayWorkout.id;

    training.startWorkoutPlayer(workoutDayId: workoutId);
    WorkoutPlayerAssistState assist =
        container.read(workoutPlayerAssistControllerProvider);
    TrainingMvpState state = container.read(trainingMvpProvider);
    expect(assist.screenAwakeRequested, isTrue);
    expect(state.workoutPlayerScreenAwakeRequested, isTrue);
    expect(state.workoutPlayerVoiceQueue, isNotEmpty);

    training.toggleWorkoutPlayerVoice();
    assist = container.read(workoutPlayerAssistControllerProvider);
    state = container.read(trainingMvpProvider);
    expect(assist.voiceEnabled, isFalse);
    expect(state.workoutPlayerVoiceEnabled, isFalse);

    for (int index = 0; index < 5; index += 1) {
      training.completeWorkoutPlayerStep();
    }
    await Future<void>.delayed(Duration.zero);

    state = container.read(trainingMvpProvider);
    assist = container.read(workoutPlayerAssistControllerProvider);
    expect(state.workoutPlayerFinished, isTrue);
    expect(state.logs, isNotEmpty);
    expect(
      state.logs.every((log) => log.userNote?.startsWith('[跟练执行]') ?? false),
      isTrue,
    );
    expect(assist.screenAwakeRequested, isFalse);
    expect(state.workoutPlayerScreenAwakeRequested, isFalse);
  });
}
