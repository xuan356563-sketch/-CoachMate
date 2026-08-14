import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/legacy_storage_migrator.dart';
import 'package:trainflow_ai/data/local/trainflow_database_gateway.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('旧设备数据会在单事务内迁移、校验并保留原始副本', () async {
    final InMemoryLocalStorageService legacy = InMemoryLocalStorageService()
      ..saveJson('trainflow.user_profile.v1', _profileDocument())
      ..saveJson('trainflow.training_logs.v1', <String, dynamic>{
        'logs': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'log-1', 'rpe': 6},
        ],
      });
    final _FakeDatabaseGateway database = _FakeDatabaseGateway();
    final LegacyStorageMigrator migrator = LegacyStorageMigrator(
      legacyStorage: legacy,
      database: database,
      storageKeys: const <String>{
        'trainflow.user_profile.v1',
        'trainflow.training_logs.v1',
        'trainflow.races.v1',
      },
      clock: () => DateTime.utc(2026, 7, 14, 12),
    );

    final LegacyMigrationResult result = await migrator.migrate();

    expect(result.migratedDocumentCount, 2);
    expect(result.wasAlreadyCompleted, isFalse);
    expect(database.documents, hasLength(2));
    expect(
      database.documents['trainflow.user_profile.v1']?['profile']?['name'],
      '迁移测试用户',
    );
    expect(database.athleteProfiles.single['id'], 'athlete-legacy');
    expect(database.athleteProfiles.single['biological_sex'], 'female');
    expect(database.checkpoints.single.sourceDocumentCount, 2);
    expect(database.checkpoints.single.migratedDocumentCount, 2);
    expect(
      legacy.readJson('trainflow.user_profile.v1')?['profile']?['name'],
      '迁移测试用户',
      reason: '迁移成功后也不能删除 SharedPreferences 中的原始数据',
    );
  });

  test('已完成的迁移再次执行时不会重复写入', () async {
    final InMemoryLocalStorageService legacy = InMemoryLocalStorageService()
      ..saveJson('trainflow.user_profile.v1', _profileDocument());
    final _FakeDatabaseGateway database = _FakeDatabaseGateway();
    final LegacyStorageMigrator migrator = LegacyStorageMigrator(
      legacyStorage: legacy,
      database: database,
      storageKeys: const <String>{'trainflow.user_profile.v1'},
    );

    await migrator.migrate();
    final int firstWriteCount = database.transactionDocumentWriteCount;
    final LegacyMigrationResult secondResult = await migrator.migrate();

    expect(secondResult.wasAlreadyCompleted, isTrue);
    expect(secondResult.migratedDocumentCount, 1);
    expect(database.transactionDocumentWriteCount, firstWriteCount);
  });

  test('任一文档回读校验失败时会回滚全部迁移内容', () async {
    final InMemoryLocalStorageService legacy = InMemoryLocalStorageService()
      ..saveJson('trainflow.user_profile.v1', _profileDocument())
      ..saveJson('trainflow.races.v1', <String, dynamic>{'races': <dynamic>[]});
    final _FakeDatabaseGateway database = _FakeDatabaseGateway(
      corruptedReadbackKey: 'trainflow.races.v1',
    );
    final LegacyStorageMigrator migrator = LegacyStorageMigrator(
      legacyStorage: legacy,
      database: database,
      storageKeys: const <String>{
        'trainflow.user_profile.v1',
        'trainflow.races.v1',
      },
    );

    await expectLater(
      migrator.migrate(),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          '错误提示',
          contains('trainflow.races.v1'),
        ),
      ),
    );

    expect(database.documents, isEmpty);
    expect(database.checkpoints, isEmpty);
    expect(database.athleteProfiles, isEmpty);
  });

  test('无旧资料时会在同一迁移事务中建立实际默认运动员', () async {
    final _FakeDatabaseGateway database = _FakeDatabaseGateway();
    final LegacyStorageMigrator migrator = LegacyStorageMigrator(
      legacyStorage: InMemoryLocalStorageService(),
      database: database,
      storageKeys: const <String>{'trainflow.user_profile.v1'},
    );

    await migrator.migrate();

    expect(database.athleteProfiles.single['id'], 'user-local-demo');
    expect(database.cutoverMarked, isTrue);
  });

  test('旧资料文档损坏时回滚运动员投影和切换标记', () async {
    final InMemoryLocalStorageService legacy = InMemoryLocalStorageService()
      ..saveJson('trainflow.user_profile.v1', <String, dynamic>{
        'profileCompleted': true,
        'profile': '损坏的资料',
      });
    final _FakeDatabaseGateway database = _FakeDatabaseGateway();

    await expectLater(
      LegacyStorageMigrator(
        legacyStorage: legacy,
        database: database,
        storageKeys: const <String>{'trainflow.user_profile.v1'},
      ).migrate(),
      throwsA(isA<FormatException>()),
    );

    expect(database.documents, isEmpty);
    expect(database.athleteProfiles, isEmpty);
    expect(database.cutoverMarked, isFalse);
  });
}

class _FakeDatabaseGateway implements TrainFlowDatabaseGateway {
  _FakeDatabaseGateway({this.corruptedReadbackKey});

  final String? corruptedReadbackKey;
  Map<String, Map<String, dynamic>> documents =
      <String, Map<String, dynamic>>{};
  List<MigrationCheckpoint> checkpoints = <MigrationCheckpoint>[];
  List<Map<String, Object?>> athleteProfiles = <Map<String, Object?>>[];
  bool cutoverMarked = false;
  int transactionDocumentWriteCount = 0;
  bool isClosed = false;

  @override
  Future<void> clearLegacyDocuments({
    Set<String> preservedKeys = const <String>{},
  }) async {
    documents.removeWhere(
      (String key, Map<String, dynamic> _) =>
          key.startsWith('trainflow.') && !preservedKeys.contains(key),
    );
  }

  @override
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  }) async {
    throw UnimplementedError('此迁移测试不需要账号清理');
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<void> deleteLegacyDocument(String key) async {
    documents.remove(key);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readAllLegacyDocuments() async {
    return _copyDocuments(documents);
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(TrainFlowDatabaseTransaction transaction) action,
  ) async {
    final Map<String, Map<String, dynamic>> pendingDocuments =
        _copyDocuments(documents);
    final List<MigrationCheckpoint> pendingCheckpoints =
        List<MigrationCheckpoint>.from(checkpoints);
    final List<Map<String, Object?>> pendingAthleteProfiles =
        athleteProfiles.map(Map<String, Object?>.from).toList();
    final _FakeDatabaseTransaction transaction = _FakeDatabaseTransaction(
      documents: pendingDocuments,
      checkpoints: pendingCheckpoints,
      athleteProfiles: pendingAthleteProfiles,
      cutoverMarked: cutoverMarked,
      corruptedReadbackKey: corruptedReadbackKey,
    );
    final T result = await action(transaction);
    documents = pendingDocuments;
    checkpoints = pendingCheckpoints;
    athleteProfiles = pendingAthleteProfiles;
    cutoverMarked = transaction.cutoverMarked;
    transactionDocumentWriteCount += transaction.documentWriteCount;
    return result;
  }

  @override
  Future<void> upsertLegacyDocument(
    String key,
    Map<String, dynamic> value,
  ) async {
    documents[key] = Map<String, dynamic>.from(value);
  }
}

class _FakeDatabaseTransaction implements TrainFlowDatabaseTransaction {
  _FakeDatabaseTransaction({
    required this.documents,
    required this.checkpoints,
    required this.athleteProfiles,
    required this.cutoverMarked,
    required this.corruptedReadbackKey,
  });

  final Map<String, Map<String, dynamic>> documents;
  final List<MigrationCheckpoint> checkpoints;
  final List<Map<String, Object?>> athleteProfiles;
  final String? corruptedReadbackKey;
  int documentWriteCount = 0;
  bool cutoverMarked;

  @override
  Future<void> upsertAthleteProfileRow(Map<String, Object?> row) async {
    athleteProfiles.removeWhere((item) => item['id'] == row['id']);
    athleteProfiles.add(Map<String, Object?>.from(row));
  }

  @override
  Future<void> markStorageCutover({
    required int schemaVersion,
    required DateTime completedAt,
  }) async {
    cutoverMarked = true;
  }

  @override
  Future<void> markMigrationCompleted(MigrationCheckpoint checkpoint) async {
    checkpoints.removeWhere(
      (MigrationCheckpoint item) => item.migrationId == checkpoint.migrationId,
    );
    checkpoints.add(checkpoint);
  }

  @override
  Future<MigrationCheckpoint?> readMigrationCheckpoint(
    String migrationId,
  ) async {
    for (final MigrationCheckpoint checkpoint in checkpoints) {
      if (checkpoint.migrationId == migrationId) {
        return checkpoint;
      }
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> readLegacyDocument(String key) async {
    if (key == corruptedReadbackKey) {
      return <String, dynamic>{'corrupted': true};
    }
    final Map<String, dynamic>? value = documents[key];
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  @override
  Future<void> upsertLegacyDocument(
    String key,
    Map<String, dynamic> value,
    DateTime migratedAt,
  ) async {
    documents[key] = Map<String, dynamic>.from(value);
    documentWriteCount += 1;
  }
}

Map<String, dynamic> _profileDocument() {
  return <String, dynamic>{
    'schemaVersion': 1,
    'profileCompleted': true,
    'profile': <String, dynamic>{
      'id': 'athlete-legacy',
      'name': '迁移测试用户',
      'gender': 'female',
      'age': 30,
      'heightCm': 165,
      'weightKg': 55,
      'trainingGoal': '验证迁移',
      'mainSports': <String>['marathon'],
      'weeklyTrainingDays': 4,
      'dailyAvailableMinutes': 45,
      'injuryHistory': <String>[],
      'workScheduleType': 'regular_office',
      'equipmentAccessType': 'gym',
      'workerProfileType': 'general',
      'createdAt': '2026-07-01T00:00:00.000',
      'updatedAt': '2026-07-15T00:00:00.000',
    },
  };
}

Map<String, Map<String, dynamic>> _copyDocuments(
  Map<String, Map<String, dynamic>> source,
) {
  return source.map(
    (String key, Map<String, dynamic> value) =>
        MapEntry<String, Map<String, dynamic>>(
      key,
      Map<String, dynamic>.from(value),
    ),
  );
}
