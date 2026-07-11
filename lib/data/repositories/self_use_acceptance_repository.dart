import '../../services/local_storage_service.dart';
import '../models/self_use_acceptance.dart';

abstract class SelfUseAcceptanceRepository {
  SelfUseAcceptanceRecord getRecord();

  SelfUseAcceptanceRecord start(DateTime startedAt);

  SelfUseAcceptanceRecord updateDay(SelfUseAcceptanceDay day);

  void clear();
}

class PersistedSelfUseAcceptanceRepository
    implements SelfUseAcceptanceRepository {
  static const String storageKey = 'trainflow.self_use_acceptance.v1';

  final LocalStorageService _storageService;
  SelfUseAcceptanceRecord _record = const SelfUseAcceptanceRecord.empty();

  PersistedSelfUseAcceptanceRepository(this._storageService) {
    _hydrate();
  }

  @override
  SelfUseAcceptanceRecord getRecord() => _record;

  @override
  SelfUseAcceptanceRecord start(DateTime startedAt) {
    final DateTime normalizedStart = DateTime(
      startedAt.year,
      startedAt.month,
      startedAt.day,
    );
    _record = SelfUseAcceptanceRecord(
      startedAt: normalizedStart,
      days: List<SelfUseAcceptanceDay>.generate(
        14,
        (int index) => SelfUseAcceptanceDay(
          dayNumber: index + 1,
          date: normalizedStart.add(Duration(days: index)),
        ),
      ),
    );
    _persist();
    return _record;
  }

  @override
  SelfUseAcceptanceRecord updateDay(SelfUseAcceptanceDay day) {
    if (!_record.isStarted) {
      return _record;
    }
    final SelfUseAcceptanceDay? currentDay = _record.findDay(day.dayNumber);
    if (currentDay == null ||
        _dateOnly(currentDay.date).isAfter(_dateOnly(DateTime.now()))) {
      return _record;
    }
    final List<SelfUseAcceptanceDay> updatedDays = _record.days.map(
      (SelfUseAcceptanceDay current) {
        return current.dayNumber == day.dayNumber ? day : current;
      },
    ).toList();
    _record = _record.copyWith(days: updatedDays);
    _persist();
    return _record;
  }

  @override
  void clear() {
    _record = const SelfUseAcceptanceRecord.empty();
    _storageService.remove(storageKey);
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState != null) {
      _record = SelfUseAcceptanceRecord.fromJson(storedState);
    }
  }

  void _persist() {
    _storageService.saveJson(storageKey, _record.toJson());
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
