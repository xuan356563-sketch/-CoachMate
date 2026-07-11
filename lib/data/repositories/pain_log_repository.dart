import '../models/pain_log.dart';
import '../../services/local_storage_service.dart';

abstract class PainLogRepository {
  List<PainLog> listPainLogs();

  PainLog savePainLog(PainLog painLog);

  void clearPainLogs();
}

class InMemoryPainLogRepository implements PainLogRepository {
  final List<PainLog> _painLogs = [];

  @override
  List<PainLog> listPainLogs() {
    return List<PainLog>.unmodifiable(_painLogs);
  }

  @override
  PainLog savePainLog(PainLog painLog) {
    _painLogs.insert(0, painLog);
    return painLog;
  }

  @override
  void clearPainLogs() {
    _painLogs.clear();
  }
}

class PersistedPainLogRepository implements PainLogRepository {
  static const String storageKey = 'trainflow.pain_logs.v1';
  static const int _maxSavedLogs = 200;

  final LocalStorageService _storageService;
  final List<PainLog> _painLogs = [];

  PersistedPainLogRepository(this._storageService) {
    _hydrate();
  }

  @override
  List<PainLog> listPainLogs() {
    _sortPainLogs();
    return List<PainLog>.unmodifiable(_painLogs);
  }

  @override
  PainLog savePainLog(PainLog painLog) {
    _painLogs.removeWhere((PainLog item) => item.id == painLog.id);
    _painLogs.insert(0, painLog);
    _sortPainLogs();
    if (_painLogs.length > _maxSavedLogs) {
      _painLogs.removeRange(_maxSavedLogs, _painLogs.length);
    }
    _persist();
    return painLog;
  }

  @override
  void clearPainLogs() {
    _painLogs.clear();
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final List<dynamic> painLogItems =
        storedState['logs'] as List<dynamic>? ?? const [];
    _painLogs.addAll(
      painLogItems
          .whereType<Map<String, dynamic>>()
          .map(PainLog.fromJson)
          .toList(),
    );
    _sortPainLogs();
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'logs': _painLogs.map((PainLog painLog) => painLog.toJson()).toList(),
    });
  }

  void _sortPainLogs() {
    _painLogs.sort(
      (PainLog a, PainLog b) => b.createdAt.compareTo(a.createdAt),
    );
  }
}
