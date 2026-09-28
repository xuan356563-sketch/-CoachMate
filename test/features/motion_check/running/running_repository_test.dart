import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trainflow_ai/data/local/database_local_storage_service.dart';
import 'package:trainflow_ai/data/local/trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/models/cloud_sync.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/features/motion_check/running/running_form_report_repository.dart';
import 'package:trainflow_ai/features/motion_check/running/running_form_assessment_service.dart';
import 'package:trainflow_ai/features/motion_check/running/running_metrics_service.dart';
import 'running_metrics_test.dart' show sequence;

RunningFormReport report(String id) => RunningFormAssessmentService().assess(
    id: id,
    now: DateTime(2026, 9, 11),
    sequence: sequence(),
    measurements: RunningMetricsService().measure(sequence()),
    captureConfirmed: true);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SharedPreferences 重启读取、业务清理与旧照片数据兼容', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    var storage = await SharedPreferencesLocalStorageService.create();
    storage.saveJson('trainflow.motion_analysis_results.v1', {'results': []});
    await storage.flush();
    await RunningFormReportRepository(storage).save(report('a'));
    storage = await SharedPreferencesLocalStorageService.create();
    expect(RunningFormReportRepository(storage).list().single.id, 'a');
    expect(storage.readJson('trainflow.motion_analysis_results.v1'),
        {'results': []});
    storage.clearBusinessData();
    await storage.flush();
    expect(RunningFormReportRepository(storage).list(), isEmpty);
  });
  test('达到二十份后拒绝新报告，用户删除后才可保存', () async {
    final repository =
        RunningFormReportRepository(InMemoryLocalStorageService());
    for (var i = 0; i < 20; i++) {
      await repository.save(report('r$i'));
    }
    await expectLater(repository.save(report('new')), throwsStateError);
    expect(repository.list(), hasLength(20));
    await repository.delete('r0');
    await repository.save(report('new'));
    expect(repository.list(), hasLength(20));
  });
  test('写入失败后恢复旧文档，保留结果供再次保存', () async {
    final storage = _FailOnceStorage();
    final actual = RunningFormReportRepository(storage);
    await actual.save(report('old'));
    storage.fail = true;
    await expectLater(actual.save(report('new')), throwsStateError);
    expect(actual.list().map((r) => r.id), ['old']);
    await actual.save(report('new'));
    expect(actual.list(), hasLength(2));
  });
  test('真实 SQLite legacy_documents 往返不建新表且不进入云同步', () async {
    final dir = await Directory.systemTemp.createTemp('running-report-test-');
    addTearDown(() => dir.delete(recursive: true));
    final db = _SqliteGateway('${dir.path}/test.sqlite');
    await db.sql(
        'CREATE TABLE legacy_documents(storage_key TEXT PRIMARY KEY,payload_json TEXT NOT NULL);');
    var storage = await DatabaseLocalStorageService.create(db);
    storage.saveJson('trainflow.account_binding.v1', {'userId': 'synthetic-a'});
    await storage.flush();
    db.cloudWrites = 0;
    await RunningFormReportRepository(storage).save(report('sqlite'));
    await storage.close();
    storage = await DatabaseLocalStorageService.create(db);
    expect(RunningFormReportRepository(storage).list().single.id, 'sqlite');
    expect(db.cloudWrites, 0);
    expect(
        (await db.sql("SELECT name FROM sqlite_master WHERE type='table';"))
            .trim(),
        'legacy_documents');
    storage.clearBusinessData();
    await storage.flush();
    expect(RunningFormReportRepository(storage).list(), isEmpty);
  });
  test('损坏或未来格式保留原文，不通过保存覆盖', () async {
    final storage = InMemoryLocalStorageService()
      ..saveJson(RunningFormReportRepository.storageKey,
          {'schemaVersion': 99, 'reports': []});
    final repository = RunningFormReportRepository(storage);
    await expectLater(repository.save(report('new')), throwsFormatException);
    expect(
        storage
            .readJson(RunningFormReportRepository.storageKey)?['schemaVersion'],
        99);
  });
}

class _FailOnceStorage extends InMemoryLocalStorageService {
  bool fail = false;
  @override
  Future<void> flush() async {
    if (fail) {
      fail = false;
      throw StateError('合成磁盘写入失败');
    }
  }
}

class _SqliteGateway
    implements TrainFlowDatabaseGateway, TrainFlowCloudSyncWriteGateway {
  _SqliteGateway(this.path);
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
