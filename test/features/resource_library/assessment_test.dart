import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trainflow_ai/data/local/database_local_storage_service.dart';
import 'package:trainflow_ai/data/local/trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/models/cloud_sync.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/features/resource_library/resource_catalog.dart';
import 'package:trainflow_ai/features/resource_library/assessment_record.dart';
import 'package:trainflow_ai/features/resource_library/assessment_record_repository.dart';
import 'package:trainflow_ai/features/resource_library/resource_library_page.dart';
import 'package:trainflow_ai/features/capabilities/assessment_history_page.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';

AssessmentRecord record(String id) => AssessmentService().record(
    guide: ResourceCatalog().list().whereType<AssessmentGuide>().first,
    id: id,
    assessedAt: DateTime(2026, 9, 12),
    values: {'duration': '30'});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('留空不补成绩，标签与来源快照稳定，非法数字拒绝', () {
    final r = record('a');
    expect(r.values, {'duration': '30'});
    expect(AssessmentRecord.fromJson(r.toJson()).toJson(), r.toJson());
    final guide = ResourceCatalog().list().whereType<AssessmentGuide>().first;
    for (final value in ['NaN', '-2', 'Infinity', 'abc']) {
      expect(
          () => AssessmentService().record(
              guide: guide,
              id: 'a',
              assessedAt: DateTime.now(),
              values: {'duration': value}),
          throwsFormatException);
    }
  });
  test('保存失败恢复旧记录，重试与显式删除正常', () async {
    final storage = FailStorage();
    final repo = AssessmentRecordRepository(storage);
    await repo.save(record('a'));
    storage.fail = true;
    await expectLater(repo.save(record('b')), throwsStateError);
    expect(repo.list().map((r) => r.id), ['a']);
    await repo.save(record('b'));
    await repo.delete('a');
    expect(repo.list().map((r) => r.id), ['b']);
  });
  test('SharedPreferences重启与清理兼容旧记录', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    var storage = await SharedPreferencesLocalStorageService.create();
    storage.saveJson('trainflow.running_form_reports.v1',
        {'schemaVersion': 1, 'reports': []});
    await AssessmentRecordRepository(storage).save(record('a'));
    storage = await SharedPreferencesLocalStorageService.create();
    expect(AssessmentRecordRepository(storage).list().single.id, 'a');
    expect(storage.readJson('trainflow.running_form_reports.v1'), isNotNull);
    storage.clearBusinessData();
    await storage.flush();
    expect(AssessmentRecordRepository(storage).list(), isEmpty);
  });
  test('未知格式禁止覆盖', () async {
    final storage = InMemoryLocalStorageService();
    storage
        .saveJson(AssessmentRecordRepository.storageKey, {'schemaVersion': 99});
    expect(() => AssessmentRecordRepository(storage).save(record('a')),
        throwsFormatException);
    expect(storage.readJson(AssessmentRecordRepository.storageKey),
        {'schemaVersion': 99});
  });
  test('SQLite评估往返不新增表不触发云同步', () async {
    final dir = await Directory.systemTemp.createTemp('resource-sqlite-');
    addTearDown(() => dir.delete(recursive: true));
    final db = SqliteGateway('${dir.path}/test.sqlite');
    await db.sql(
        'CREATE TABLE legacy_documents(storage_key TEXT PRIMARY KEY,payload_json TEXT NOT NULL);');
    var storage = await DatabaseLocalStorageService.create(db);
    storage.saveJson('trainflow.account_binding.v1', {'userId': 'synthetic-a'});
    await storage.flush();
    db.cloudWrites = 0;
    await AssessmentRecordRepository(storage).save(record('a'));
    storage = await DatabaseLocalStorageService.create(db);
    expect(AssessmentRecordRepository(storage).list().single.id, 'a');
    expect(db.cloudWrites, 0);
    expect(
        (await db.sql("SELECT name FROM sqlite_master WHERE type='table';"))
            .trim(),
        'legacy_documents');
  });
  testWidgets('先预览再保存，计划不变；停用后只读历史，账号清理后消失', (tester) async {
    final f = await ResourceFixture.create();
    addTearDown(f.close);
    f.storage
        .saveJson('trainflow.generated_training_plan.v1', {'sentinel': '当前计划'});
    await tester.pumpWidget(UncontrolledProviderScope(
        container: f.container,
        child: const MaterialApp(
            home: ResourceDetailPage(
                resourceId: 'assessment.marathon.baseline'))));
    await tester.enterText(find.byKey(const ValueKey('duration')), '30');
    await tester.ensureVisible(find.text('查看事实汇总'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看事实汇总'));
    await tester.pump();
    expect(AssessmentRecordRepository(f.storage).list(), isEmpty);
    await tester.ensureVisible(find.text('保存评估记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存评估记录'));
    await tester.pumpAndSettle();
    expect(AssessmentRecordRepository(f.storage).list(), hasLength(1));
    expect(f.storage.readJson('trainflow.generated_training_plan.v1'),
        {'sentinel': '当前计划'});
    await f.runtime.disable('feature.resource_library');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: f.container,
        child: const MaterialApp(home: AssessmentHistoryPage())));
    await tester.pumpAndSettle();
    expect(find.text('马拉松训练基础评估'), findsOneWidget);
    await f.runtime.changeAccountScope(replaceScope: () async {
      f.storage.clearBusinessData();
      await f.storage.flush();
    });
    await tester.pumpAndSettle();
    expect(find.text('还没有已保存的评估记录。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class FailStorage extends InMemoryLocalStorageService {
  bool fail = false;
  @override
  Future<void> flush() async {
    if (fail) {
      fail = false;
      throw StateError('合成持久化失败');
    }
  }
}

class ResourceFixture {
  ResourceFixture(this.storage, this.runtime, this.container);
  final InMemoryLocalStorageService storage;
  final PluginRuntime runtime;
  final ProviderContainer container;
  static Future<ResourceFixture> create(
      {InMemoryLocalStorageService? storage}) async {
    final local = storage ?? InMemoryLocalStorageService();
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(local),
      pluginRuntimeProvider.overrideWith((ref) => runtime)
    ]);
    return ResourceFixture(local, runtime, container);
  }

  void close() => container.dispose();
}

class SqliteGateway
    implements TrainFlowDatabaseGateway, TrainFlowCloudSyncWriteGateway {
  SqliteGateway(this.path);
  final String path;
  int cloudWrites = 0;
  Future<String> sql(String query) async {
    final result = await Process.run('sqlite3', [path, query]);
    if (result.exitCode != 0) throw StateError('合成 SQLite 测试失败');
    return result.stdout as String;
  }

  String quote(String s) => "'${s.replaceAll("'", "''")}'";
  @override
  Future<Map<String, Map<String, dynamic>>> readAllLegacyDocuments() async {
    final raw = await sql(
        "SELECT json_group_array(json_object('key',storage_key,'value',payload_json)) FROM legacy_documents;");
    return {
      for (final row in jsonDecode(raw) as List)
        row['key'] as String:
            Map<String, dynamic>.from(jsonDecode(row['value'] as String) as Map)
    };
  }

  @override
  Future<void> upsertLegacyDocument(
      String key, Map<String, dynamic> value) async {
    await sql(
        'INSERT OR REPLACE INTO legacy_documents VALUES(${quote(key)},${quote(jsonEncode(value))});');
  }

  @override
  Future<void> deleteLegacyDocument(String key) async {
    await sql('DELETE FROM legacy_documents WHERE storage_key=${quote(key)};');
  }

  @override
  Future<void> clearLegacyDocuments(
      {Set<String> preservedKeys = const {}}) async {
    await sql('DELETE FROM legacy_documents;');
  }

  @override
  Future<void> close() async {}
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
