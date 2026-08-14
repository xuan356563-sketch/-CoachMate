import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../features/cloud_sync/data/cloud_sync_local_store.dart';
import 'cloud_sync_projection_builder.dart';
import '../models/cloud_sync.dart';

class SqfliteCloudSyncLocalStore implements CloudSyncLocalStore {
  const SqfliteCloudSyncLocalStore(this._database);

  final Database _database;

  @override
  Future<CloudSyncAccountState> readAccountState(String accountId) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'sync_cursor',
      where: 'account_id = ?',
      whereArgs: <Object?>[accountId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const CloudSyncAccountState(
        enabled: false,
        snapshotRequired: true,
        cursor: 0,
        hasExistingLocalData: false,
      );
    }
    final Map<String, Object?> row = rows.single;
    return CloudSyncAccountState(
      enabled: row['enabled'] == 1,
      snapshotRequired: row['snapshot_required'] == 1,
      cursor: row['cursor']! as int,
      hasExistingLocalData: row['has_existing_local_data'] == 1,
    );
  }

  @override
  Future<void> setEnabled(String accountId, bool enabled) async {
    final String now = DateTime.now().toUtc().toIso8601String();
    await _database.transaction<void>((Transaction transaction) async {
      final List<Map<String, Object?>> existingCursorRows =
          await transaction.query(
        'sync_cursor',
        columns: const <String>['enabled'],
        where: 'account_id = ?',
        whereArgs: <Object?>[accountId],
        limit: 1,
      );
      final bool wasEnabled = existingCursorRows.isNotEmpty &&
          existingCursorRows.single['enabled'] == 1;
      final bool hasExistingLocalData =
          enabled && await _hasExistingLocalData(transaction);
      await transaction.rawInsert(
        '''
INSERT INTO sync_cursor(
  account_id, enabled, cursor, snapshot_required,
  has_existing_local_data, updated_at
) VALUES (?, ?, 0, 1, ?, ?)
ON CONFLICT(account_id) DO UPDATE SET
  enabled = excluded.enabled,
  snapshot_required = CASE
    WHEN excluded.enabled = 1 THEN 1
    ELSE sync_cursor.snapshot_required
  END,
  has_existing_local_data = CASE
    WHEN excluded.enabled = 1 THEN excluded.has_existing_local_data
    ELSE sync_cursor.has_existing_local_data
  END,
  updated_at = excluded.updated_at
''',
        <Object?>[
          accountId,
          enabled ? 1 : 0,
          hasExistingLocalData ? 1 : 0,
          now,
        ],
      );
      if (enabled && !wasEnabled) {
        final Map<String, Map<String, dynamic>> documents =
            await _readLegacyDocumentsOn(transaction);
        final List<CloudSyncMutation> mutations =
            _buildInitialMutations(documents);
        if (mutations.isNotEmpty) {
          await enqueueMutationsOnExecutor(
            transaction,
            accountId: accountId,
            mutations: mutations,
            timestamp: now,
          );
        }
      }
    });
  }

  Future<void> enqueueMutationAtomically({
    required String accountId,
    required CloudSyncMutation mutation,
    Future<void> Function(DatabaseExecutor executor)? localWrite,
  }) async {
    final String now = DateTime.now().toUtc().toIso8601String();
    await _database.transaction<void>((Transaction transaction) async {
      final List<Map<String, Object?>> cursorRows = await transaction.query(
        'sync_cursor',
        columns: const <String>['enabled'],
        where: 'account_id = ?',
        whereArgs: <Object?>[accountId],
        limit: 1,
      );
      if (cursorRows.isEmpty || cursorRows.single['enabled'] != 1) {
        throw StateError('云同步尚未由用户明确启用');
      }
      await localWrite?.call(transaction);
      await enqueueMutationsOnExecutor(
        transaction,
        accountId: accountId,
        mutations: <CloudSyncMutation>[mutation],
        timestamp: now,
      );
    });
  }

  Future<void> enqueueMutationsOnExecutor(
    DatabaseExecutor executor, {
    required String accountId,
    required List<CloudSyncMutation> mutations,
    String? timestamp,
  }) async {
    final String now = timestamp ?? DateTime.now().toUtc().toIso8601String();
    for (final CloudSyncMutation mutation in mutations) {
      int? baseVersion = mutation.baseVersion;
      if (baseVersion == null &&
          mutation.entityType != CloudSyncEntityType.completionSummaries) {
        final List<Map<String, Object?>> stateRows = await executor.query(
          'sync_entity_state',
          columns: const <String>['cloud_version'],
          where: 'account_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: <Object?>[
            accountId,
            mutation.entityType.wireName,
            mutation.entityId,
          ],
          limit: 1,
        );
        baseVersion = stateRows.firstOrNull?['cloud_version'] as int? ?? 0;
      }
      // 同一实体尚未发送的旧投影已被当前本地状态取代，避免批量发送时自相冲突。
      await executor.delete(
        'sync_outbox',
        where: '''
account_id = ? AND entity_type = ? AND entity_id = ?
AND state IN ('pending', 'failed')
''',
        whereArgs: <Object?>[
          accountId,
          mutation.entityType.wireName,
          mutation.entityId,
        ],
      );
      await executor.insert(
        'sync_outbox',
        <String, Object?>{
          'id': mutation.mutationId,
          'account_id': accountId,
          'mutation_id': mutation.mutationId,
          'entity_type': mutation.entityType.wireName,
          'entity_id': mutation.entityId,
          'operation': 'upsert',
          'base_version': baseVersion,
          'payload_json': jsonEncode(mutation.payload),
          'state': 'pending',
          'attempt_count': 0,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await executor.rawInsert(
        '''
INSERT INTO sync_entity_state(
  account_id, entity_type, entity_id, cloud_version, local_version,
  cloud_payload_json, local_payload_json, last_mutation_id, updated_at
) VALUES (?, ?, ?, ?, 1, '{}', ?, ?, ?)
ON CONFLICT(account_id, entity_type, entity_id) DO UPDATE SET
  local_version = sync_entity_state.local_version + 1,
  local_payload_json = excluded.local_payload_json,
  last_mutation_id = excluded.last_mutation_id,
  updated_at = excluded.updated_at
''',
        <Object?>[
          accountId,
          mutation.entityType.wireName,
          mutation.entityId,
          mutation.baseVersion ?? 0,
          jsonEncode(mutation.payload),
          mutation.mutationId,
          now,
        ],
      );
    }
  }

  @override
  Future<List<CloudSyncMutation>> readPendingMutations(
    String accountId, {
    int limit = 100,
  }) async {
    final String now = DateTime.now().toUtc().toIso8601String();
    final List<Map<String, Object?>> rows = await _database.query(
      'sync_outbox',
      where: '''
account_id = ? AND state IN ('pending', 'failed')
AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
''',
      whereArgs: <Object?>[accountId, now],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(_mutationFromRow).toList(growable: false);
  }

  @override
  Future<int> applySnapshot(
    String accountId,
    CloudSyncSnapshot snapshot,
  ) async {
    return _database.transaction<int>((Transaction transaction) async {
      int conflicts = 0;
      for (final CloudSyncEntity entity in snapshot.entities) {
        final Map<String, Object?>? localState =
            await _readEntityState(transaction, accountId, entity);
        final bool hasLocalVersion =
            (localState?['local_version'] as int? ?? 0) > 0;
        if (hasLocalVersion) {
          final bool isPending = await _insertConflict(
            transaction,
            accountId: accountId,
            entity: entity,
            localPayloadJson:
                localState?['local_payload_json'] as String? ?? '{}',
          );
          if (isPending) conflicts += 1;
          continue;
        }
        await _upsertCloudEntity(transaction, accountId, entity);
      }
      if (conflicts == 0) {
        await transaction.update(
          'sync_cursor',
          <String, Object?>{
            'cursor': snapshot.cursor,
            'snapshot_required': 0,
            'snapshot_applied_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'account_id = ?',
          whereArgs: <Object?>[accountId],
        );
      }
      return conflicts;
    });
  }

  @override
  Future<void> applyMutationResults(
    String accountId,
    List<CloudSyncMutationResult> results,
  ) async {
    await _database.transaction<void>((Transaction transaction) async {
      for (final CloudSyncMutationResult result in results) {
        final List<Map<String, Object?>> outboxRows = await transaction.query(
          'sync_outbox',
          where: 'account_id = ? AND mutation_id = ?',
          whereArgs: <Object?>[accountId, result.mutationId],
          limit: 1,
        );
        if (outboxRows.isEmpty) continue;
        final Map<String, Object?> outbox = outboxRows.single;
        if (result.status == CloudSyncMutationStatus.applied) {
          await transaction.delete(
            'sync_outbox',
            where: 'account_id = ? AND mutation_id = ?',
            whereArgs: <Object?>[accountId, result.mutationId],
          );
          await transaction.rawUpdate(
            '''
UPDATE sync_entity_state SET
  cloud_version = ?,
  local_version = 0,
  cloud_payload_json = local_payload_json,
  last_mutation_id = ?,
  updated_at = ?
WHERE account_id = ? AND entity_type = ? AND entity_id = ?
''',
            <Object?>[
              result.version,
              result.mutationId,
              DateTime.now().toUtc().toIso8601String(),
              accountId,
              result.entityType.wireName,
              result.entityId,
            ],
          );
          continue;
        }
        final CloudSyncEntity cloudEntity = CloudSyncEntity(
          entityType: result.entityType,
          entityId: result.entityId,
          version: result.version,
          payload: result.cloudPayload ?? const <String, Object?>{},
        );
        await _insertConflict(
          transaction,
          accountId: accountId,
          entity: cloudEntity,
          localPayloadJson: outbox['payload_json']! as String,
        );
        await transaction.update(
          'sync_outbox',
          <String, Object?>{
            'state': 'conflict',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'account_id = ? AND mutation_id = ?',
          whereArgs: <Object?>[accountId, result.mutationId],
        );
      }
    });
  }

  @override
  Future<void> applyChanges(
    String accountId,
    CloudSyncChangePage page,
  ) async {
    await _database.transaction<void>((Transaction transaction) async {
      for (final CloudSyncChange change in page.changes) {
        final Map<String, Object?>? localState =
            await _readEntityState(transaction, accountId, change);
        final bool hasLocalVersion =
            (localState?['local_version'] as int? ?? 0) > 0;
        if (hasLocalVersion) {
          await _insertConflict(
            transaction,
            accountId: accountId,
            entity: change,
            localPayloadJson:
                localState?['local_payload_json'] as String? ?? '{}',
          );
          continue;
        }
        await _upsertCloudEntity(transaction, accountId, change);
      }
      await transaction.update(
        'sync_cursor',
        <String, Object?>{
          'cursor': page.nextCursor,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'account_id = ?',
        whereArgs: <Object?>[accountId],
      );
    });
  }

  @override
  Future<void> markMutationsForRetry({
    required String accountId,
    required List<CloudSyncMutation> mutations,
    required String errorCode,
  }) async {
    if (mutations.isEmpty) return;
    final String retryAt = DateTime.now()
        .toUtc()
        .add(const Duration(seconds: 30))
        .toIso8601String();
    await _database.transaction<void>((Transaction transaction) async {
      for (final CloudSyncMutation mutation in mutations) {
        await transaction.rawUpdate(
          '''
UPDATE sync_outbox SET
  state = 'failed',
  attempt_count = attempt_count + 1,
  next_attempt_at = ?,
  last_error_code = ?,
  updated_at = ?
WHERE account_id = ? AND mutation_id = ?
''',
          <Object?>[
            retryAt,
            errorCode,
            DateTime.now().toUtc().toIso8601String(),
            accountId,
            mutation.mutationId,
          ],
        );
      }
    });
  }

  @override
  Future<List<CloudSyncConflict>> readPendingConflicts(
    String accountId,
  ) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'sync_conflicts',
      columns: const <String>[
        'id',
        'entity_type',
        'entity_id',
        'cloud_version',
      ],
      where: 'account_id = ? AND status = ?',
      whereArgs: <Object?>[accountId, 'pending'],
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (Map<String, Object?> row) => CloudSyncConflict(
            id: row['id']! as String,
            entityType: CloudSyncEntityType.fromWireName(
              row['entity_type']! as String,
            ),
            entityId: row['entity_id']! as String,
            cloudVersion: row['cloud_version']! as int,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> resolveConflict({
    required String accountId,
    required String conflictId,
    required CloudSyncConflictResolution resolution,
  }) async {
    await _database.transaction<void>((Transaction transaction) async {
      final List<Map<String, Object?>> rows = await transaction.query(
        'sync_conflicts',
        where: 'id = ? AND account_id = ? AND status = ?',
        whereArgs: <Object?>[conflictId, accountId, 'pending'],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('未找到可处理的同步冲突');
      }
      final Map<String, Object?> conflict = rows.single;
      final String entityType = conflict['entity_type']! as String;
      final String entityId = conflict['entity_id']! as String;
      final int cloudVersion = conflict['cloud_version']! as int;
      final String localPayload = conflict['local_payload_json']! as String;
      final String cloudPayload = conflict['cloud_payload_json']! as String;
      final String now = DateTime.now().toUtc().toIso8601String();

      await transaction.update(
        'sync_outbox',
        <String, Object?>{'state': 'resolved', 'updated_at': now},
        where: '''
account_id = ? AND entity_type = ? AND entity_id = ? AND state = 'conflict'
''',
        whereArgs: <Object?>[accountId, entityType, entityId],
      );

      if (resolution == CloudSyncConflictResolution.useCloud) {
        await transaction.rawInsert(
          '''
INSERT INTO sync_entity_state(
  account_id, entity_type, entity_id, cloud_version, local_version,
  cloud_payload_json, local_payload_json, updated_at
) VALUES (?, ?, ?, ?, 0, ?, ?, ?)
ON CONFLICT(account_id, entity_type, entity_id) DO UPDATE SET
  cloud_version = excluded.cloud_version,
  local_version = 0,
  cloud_payload_json = excluded.cloud_payload_json,
  local_payload_json = excluded.local_payload_json,
  updated_at = excluded.updated_at
''',
          <Object?>[
            accountId,
            entityType,
            entityId,
            cloudVersion,
            cloudPayload,
            cloudPayload,
            now,
          ],
        );
      } else {
        final Object? decoded = jsonDecode(localPayload);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('本地冲突数据无效');
        }
        final String mutationId =
            'resolve:$conflictId:${DateTime.now().microsecondsSinceEpoch}';
        final CloudSyncMutation mutation = CloudSyncMutation.fromPayload(
          mutationId: mutationId,
          entityType: CloudSyncEntityType.fromWireName(entityType),
          entityId: entityId,
          baseVersion: cloudVersion,
          payload: decoded.cast<String, Object?>(),
        );
        await transaction.insert(
          'sync_outbox',
          <String, Object?>{
            'id': mutationId,
            'account_id': accountId,
            'mutation_id': mutationId,
            'entity_type': entityType,
            'entity_id': entityId,
            'operation': 'upsert',
            'base_version': cloudVersion,
            'payload_json': jsonEncode(mutation.payload),
            'state': 'pending',
            'attempt_count': 0,
            'created_at': now,
            'updated_at': now,
          },
        );
        await transaction.update(
          'sync_entity_state',
          <String, Object?>{
            'cloud_version': cloudVersion,
            'cloud_payload_json': cloudPayload,
            'last_mutation_id': mutationId,
            'updated_at': now,
          },
          where: 'account_id = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: <Object?>[accountId, entityType, entityId],
        );
      }

      await transaction.update(
        'sync_conflicts',
        <String, Object?>{
          'status': resolution == CloudSyncConflictResolution.useCloud
              ? 'resolved_use_cloud'
              : 'resolved_keep_local',
          'resolved_at': now,
        },
        where: 'id = ? AND account_id = ?',
        whereArgs: <Object?>[conflictId, accountId],
      );
    });
  }

  Future<bool> _hasExistingLocalData(DatabaseExecutor executor) async {
    for (final String table in <String>[
      'training_plan_versions',
      'scheduled_workouts',
      'training_logs',
      'athlete_profiles',
    ]) {
      final List<Map<String, Object?>> rows = await executor.rawQuery(
        'SELECT EXISTS(SELECT 1 FROM $table LIMIT 1) AS has_rows',
      );
      if (rows.single['has_rows'] == 1) return true;
    }
    final List<Map<String, Object?>> legacyRows = await executor.query(
      'legacy_documents',
      columns: const <String>['storage_key'],
      where: '''
storage_key IN (?, ?, ?, ?, ?, ?)
''',
      whereArgs: const <Object?>[
        'trainflow.user_profile.v1',
        'trainflow.training_availability.v1',
        'trainflow.generated_training_plan.v1',
        'trainflow.training_schedule.v1',
        'trainflow.training_logs.v1',
        'trainflow.reminder_settings.v1',
      ],
      limit: 1,
    );
    if (legacyRows.isNotEmpty) return true;
    return false;
  }

  Future<Map<String, Map<String, dynamic>>> _readLegacyDocumentsOn(
    DatabaseExecutor executor,
  ) async {
    final List<Map<String, Object?>> rows = await executor.query(
      'legacy_documents',
      columns: const <String>['storage_key', 'payload_json'],
    );
    final Map<String, Map<String, dynamic>> documents =
        <String, Map<String, dynamic>>{};
    for (final Map<String, Object?> row in rows) {
      final Object? decoded = jsonDecode(row['payload_json']! as String);
      if (decoded is Map<String, dynamic>) {
        documents[row['storage_key']! as String] = decoded;
      }
    }
    return documents;
  }

  List<CloudSyncMutation> _buildInitialMutations(
    Map<String, Map<String, dynamic>> documents,
  ) {
    const List<String> projectionKeys = <String>[
      'trainflow.user_profile.v1',
      'trainflow.training_availability.v1',
      'trainflow.generated_training_plan.v1',
      'trainflow.training_schedule.v1',
      'trainflow.training_logs.v1',
      'trainflow.reminder_settings.v1',
    ];
    return <CloudSyncMutation>[
      for (final String key in projectionKeys)
        ...CloudSyncProjectionBuilder.build(
          changedKey: key,
          previousDocuments: const <String, Map<String, dynamic>>{},
          currentDocuments: documents,
        ),
    ];
  }

  Future<Map<String, Object?>?> _readEntityState(
    DatabaseExecutor executor,
    String accountId,
    CloudSyncEntity entity,
  ) async {
    final List<Map<String, Object?>> rows = await executor.query(
      'sync_entity_state',
      where: 'account_id = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>[
        accountId,
        entity.entityType.wireName,
        entity.entityId,
      ],
      limit: 1,
    );
    return rows.firstOrNull;
  }

  Future<void> _upsertCloudEntity(
    DatabaseExecutor executor,
    String accountId,
    CloudSyncEntity entity,
  ) async {
    final String payload = jsonEncode(entity.payload);
    final String now = DateTime.now().toUtc().toIso8601String();
    await executor.rawInsert(
      '''
INSERT INTO sync_entity_state(
  account_id, entity_type, entity_id, cloud_version, local_version,
  cloud_payload_json, local_payload_json, updated_at
) VALUES (?, ?, ?, ?, 0, ?, ?, ?)
ON CONFLICT(account_id, entity_type, entity_id) DO UPDATE SET
  cloud_version = excluded.cloud_version,
  cloud_payload_json = excluded.cloud_payload_json,
  local_payload_json = CASE
    WHEN sync_entity_state.local_version = 0
      THEN excluded.local_payload_json
    ELSE sync_entity_state.local_payload_json
  END,
  updated_at = excluded.updated_at
''',
      <Object?>[
        accountId,
        entity.entityType.wireName,
        entity.entityId,
        entity.version,
        payload,
        payload,
        now,
      ],
    );
  }

  Future<bool> _insertConflict(
    DatabaseExecutor executor, {
    required String accountId,
    required CloudSyncEntity entity,
    required String localPayloadJson,
  }) async {
    final String now = DateTime.now().toUtc().toIso8601String();
    final String id = 'conflict:$accountId:${entity.entityType.wireName}:'
        '${entity.entityId}:${entity.version}';
    await executor.insert(
      'sync_conflicts',
      <String, Object?>{
        'id': id,
        'account_id': accountId,
        'entity_type': entity.entityType.wireName,
        'entity_id': entity.entityId,
        'local_payload_json': localPayloadJson,
        'cloud_payload_json': jsonEncode(entity.payload),
        'cloud_version': entity.version,
        'status': 'pending',
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final List<Map<String, Object?>> rows = await executor.query(
      'sync_conflicts',
      columns: const <String>['status'],
      where: 'id = ? AND account_id = ?',
      whereArgs: <Object?>[id, accountId],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['status'] == 'pending';
  }

  CloudSyncMutation _mutationFromRow(Map<String, Object?> row) {
    final Object? decoded = jsonDecode(row['payload_json']! as String);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('本地同步队列数据无效');
    }
    return CloudSyncMutation.fromPayload(
      mutationId: row['mutation_id']! as String,
      entityType:
          CloudSyncEntityType.fromWireName(row['entity_type']! as String),
      entityId: row['entity_id']! as String,
      baseVersion: row['base_version'] as int?,
      payload: decoded.cast<String, Object?>(),
    );
  }
}
