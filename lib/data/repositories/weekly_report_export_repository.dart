import '../models/weekly_report_export.dart';
import '../../services/local_storage_service.dart';

abstract class WeeklyReportExportRepository {
  List<WeeklyReportExportRecord> listRecords();

  WeeklyReportExportRecord saveRecord(WeeklyReportExportRecord record);

  void clearRecords();
}

class PersistedWeeklyReportExportRepository
    implements WeeklyReportExportRepository {
  static const String storageKey = 'trainflow.weekly_report_exports.v1';
  static const int _maxSavedRecords = 30;

  final LocalStorageService _storageService;
  final List<WeeklyReportExportRecord> _records = [];

  PersistedWeeklyReportExportRepository(this._storageService) {
    _hydrate();
  }

  @override
  List<WeeklyReportExportRecord> listRecords() {
    _sortRecords();
    return List<WeeklyReportExportRecord>.unmodifiable(_records);
  }

  @override
  WeeklyReportExportRecord saveRecord(WeeklyReportExportRecord record) {
    _records.removeWhere(
      (WeeklyReportExportRecord item) => item.id == record.id,
    );
    _records.insert(0, record);
    _sortRecords();
    if (_records.length > _maxSavedRecords) {
      _records.removeRange(_maxSavedRecords, _records.length);
    }
    _persist();
    return record;
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
          .map(WeeklyReportExportRecord.fromJson)
          .toList(),
    );
    _sortRecords();
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'records': _records
          .map((WeeklyReportExportRecord record) => record.toJson())
          .toList(),
    });
  }

  void _sortRecords() {
    _records.sort(
      (WeeklyReportExportRecord a, WeeklyReportExportRecord b) =>
          b.exportedAt.compareTo(a.exportedAt),
    );
  }
}
