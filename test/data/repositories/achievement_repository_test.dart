import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/achievement.dart';
import 'package:trainflow_ai/data/repositories/achievement_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('成就记录仓库持久化已解锁进度、按定义去重并保留解锁时间', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final PersistedAchievementRecordRepository repository =
        PersistedAchievementRecordRepository(storage);
    const AchievementDefinition definition = AchievementDefinition(
      id: 'achievement-test',
      title: '测试成就',
      description: '用于验证成就记录持久化。',
      category: AchievementCategory.execution,
      targetValue: 2,
    );

    repository.syncUnlockedProgresses(
      const [AchievementProgress(definition: definition, currentValue: 2)],
    );
    final DateTime unlockedAt = repository.listRecords().single.unlockedAt;
    repository.syncUnlockedProgresses(
      const [AchievementProgress(definition: definition, currentValue: 3)],
    );

    final PersistedAchievementRecordRepository restored =
        PersistedAchievementRecordRepository(storage);
    expect(restored.listRecords(), hasLength(1));
    expect(restored.listRecords().single.definitionId, 'achievement-test');
    expect(restored.listRecords().single.currentValue, 2);
    expect(restored.listRecords().single.unlockedAt, unlockedAt);

    restored.clearRecords();
    expect(
      PersistedAchievementRecordRepository(storage).listRecords(),
      isEmpty,
    );
  });
}
