import '../models/training_log.dart';
import '../../services/local_storage_service.dart';

abstract class TrainingLogRepository {
  List<TrainingLog> listLogs();

  TrainingLog saveLog(TrainingLog log);

  void clearLogs();
}

class InMemoryTrainingLogRepository implements TrainingLogRepository {
  final List<TrainingLog> _logs = [];

  @override
  List<TrainingLog> listLogs() {
    return List<TrainingLog>.unmodifiable(_logs);
  }

  @override
  TrainingLog saveLog(TrainingLog log) {
    _logs.insert(0, log);
    return log;
  }

  @override
  void clearLogs() {
    _logs.clear();
  }
}

class PersistedTrainingLogRepository implements TrainingLogRepository {
  static const String storageKey = 'trainflow.training_logs.v1';
  static const int _maxSavedLogs = 200;

  final LocalStorageService _storageService;
  final List<TrainingLog> _logs = [];

  PersistedTrainingLogRepository(this._storageService) {
    _hydrate();
  }

  @override
  List<TrainingLog> listLogs() {
    _sortLogs();
    return List<TrainingLog>.unmodifiable(_logs);
  }

  @override
  TrainingLog saveLog(TrainingLog log) {
    _logs.removeWhere((TrainingLog item) => item.id == log.id);
    _logs.insert(0, log);
    _sortLogs();
    if (_logs.length > _maxSavedLogs) {
      _logs.removeRange(_maxSavedLogs, _logs.length);
    }
    _persist();
    return log;
  }

  @override
  void clearLogs() {
    _logs.clear();
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final List<dynamic> logItems =
        storedState['logs'] as List<dynamic>? ?? const [];
    _logs.addAll(
      logItems
          .whereType<Map<String, dynamic>>()
          .map(TrainingLog.fromJson)
          .toList(),
    );
    _sortLogs();
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'logs': _logs.map((TrainingLog log) => log.toJson()).toList(),
    });
  }

  void _sortLogs() {
    _logs.sort(
      (TrainingLog a, TrainingLog b) => b.createdAt.compareTo(a.createdAt),
    );
  }
}
