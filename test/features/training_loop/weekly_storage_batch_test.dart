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
import 'package:trainflow_ai/data/models/weekly_psych_check_in.dart';
import 'package:trainflow_ai/data/repositories/weekly_report_repository.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final sqlite in [true, false]) {
    test('${sqlite ? 'SQLite 文档适配器' : 'SharedPreferences'}真实写队列失败恢复、重建回读与账号清理',
        () async {
      final database = _Database();
      final preferences = _Preferences();
      final previousPlatform = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance = preferences;
      addTearDown(
          () => SharedPreferencesAsyncPlatform.instance = previousPlatform);
      Future<LocalStorageService> reopen() => sqlite
          ? DatabaseLocalStorageService.create(database)
          : SharedPreferencesLocalStorageService.create();
      final storage = await reopen();
      final container = ProviderContainer(overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);
      final controller = container.read(trainingMvpProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await storage.flush();
      final planBefore =
          container.read(trainingMvpProvider).activePlan.toJson();
      final logsBefore = container
          .read(trainingMvpProvider)
          .logs
          .map((e) => e.toJson())
          .toList();
      // 给投影提供账号条件，不能因为没有账号而假称报告不会进入同步。
      storage.saveJson(
          'trainflow.account_binding.v1', {'userId': 'synthetic-account'});
      await storage.flush();
      database.cloudWrites = 0;
      Future<void> save(String note) => controller.savePsychologyWeeklyReport(
          psychCheckIn: WeeklyPsychCheckIn(weekNote: note));
      await save('账号甲旧报告');
      final old = storage.readJson(PersistedWeeklyReportRepository.storageKey);
      if (sqlite) {
        database.failNextReport = true;
      } else {
        preferences.failNextReport = true;
      }
      await expectLater(save('不能显示成功'), throwsStateError);
      expect(storage.readJson(PersistedWeeklyReportRepository.storageKey), old);
      expect(
          (await reopen()).readJson(PersistedWeeklyReportRepository.storageKey),
          old);
      await save('重试保存');
      var restored =
          PersistedWeeklyReportRepository(await reopen()).listReports();
      expect(restored, hasLength(1));
      expect(restored.single.psychCheckIn!.weekNote, '重试保存');
      final option = restored.single.options.first.id;
      await controller.selectWeeklyReportOption(
          reportId: restored.single.id, optionId: option);
      await controller.selectWeeklyReportOption(
          reportId: restored.single.id, optionId: option);
      restored = PersistedWeeklyReportRepository(await reopen()).listReports();
      expect(restored, hasLength(1));
      expect(restored.single.selectedOptionId, option);
      expect(
          container.read(trainingMvpProvider).activePlan.toJson(), planBefore);
      expect(
          container
              .read(trainingMvpProvider)
              .logs
              .map((e) => e.toJson())
              .toList(),
          logsBefore);
      expect(database.cloudWrites, 0);
      storage.clearBusinessData();
      await storage.flush();
      expect(PersistedWeeklyReportRepository(await reopen()).listReports(),
          isEmpty);
    });
  }
}

final class _Preferences extends InMemorySharedPreferencesAsync {
  _Preferences() : super.empty();
  bool failNextReport = false;
  @override
  Future<bool> setString(
      String key, String value, SharedPreferencesOptions options) async {
    if (key == PersistedWeeklyReportRepository.storageKey && failNextReport) {
      failNextReport = false;
      throw StateError('合成偏好存储写入失败');
    }
    return super.setString(key, value, options);
  }
}

// 复用真实 SQLite 文档适配器的缓存与写队列，只在底层网关注入故障。
class _Database
    implements TrainFlowDatabaseGateway, TrainFlowCloudSyncWriteGateway {
  final Map<String, Map<String, dynamic>> documents = {};
  bool failNextReport = false;
  int cloudWrites = 0;
  Map<String, dynamic> copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  @override
  Future<Map<String, Map<String, dynamic>>> readAllLegacyDocuments() async =>
      documents.map((key, value) => MapEntry(key, copy(value)));
  @override
  Future<void> upsertLegacyDocument(
      String key, Map<String, dynamic> value) async {
    if (key == PersistedWeeklyReportRepository.storageKey && failNextReport) {
      failNextReport = false;
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
