import '../models/body_metric_export.dart';
import '../../services/local_storage_service.dart';
import '../../services/confirmed_local_document_write.dart';

abstract class BodyMetricExportRepository {
  List<BodyMetricExportRecord> listRecords();

  BodyMetricExportRecord saveRecord(BodyMetricExportRecord record);

  void clearRecords();

  Future<void> saveConfirmedRecord(BodyMetricExportRecord record);

  Future<void> clearConfirmedRecords();
}

class PersistedBodyMetricExportRepository
    implements BodyMetricExportRepository {
  static const String storageKey = 'trainflow.body_metric_exports.v1';
  static const int _maxSavedRecords = 50;

  final LocalStorageService _storageService;
  final List<BodyMetricExportRecord> _records = [];
  bool _saving = false;
  bool _recoveryRequired = false;

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
    _checkWritable();
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
    _checkWritable();
    _records.clear();
    _persist();
  }

  @override
  Future<void> saveConfirmedRecord(BodyMetricExportRecord record) async {
    _checkWritable();
    final candidate = [
      record,
      ..._records.where((item) => item.id != record.id),
    ]..sort((a, b) => b.exportedAt.compareTo(a.exportedAt));
    await _commit(candidate.take(_maxSavedRecords).toList());
  }

  @override
  Future<void> clearConfirmedRecords() async {
    _checkWritable();
    await _commit([]);
  }

  Future<void> _commit(List<BodyMetricExportRecord> candidate) async {
    _saving = true;
    await commitLocalDocumentWrites(
        _storageService,
        [
          PreparedLocalDocumentWrite(
            key: storageKey,
            document: {
              'schemaVersion': 1,
              'records': candidate.map((record) => record.toJson()).toList(),
            },
            publish: () {
              _records
                ..clear()
                ..addAll(candidate);
            },
            blockRecovery: () => _recoveryRequired = true,
            release: () => _saving = false,
          ),
        ],
        label: '身体数据导出登记');
  }

  void _checkWritable() {
    if (_recoveryRequired) {
      throw StateError('导出登记恢复尚未确认，请重启检查后再操作。');
    }
    if (_saving) throw StateError('导出登记正在保存，请等待完成后再操作。');
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
