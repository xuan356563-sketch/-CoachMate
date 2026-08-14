import '../models/daily_check_in_record.dart';
import '../../services/local_storage_service.dart';

abstract interface class DailyCheckInRepository {
  DailyCheckInSnapshot getSnapshot();

  DailyCheckInWriteResult record({
    required DateTime localDate,
    required DateTime confirmedAt,
    required DailyCheckInSource source,
    DailyContinuityKind continuityKind = DailyContinuityKind.standard,
  });

  void markCelebrationSeen(String id, {required DateTime seenAt});

  void clear();
}

class PersistedDailyCheckInRepository implements DailyCheckInRepository {
  PersistedDailyCheckInRepository(this._storage) {
    _hydrate();
  }

  static const String storageKey = 'trainflow.daily_check_ins.v1';

  final LocalStorageService _storage;
  final List<DailyCheckInRecord> _records = <DailyCheckInRecord>[];
  final List<CheckInCelebrationReceipt> _celebrations =
      <CheckInCelebrationReceipt>[];

  @override
  DailyCheckInSnapshot getSnapshot() {
    final List<DailyCheckInRecord> records = List<DailyCheckInRecord>.from(
      _records,
    )..sort(
        (DailyCheckInRecord first, DailyCheckInRecord second) =>
            first.localDate.compareTo(second.localDate),
      );
    return DailyCheckInSnapshot(
      records: List<DailyCheckInRecord>.unmodifiable(records),
      celebrations: List<CheckInCelebrationReceipt>.unmodifiable(
        _celebrations,
      ),
      streak: _buildStreak(records),
    );
  }

  @override
  DailyCheckInWriteResult record({
    required DateTime localDate,
    required DateTime confirmedAt,
    required DailyCheckInSource source,
    DailyContinuityKind continuityKind = DailyContinuityKind.standard,
  }) {
    final DateTime normalizedDate = _dateOnly(localDate);
    final bool exists = _records.any(
      (DailyCheckInRecord item) => _sameDate(item.localDate, normalizedDate),
    );
    if (exists) {
      return DailyCheckInWriteResult(
        created: false,
        snapshot: getSnapshot(),
        newCelebrations: const <CheckInCelebrationReceipt>[],
      );
    }

    _records.add(
      DailyCheckInRecord(
        id: 'daily-check-in-${_dateKey(normalizedDate)}',
        localDate: normalizedDate,
        confirmedAt: confirmedAt,
        source: source,
        continuityKind: continuityKind,
      ),
    );
    final DailyCheckInSnapshot nextSnapshot = getSnapshot();
    final Set<String> existingIds =
        _celebrations.map((CheckInCelebrationReceipt item) => item.id).toSet();
    final List<CheckInCelebrationReceipt> created = _eligibleMilestones(
            nextSnapshot.streak, confirmedAt)
        .where(
            (CheckInCelebrationReceipt item) => !existingIds.contains(item.id))
        .toList(growable: false);
    _celebrations.addAll(created);
    _persist();
    return DailyCheckInWriteResult(
      created: true,
      snapshot: getSnapshot(),
      newCelebrations: List<CheckInCelebrationReceipt>.unmodifiable(created),
    );
  }

  @override
  void markCelebrationSeen(String id, {required DateTime seenAt}) {
    final int index = _celebrations.indexWhere(
      (CheckInCelebrationReceipt item) => item.id == id,
    );
    if (index < 0 || _celebrations[index].isSeen) return;
    _celebrations[index] = _celebrations[index].copyWith(seenAt: seenAt);
    _persist();
  }

  @override
  void clear() {
    _records.clear();
    _celebrations.clear();
    _storage.remove(storageKey);
  }

  void _hydrate() {
    final Map<String, dynamic>? document = _storage.readJson(storageKey);
    if (document == null) return;
    final List<dynamic> records =
        document['records'] as List<dynamic>? ?? const <dynamic>[];
    final List<dynamic> celebrations =
        document['celebrations'] as List<dynamic>? ?? const <dynamic>[];
    _records.addAll(
      records
          .whereType<Map<String, dynamic>>()
          .map(DailyCheckInRecord.fromJson),
    );
    _celebrations.addAll(
      celebrations
          .whereType<Map<String, dynamic>>()
          .map(CheckInCelebrationReceipt.fromJson),
    );
  }

  void _persist() {
    _storage.saveJson(storageKey, <String, dynamic>{
      'schemaVersion': 2,
      'records': _records
          .map((DailyCheckInRecord item) => item.toJson())
          .toList(growable: false),
      'celebrations': _celebrations
          .map((CheckInCelebrationReceipt item) => item.toJson())
          .toList(growable: false),
    });
  }
}

CheckInStreakState _buildStreak(List<DailyCheckInRecord> records) {
  if (records.isEmpty) return const CheckInStreakState.empty();
  int current = 1;
  int longest = 1;
  for (int index = 1; index < records.length; index += 1) {
    final int gap = records[index]
        .localDate
        .difference(records[index - 1].localDate)
        .inDays;
    current = gap == 1 ? current + 1 : 1;
    if (current > longest) longest = current;
  }
  return CheckInStreakState(
    currentStreak: current,
    longestStreak: longest,
    totalCheckInDays: records.length,
    lastCheckInDate: records.last.localDate,
  );
}

List<CheckInCelebrationReceipt> _eligibleMilestones(
  CheckInStreakState state,
  DateTime achievedAt,
) {
  final List<CheckInCelebrationReceipt> result = <CheckInCelebrationReceipt>[];
  // 只奖励累计记录，不把日连续塑造成会因休息而损失的资产。
  // 已经持久化的旧 checkin_streak_* 回执仍由 hydrate 保留展示。
  for (final int target in <int>[7, 30, 60, 90, 180, 365]) {
    if (state.totalCheckInDays >= target) {
      result.add(
        CheckInCelebrationReceipt(
          id: 'growth_days_$target',
          title: '累计记录 $target 天',
          achievedAt: achievedAt,
        ),
      );
    }
  }
  return result;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
