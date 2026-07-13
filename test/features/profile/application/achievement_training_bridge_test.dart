import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/profile/application/achievement_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('成就控制器同步旧训练状态并保留跟练会话', () async {
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
    training.startWorkoutPlayer(
      workoutDayId: container.read(trainingMvpProvider).todayWorkout.id,
    );
    training.setKnowledgeSearchQuery('深蹲');
    final TrainingMvpState before = container.read(trainingMvpProvider);

    container.read(achievementControllerProvider.notifier).sync(
          before.achievementProgressList,
          showNoChangeMessage: true,
        );
    await Future<void>.delayed(Duration.zero);

    final TrainingMvpState after = container.read(trainingMvpProvider);
    expect(after.achievementRecords, isNotEmpty);
    expect(after.achievementRecordStatusMessage, contains('本地 achievements 表'));
    expect(after.activeWorkoutPlayerDayId, before.activeWorkoutPlayerDayId);
    expect(after.knowledgeSearchQuery, before.knowledgeSearchQuery);
  });
}
