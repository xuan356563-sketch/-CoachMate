import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:trainflow_ai/data/local/database_local_storage_service.dart';
import 'package:trainflow_ai/data/local/trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/models/cloud_sync.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/repositories/training_log_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/data/repositories/daily_check_in_repository.dart';
import 'package:trainflow_ai/data/models/daily_check_in_record.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_export_controller.dart';
import 'package:trainflow_ai/data/repositories/body_metric_export_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final sqlite in [true, false]) {
    test('${sqlite ? 'SQLite 文档适配器' : 'SharedPreferences'}恢复来源标记重启与账号清理', () async {
      final database = _Database();
      final preferences = _Preferences();
      final previous = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance = preferences;
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
      Future<LocalStorageService> reopen() => sqlite
          ? DatabaseLocalStorageService.create(database)
          : SharedPreferencesLocalStorageService.create();
      final storage = await reopen();
      final now = DateTime.now();
      final raw = <String, dynamic>{
        'id': 'synthetic-recovery-old', 'workoutDayId': 'synthetic-workout',
        'date': now.toIso8601String(), 'createdAt': now.toIso8601String(),
        'completed': true, 'rpe': 8, 'logKind': 'unknown',
      };
      PersistedTrainingLogRepository(storage).saveLog(TrainingLog.fromJson(raw));
      await storage.flush();
      final restored = PersistedTrainingLogRepository(await reopen()).listLogs().single;
      expect(restored.rpe, 8);
      expect(restored.canEstimateRecoveryAt(DateTime.now()), isFalse);
      final valid = TrainingLog.fromJson({...raw, 'id': 'synthetic-recovery-valid', 'logKind': 'sessionReview'});
      PersistedTrainingLogRepository(storage).saveLog(valid);
      await storage.flush();
      expect(PersistedTrainingLogRepository(await reopen()).listLogs()
          .singleWhere((log) => log.id == valid.id).canEstimateRecoveryAt(DateTime.now()), isTrue);
      storage.clearBusinessData();
      await storage.flush();
      expect(PersistedTrainingLogRepository(await reopen()).listLogs(), isEmpty);
    });
    for (final clearing in [false, true]) {
      test('${sqlite ? 'SQLite 文档适配器' : 'SharedPreferences'}导出${clearing ? '清除' : '登记'}失败恢复、重启与账号清理', () async {
        final database = _Database();
        final preferences = _Preferences();
        final previous = SharedPreferencesAsyncPlatform.instance;
        SharedPreferencesAsyncPlatform.instance = preferences;
        addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
        Future<LocalStorageService> reopen() => sqlite
            ? DatabaseLocalStorageService.create(database)
            : SharedPreferencesLocalStorageService.create();
        final storage = await reopen();
        final container = ProviderContainer(overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
        ]);
        addTearDown(container.dispose);
        storage.saveJson('trainflow.account_binding.v1', {'userId': 'synthetic-export-account'});
        await storage.flush();
        database.cloudWrites = 0;
        final controller = container.read(bodyMetricExportControllerProvider.notifier);
        await controller.recordJsonExport('旧合成预览');
        const key = PersistedBodyMetricExportRepository.storageKey;
        final before = (await reopen()).readJson(key);
        if (sqlite) {
          database.failNextExport = true;
        } else {
          preferences.failNextExport = true;
        }
        Future<void> action() => clearing ? controller.clear() : controller.recordCsvExport('新合成预览');
        await expectLater(action(), throwsStateError);
        expect((await reopen()).readJson(key), before);
        expect(container.read(bodyMetricExportControllerProvider).records, hasLength(1));
        await action();
        expect(PersistedBodyMetricExportRepository(await reopen()).listRecords(), hasLength(clearing ? 0 : 2));
        expect(database.cloudWrites, 0);
        storage.clearBusinessData();
        await storage.flush();
        expect((await reopen()).readJson(key), isNull);
      });
    }
    for (final sameYesterday in [false, true]) {
      for (final failBody in [false, true]) {
        test('${sqlite ? "SQLite" : "SharedPreferences"} ${sameYesterday ? "昨日预填" : "快录"} ${failBody ? "首文档" : "次文档"}失败恢复、重启、重试和账号清理', () async {
          final database = _Database();
          final preferences = _Preferences();
          final previous = SharedPreferencesAsyncPlatform.instance;
          SharedPreferencesAsyncPlatform.instance = preferences;
          addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
          Future<LocalStorageService> reopen() => sqlite
              ? DatabaseLocalStorageService.create(database)
              : SharedPreferencesLocalStorageService.create();
          final storage = await reopen();
          final container = ProviderContainer(overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
          ]);
          addTearDown(container.dispose);
          storage.saveJson('trainflow.account_binding.v1', {'userId': 'synthetic-joint-account'});
          if (sameYesterday) {
            final now = DateTime.now();
            storage.saveJson('trainflow.body_metrics.v1', {'metrics': [{
              'id': 'synthetic-yesterday',
              'measuredAt': DateTime(now.year, now.month, now.day - 1, 7).toIso8601String(),
              'source': 'manual', 'weightKg': 70.0, 'restingHeartRate': 60,
              'hrvMs': 50, 'sleepHours': 7.0, 'fatigueLevel': 3,
            }]});
          }
          await storage.flush();
          final controller = container.read(bodyMetricControllerProvider.notifier);
          controller.recognizeSnapshotText('体重 70 体脂率 18 静息心率 60 HRV 50 睡眠 7 疲劳 3 酸痛 2');
          await controller.confirmPendingMetric();
          const bodyKey = 'trainflow.body_metrics.v1';
          const checkKey = PersistedDailyCheckInRepository.storageKey;
          final oldBody = storage.readJson(bodyKey);
          final oldCheck = storage.readJson(checkKey);
          database.cloudWrites = 0;
          if (sqlite) {
            database.failNextBody = failBody;
            database.failNextCheckIn = !failBody;
          } else {
            preferences.failNextBody = failBody;
            preferences.failNextCheckIn = !failBody;
          }
          Future<void> save() => sameYesterday
              ? controller.confirmDailyCheckInSameAsYesterday()
              : controller.saveManualMetric(weightKg: 71, restingHeartRate: 61,
                  hrvMs: 51, sleepHours: 7.1, fatigueLevel: 3);
          await expectLater(save(), throwsStateError);
          final failed = await reopen();
          expect(failed.readJson(bodyKey), oldBody);
          expect(failed.readJson(checkKey), oldCheck);
          await save();
          final saved = await reopen();
          expect(PersistedBodyMetricRepository(saved).listMetrics().first.weightKg,
              sameYesterday ? 70 : 71);
          expect(PersistedBodyMetricRepository(saved).listMetrics(), hasLength(sameYesterday ? 2 : 1));
          expect(PersistedBodyMetricRepository(saved).listRevisions(), hasLength(1));
          expect(PersistedDailyCheckInRepository(saved).getSnapshot().records, hasLength(1));
          expect(database.cloudWrites, 0);
          storage.clearBusinessData();
          await storage.flush();
          final cleared = await reopen();
          expect(cleared.readJson(bodyKey), isNull);
          expect(cleared.readJson(checkKey), isNull);
        });
      }
    }
    test('${sqlite ? 'SQLite 文档适配器' : 'SharedPreferences'}签到与成就收取失败恢复、重启及本机边界', () async {
      final database = _Database();
      final preferences = _Preferences();
      final previous = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance = preferences;
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
      Future<LocalStorageService> reopen() => sqlite
          ? DatabaseLocalStorageService.create(database)
          : SharedPreferencesLocalStorageService.create();
      final storage = await reopen();
      storage.saveJson('trainflow.account_binding.v1', {'userId': 'synthetic-check-in-account'});
      final seed = PersistedDailyCheckInRepository(storage);
      final today = DateTime.now();
      for (var i = 6; i > 0; i--) {
        final date = DateTime(today.year, today.month, today.day - i);
        seed.record(localDate: date, confirmedAt: date, source: DailyCheckInSource.prefilled);
      }
      await storage.flush();
      database.cloudWrites = 0;
      final container = ProviderContainer(overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
      addTearDown(container.dispose);
      final controller = container.read(bodyMetricControllerProvider.notifier);
      void fail() {
        if (sqlite) { database.failNextCheckIn = true; }
        else { preferences.failNextCheckIn = true; }
      }
      const key = PersistedDailyCheckInRepository.storageKey;
      final before = storage.readJson(key);
      fail();
      await expectLater(controller.recordContinuityDay(DailyContinuityKind.plannedRest), throwsStateError);
      expect((await reopen()).readJson(key), before);
      await controller.recordContinuityDay(DailyContinuityKind.plannedRest);
      var reopened = PersistedDailyCheckInRepository(await reopen()).getSnapshot();
      expect(reopened.records, hasLength(7));
      expect(reopened.unseenCelebrations.single.id, 'growth_days_7');
      final saved = storage.readJson(key);
      fail();
      await expectLater(controller.markCheckInCelebrationSeen('growth_days_7'), throwsStateError);
      expect((await reopen()).readJson(key), saved);
      await controller.markCheckInCelebrationSeen('growth_days_7');
      reopened = PersistedDailyCheckInRepository(await reopen()).getSnapshot();
      expect(reopened.records, hasLength(7));
      expect(reopened.unseenCelebrations, isEmpty);
      expect(database.cloudWrites, 0);
      storage.clearBusinessData(); await storage.flush();
      expect(PersistedDailyCheckInRepository(await reopen()).getSnapshot().records, isEmpty);
    });
    test('${sqlite ? 'SQLite 文档适配器' : 'SharedPreferences'}CSV 整批失败恢复、重试和账号清理', () async {
      final database = _Database();
      final preferences = _Preferences();
      final previous = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance = preferences;
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
      Future<LocalStorageService> reopen() => sqlite
          ? DatabaseLocalStorageService.create(database)
          : SharedPreferencesLocalStorageService.create();
      final storage = await reopen();
      final container = ProviderContainer(overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);
      storage.saveJson('trainflow.account_binding.v1', {'userId': 'synthetic-csv-account'});
      await storage.flush();
      database.cloudWrites = 0;
      const header = 'date,weight,body_fat,resting_hr,hrv,sleep,fatigue,soreness';
      const initial = '$header\n2026-09-16,70,18,60,50,7,3,2';
      const batch = '$header\n2026-09-16,71,18,60,50,7,3,2\n2026-09-17,72,18,60,50,7,3,2';
      final controller = container.read(bodyMetricControllerProvider.notifier);
      await controller.importCsv(initial);
      final before = storage.readJson('trainflow.body_metrics.v1');
      if (sqlite) {
        database.failNextBody = true;
      } else {
        preferences.failNextBody = true;
      }
      await expectLater(controller.importCsv(batch), throwsStateError);
      expect((await reopen()).readJson('trainflow.body_metrics.v1'), before);
      expect(container.read(bodyMetricControllerProvider).metrics.single.weightKg, 70);
      await controller.importCsv(batch);
      final restored = PersistedBodyMetricRepository(await reopen());
      expect(restored.listMetrics().map((e) => e.weightKg), [72, 71]);
      expect(restored.listRevisions(), hasLength(1));
      expect(database.cloudWrites, 0);
      storage.clearBusinessData();
      await storage.flush();
      expect(PersistedBodyMetricRepository(await reopen()).listMetrics(), isEmpty);
    });
    test('${sqlite ? 'SQLite 文档适配器' : 'SharedPreferences'}确认失败恢复、重启回读和本机边界',
        () async {
      final database = _Database();
      final preferences = _Preferences();
      final previous = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance = preferences;
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
      Future<LocalStorageService> reopen() => sqlite
          ? DatabaseLocalStorageService.create(database)
          : SharedPreferencesLocalStorageService.create();
      final storage = await reopen();
      final container = ProviderContainer(overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);
      storage.saveJson(
          'trainflow.account_binding.v1', {'userId': 'synthetic-account'});
      await storage.flush();
      database.cloudWrites = 0;
      final controller = container.read(bodyMetricControllerProvider.notifier);
      controller
          .recognizeSnapshotText('体重 70 体脂率 18 静息心率 60 HRV 50 睡眠 7 疲劳 3 酸痛 2');
      await controller.confirmPendingMetric();
      final before = storage.readJson('trainflow.body_metrics.v1');
      controller
          .recognizeSnapshotText('体重 71 体脂率 18 静息心率 60 HRV 50 睡眠 7 疲劳 3 酸痛 2');
      if (sqlite) {
        database.failNextBody = true;
      } else {
        preferences.failNextBody = true;
      }
      await expectLater(controller.confirmPendingMetric(), throwsStateError);
      expect((await reopen()).readJson('trainflow.body_metrics.v1'), before);
      await controller.confirmPendingMetric();
      final restored = PersistedBodyMetricRepository(await reopen());
      expect(restored.listMetrics().single.weightKg, 71);
      expect(restored.listRevisions(), hasLength(1));
      expect(database.cloudWrites, 0);
      storage.clearBusinessData();
      await storage.flush();
      expect(
          PersistedBodyMetricRepository(await reopen()).listMetrics(), isEmpty);
    });
  }
}

final class _Preferences extends InMemorySharedPreferencesAsync {
  _Preferences() : super.empty();
  bool failNextBody = false;
  bool failNextCheckIn = false;
  bool failNextExport = false;
  @override
  Future<bool> setString(
      String key, String value, SharedPreferencesOptions options) async {
    if (key == PersistedBodyMetricExportRepository.storageKey && failNextExport) {
      failNextExport = false;
      throw StateError('合成导出登记写入失败');
    }
    if (key == PersistedDailyCheckInRepository.storageKey && failNextCheckIn) {
      failNextCheckIn = false;
      throw StateError('合成签到写入失败');
    }
    if (key == 'trainflow.body_metrics.v1' && failNextBody) {
      failNextBody = false;
      throw StateError('合成偏好存储写入失败');
    }
    return super.setString(key, value, options);
  }
}

// 复用真实 SQLite 文档适配器的缓存与写队列，只在底层网关注入故障。
class _Database
    implements TrainFlowDatabaseGateway, TrainFlowCloudSyncWriteGateway {
  final Map<String, Map<String, dynamic>> documents = {};
  bool failNextBody = false;
  bool failNextCheckIn = false;
  bool failNextExport = false;
  int cloudWrites = 0;
  Map<String, dynamic> copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  @override
  Future<Map<String, Map<String, dynamic>>> readAllLegacyDocuments() async =>
      documents.map((key, value) => MapEntry(key, copy(value)));
  @override
  Future<void> upsertLegacyDocument(
      String key, Map<String, dynamic> value) async {
    if (key == PersistedBodyMetricExportRepository.storageKey && failNextExport) {
      failNextExport = false;
      throw StateError('合成导出登记写入失败');
    }
    if (key == PersistedDailyCheckInRepository.storageKey && failNextCheckIn) {
      failNextCheckIn = false;
      throw StateError('合成签到写入失败');
    }
    if (key == 'trainflow.body_metrics.v1' && failNextBody) {
      failNextBody = false;
      throw StateError('合成数据库写入失败');
    }
    documents[key] = copy(value);
  }

  @override
  Future<void> deleteLegacyDocument(String key) async => documents.remove(key);
  @override
  Future<void> clearLegacyDocuments(
          {Set<String> preservedKeys = const {}}) async =>
      documents.removeWhere((key, _) => !preservedKeys.contains(key));
  @override
  Future<void> replaceBusinessDataAtomically(
      {Set<String> preservedKeys = const {},
      Map<String, Map<String, dynamic>> replacementDocuments =
          const {}}) async {
    await clearLegacyDocuments(preservedKeys: preservedKeys);
    documents.addAll(
        replacementDocuments.map((key, value) => MapEntry(key, copy(value))));
  }

  @override
  Future<void> upsertLegacyDocumentWithCloudMutations(
      {required String key,
      required Map<String, dynamic> value,
      required String accountId,
      required List<CloudSyncMutation> mutations}) async {
    cloudWrites++;
    await upsertLegacyDocument(key, value);
  }

  @override
  Future<T> transaction<T>(
          Future<T> Function(TrainFlowDatabaseTransaction) action) =>
      throw StateError('此合成测试未提供事务接口');
  @override
  Future<void> close() async {}
}
