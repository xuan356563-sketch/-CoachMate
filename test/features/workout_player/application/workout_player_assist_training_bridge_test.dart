import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/workout_player/application/workout_player_assist_controller.dart';
import 'package:trainflow_ai/features/workout_player/workout_player_page.dart';
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
      await training.completeWorkoutPlayerStep();
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

  testWidgets('步骤日志落盘期间合并重复完成并禁用生产按钮', (tester) async {
    final storage = _BlockingFlushStorage();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final training = container.read(trainingMvpProvider.notifier);
    final initialState = container.read(trainingMvpProvider);
    training.startWorkoutPlayer(workoutDayId: initialState.todayWorkout.id);
    final initialIndex =
        container.read(trainingMvpProvider).workoutPlayerSafeIndex;
    final initialLogCount = container.read(trainingMvpProvider).logs.length;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WorkoutPlayerPage()),
      ),
    );

    final first = training.completeWorkoutPlayerStep();
    await storage.started.future;
    await tester.pump();
    final second = training.completeWorkoutPlayerStep();

    expect(second, same(first));
    expect(container.read(trainingMvpProvider).workoutPlayerStepSaving, isTrue);
    final completeButton =
        find.byKey(const ValueKey<String>('workout-player-complete-step'));
    await tester.scrollUntilVisible(
      completeButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final savingButton = tester.widget<FilledButton>(
      completeButton,
    );
    expect(savingButton.onPressed, isNull);
    expect(
        container.read(trainingMvpProvider).logs, hasLength(initialLogCount));
    expect(
      container.read(trainingMvpProvider).workoutPlayerSafeIndex,
      initialIndex,
    );

    storage.finish.complete();
    await Future.wait<void>([first, second]);
    await tester.pump();
    final completed = container.read(trainingMvpProvider);
    expect(completed.workoutPlayerStepSaving, isFalse);
    expect(completed.logs, hasLength(initialLogCount + 1));
    expect(completed.workoutPlayerSafeIndex, initialIndex + 1);
  });

  test('步骤日志保存失败保留当前步骤并允许重试', () async {
    final storage = _FailFirstFlushStorage();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final training = container.read(trainingMvpProvider.notifier);
    final initialState = container.read(trainingMvpProvider);
    training.startWorkoutPlayer(workoutDayId: initialState.todayWorkout.id);
    final initialIndex =
        container.read(trainingMvpProvider).workoutPlayerSafeIndex;
    final initialLogCount = container.read(trainingMvpProvider).logs.length;

    await training.completeWorkoutPlayerStep();
    final failed = container.read(trainingMvpProvider);
    expect(failed.workoutPlayerStepSaving, isFalse);
    expect(failed.workoutPlayerSafeIndex, initialIndex);
    expect(failed.workoutPlayerStatusMessage, contains('训练记录保存失败'));
    expect(failed.workoutPlayerStatusMessage, contains('请重试当前步骤'));

    await training.completeWorkoutPlayerStep();
    final retried = container.read(trainingMvpProvider);
    expect(retried.workoutPlayerStepSaving, isFalse);
    expect(retried.workoutPlayerSafeIndex, initialIndex + 1);
    expect(retried.logs, hasLength(initialLogCount + 1));
  });
}

class _BlockingFlushStorage extends InMemoryLocalStorageService {
  final started = Completer<void>();
  final finish = Completer<void>();

  @override
  Future<void> flush() async {
    if (!started.isCompleted) started.complete();
    await finish.future;
  }
}

class _FailFirstFlushStorage extends InMemoryLocalStorageService {
  var flushCount = 0;

  @override
  Future<void> flush() async {
    flushCount += 1;
    if (flushCount == 1) throw StateError('测试落盘失败');
  }
}
