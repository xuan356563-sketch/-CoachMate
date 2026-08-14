import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localStorageServiceProvider = Provider<LocalStorageService>(
  (ref) => InMemoryLocalStorageService(),
);

abstract class LocalStorageService {
  Map<String, dynamic>? readJson(String key);

  void saveJson(String key, Map<String, dynamic> value);

  void remove(String key);

  void clearBusinessData({Set<String> preservedKeys = const <String>{}});

  Future<void> flush() async {}

  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  }) async {
    clearBusinessData(preservedKeys: preservedKeys);
    for (final MapEntry<String, Map<String, dynamic>> entry
        in replacementDocuments.entries) {
      saveJson(entry.key, entry.value);
    }
    await flush();
  }
}

class InMemoryLocalStorageService implements LocalStorageService {
  final Map<String, Map<String, dynamic>> _store = {};

  @override
  Map<String, dynamic>? readJson(String key) {
    final Map<String, dynamic>? value = _store[key];
    if (value == null) {
      return null;
    }
    return Map<String, dynamic>.from(value);
  }

  @override
  void saveJson(String key, Map<String, dynamic> value) {
    _store[key] = Map<String, dynamic>.from(value);
  }

  @override
  void remove(String key) {
    _store.remove(key);
  }

  @override
  void clearBusinessData({Set<String> preservedKeys = const <String>{}}) {
    _store.removeWhere(
      (String key, Map<String, dynamic> _) =>
          key.startsWith('trainflow.') && !preservedKeys.contains(key),
    );
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  }) async {
    clearBusinessData(preservedKeys: preservedKeys);
    for (final MapEntry<String, Map<String, dynamic>> entry
        in replacementDocuments.entries) {
      saveJson(entry.key, entry.value);
    }
  }
}

/// 已切换 SQLite 后发生故障时使用，防止读取陈旧副本。
class ReadOnlyRecoveryLocalStorageService implements LocalStorageService {
  const ReadOnlyRecoveryLocalStorageService();

  static StateError get _writeError => StateError('当前处于本地数据只读恢复状态，不能写入');

  @override
  Map<String, dynamic>? readJson(String key) => null;

  @override
  void saveJson(String key, Map<String, dynamic> value) => throw _writeError;

  @override
  void remove(String key) => throw _writeError;

  @override
  void clearBusinessData({Set<String> preservedKeys = const <String>{}}) =>
      throw _writeError;

  @override
  Future<void> flush() async {}

  @override
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  }) async {
    throw _writeError;
  }
}

class SharedPreferencesLocalStorageService implements LocalStorageService {
  final SharedPreferencesWithCache _preferences;

  SharedPreferencesLocalStorageService(this._preferences);

  Future<void> _pendingWrites = Future<void>.value();
  Object? _lastWriteError;
  StackTrace? _lastWriteStackTrace;

  static const Set<String> allowedKeys = {
    'trainflow.user_profile.v1',
    'trainflow.body_metrics.v1',
    'trainflow.weekly_reports.v1',
    'trainflow.achievement_records.v1',
    'trainflow.user_insight_tables.v1',
    'trainflow.knowledge_library.v1',
    'trainflow.training_logs.v1',
    'trainflow.pain_logs.v1',
    'trainflow.starter_progress.v1',
    'trainflow.formal_ai_plan.v1',
    'trainflow.reminder_settings.v1',
    'trainflow.daily_context.v1',
    'trainflow.motion_analysis_results.v1',
    'trainflow.meal_preference.v1',
    'trainflow.imported_workouts.v1',
    'trainflow.weekly_report_exports.v1',
    'trainflow.races.v1',
    'trainflow.body_metric_exports.v1',
    'trainflow.plan_adjustments.v1',
    'trainflow.self_use_acceptance.v1',
    'trainflow.daily_check_ins.v1',
    'trainflow.pilot_validation.v1',
    'trainflow.installation_id.v1',
    'trainflow.account_binding.v1',
    'trainflow.training_availability.v1',
    'trainflow.training_schedule.v1',
    'trainflow.generated_training_plan.v1',
    'trainflow.generated_training_plan_draft.v1',
    'trainflow.generated_training_plan_versions.v1',
    'trainflow.health_sync.v1',
    'trainflow.ai_artifacts.v1',
    'trainflow.ai_chat.v1',
    'trainflow.coach_cloud_consent.v1',
    'trainflow.growth_evidence.v2',
    'trainflow.sqlite_cutover.v1',
  };

  static const SharedPreferencesWithCacheOptions cacheOptions =
      SharedPreferencesWithCacheOptions(
    allowList: allowedKeys,
  );

  static Future<SharedPreferencesLocalStorageService> create() async {
    final SharedPreferencesWithCache preferences =
        await SharedPreferencesWithCache.create(cacheOptions: cacheOptions);
    return SharedPreferencesLocalStorageService(preferences);
  }

  @override
  Map<String, dynamic>? readJson(String key) {
    final String? rawValue = _preferences.getString(key);
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }
    final Object? decoded = jsonDecode(rawValue);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return decoded;
  }

  @override
  void saveJson(String key, Map<String, dynamic> value) {
    _enqueueWrite(() async {
      await _preferences.setString(key, jsonEncode(value));
    });
  }

  @override
  void remove(String key) {
    _enqueueWrite(() async {
      await _preferences.remove(key);
    });
  }

  @override
  void clearBusinessData({Set<String> preservedKeys = const <String>{}}) {
    for (final String key in allowedKeys) {
      if (!preservedKeys.contains(key)) {
        _enqueueWrite(() async {
          await _preferences.remove(key);
        });
      }
    }
  }

  @override
  Future<void> flush() async {
    await _pendingWrites;
    final Object? error = _lastWriteError;
    if (error != null) {
      final StackTrace stackTrace = _lastWriteStackTrace ?? StackTrace.current;
      _lastWriteError = null;
      _lastWriteStackTrace = null;
      Error.throwWithStackTrace(
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  }) async {
    clearBusinessData(preservedKeys: preservedKeys);
    for (final MapEntry<String, Map<String, dynamic>> entry
        in replacementDocuments.entries) {
      saveJson(entry.key, entry.value);
    }
    await flush();
  }

  void _enqueueWrite(Future<void> Function() write) {
    _pendingWrites = _pendingWrites.then((_) => write()).catchError(
      (Object error, StackTrace stackTrace) {
        _lastWriteError = error;
        _lastWriteStackTrace = stackTrace;
      },
    );
    unawaited(_pendingWrites);
  }
}
