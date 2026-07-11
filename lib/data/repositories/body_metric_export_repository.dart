import '../models/body_metric_export.dart';
import '../../services/local_storage_service.dart';

abstract class BodyMetricExportRepository {
  List<BodyMetricExportRecord> listRecords();

  BodyMetricExportRecord saveRecord(BodyMetricExportRecord record);

  void clearRecords();
}

class PersistedBodyMetricExportRepository
    implements BodyMetricExportRepository {
  static const String storageKey = 'trainflow.body_metric_exports.v1';
  static const int _maxSavedRecords = 50;

  final LocalStorageService _storageService;
  final List<BodyMetricExportRecord> _records = [];

  PersistedBodyMetricExportRepository(this._storageService) {
    _hydrate();
  }

  @override
  List<BodyMetricExportRecord> listRecords() {
    _sortRecords();
    return List<BodyMetricExportRecord>.unmodifiable(_records);
  }

  @override
  BodyMetricExportRecord saveRecord(BodyMetricExportRecord record) {
    _records.removeWhere((BodyMetricExportRecord item) => item.id == record.id);
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
          .map(BodyMetricExportRecord.fromJson)
          .toList(),
    );
    _sortRecords();
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'records': _records
          .map((BodyMetricExportRecord record) => record.toJson())
          .toList(),
    });
  }

  void _sortRecords() {
    _records.sort(
      (BodyMetricExportRecord a, BodyMetricExportRecord b) =>
          b.exportedAt.compareTo(a.exportedAt),
    );
  }
}
