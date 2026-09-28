import '../../services/local_storage_service.dart';
import 'assessment_record.dart';

/// 独立本地文档的失败恢复；调用方须通过账号域 commit 提交。
class ResourceDocumentWriter {
  ResourceDocumentWriter(this.storage);
  final LocalStorageService storage;
  bool _writing = false, _recoveryRequired = false;
  Future<void> write(String key, Map<String, dynamic>? document) async {
    if (_writing || _recoveryRequired) throw StateError('本地资料正在保存或需要恢复，请稍后重试');
    final previous = storage.readJson(key);
    _writing = true;
    try {
      if (document == null) {
        storage.remove(key);
      } else {
        storage.saveJson(key, document);
      }
      await storage.flush();
    } catch (_) {
      try {
        if (previous == null) {
          storage.remove(key);
        } else {
          storage.saveJson(key, previous);
        }
        await storage.flush();
      } catch (_) {
        _recoveryRequired = true;
      }
      rethrow;
    } finally {
      _writing = false;
    }
  }
}

class AssessmentRecordRepository {
  AssessmentRecordRepository(this.storage)
      : _writer = ResourceDocumentWriter(storage);
  static const storageKey = 'trainflow.assessment_records.v1';
  final LocalStorageService storage;
  final ResourceDocumentWriter _writer;
  List<AssessmentRecord> list() {
    final j = storage.readJson(storageKey);
    if (j == null) return const [];
    if (j['schemaVersion'] != 1 || j['records'] is! List) {
      throw const FormatException('评估记录格式不受支持，已保留原始数据');
    }
    final records = (j['records'] as List)
        .map((r) =>
            AssessmentRecord.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
    if (records.map((r) => r.id).toSet().length != records.length) {
      throw const FormatException('评估记录标识重复');
    }
    records.sort((a, b) => b.assessedAt.compareTo(a.assessedAt));
    return List.unmodifiable(records);
  }

  Future<void> save(AssessmentRecord record) {
    AssessmentRecord.fromJson(record.toJson());
    final records = list();
    if (records.any((r) => r.id == record.id)) {
      throw StateError('该评估已保存，请重新记录一份新的评估');
    }
    return _write([record, ...records]);
  }

  Future<void> delete(String id) =>
      _write(list().where((r) => r.id != id).toList());
  Future<void> _write(List<AssessmentRecord> records) => _writer.write(
      storageKey,
      {'schemaVersion': 1, 'records': records.map((r) => r.toJson()).toList()});
}
