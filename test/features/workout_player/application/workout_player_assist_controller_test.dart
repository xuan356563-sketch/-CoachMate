import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/workout_player/application/workout_player_assist_controller.dart';
import 'package:trainflow_ai/services/workout_platform_service.dart';

void main() {
  test('语音队列最多保留六条并可关闭播报', () {
    final _FakeWorkoutPlatformService platform = _FakeWorkoutPlatformService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        workoutPlatformServiceProvider.overrideWithValue(platform),
      ],
    );
    addTearDown(container.dispose);
    final WorkoutPlayerAssistController controller =
        container.read(workoutPlayerAssistControllerProvider.notifier);

    for (int index = 0; index < 8; index += 1) {
      controller.enqueueCue('提示 $index');
    }
    WorkoutPlayerAssistState state =
        container.read(workoutPlayerAssistControllerProvider);
    expect(state.voiceQueue, hasLength(6));
    expect(state.voiceQueue.first, '提示 7');
    expect(platform.spoken.last, '提示 7');

    controller.toggleVoice();
    controller.enqueueCue('关闭后不播报');
    state = container.read(workoutPlayerAssistControllerProvider);
    expect(state.voiceEnabled, isFalse);
    expect(state.voiceQueue, hasLength(6));
    expect(state.voiceStatusMessage, contains('已关闭'));
    expect(platform.spoken, isNot(contains('关闭后不播报')));
    expect(platform.stopSpeechCount, 1);
  });

  test('屏幕常亮切换同步状态和平台调用', () {
    final _FakeWorkoutPlatformService platform = _FakeWorkoutPlatformService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        workoutPlatformServiceProvider.overrideWithValue(platform),
      ],
    );
    addTearDown(container.dispose);
    final WorkoutPlayerAssistController controller =
        container.read(workoutPlayerAssistControllerProvider.notifier);

    controller.toggleScreenAwake();
    expect(
      container
          .read(workoutPlayerAssistControllerProvider)
          .screenAwakeRequested,
      isTrue,
    );
    expect(platform.screenAwakeRequests.last, isTrue);

    controller.toggleScreenAwake();
    expect(
      container
          .read(workoutPlayerAssistControllerProvider)
          .screenAwakeRequested,
      isFalse,
    );
    expect(platform.screenAwakeRequests.last, isFalse);
  });
}

class _FakeWorkoutPlatformService extends WorkoutPlatformService {
  final List<String> spoken = [];
  final List<bool> screenAwakeRequests = [];
  int stopSpeechCount = 0;

  @override
  Future<bool> speak(String text) async {
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stopSpeech() async {
    stopSpeechCount += 1;
  }

  @override
  Future<bool> setScreenAwake(bool enabled) async {
    screenAwakeRequests.add(enabled);
    return true;
  }
}
