import 'dart:async';
import 'dart:convert';

import 'package:trainflow_ai/data/local/trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/models/cloud_sync.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

import 'cloud_sync_projection_builder.dart';

typedef DatabaseWriteErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

class DatabaseLocalStorageService implements LocalStorageService {
  DatabaseLocalStorageService._(
    this._database,
    this._cache,
    this._onWriteError,
  );

  final TrainFlowDatabaseGateway _database;
  final Map<String, Map<String, dynamic>> _cache;
  final DatabaseWriteErrorHandler? _onWriteError;

  Future<void> _pendingWrites = Future<void>.value();
  Object? _lastWriteError;
  StackTrace? _lastWriteStackTrace;

  static Future<DatabaseLocalStorageService> create(
    TrainFlowDatabaseGateway database, {
    DatabaseWriteErrorHandler? onWriteError,
  }) async {
    final Map<String, Map<String, dynamic>> documents =
        await database.readAllLegacyDocuments();
    return DatabaseLocalStorageService._(
      database,
      <String, Map<String, dynamic>>{
        for (final MapEntry<String, Map<String, dynamic>> entry
            in documents.entries)
          entry.key: _copyJsonMap(entry.value),
      },
      onWriteError,
    );
  }

  Object? get lastWriteError => _lastWriteError;

  @override
  Map<String, dynamic>? readJson(String key) {
    final Map<String, dynamic>? value = _cache[key];
    return value == null ? null : _copyJsonMap(value);
  }

  @override
  void saveJson(String key, Map<String, dynamic> value) {
    final Map<String, dynamic> snapshot = _copyJsonMap(value);
    final Map<String, Map<String, dynamic>> previousDocuments =
        Map<String, Map<String, dynamic>>.from(_cache);
    _cache[key] = snapshot;
    final List<CloudSyncMutation> mutations = CloudSyncProjectionBuilder.build(
      changedKey: key,
      previousDocuments: previousDocuments,
      currentDocuments: _cache,
    );
    final String? accountId =
        _cache['trainflow.account_binding.v1']?['userId'] as String?;
    _enqueueWrite(
      () {
        final TrainFlowDatabaseGateway database = _database;
        if (database is TrainFlowCloudSyncWriteGateway &&
            accountId != null &&
            accountId.isNotEmpty &&
            mutations.isNotEmpty) {
          final TrainFlowCloudSyncWriteGateway cloudDatabase =
              database as TrainFlowCloudSyncWriteGateway;
          return cloudDatabase.upsertLegacyDocumentWithCloudMutations(
            key: key,
            value: snapshot,
            accountId: accountId,
            mutations: mutations,
          );
        }
        return database.upsertLegacyDocument(key, snapshot);
      },
    );
  }

  @override
  void remove(String key) {
    _cache.remove(key);
    _enqueueWrite(() => _database.deleteLegacyDocument(key));
  }

  @override
  void clearBusinessData({Set<String> preservedKeys = const <String>{}}) {
    _cache.removeWhere(
      (String key, Map<String, dynamic> _) =>
          key.startsWith('trainflow.') && !preservedKeys.contains(key),
    );
    _enqueueWrite(
      () => _database.clearLegacyDocuments(preservedKeys: preservedKeys),
    );
  }

  @override
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  }) async {
    await flush();
    final Map<String, Map<String, dynamic>> next =
        <String, Map<String, dynamic>>{
      for (final MapEntry<String, Map<String, dynamic>> entry in _cache.entries)
        entry.key: _copyJsonMap(entry.value),
    };
    next.removeWhere(
      (String key, Map<String, dynamic> _) =>
          key.startsWith('trainflow.') && !preservedKeys.contains(key),
    );
    for (final MapEntry<String, Map<String, dynamic>> entry
        in replacementDocuments.entries) {
      next[entry.key] = _copyJsonMap(entry.value);
    }
    await _database.replaceBusinessDataAtomically(
      preservedKeys: preservedKeys,
      replacementDocuments: replacementDocuments,
    );
    _cache
      ..clear()
      ..addAll(next);
  }

  @override
  Future<void> flush() async {
    await _pendingWrites;
    final Object? error = _lastWriteError;
    final StackTrace? stackTrace = _lastWriteStackTrace;
    if (error != null) {
      _lastWriteError = null;
      _lastWriteStackTrace = null;
      Error.throwWithStackTrace(error, stackTrace ?? StackTrace.current);
    }
  }

  Future<void> close() async {
    await flush();
    await _database.close();
  }

  void _enqueueWrite(Future<void> Function() write) {
    _pendingWrites = _pendingWrites.then((_) => write()).catchError(
      (Object error, StackTrace stackTrace) {
        _lastWriteError = error;
        _lastWriteStackTrace = stackTrace;
        _onWriteError?.call(error, stackTrace);
      },
    );
    unawaited(_pendingWrites);
  }
}

Map<String, dynamic> _copyJsonMap(Map<String, dynamic> source) {
  return Map<String, dynamic>.from(
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>,
  );
}
