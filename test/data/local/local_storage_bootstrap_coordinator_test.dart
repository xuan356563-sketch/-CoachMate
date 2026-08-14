import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/database_local_storage_service.dart';
import 'package:trainflow_ai/data/local/companion_database_gateway.dart';
import 'package:trainflow_ai/data/local/local_storage_bootstrap_coordinator.dart';
import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/local/trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/local/trainflow_database_schema.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('数据库初始化与迁移成功后才切换到 SQLite 存储', () async {
    final InMemoryLocalStorageService legacy = InMemoryLocalStorageService()
      ..saveJson('trainflow.training_logs.v1', <String, dynamic>{
        'name': '切换测试',
      });
    final _BootstrapDatabaseGateway database = _BootstrapDatabaseGateway();
    final LocalStorageBootstrapCoordinator coordinator =
        LocalStorageBootstrapCoordinator(
      legacyStorage: legacy,
      openDatabase: () async => database,
      storageKeys: const <String>{'trainflow.training_logs.v1'},
    );

    final LocalStorageBootstrapResult result = await coordinator.initialize();

    expect(result.backend, LocalStorageBackend.sqlite);
    expect(result.storageService, isA<DatabaseLocalStorageService>());
    expect(result.migrationResult?.migratedDocumentCount, 1);
    expect(result.fallbackReason, isNull);
    expect(
      identical(result.petDatabaseGateway, database.petDatabaseGateway),
      isTrue,
    );
    expect(
      identical(
          result.companionDatabaseGateway, database.companionDatabaseGateway),
      isTrue,
    );
    expect(
        result.storageService.readJson('trainflow.training_logs.v1')?['name'],
        '切换测试');
    expect(legacy.readJson('trainflow.training_logs.v1')?['name'], '切换测试');
    expect(database.isClosed, isFalse);
    expect(
      legacy.readJson(
          LocalStorageBootstrapCoordinator.cutoverMarkerKey)?['schemaVersion'],
      TrainFlowDatabaseSchema.version,
    );
  });

  test('数据库迁移失败时关闭数据库并继续使用原存储', () async {
    final InMemoryLocalStorageService legacy = InMemoryLocalStorageService()
      ..saveJson(
          'trainflow.training_logs.v1', <String, dynamic>{'name': '回退测试'});
    final _BootstrapDatabaseGateway database = _BootstrapDatabaseGateway(
      transactionError: StateError('模拟事务失败'),
    );
    final LocalStorageBootstrapCoordinator coordinator =
        LocalStorageBootstrapCoordinator(
      legacyStorage: legacy,
      openDatabase: () async => database,
      storageKeys: const <String>{'trainflow.training_logs.v1'},
    );

    final LocalStorageBootstrapResult result = await coordinator.initialize();

    expect(result.backend, LocalStorageBackend.sharedPreferences);
    expect(identical(result.storageService, legacy), isTrue);
    expect(result.migrationResult, isNull);
    expect(result.petDatabaseGateway, isNull);
    expect(result.companionDatabaseGateway, isNull);
    expect(result.fallbackReason, contains('已继续使用原设备存储'));
    expect(database.isClosed, isTrue);
  });

  test('已切换 SQLite 后初始化失败会进入只读恢复而不读取陈旧数据', () async {
    final InMemoryLocalStorageService legacy = InMemoryLocalStorageService()
      ..saveJson(LocalStorageBootstrapCoordinator.cutoverMarkerKey,
          <String, dynamic>{'schemaVersion': 3, 'completed': true})
      ..saveJson('trainflow.user_profile.v1', <String, dynamic>{
        'profileCompleted': true,
      });
    final LocalStorageBootstrapResult result =
        await LocalStorageBootstrapCoordinator(
      legacyStorage: legacy,
      openDatabase: () async => throw StateError('模拟数据库无法打开'),
      storageKeys: const <String>{'trainflow.user_profile.v1'},
    ).initialize();

    expect(result.backend, LocalStorageBackend.readOnlyRecovery);
    expect(result.petDatabaseGateway, isNull);
    expect(result.companionDatabaseGateway, isNull);
    expect(result.storageService.readJson('trainflow.user_profile.v1'), isNull);
    expect(result.fallbackReason, contains('为保护训练数据'));
  });
}

class _BootstrapDatabaseGateway
    implements
        TrainFlowDatabaseGateway,
        PetDatabaseGatewayProvider,
        CompanionDatabaseGatewayProvider {
  _BootstrapDatabaseGateway({this.transactionError});

  final Object? transactionError;
  final Map<String, Map<String, dynamic>> documents =
      <String, Map<String, dynamic>>{};
  MigrationCheckpoint? checkpoint;
  bool isClosed = false;
  final PetDatabaseGateway petDatabaseGateway = _BootstrapPetDatabaseGateway();
  final CompanionDatabaseGateway companionDatabaseGateway =
      _BootstrapCompanionDatabaseGateway();

  @override
  PetDatabaseGateway createPetDatabaseGateway() => petDatabaseGateway;

  @override
  CompanionDatabaseGateway createCompanionDatabaseGateway() =>
      companionDatabaseGateway;

  @override
  Future<void> clearLegacyDocuments({
    Set<String> preservedKeys = const <String>{},
  }) async {}

  @override
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  }) async {}

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
    return documents;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(TrainFlowDatabaseTransaction transaction) action,
  ) async {
    final Object? error = transactionError;
    if (error != null) {
      throw error;
    }
    return action(_BootstrapTransaction(this));
  }

  @override
  Future<void> upsertLegacyDocument(
    String key,
    Map<String, dynamic> value,
  ) async {
    documents[key] = Map<String, dynamic>.from(value);
  }
}

class _BootstrapPetDatabaseGateway implements PetDatabaseGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BootstrapCompanionDatabaseGateway implements CompanionDatabaseGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BootstrapTransaction implements TrainFlowDatabaseTransaction {
  const _BootstrapTransaction(this.database);

  final _BootstrapDatabaseGateway database;

  @override
  Future<void> upsertAthleteProfileRow(Map<String, Object?> row) async {}

  @override
  Future<void> markStorageCutover({
    required int schemaVersion,
    required DateTime completedAt,
  }) async {}

  @override
  Future<void> markMigrationCompleted(MigrationCheckpoint checkpoint) async {
    database.checkpoint = checkpoint;
  }

  @override
  Future<MigrationCheckpoint?> readMigrationCheckpoint(
    String migrationId,
  ) async {
    return database.checkpoint;
  }

  @override
  Future<Map<String, dynamic>?> readLegacyDocument(String key) async {
    return database.documents[key];
  }

  @override
  Future<void> upsertLegacyDocument(
    String key,
    Map<String, dynamic> value,
    DateTime migratedAt,
  ) async {
    database.documents[key] = Map<String, dynamic>.from(value);
  }
}
