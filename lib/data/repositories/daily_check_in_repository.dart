import '../models/daily_check_in_record.dart';
import '../../services/local_storage_service.dart';
import '../../services/confirmed_local_document_write.dart';

abstract interface class DailyCheckInRepository {
  DailyCheckInSnapshot getSnapshot();

  DailyCheckInWriteResult record({
    required DateTime localDate,
    required DateTime confirmedAt,
    required DailyCheckInSource source,
    DailyContinuityKind continuityKind = DailyContinuityKind.standard,
  });

  /// 等待落盘后发布签到及里程碑，失败恢复原文档。
  Future<DailyCheckInWriteResult> recordConfirmed({
    required DateTime localDate,
    required DateTime confirmedAt,
    required DailyCheckInSource source,
    DailyContinuityKind continuityKind = DailyContinuityKind.standard,
  });

  Future<void> markCelebrationSeenConfirmed(String id,
      {required DateTime seenAt});

  void markCelebrationSeen(String id, {required DateTime seenAt});

  /// 准备参与身体记录的联合提交，沿用原同日幂等与里程碑规则。
  PreparedLocalDocumentWrite prepareConfirmedRecord({
    required DateTime localDate, required DateTime confirmedAt,
    required DailyCheckInSource source,
  });

  void clear();
}

class PersistedDailyCheckInRepository implements DailyCheckInRepository {
  PersistedDailyCheckInRepository(this._storage) {
    _hydrate();
  }

  static const String storageKey = 'trainflow.daily_check_ins.v1';

  final LocalStorageService _storage;
  bool _saving = false;
  bool _recoveryRequired = false;
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
    _checkWritable();
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
    _checkWritable();
    final int index = _celebrations.indexWhere(
      (CheckInCelebrationReceipt item) => item.id == id,
    );
    if (index < 0 || _celebrations[index].isSeen) return;
    _celebrations[index] = _celebrations[index].copyWith(seenAt: seenAt);
    _persist();
  }

  @override
  void clear() {
    _checkWritable();
    _records.clear();
    _celebrations.clear();
    _storage.remove(storageKey);
  }

  @override
  Future<DailyCheckInWriteResult> recordConfirmed({
    required DateTime localDate,
    required DateTime confirmedAt,
    required DailyCheckInSource source,
    DailyContinuityKind continuityKind = DailyContinuityKind.standard,
  }) async {
    _checkWritable();
    if (_records.any((item) => _sameDate(item.localDate, localDate))) {
      return DailyCheckInWriteResult(
          created: false, snapshot: getSnapshot(), newCelebrations: const []);
    }
    return _commitConfirmed((candidate) => candidate.record(
          localDate: localDate,
          confirmedAt: confirmedAt,
          source: source,
          continuityKind: continuityKind,
        ));
  }

  @override
  Future<void> markCelebrationSeenConfirmed(String id,
      {required DateTime seenAt}) async {
    _checkWritable();
    if (!_celebrations.any((item) => item.id == id && !item.isSeen)) return;
    await _commitConfirmed(
        (candidate) => candidate.markCelebrationSeen(id, seenAt: seenAt));
  }

  @override
  PreparedLocalDocumentWrite prepareConfirmedRecord({
    required DateTime localDate, required DateTime confirmedAt,
    required DailyCheckInSource source,
  }) => _prepareUpdate((candidate) => candidate.record(
      localDate: localDate, confirmedAt: confirmedAt, source: source)).write;

  Future<T> _commitConfirmed<T>(
      T Function(PersistedDailyCheckInRepository candidate) update) async {
    final prepared = _prepareUpdate(update);
    await commitLocalDocumentWrites(_storage, [prepared.write], label: '签到');
    return prepared.result;
  }

  ({PreparedLocalDocumentWrite write, T result}) _prepareUpdate<T>(
      T Function(PersistedDailyCheckInRepository candidate) update) {
    _checkWritable();
    _saving = true;
    try {
      final staging = InMemoryLocalStorageService();
      staging.saveJson(storageKey, _document());
      final candidate = PersistedDailyCheckInRepository(staging);
      final result = update(candidate);
      return (result: result, write: PreparedLocalDocumentWrite(
        key: storageKey, document: staging.readJson(storageKey)!,
        changed: result is! DailyCheckInWriteResult || result.created,
        publish: () {
          _records..clear()..addAll(candidate._records);
          _celebrations..clear()..addAll(candidate._celebrations);
        },
        blockRecovery: () => _recoveryRequired = true,
        release: () => _saving = false,
      ));
    } catch (_) {
      _saving = false;
      rethrow;
    }
  }

  void _checkWritable() {
    if (_recoveryRequired) throw StateError('签到恢复尚未确认，请重启检查后再操作。');
    if (_saving) throw StateError('签到正在保存，请等待完成后再操作。');
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

  void _persist() => _storage.saveJson(storageKey, _document());

  Map<String, dynamic> _document() => <String, dynamic>{
        'schemaVersion': 2,
        'records':
            _records.map((item) => item.toJson()).toList(growable: false),
        'celebrations':
            _celebrations.map((item) => item.toJson()).toList(growable: false),
      };
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
