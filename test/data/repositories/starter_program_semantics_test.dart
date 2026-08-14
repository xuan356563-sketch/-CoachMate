import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/achievement.dart';
import 'package:trainflow_ai/data/models/starter_program.dart';
import 'package:trainflow_ai/data/repositories/achievement_repository.dart';
import 'package:trainflow_ai/data/repositories/starter_program_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('成长日成就保留兼容标识并统一使用累计成长语义', () {
    final List<AchievementDefinition> definitions =
        InMemoryAchievementRepository().listAchievements();
    final List<AchievementDefinition> growthDayDefinitions = definitions
        .where(
          (AchievementDefinition definition) =>
              definition.id == 'seven_day_streak' ||
              definition.id == 'thirty_day_streak',
        )
        .toList();

    expect(growthDayDefinitions, hasLength(2));
    for (final AchievementDefinition definition in growthDayDefinitions) {
      expect(definition.title, contains('累计成长'));
      expect(
        '${definition.title}${definition.description}',
        isNot(matches(RegExp(r'连续打卡|连续完成|连击|断签'))),
      );
    }

    final AchievementRecord restored = AchievementRecord.fromJson({
      'definitionId': 'seven_day_streak',
      'title': '连续 7 天',
      'description': '30 天引导连续完成 7 天。',
    });
    expect(restored.title, '累计成长 7 天');
    expect(restored.description, '30 天引导累计完成 7 天。');
  });

  test('旧新手进度提示恢复后不再展示连击或断签惩罚语义', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    storage.saveJson(PersistedStarterProgramRepository.storageKey, {
      'schemaVersion': 1,
      'progress': const StarterProgramProgress(
        goal: StarterProgramGoal.habit,
        dayIndex: 8,
        streak: 7,
        rescueMode: true,
        statusMessage: '已切换 5 分钟补救版，完成后仍可保住连击。',
      ).toJson(),
    });

    final StarterProgramProgress restored = PersistedStarterProgramRepository(
      storageService: storage,
    ).getProgress();

    expect(restored.streak, 7);
    expect(restored.statusMessage, '已切换 5 分钟补救版，完成后计入累计成长日。');
    expect(
      restored.statusMessage,
      isNot(matches(RegExp(r'连续打卡|连击|断签|漏练不惩罚'))),
    );
  });
}
