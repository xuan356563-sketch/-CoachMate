import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/achievement.dart';
import '../../../data/repositories/achievement_repository.dart';
import '../../../services/local_storage_service.dart';

final achievementRepositoryProvider = Provider<AchievementRepository>(
  (Ref ref) => InMemoryAchievementRepository(),
);

final achievementRecordRepositoryProvider =
    Provider<AchievementRecordRepository>(
  (Ref ref) => PersistedAchievementRecordRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

final achievementControllerProvider =
    NotifierProvider<AchievementController, AchievementState>(
  AchievementController.new,
);

class AchievementState {
  final List<AchievementDefinition> definitions;
  final List<AchievementRecord> records;
  final String statusMessage;

  const AchievementState({
    required this.definitions,
    required this.records,
    required this.statusMessage,
  });
}

class AchievementController extends Notifier<AchievementState> {
  @override
  AchievementState build() {
    final List<AchievementRecord> records =
        ref.read(achievementRecordRepositoryProvider).listRecords();
    return AchievementState(
      definitions: ref.read(achievementRepositoryProvider).listAchievements(),
      records: records,
      statusMessage: records.isEmpty
          ? '尚未同步成就记录；解锁后会写入本地 achievements 表。'
          : '已从本地 achievements 表读取 ${records.length} 条记录。',
    );
  }

  void sync(
    List<AchievementProgress> progresses, {
    bool showNoChangeMessage = false,
  }) {
    final int previousCount = state.records.length;
    final int unlockedCount =
        progresses.where((AchievementProgress item) => item.unlocked).length;
    final List<AchievementRecord> records = ref
        .read(achievementRecordRepositoryProvider)
        .syncUnlockedProgresses(progresses);
    final int addedCount = records.length - previousCount;
    String statusMessage = state.statusMessage;
    if (addedCount > 0) {
      statusMessage =
          '已写入 $addedCount 条新成就记录，本地 achievements 表共 ${records.length} 条。';
    } else if (showNoChangeMessage && unlockedCount == 0) {
      statusMessage = '还没有可写入的已解锁成就。';
    } else if (showNoChangeMessage) {
      statusMessage = '本地 achievements 表已是最新，共 ${records.length} 条。';
    }
    state = AchievementState(
      definitions: state.definitions,
      records: records,
      statusMessage: statusMessage,
    );
  }
}
