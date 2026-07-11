import '../models/achievement.dart';
import '../seed/seed_achievements.dart';
import '../../services/local_storage_service.dart';

abstract class AchievementRepository {
  List<AchievementDefinition> listAchievements();
}

class InMemoryAchievementRepository implements AchievementRepository {
  @override
  List<AchievementDefinition> listAchievements() {
    return List<AchievementDefinition>.unmodifiable(seedAchievements);
  }
}

abstract class AchievementRecordRepository {
  List<AchievementRecord> listRecords();

  List<AchievementRecord> syncUnlockedProgresses(
    List<AchievementProgress> progresses,
  );

  void clearRecords();
}

class PersistedAchievementRecordRepository
    implements AchievementRecordRepository {
  static const String storageKey = 'trainflow.achievement_records.v1';

  final LocalStorageService _storageService;
  final List<AchievementRecord> _records = [];

  PersistedAchievementRecordRepository(this._storageService) {
    _hydrate();
  }

  @override
  List<AchievementRecord> listRecords() {
    _sortRecords();
    return List<AchievementRecord>.unmodifiable(_records);
  }

  @override
  List<AchievementRecord> syncUnlockedProgresses(
    List<AchievementProgress> progresses,
  ) {
    bool changed = false;
    for (final AchievementProgress progress in progresses) {
      if (!progress.unlocked) {
        continue;
      }
      final int existingIndex = _records.indexWhere(
        (AchievementRecord record) =>
            record.definitionId == progress.definition.id,
      );
      final DateTime unlockedAt = existingIndex == -1
          ? DateTime.now()
          : _records[existingIndex].unlockedAt;
      final AchievementRecord nextRecord = AchievementRecord.fromProgress(
        progress,
        unlockedAt: unlockedAt,
      );
      if (existingIndex == -1) {
        _records.add(nextRecord);
        changed = true;
      } else if (_records[existingIndex].toJson().toString() !=
          nextRecord.toJson().toString()) {
        _records[existingIndex] = nextRecord;
        changed = true;
      }
    }
    _sortRecords();
    if (changed) {
      _persist();
    }
    return listRecords();
  }

  @override
  void clearRecords() {
    _records.clear();
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final List<dynamic> recordItems =
        storedState['records'] as List<dynamic>? ?? const [];
    _records.addAll(
      recordItems
          .whereType<Map<String, dynamic>>()
          .map(AchievementRecord.fromJson)
          .toList(),
    );
    _sortRecords();
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'records':
          _records.map((AchievementRecord record) => record.toJson()).toList(),
    });
  }

  void _sortRecords() {
    _records.sort(
      (AchievementRecord a, AchievementRecord b) =>
          b.unlockedAt.compareTo(a.unlockedAt),
    );
  }
}
