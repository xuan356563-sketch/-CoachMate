import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/achievement.dart';
import 'package:trainflow_ai/features/profile/application/achievement_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  ProviderContainer createContainer(InMemoryLocalStorageService storage) {
    return ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
  }

  test('初始状态读取定义并提示尚未同步', () {
    final ProviderContainer container =
        createContainer(InMemoryLocalStorageService());
    addTearDown(container.dispose);

    final AchievementState state =
        container.read(achievementControllerProvider);
    expect(state.definitions, hasLength(7));
    expect(state.records, isEmpty);
    expect(state.statusMessage, contains('尚未同步成就记录'));
  });

  test('同步解锁成就会持久化、去重并保留首次解锁时间', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer first = createContainer(storage);
    final AchievementDefinition definition =
        first.read(achievementControllerProvider).definitions.first;
    final List<AchievementProgress> progresses = [
      AchievementProgress(
        definition: definition,
        currentValue: definition.targetValue,
      ),
    ];

    first.read(achievementControllerProvider.notifier).sync(progresses);
    final DateTime unlockedAt =
        first.read(achievementControllerProvider).records.single.unlockedAt;
    first.read(achievementControllerProvider.notifier).sync(
          progresses,
          showNoChangeMessage: true,
        );
    expect(first.read(achievementControllerProvider).records, hasLength(1));
    expect(
      first.read(achievementControllerProvider).records.single.unlockedAt,
      unlockedAt,
    );
    expect(first.read(achievementControllerProvider).statusMessage,
        contains('已是最新'));
    first.dispose();

    final ProviderContainer restored = createContainer(storage);
    addTearDown(restored.dispose);
    expect(restored.read(achievementControllerProvider).records, hasLength(1));
    expect(
      restored.read(achievementControllerProvider).records.single.unlockedAt,
      unlockedAt,
    );
  });

  test('没有解锁进度时显示原有提示', () {
    final ProviderContainer container =
        createContainer(InMemoryLocalStorageService());
    addTearDown(container.dispose);
    final AchievementDefinition definition =
        container.read(achievementControllerProvider).definitions.first;

    container.read(achievementControllerProvider.notifier).sync(
      [AchievementProgress(definition: definition, currentValue: 0)],
      showNoChangeMessage: true,
    );

    expect(
      container.read(achievementControllerProvider).statusMessage,
      '还没有可写入的已解锁成就。',
    );
  });
}
