import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/training_log/application/training_log_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('手动日志与跟练日志写入独立控制器并同步旧训练状态', () async {
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

    training.saveTodayLog(completed: true, rpe: 6, userNote: '桥接测试');
    expect(container.read(trainingLogControllerProvider), hasLength(1));
    expect(container.read(trainingMvpProvider).logs, hasLength(1));

    training.startWorkoutPlayer(
      workoutDayId: container.read(trainingMvpProvider).todayWorkout.id,
    );
    training.completeWorkoutPlayerStep();
    await Future<void>.delayed(Duration.zero);

    final TrainingMvpState state = container.read(trainingMvpProvider);
    expect(container.read(trainingLogControllerProvider), hasLength(2));
    expect(state.logs, hasLength(2));
    expect(state.logs.first.userNote, startsWith('[跟练执行]'));
    expect(state.coachAdvices, isNotEmpty);
    expect(state.achievementRecords, isNotEmpty);
  });
}
