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
}

class SharedPreferencesLocalStorageService implements LocalStorageService {
  final SharedPreferencesWithCache _preferences;

  const SharedPreferencesLocalStorageService(this._preferences);

  static const SharedPreferencesWithCacheOptions cacheOptions =
      SharedPreferencesWithCacheOptions(
    allowList: {
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
    },
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
    unawaited(_preferences.setString(key, jsonEncode(value)));
  }

  @override
  void remove(String key) {
    unawaited(_preferences.remove(key));
  }
}
