import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/database_local_storage_service.dart';
import 'package:trainflow_ai/data/local/trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/models/cloud_sync.dart';

void main() {
  test('数据库存储服务会预加载数据并按调用顺序持久化修改', () async {
    final _StorageDatabaseGateway database = _StorageDatabaseGateway(
      <String, Map<String, dynamic>>{
        'trainflow.user_profile.v1': <String, dynamic>{
          'name': '数据库用户',
        },
      },
    );
    final DatabaseLocalStorageService storage =
        await DatabaseLocalStorageService.create(database);

    expect(storage.readJson('trainflow.user_profile.v1')?['name'], '数据库用户');

    final Map<String, dynamic> value = <String, dynamic>{
      'logs': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'log-1'},
      ],
    };
    storage.saveJson('trainflow.training_logs.v1', value);
    (value['logs'] as List<Map<String, dynamic>>).first['id'] = '被外部修改';
    storage.remove('trainflow.user_profile.v1');
    await storage.flush();

    expect(database.documents, isNot(contains('trainflow.user_profile.v1')));
    expect(
      (database.documents['trainflow.training_logs.v1']?['logs'] as List)
          .first['id'],
      'log-1',
      reason: '存储层必须隔离调用方后续对原 Map 的修改',
    );
  });

  test('清理业务数据时会保留明确指定的设备级键', () async {
    final _StorageDatabaseGateway database = _StorageDatabaseGateway(
      <String, Map<String, dynamic>>{
        'trainflow.user_profile.v1': <String, dynamic>{'name': '测试'},
        'trainflow.installation_id.v1': <String, dynamic>{'id': 'device-1'},
        'unrelated.key': <String, dynamic>{'value': true},
      },
    );
    final DatabaseLocalStorageService storage =
        await DatabaseLocalStorageService.create(database);

    storage.clearBusinessData(
      preservedKeys: const <String>{'trainflow.installation_id.v1'},
    );
    await storage.flush();

    expect(storage.readJson('trainflow.user_profile.v1'), isNull);
    expect(storage.readJson('trainflow.installation_id.v1')?['id'], 'device-1');
    expect(storage.readJson('unrelated.key')?['value'], isTrue);
    expect(database.documents.keys, <String>{
      'trainflow.installation_id.v1',
      'unrelated.key',
    });
  });

  test('账号切换会等待数据库原子清理并写入新绑定', () async {
    final _StorageDatabaseGateway database = _StorageDatabaseGateway(
      <String, Map<String, dynamic>>{
        'trainflow.user_profile.v1': <String, dynamic>{'name': '旧资料'},
        'trainflow.installation_id.v1': <String, dynamic>{'value': 'device-1'},
        'trainflow.account_binding.v1': <String, dynamic>{'userId': 'old-user'},
      },
    );
    final DatabaseLocalStorageService storage =
        await DatabaseLocalStorageService.create(database);

    await storage.replaceBusinessDataAtomically(
      preservedKeys: const <String>{'trainflow.installation_id.v1'},
      replacementDocuments: <String, Map<String, dynamic>>{
        'trainflow.account_binding.v1': <String, dynamic>{
          'userId': 'new-user',
        },
      },
    );

    expect(storage.readJson('trainflow.user_profile.v1'), isNull);
    expect(
        storage.readJson('trainflow.installation_id.v1')?['value'], 'device-1');
    expect(storage.readJson('trainflow.account_binding.v1')?['userId'],
        'new-user');
    expect(database.atomicReplacementCount, 1);
  });

  test('账号原子清理失败时内存缓存也保留旧数据', () async {
    final _StorageDatabaseGateway database = _StorageDatabaseGateway(
      <String, Map<String, dynamic>>{
        'trainflow.user_profile.v1': <String, dynamic>{'name': '旧资料'},
      },
      atomicReplacementError: StateError('模拟原子清理失败'),
    );
    final DatabaseLocalStorageService storage =
        await DatabaseLocalStorageService.create(database);

    await expectLater(
      storage.replaceBusinessDataAtomically(
        replacementDocuments: <String, Map<String, dynamic>>{
          'trainflow.account_binding.v1': <String, dynamic>{
            'userId': 'new-user',
          },
        },
      ),
      throwsStateError,
    );

    expect(storage.readJson('trainflow.user_profile.v1')?['name'], '旧资料');
    expect(storage.readJson('trainflow.account_binding.v1'), isNull);
  });

  test('flush 报告一次写入错误后会消费错误并允许重试', () async {
    final _StorageDatabaseGateway database =
        _StorageDatabaseGateway(<String, Map<String, dynamic>>{})
          ..failNextUpsert = true;
    final DatabaseLocalStorageService storage =
        await DatabaseLocalStorageService.create(database);

    storage.saveJson('trainflow.first.v1', <String, dynamic>{'value': 1});
    await expectLater(storage.flush(), throwsStateError);
    expect(storage.lastWriteError, isNull);

    storage.saveJson('trainflow.second.v1', <String, dynamic>{'value': 2});
    await storage.flush();
    expect(database.documents['trainflow.second.v1']?['value'], 2);
  });

  test('SQLite 能力可用时本地文档与白名单 outbox 由同一原子入口写入', () async {
    final _CloudStorageDatabaseGateway database =
        _CloudStorageDatabaseGateway(<String, Map<String, dynamic>>{
      'trainflow.account_binding.v1': <String, dynamic>{
        'userId': 'account-a',
      },
      'trainflow.training_availability.v1': <String, dynamic>{
        'slots': <Map<String, dynamic>>[
          <String, dynamic>{'date': '2026-07-28T00:00:00.000'},
        ],
      },
    });
    final DatabaseLocalStorageService storage =
        await DatabaseLocalStorageService.create(database);

    storage.saveJson('trainflow.user_profile.v1', <String, dynamic>{
      'profile': <String, dynamic>{
        'trainingGoal': '提升综合体能',
        'mainSports': <String>['running'],
        'trainingExperienceLevel': 'beginner',
        'equipmentAccessType': 'none',
        'weightKg': 70,
      },
    });
    await storage.flush();

    expect(database.atomicCloudWriteCount, 1);
    expect(database.lastAccountId, 'account-a');
    expect(database.lastMutations, hasLength(1));
    expect(
      database.lastMutations.single.entityType,
      CloudSyncEntityType.trainingPreferences,
    );
    expect(
      database.lastMutations.single.payload,
      isNot(containsPair('weightKg', 70)),
    );
  });
}

class _StorageDatabaseGateway implements TrainFlowDatabaseGateway {
  _StorageDatabaseGateway(
    Map<String, Map<String, dynamic>> initialDocuments, {
    this.atomicReplacementError,
  }) : documents = initialDocuments.map(
          (String key, Map<String, dynamic> value) => MapEntry(
            key,
            _deepCopy(value),
          ),
        );

  final Map<String, Map<String, dynamic>> documents;
  final Object? atomicReplacementError;
  int atomicReplacementCount = 0;
  bool failNextUpsert = false;

  @override
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  }) async {
    final Object? error = atomicReplacementError;
    if (error != null) throw error;
    documents.removeWhere(
      (String key, Map<String, dynamic> _) =>
          key.startsWith('trainflow.') && !preservedKeys.contains(key),
    );
    documents.addAll(replacementDocuments.map(
      (key, value) => MapEntry(key, _deepCopy(value)),
    ));
    atomicReplacementCount += 1;
  }

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
  Future<void> close() async {}

  @override
  Future<void> deleteLegacyDocument(String key) async {
    documents.remove(key);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readAllLegacyDocuments() async {
    return documents.map(
      (String key, Map<String, dynamic> value) =>
          MapEntry(key, _deepCopy(value)),
    );
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(TrainFlowDatabaseTransaction transaction) action,
  ) {
    throw UnimplementedError('此测试不需要事务');
  }

  @override
  Future<void> upsertLegacyDocument(
    String key,
    Map<String, dynamic> value,
  ) async {
    if (failNextUpsert) {
      failNextUpsert = false;
      throw StateError('模拟单次写入失败');
    }
    documents[key] = _deepCopy(value);
  }
}

class _CloudStorageDatabaseGateway extends _StorageDatabaseGateway
    implements TrainFlowCloudSyncWriteGateway {
  _CloudStorageDatabaseGateway(super.initialDocuments);

  int atomicCloudWriteCount = 0;
  String? lastAccountId;
  List<CloudSyncMutation> lastMutations = const <CloudSyncMutation>[];

  @override
  Future<void> upsertLegacyDocumentWithCloudMutations({
    required String key,
    required Map<String, dynamic> value,
    required String accountId,
    required List<CloudSyncMutation> mutations,
  }) async {
    documents[key] = _deepCopy(value);
    atomicCloudWriteCount += 1;
    lastAccountId = accountId;
    lastMutations = List<CloudSyncMutation>.of(mutations);
  }
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> value) {
  return <String, dynamic>{
    for (final MapEntry<String, dynamic> entry in value.entries)
      entry.key: entry.value is List
          ? (entry.value as List)
              .map<dynamic>((dynamic item) =>
                  item is Map<String, dynamic> ? _deepCopy(item) : item)
              .toList()
          : entry.value,
  };
}
