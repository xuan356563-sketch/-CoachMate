import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:trainflow_ai/data/local/athlete_profile_projection.dart';
import 'package:trainflow_ai/data/local/coach_database_gateway.dart';
import 'package:trainflow_ai/data/local/companion_database_gateway.dart';
import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/local/sqflite_companion_database_gateway.dart';
import 'package:trainflow_ai/data/local/sqflite_coach_database_gateway.dart';
import 'package:trainflow_ai/data/local/sqflite_pet_database_gateway.dart';
import 'package:trainflow_ai/data/local/trainmate_structured_database_gateway.dart';
import 'package:trainflow_ai/data/local/trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/local/trainflow_database_schema.dart';
import 'package:trainflow_ai/data/local/rhythm_database_gateway.dart';
import 'package:trainflow_ai/data/local/sqflite_cloud_sync_local_store.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/models/cloud_sync.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway_contract.dart';

class SqfliteTrainFlowDatabaseGateway
    implements
        TrainFlowDatabaseGateway,
        GrowthDatabaseGateway,
        TrainMateStructuredDatabaseGateway,
        RhythmDatabaseGateway,
        RunContextDatabaseGateway,
        StructuredStorageDriver,
        PetDatabaseGatewayProvider,
        CompanionDatabaseGatewayProvider,
        CoachDatabaseGatewayProvider,
        TrainFlowCloudSyncWriteGateway {
  const SqfliteTrainFlowDatabaseGateway._(this._database);

  final Database _database;

  SqfliteCloudSyncLocalStore createCloudSyncLocalStore() {
    return SqfliteCloudSyncLocalStore(_database);
  }

  @override
  PetDatabaseGateway createPetDatabaseGateway() {
    return SqflitePetDatabaseGateway.fromDatabase(_database);
  }

  @override
  CompanionDatabaseGateway createCompanionDatabaseGateway() {
    return SqfliteCompanionDatabaseGateway.fromDatabase(_database);
  }

  @override
  CoachDatabaseGateway createCoachDatabaseGateway() {
    return SqfliteCoachDatabaseGateway.fromDatabase(_database);
  }

  static Future<SqfliteTrainFlowDatabaseGateway> open({
    String? databasePath,
  }) async {
    final String resolvedPath = databasePath ??
        p.join(
          await getDatabasesPath(),
          TrainFlowDatabaseSchema.databaseName,
        );
    await _createConsistentPreMigrationBackup(resolvedPath);

    late final Database database;
    try {
      database = await openDatabase(
        resolvedPath,
        version: TrainFlowDatabaseSchema.version,
        onConfigure: (Database database) async {
          for (final String statement
              in TrainFlowDatabaseSchema.configureStatements) {
            await database.execute(statement);
          }
        },
        onCreate: (Database database, int version) async {
          for (final String statement
              in TrainFlowDatabaseSchema.creationStatements) {
            await database.execute(statement);
          }
        },
        onUpgrade: (Database database, int oldVersion, int newVersion) async {
          if (oldVersion < 2 && newVersion >= 2) {
            for (final String statement
                in TrainFlowDatabaseSchema.version2UpgradeStatements) {
              await database.execute(statement);
            }
          }
          if (oldVersion < 3 && newVersion >= 3) {
            for (final String statement
                in TrainFlowDatabaseSchema.version3UpgradeStatements) {
              await database.execute(statement);
            }
          }
          if (oldVersion < 4 && newVersion >= 4) {
            for (final String statement
                in TrainFlowDatabaseSchema.version4UpgradeStatements) {
              await database.execute(statement);
            }
          }
          if (oldVersion < 5 && newVersion >= 5) {
            for (final String statement
                in TrainFlowDatabaseSchema.version5UpgradeStatements) {
              await database.execute(statement);
            }
          }
          if (oldVersion < 6 && newVersion >= 6) {
            for (final String statement
                in TrainFlowDatabaseSchema.version6UpgradeStatements) {
              await database.execute(statement);
            }
          }
          if (oldVersion < 7 && newVersion >= 7) {
            for (final String statement
                in TrainFlowDatabaseSchema.version7UpgradeStatements) {
              await database.execute(statement);
            }
          }
          if (oldVersion < 8 && newVersion >= 8) {
            final List<String> statements;
            if (oldVersion == 7) {
              final Set<String> existingColumns = (await database.rawQuery(
                'PRAGMA table_info(companion_messages)',
              ))
                  .map((Map<String, Object?> row) => row['name'] as String?)
                  .whereType<String>()
                  .toSet();
              statements = <String>[
                ...TrainFlowDatabaseSchema.pendingVersion8AddedColumnStatements(
                    existingColumns),
                ...TrainFlowDatabaseSchema.version8CreationStatements,
              ];
            } else {
              statements = TrainFlowDatabaseSchema.version8CreationStatements;
            }
            for (final String statement in statements) {
              await database.execute(statement);
            }
          }
        },
      );
    } catch (_) {
      rethrow;
    }
    final SqfliteTrainFlowDatabaseGateway gateway =
        SqfliteTrainFlowDatabaseGateway._(database);
    try {
      await gateway._verifyDatabase();
      return gateway;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readAllLegacyDocuments() async {
    final List<Map<String, Object?>> rows = await _database.query(
      'legacy_documents',
      columns: const <String>['storage_key', 'payload_json'],
      orderBy: 'storage_key ASC',
    );
    final Map<String, Map<String, dynamic>> documents =
        <String, Map<String, dynamic>>{};
    for (final Map<String, Object?> row in rows) {
      final String key = row['storage_key']! as String;
      documents[key] = _decodeDocument(key, row['payload_json']);
    }
    return documents;
  }

  @override
  Future<void> upsertLegacyDocument(
    String key,
    Map<String, dynamic> value,
  ) async {
    final String now = DateTime.now().toUtc().toIso8601String();
    final Map<String, Object?>? athleteProfileRow =
        key == 'trainflow.user_profile.v1'
            ? AthleteProfileProjection.fromLegacyDocument(
                value,
                projectedAt: DateTime.parse(now),
              )
            : null;
    await _database.transaction<void>((Transaction transaction) async {
      await _upsertLegacyDocumentOnExecutor(
        transaction,
        key: key,
        value: value,
        timestamp: now,
      );
      if (athleteProfileRow != null) {
        await _upsertAthleteProfileOnExecutor(transaction, athleteProfileRow);
      }
    });
  }

  @override
  Future<void> upsertLegacyDocumentWithCloudMutations({
    required String key,
    required Map<String, dynamic> value,
    required String accountId,
    required List<CloudSyncMutation> mutations,
  }) async {
    final String now = DateTime.now().toUtc().toIso8601String();
    final Map<String, Object?>? athleteProfileRow =
        key == 'trainflow.user_profile.v1'
            ? AthleteProfileProjection.fromLegacyDocument(
                value,
                projectedAt: DateTime.parse(now),
              )
            : null;
    await _database.transaction<void>((Transaction transaction) async {
      await _upsertLegacyDocumentOnExecutor(
        transaction,
        key: key,
        value: value,
        timestamp: now,
      );
      if (athleteProfileRow != null) {
        await _upsertAthleteProfileOnExecutor(
          transaction,
          athleteProfileRow,
        );
      }
      final List<Map<String, Object?>> cursorRows = await transaction.query(
        'sync_cursor',
        columns: const <String>['enabled'],
        where: 'account_id = ?',
        whereArgs: <Object?>[accountId],
        limit: 1,
      );
      if (cursorRows.isEmpty || cursorRows.single['enabled'] != 1) {
        return;
      }
      await SqfliteCloudSyncLocalStore(_database).enqueueMutationsOnExecutor(
        transaction,
        accountId: accountId,
        mutations: mutations,
      );
    });
  }

  static Future<void> _upsertLegacyDocumentOnExecutor(
    DatabaseExecutor executor, {
    required String key,
    required Map<String, dynamic> value,
    required String timestamp,
  }) async {
    await executor.rawInsert(
      '''
INSERT INTO legacy_documents(
  storage_key, payload_json, migrated_at, updated_at
) VALUES (?, ?, ?, ?)
ON CONFLICT(storage_key) DO UPDATE SET
  payload_json = excluded.payload_json,
  updated_at = excluded.updated_at
''',
      <Object?>[key, jsonEncode(value), timestamp, timestamp],
    );
  }

  @override
  Future<void> deleteLegacyDocument(String key) async {
    await _database.delete(
      'legacy_documents',
      where: 'storage_key = ?',
      whereArgs: <Object?>[key],
    );
  }

  @override
  Future<void> clearLegacyDocuments({
    Set<String> preservedKeys = const <String>{},
  }) async {
    if (preservedKeys.isEmpty) {
      await _database.delete(
        'legacy_documents',
        where: 'storage_key LIKE ?',
        whereArgs: const <Object?>['trainflow.%'],
      );
      return;
    }
    final List<String> orderedKeys = preservedKeys.toList()..sort();
    final String placeholders = List<String>.filled(
      orderedKeys.length,
      '?',
    ).join(', ');
    await _database.delete(
      'legacy_documents',
      where: 'storage_key LIKE ? AND storage_key NOT IN ($placeholders)',
      whereArgs: <Object?>['trainflow.%', ...orderedKeys],
    );
  }

  @override
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final Map<String, Object?> athleteProfileRow =
        AthleteProfileProjection.fromLegacyDocument(
      replacementDocuments['trainflow.user_profile.v1'],
      projectedAt: now,
    );
    // 先清理受控旧备份；失败时不开始账号切换，避免数据库已切换但上层仍保留旧缓存。
    await removeControlledVersionedDatabaseBackups(_database.path);
    await _database.transaction<void>((Transaction transaction) async {
      await transaction.delete('athlete_profiles');
      if (preservedKeys.isEmpty) {
        await transaction.delete(
          'legacy_documents',
          where: 'storage_key LIKE ?',
          whereArgs: const <Object?>['trainflow.%'],
        );
      } else {
        final List<String> orderedKeys = preservedKeys.toList()..sort();
        final String placeholders =
            List<String>.filled(orderedKeys.length, '?').join(', ');
        await transaction.delete(
          'legacy_documents',
          where: 'storage_key LIKE ? AND storage_key NOT IN ($placeholders)',
          whereArgs: <Object?>['trainflow.%', ...orderedKeys],
        );
      }
      final String timestamp = now.toIso8601String();
      for (final MapEntry<String, Map<String, dynamic>> entry
          in replacementDocuments.entries) {
        await _upsertLegacyDocumentOnExecutor(
          transaction,
          key: entry.key,
          value: entry.value,
          timestamp: timestamp,
        );
      }
      await _upsertAthleteProfileOnExecutor(transaction, athleteProfileRow);
      final List<Map<String, Object?>> violations =
          await transaction.rawQuery('PRAGMA foreign_key_check');
      if (violations.isNotEmpty) {
        throw StateError('账号数据清理后的外键校验失败');
      }
    });
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(TrainFlowDatabaseTransaction transaction) action,
  ) {
    return _database.transaction<T>(
      (Transaction transaction) => action(
        _SqfliteTrainFlowDatabaseTransaction(transaction),
      ),
    );
  }

  @override
  Future<T> runStructuredTransaction<T>(
    Future<T> Function(StructuredStorageTransaction transaction) action,
  ) {
    return _database.transaction<T>(
      (Transaction transaction) => action(
        _SqfliteStructuredStorageTransaction(transaction),
      ),
    );
  }

  @override
  Future<L1ScheduleProjectionWriteResult> saveL1ScheduleProjection(
    L1ScheduleProjectionWrite write,
  ) {
    return StructuredL1ScheduleCoordinator(this).apply(write);
  }

  @override
  Future<LocalTrainingFactWriteResult> saveLocalTrainingFact(
    LocalTrainingFactWrite write,
  ) {
    return StructuredLocalTrainingCoordinator(this).apply(write);
  }

  @override
  Future<List<StructuredScheduledWorkoutResult>> listScheduledWorkoutResults({
    required String athleteProfileId,
    required DateTime startLocalDate,
    required DateTime endExclusiveLocalDate,
  }) async {
    if (athleteProfileId.trim().isEmpty) {
      throw ArgumentError.value(
        athleteProfileId,
        'athleteProfileId',
        '运动员资料 ID 不能为空',
      );
    }
    final DateTime start = _dateOnly(startLocalDate);
    final DateTime end = _dateOnly(endExclusiveLocalDate);
    if (!start.isBefore(end)) {
      throw const FormatException('L1 判定查询的结束日期必须晚于开始日期。');
    }
    final List<Map<String, Object?>> rows = await _database.rawQuery(
      '''
SELECT r.*,
       sw.source_workout_id AS source_scheduled_workout_id,
       COALESCE(sw.scheduled_date, w.local_date) AS result_local_date
FROM scheduled_workout_results r
LEFT JOIN scheduled_workouts sw ON sw.id = r.scheduled_workout_id
LEFT JOIN workouts w ON w.id = r.workout_id
WHERE r.athlete_profile_id = ?
  AND COALESCE(sw.scheduled_date, w.local_date) >= ?
  AND COALESCE(sw.scheduled_date, w.local_date) < ?
  AND (r.scheduled_workout_id IS NULL OR sw.status <> 'superseded')
ORDER BY result_local_date ASC, r.id ASC
''',
      <Object?>[
        athleteProfileId,
        _localDateKey(start),
        _localDateKey(end),
      ],
    );
    return List<StructuredScheduledWorkoutResult>.unmodifiable(
      rows.map(_scheduledWorkoutResultFromRow),
    );
  }

  @override
  Future<StructuredScheduledWorkoutResult> setScheduledWorkoutResultOverride({
    required String athleteProfileId,
    required String resultId,
    required WorkoutCompletionStatus status,
    required String reason,
    required DateTime overriddenAt,
  }) {
    const Set<WorkoutCompletionStatus> allowed = <WorkoutCompletionStatus>{
      WorkoutCompletionStatus.completed,
      WorkoutCompletionStatus.partial,
      WorkoutCompletionStatus.missed,
    };
    if (!allowed.contains(status)) {
      throw const FormatException('人工覆盖只能选择已完成、部分完成或未完成。');
    }
    return _updateScheduledWorkoutResultOverride(
      athleteProfileId: athleteProfileId,
      resultId: resultId,
      manualOverrideStatus: status.name,
      reason: reason,
      changedAt: overriddenAt,
    );
  }

  @override
  Future<StructuredScheduledWorkoutResult> clearScheduledWorkoutResultOverride({
    required String athleteProfileId,
    required String resultId,
    required String reason,
    required DateTime clearedAt,
  }) {
    final String normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw const FormatException('清除人工覆盖必须填写原因。');
    }
    return _updateScheduledWorkoutResultOverride(
      athleteProfileId: athleteProfileId,
      resultId: resultId,
      manualOverrideStatus: null,
      reason: '已清除人工覆盖：$normalizedReason',
      changedAt: clearedAt,
    );
  }

  Future<StructuredScheduledWorkoutResult>
      _updateScheduledWorkoutResultOverride({
    required String athleteProfileId,
    required String resultId,
    required String? manualOverrideStatus,
    required String reason,
    required DateTime changedAt,
  }) async {
    if (athleteProfileId.trim().isEmpty || resultId.trim().isEmpty) {
      throw const FormatException('人工覆盖缺少运动员资料 ID 或判定 ID。');
    }
    final String normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw const FormatException('人工覆盖或清除覆盖必须填写原因。');
    }
    return _database.transaction<StructuredScheduledWorkoutResult>(
      (Transaction transaction) async {
        final int updated = await transaction.update(
          'scheduled_workout_results',
          <String, Object?>{
            'manual_override_status': manualOverrideStatus,
            'override_reason': normalizedReason,
            'updated_at': changedAt.toUtc().toIso8601String(),
          },
          where: 'id = ? AND athlete_profile_id = ?',
          whereArgs: <Object?>[resultId, athleteProfileId],
        );
        if (updated != 1) {
          throw StateError('找不到可人工覆盖的 L1 判定。');
        }
        final Map<String, Object?>? row = await _readScheduledWorkoutResultRow(
          transaction,
          athleteProfileId: athleteProfileId,
          resultId: resultId,
        );
        if (row == null) throw StateError('人工覆盖后的 L1 判定读取失败。');
        return _scheduledWorkoutResultFromRow(row);
      },
    );
  }

  @override
  Future<HealthSyncApplyResult> applyHealthSyncBatch(
    HealthSyncBatch batch, {
    String syncMode = 'background',
  }) {
    return StructuredHealthSyncCoordinator(this).apply(
      batch,
      syncMode: syncMode,
    );
  }

  @override
  Future<void> clearAthleteStructuredData(String athleteId) async {
    // 文件清理失败时不触碰主数据库，调用方可安全重试。
    await removeControlledVersionedDatabaseBackups(_database.path);
    await StructuredHealthSyncCoordinator(this).clearAthleteData(athleteId);
  }

  @override
  Future<Map<String, Object?>?> readHealthSyncAnchor({
    required String athleteId,
    required String objectType,
    required int queryVersion,
  }) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'health_sync_anchors',
      where: 'athlete_profile_id = ? AND object_type = ? AND query_version = ?',
      whereArgs: <Object?>[athleteId, objectType, queryVersion],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  @override
  Future<Map<String, Object?>?> readAthleteProfileRow(
    String athleteProfileId,
  ) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'athlete_profiles',
      where: 'id = ?',
      whereArgs: <Object?>[athleteProfileId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  @override
  Future<Map<String, Object?>?> readWorkoutFactRow({
    required String athleteProfileId,
    required String workoutId,
  }) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'workouts',
      where: 'id = ? AND athlete_profile_id = ?',
      whereArgs: <Object?>[workoutId, athleteProfileId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  @override
  Future<Map<String, Object?>?> findWorkoutFactRowByExternalId({
    required String athleteProfileId,
    required String sourceBundleId,
    required String externalUuid,
  }) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'workouts',
      where: '''
athlete_profile_id = ? AND source_bundle_id = ? AND external_uuid = ?
''',
      whereArgs: <Object?>[
        athleteProfileId,
        sourceBundleId,
        externalUuid,
      ],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  @override
  Future<List<Map<String, Object?>>> listWorkoutFactRows({
    required String athleteProfileId,
    required String startedAtOrAfter,
    required String startedBefore,
  }) {
    return _database.query(
      'workouts',
      where: '''
athlete_profile_id = ? AND started_at_utc >= ? AND started_at_utc < ?
AND source_deleted_at IS NULL
''',
      whereArgs: <Object?>[
        athleteProfileId,
        startedAtOrAfter,
        startedBefore,
      ],
      orderBy: 'started_at_utc ASC, id ASC',
    );
  }

  @override
  Future<List<Map<String, Object?>>> listStrengthSetRows({
    required String athleteProfileId,
    required String localDateOnOrAfter,
    required String localDateBefore,
  }) {
    return _database.rawQuery(
      '''
SELECT ss.*, w.local_date, w.started_at_utc, w.time_zone_name
FROM strength_sets ss
JOIN workouts w ON w.id = ss.workout_id
WHERE ss.athlete_profile_id = ?
  AND w.athlete_profile_id = ?
  AND w.local_date >= ?
  AND w.local_date < ?
  AND w.source_deleted_at IS NULL
ORDER BY w.local_date ASC, ss.workout_id ASC,
  ss.exercise_key ASC, ss.set_index ASC
''',
      <Object?>[
        athleteProfileId,
        athleteProfileId,
        localDateOnOrAfter,
        localDateBefore,
      ],
    );
  }

  @override
  Future<List<Map<String, Object?>>> listAthletePrimaryExerciseRows({
    required String athleteProfileId,
  }) {
    return _database.query(
      'athlete_primary_exercises',
      where: 'athlete_profile_id = ?',
      whereArgs: <Object?>[athleteProfileId],
      orderBy: 'is_active DESC, updated_at DESC, exercise_key ASC',
    );
  }

  @override
  Future<void> setAthletePrimaryExercise({
    required String athleteProfileId,
    required String exerciseKey,
    required String displayName,
    required bool isActive,
    required DateTime updatedAt,
  }) async {
    final String normalizedAthleteId = athleteProfileId.trim();
    final String normalizedExerciseKey = exerciseKey.trim();
    final String normalizedDisplayName = displayName.trim();
    if (normalizedAthleteId.isEmpty ||
        normalizedExerciseKey.isEmpty ||
        normalizedDisplayName.isEmpty) {
      throw const FormatException('主项设置缺少运动员、动作标识或显示名称。');
    }
    final String timestamp = updatedAt.toUtc().toIso8601String();
    await _database.transaction<void>((Transaction transaction) async {
      final int athleteCount = Sqflite.firstIntValue(
            await transaction.rawQuery(
              'SELECT COUNT(*) FROM athlete_profiles WHERE id = ?',
              <Object?>[normalizedAthleteId],
            ),
          ) ??
          0;
      if (athleteCount != 1) {
        throw StateError('主项设置引用的运动员资料不存在。');
      }
      await transaction.rawInsert(
        '''
INSERT INTO athlete_primary_exercises(
  athlete_profile_id, exercise_key, display_name, is_active,
  created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(athlete_profile_id, exercise_key) DO UPDATE SET
  display_name = excluded.display_name,
  is_active = excluded.is_active,
  updated_at = excluded.updated_at
''',
        <Object?>[
          normalizedAthleteId,
          normalizedExerciseKey,
          normalizedDisplayName,
          isActive ? 1 : 0,
          timestamp,
          timestamp,
        ],
      );
      final List<Map<String, Object?>> violations =
          await transaction.rawQuery('PRAGMA foreign_key_check');
      if (violations.isNotEmpty) {
        throw StateError('主项设置保存后的外键校验失败。');
      }
    });
  }

  @override
  Future<List<Map<String, Object?>>> listRunningWorkoutsNeedingContext({
    required String athleteProfileId,
    int limit = 20,
  }) {
    if (athleteProfileId.trim().isEmpty) {
      throw ArgumentError.value(
        athleteProfileId,
        'athleteProfileId',
        '运动员标识不能为空',
      );
    }
    final int safeLimit = limit.clamp(1, 100).toInt();
    return _database.query(
      'workouts',
      columns: const <String>[
        'id',
        'started_at_utc',
        'local_date',
        'time_zone_name',
        'distance_meters',
        'active_duration_seconds',
        'source_bundle_id',
        'source_product_type',
      ],
      where: '''
athlete_profile_id = ? AND external_uuid IS NOT NULL
AND source_kind = 'healthKit'
AND discipline IN ('roadRun', 'trailRun')
AND (run_context IS NULL OR run_context = '' OR run_context = 'unspecified')
AND source_deleted_at IS NULL
''',
      whereArgs: <Object?>[athleteProfileId],
      orderBy: 'started_at_utc DESC, id DESC',
      limit: safeLimit,
    );
  }

  @override
  Future<void> confirmRunningWorkoutContext({
    required String athleteProfileId,
    required String workoutId,
    required String runContext,
    required DateTime confirmedAt,
  }) async {
    if (athleteProfileId.trim().isEmpty || workoutId.trim().isEmpty) {
      throw const FormatException('跑步项目确认缺少运动员或训练标识。');
    }
    if (runContext != 'road' && runContext != 'trail') {
      throw const FormatException('跑步项目只能确认为公路跑或越野跑。');
    }
    final String timestamp = confirmedAt.toUtc().toIso8601String();
    await _database.transaction<void>((Transaction transaction) async {
      final List<Map<String, Object?>> rows = await transaction.query(
        'workouts',
        columns: const <String>[
          'id',
          'external_uuid',
          'discipline',
          'source_kind',
          'payload_json',
          'source_deleted_at',
        ],
        where: 'id = ? AND athlete_profile_id = ?',
        whereArgs: <Object?>[workoutId, athleteProfileId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('找不到待确认的跑步训练。');
      final Map<String, Object?> row = rows.single;
      if (row['external_uuid'] == null || row['source_deleted_at'] != null) {
        throw StateError('该训练不是可确认的有效 HealthKit 跑步事实。');
      }
      if (row['source_kind'] != 'healthKit') {
        throw StateError('该训练并非 HealthKit 跑步事实，不能使用此确认入口。');
      }
      if (row['discipline'] != 'roadRun' && row['discipline'] != 'trailRun') {
        throw StateError('该训练不是 HealthKit `.running` 跑步记录。');
      }
      await transaction.update(
        'workouts',
        <String, Object?>{
          'run_context': runContext,
          'discipline': runContext == 'trail' ? 'trailRun' : 'roadRun',
          'payload_json': jsonEncode(
            _decodeDocument('workouts.payload_json', row['payload_json'])
              ..['runContextConfirmation'] = <String, Object?>{
                'source': 'user',
                'value': runContext,
                'confirmedAt': timestamp,
              },
          ),
          'updated_at': timestamp,
        },
        where: 'id = ? AND athlete_profile_id = ?',
        whereArgs: <Object?>[workoutId, athleteProfileId],
      );
      await transaction.update(
        'workout_analysis_runs',
        <String, Object?>{
          'status': 'invalidated',
          'invalidated_at': timestamp,
        },
        where: 'athlete_profile_id = ? AND workout_id = ?',
        whereArgs: <Object?>[athleteProfileId, workoutId],
      );
      await _invalidateMetricRowsOnExecutor(
        transaction,
        athleteProfileId: athleteProfileId,
        sourceType: 'workouts',
        sourceId: workoutId,
        invalidatedAt: timestamp,
      );
      final List<Map<String, Object?>> violations =
          await transaction.rawQuery('PRAGMA foreign_key_check');
      if (violations.isNotEmpty) {
        throw StateError('跑步项目确认后的外键校验失败。');
      }
    });
  }

  @override
  Future<List<Map<String, Object?>>> listHealthObservationFactRows({
    required String athleteProfileId,
    required String observedAtOrAfter,
    required String observedBefore,
  }) {
    return _database.query(
      'health_observations',
      where: '''
athlete_profile_id = ? AND observed_at_utc >= ? AND observed_at_utc < ?
AND source_deleted_at IS NULL
''',
      whereArgs: <Object?>[
        athleteProfileId,
        observedAtOrAfter,
        observedBefore,
      ],
      orderBy: 'observed_at_utc ASC, id ASC',
    );
  }

  @override
  Future<Map<String, Object?>?> readRhythmSnapshot({
    required String athleteProfileId,
    required String weekStart,
  }) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'rhythm_snapshots',
      where: 'athlete_profile_id = ? AND week_start = ?',
      whereArgs: <Object?>[athleteProfileId, weekStart],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  @override
  Future<Map<String, Object?>> insertRhythmSnapshotIfAbsent(
    Map<String, Object?> row,
  ) async {
    await _database.insert(
      'rhythm_snapshots',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final Map<String, Object?>? persisted = await readRhythmSnapshot(
      athleteProfileId: row['athlete_profile_id']! as String,
      weekStart: row['week_start']! as String,
    );
    if (persisted == null) {
      throw StateError('本周身体节奏快照写入失败。');
    }
    return persisted;
  }

  @override
  Future<List<Map<String, Object?>>> listMealRecords({
    required String athleteProfileId,
    required String localDateOnOrAfter,
    required String localDateOnOrBefore,
  }) {
    return _database.query(
      'meal_records',
      where: '''
athlete_profile_id = ? AND local_date >= ? AND local_date <= ?
AND revoked_at IS NULL
''',
      whereArgs: <Object?>[
        athleteProfileId,
        localDateOnOrAfter,
        localDateOnOrBefore,
      ],
      orderBy: 'local_date DESC, created_at DESC',
    );
  }

  @override
  Future<void> saveMealRecord(Map<String, Object?> row) async {
    final String summary = (row['summary'] as String? ?? '').trim();
    if (summary.isEmpty) {
      throw const FormatException('饮食记录内容不能为空。');
    }
    await _database.insert(
      'meal_records',
      <String, Object?>{...row, 'summary': summary},
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<void> revokeMealRecord({
    required String athleteProfileId,
    required String recordId,
    required String revokedAt,
  }) async {
    await _database.update(
      'meal_records',
      <String, Object?>{'revoked_at': revokedAt},
      where: 'id = ? AND athlete_profile_id = ? AND revoked_at IS NULL',
      whereArgs: <Object?>[recordId, athleteProfileId],
    );
  }

  @override
  Future<void> saveWorkoutAnalysisRunRow(
    Map<String, Object?> row, {
    bool markRouteAvailable = false,
  }) async {
    await _database.transaction<void>((Transaction transaction) async {
      final List<Map<String, Object?>> existing = await transaction.query(
        'workout_analysis_runs',
        columns: const <String>['athlete_profile_id', 'workout_id'],
        where: 'id = ?',
        whereArgs: <Object?>[row['id']],
        limit: 1,
      );
      if (existing.isNotEmpty &&
          (existing.single['athlete_profile_id'] != row['athlete_profile_id'] ||
              existing.single['workout_id'] != row['workout_id'])) {
        throw StateError('训练分析运行不能移动到其他运动员或训练记录。');
      }
      await transaction.rawInsert(
        '''
INSERT INTO workout_analysis_runs(
  id, athlete_profile_id, workout_id, algorithm_version, input_fingerprint,
  status, quality_json, result_json, started_at, completed_at, invalidated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  status = excluded.status,
  quality_json = excluded.quality_json,
  result_json = excluded.result_json,
  started_at = excluded.started_at,
  completed_at = excluded.completed_at,
  invalidated_at = excluded.invalidated_at
''',
        <Object?>[
          row['id'],
          row['athlete_profile_id'],
          row['workout_id'],
          row['algorithm_version'],
          row['input_fingerprint'],
          row['status'],
          row['quality_json'],
          row['result_json'],
          row['started_at'],
          row['completed_at'],
          row['invalidated_at'],
        ],
      );
      final Object? rawWorkoutSummary = row['workout_summary'];
      if (rawWorkoutSummary is Map) {
        final Map<String, Object?> summary =
            Map<String, Object?>.from(rawWorkoutSummary);
        final int? sampleCount =
            (summary['heartRateSampleCount'] as num?)?.toInt();
        final double? coverage =
            (summary['heartRateCoverage'] as num?)?.toDouble();
        final double? average =
            (summary['averageHeartRate'] as num?)?.toDouble();
        final double? maximum =
            (summary['maximumHeartRate'] as num?)?.toDouble();
        if (sampleCount == null ||
            sampleCount < 0 ||
            coverage == null ||
            !coverage.isFinite ||
            coverage < 0 ||
            coverage > 1 ||
            (average != null && !average.isFinite) ||
            (maximum != null && !maximum.isFinite)) {
          throw StateError('训练分析生成的心率摘要无效。');
        }
        final int updated = await transaction.update(
          'workouts',
          <String, Object?>{
            'average_heart_rate': average,
            'maximum_heart_rate': maximum,
            'heart_rate_sample_count': sampleCount,
            'heart_rate_coverage': coverage,
            'updated_at': row['completed_at'] ?? row['started_at'],
          },
          where: '''
id = ? AND athlete_profile_id = ? AND source_deleted_at IS NULL
''',
          whereArgs: <Object?>[
            row['workout_id'],
            row['athlete_profile_id'],
          ],
        );
        if (updated != 1) {
          throw StateError('心率摘要对应的训练事实不存在或已删除。');
        }
      }
      if (markRouteAvailable) {
        await transaction.update(
          'workouts',
          <String, Object?>{
            'route_status': 'available',
            'updated_at': row['completed_at'] ?? row['started_at'],
          },
          where: '''
id = ? AND athlete_profile_id = ? AND source_deleted_at IS NULL
AND route_external_uuid IS NOT NULL AND route_status = 'pending'
''',
          whereArgs: <Object?>[row['workout_id'], row['athlete_profile_id']],
        );
      }
    });
  }

  @override
  Future<List<Map<String, Object?>>> listWorkoutAnalysisRunRows({
    required String athleteProfileId,
    required String workoutStartedAtOrAfter,
    required String workoutStartedBefore,
  }) {
    return _database.rawQuery(
      '''
SELECT war.*
FROM workout_analysis_runs war
JOIN workouts w ON w.id = war.workout_id
WHERE war.athlete_profile_id = ?
  AND w.started_at_utc >= ?
  AND w.started_at_utc < ?
  AND w.source_deleted_at IS NULL
  AND war.invalidated_at IS NULL
  AND war.status = 'completed'
ORDER BY w.started_at_utc ASC, war.id ASC
''',
      <Object?>[
        athleteProfileId,
        workoutStartedAtOrAfter,
        workoutStartedBefore,
      ],
    );
  }

  @override
  Future<void> saveMetricAggregateRow(Map<String, Object?> row) async {
    await _database.transaction<void>((Transaction transaction) async {
      final List<Map<String, Object?>> existing = await transaction.query(
        'metric_aggregates',
        columns: const <String>['athlete_profile_id'],
        where: 'id = ?',
        whereArgs: <Object?>[row['id']],
        limit: 1,
      );
      if (existing.isNotEmpty &&
          existing.single['athlete_profile_id'] != row['athlete_profile_id']) {
        throw StateError('指标记录不能移动到其他运动员账号。');
      }
      await transaction.rawInsert(
        '''
INSERT INTO metric_aggregates(
  id, athlete_profile_id, metric_code, load_method, period_type,
  period_start_local, period_end_local, time_zone_name, value, unit,
  sample_count, sample_duration_seconds, coverage, status, baseline_value,
  algorithm_version, input_fingerprint, computed_at, invalidated_at,
  metadata_json
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  metric_code = excluded.metric_code,
  load_method = excluded.load_method,
  period_type = excluded.period_type,
  period_start_local = excluded.period_start_local,
  period_end_local = excluded.period_end_local,
  time_zone_name = excluded.time_zone_name,
  value = excluded.value,
  unit = excluded.unit,
  sample_count = excluded.sample_count,
  sample_duration_seconds = excluded.sample_duration_seconds,
  coverage = excluded.coverage,
  status = excluded.status,
  baseline_value = excluded.baseline_value,
  algorithm_version = excluded.algorithm_version,
  input_fingerprint = excluded.input_fingerprint,
  computed_at = excluded.computed_at,
  invalidated_at = excluded.invalidated_at,
  metadata_json = excluded.metadata_json
''',
        <Object?>[
          row['id'],
          row['athlete_profile_id'],
          row['metric_code'],
          row['load_method'],
          row['period_type'],
          row['period_start_local'],
          row['period_end_local'],
          row['time_zone_name'],
          row['value'],
          row['unit'],
          row['sample_count'],
          row['sample_duration_seconds'],
          row['coverage'],
          row['status'],
          row['baseline_value'],
          row['algorithm_version'],
          row['input_fingerprint'],
          row['computed_at'],
          row['invalidated_at'],
          row['metadata_json'],
        ],
      );
    });
  }

  @override
  Future<List<Map<String, Object?>>> listMetricAggregateRows({
    required String athleteProfileId,
    String? periodType,
    String? periodStartLocal,
    required bool includeInvalidated,
  }) {
    final List<String> clauses = <String>['athlete_profile_id = ?'];
    final List<Object?> arguments = <Object?>[athleteProfileId];
    if (periodType != null) {
      clauses.add('period_type = ?');
      arguments.add(periodType);
    }
    if (periodStartLocal != null) {
      clauses.add('period_start_local = ?');
      arguments.add(periodStartLocal);
    }
    if (!includeInvalidated) {
      clauses.add("status <> 'invalidated' AND invalidated_at IS NULL");
    }
    return _database.query(
      'metric_aggregates',
      where: clauses.join(' AND '),
      whereArgs: arguments,
      orderBy: 'period_start_local DESC, metric_code ASC, id ASC',
    );
  }

  @override
  Future<void> saveMetricLineageRow(Map<String, Object?> row) async {
    await _database.rawInsert(
      '''
INSERT INTO metric_lineage(
  metric_aggregate_id, source_table, source_id, source_fingerprint,
  relationship, created_at, invalidated_at
) VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(metric_aggregate_id, source_table, source_id, relationship)
DO UPDATE SET
  source_fingerprint = excluded.source_fingerprint,
  created_at = excluded.created_at,
  invalidated_at = excluded.invalidated_at
''',
      <Object?>[
        row['metric_aggregate_id'],
        row['source_table'],
        row['source_id'],
        row['source_fingerprint'],
        row['relationship'],
        row['created_at'],
        row['invalidated_at'],
      ],
    );
  }

  @override
  Future<List<Map<String, Object?>>> listMetricLineageRows({
    required String metricId,
  }) {
    return _database.query(
      'metric_lineage',
      where: 'metric_aggregate_id = ?',
      whereArgs: <Object?>[metricId],
      orderBy: 'created_at ASC, source_table ASC, source_id ASC',
    );
  }

  @override
  Future<List<String>> invalidateMetricRowsBySource({
    required String athleteProfileId,
    required String sourceType,
    required String sourceId,
    required String invalidatedAt,
  }) {
    return _database.transaction<List<String>>(
      (Transaction transaction) => _invalidateMetricRowsOnExecutor(
        transaction,
        athleteProfileId: athleteProfileId,
        sourceType: sourceType,
        sourceId: sourceId,
        invalidatedAt: invalidatedAt,
      ),
    );
  }

  @override
  Future<void> saveReportRevisionRow(Map<String, Object?> row) async {
    await _database.transaction<void>((Transaction transaction) async {
      final List<Map<String, Object?>> sameId = await transaction.query(
        'report_revisions',
        where: 'id = ?',
        whereArgs: <Object?>[row['id']],
        limit: 1,
      );
      if (sameId.isNotEmpty) {
        if (_sameReportRevisionRow(sameId.single, row)) return;
        throw StateError('报告修订不可覆盖，请创建新的修订号。');
      }
      final List<Map<String, Object?>> sameRevision = await transaction.query(
        'report_revisions',
        columns: const <String>['id'],
        where: '''
athlete_profile_id = ? AND report_type = ? AND period_key = ?
AND revision_number = ?
''',
        whereArgs: <Object?>[
          row['athlete_profile_id'],
          row['report_type'],
          row['period_key'],
          row['revision_number'],
        ],
        limit: 1,
      );
      if (sameRevision.isNotEmpty) {
        throw StateError('同一周期的报告修订号已存在。');
      }
      await transaction.insert('report_revisions', row);
    });
  }

  @override
  Future<List<Map<String, Object?>>> listReportRevisionRows({
    required String athleteProfileId,
    required String reportType,
    required String periodKey,
  }) {
    return _database.query(
      'report_revisions',
      where: 'athlete_profile_id = ? AND report_type = ? AND period_key = ?',
      whereArgs: <Object?>[athleteProfileId, reportType, periodKey],
      orderBy: 'revision_number DESC, created_at DESC',
    );
  }

  @override
  Future<void> saveAdjustmentProposalRow(Map<String, Object?> row) async {
    await _database.transaction<void>((Transaction transaction) async {
      final List<Map<String, Object?>> existing = await transaction.query(
        'adjustment_proposals',
        columns: const <String>['athlete_profile_id'],
        where: 'id = ?',
        whereArgs: <Object?>[row['id']],
        limit: 1,
      );
      if (existing.isNotEmpty &&
          existing.single['athlete_profile_id'] != row['athlete_profile_id']) {
        throw StateError('调整建议不能移动到其他运动员账号。');
      }
      await transaction.rawInsert(
        '''
INSERT INTO adjustment_proposals(
  id, athlete_profile_id, trigger_metric_id, trigger_metric_code, plan_id,
  workout_day_id, workout_title, algorithm_version, status, reason,
  before_json, proposed_json, created_at, confirmed_at, rejected_at, undone_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  trigger_metric_id = excluded.trigger_metric_id,
  trigger_metric_code = excluded.trigger_metric_code,
  plan_id = excluded.plan_id,
  workout_day_id = excluded.workout_day_id,
  workout_title = excluded.workout_title,
  algorithm_version = excluded.algorithm_version,
  status = excluded.status,
  reason = excluded.reason,
  before_json = excluded.before_json,
  proposed_json = excluded.proposed_json,
  confirmed_at = excluded.confirmed_at,
  rejected_at = excluded.rejected_at,
  undone_at = excluded.undone_at
''',
        <Object?>[
          row['id'],
          row['athlete_profile_id'],
          row['trigger_metric_id'],
          row['trigger_metric_code'],
          row['plan_id'],
          row['workout_day_id'],
          row['workout_title'],
          row['algorithm_version'],
          row['status'],
          row['reason'],
          row['before_json'],
          row['proposed_json'],
          row['created_at'],
          row['confirmed_at'],
          row['rejected_at'],
          row['undone_at'],
        ],
      );
    });
  }

  @override
  Future<List<Map<String, Object?>>> listAdjustmentProposalRows({
    required String athleteProfileId,
  }) {
    return _database.query(
      'adjustment_proposals',
      where: 'athlete_profile_id = ?',
      whereArgs: <Object?>[athleteProfileId],
      orderBy: 'created_at DESC, id DESC',
    );
  }

  @override
  Future<void> close() => _database.close();

  @override
  Future<void> upsertGrowthEvidenceRow(Map<String, Object?> row) async {
    await _database.rawInsert(
      '''
INSERT INTO growth_evidence_events(
  id, athlete_profile_id, event_type, title, description, occurred_at,
  occurred_on, time_zone_offset_minutes, time_zone_name, source_table,
  source_id, evidence_json, created_at, updated_at, revoked_at, model_version
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  event_type = excluded.event_type,
  title = excluded.title,
  description = excluded.description,
  occurred_at = excluded.occurred_at,
  occurred_on = excluded.occurred_on,
  time_zone_offset_minutes = excluded.time_zone_offset_minutes,
  time_zone_name = excluded.time_zone_name,
  source_table = excluded.source_table,
  source_id = excluded.source_id,
  evidence_json = excluded.evidence_json,
  updated_at = excluded.updated_at,
  revoked_at = excluded.revoked_at,
  model_version = excluded.model_version
''',
      <Object?>[
        row['id'],
        row['athlete_profile_id'],
        row['event_type'],
        row['title'],
        row['description'],
        row['occurred_at'],
        row['occurred_on'],
        row['time_zone_offset_minutes'],
        row['time_zone_name'],
        row['source_table'],
        row['source_id'],
        row['evidence_json'],
        row['created_at'],
        row['updated_at'],
        row['revoked_at'],
        row['model_version'],
      ],
    );
  }

  @override
  Future<List<Map<String, Object?>>> listGrowthEvidenceRows({
    required String athleteProfileId,
    required bool includeRevoked,
    required int limit,
    required int offset,
  }) {
    return _database.query(
      'growth_evidence_events',
      where: includeRevoked
          ? 'athlete_profile_id = ?'
          : 'athlete_profile_id = ? AND revoked_at IS NULL',
      whereArgs: <Object?>[athleteProfileId],
      orderBy: 'occurred_at DESC, id DESC',
      limit: limit.clamp(1, 100).toInt(),
      offset: offset < 0 ? 0 : offset,
    );
  }

  @override
  Future<void> revokeGrowthEvidenceRow({
    required String athleteProfileId,
    required String sourceTable,
    required String sourceId,
    required String revokedAt,
  }) {
    return _database.update(
      'growth_evidence_events',
      <String, Object?>{
        'revoked_at': revokedAt,
        'updated_at': revokedAt,
      },
      where: 'athlete_profile_id = ? AND source_table = ? AND source_id = ?',
      whereArgs: <Object?>[athleteProfileId, sourceTable, sourceId],
    );
  }

  @override
  Future<Map<String, Object?>?> readGrowthLevelStateRow(
    String athleteProfileId,
  ) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'growth_level_state',
      where: 'athlete_profile_id = ?',
      whereArgs: <Object?>[athleteProfileId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  @override
  Future<void> upsertGrowthLevelStateRow(Map<String, Object?> row) async {
    await _database.rawInsert(
      '''
INSERT INTO growth_level_state(
  athlete_profile_id, peak_xp, peak_level, model_version, updated_at
) VALUES (?, ?, ?, ?, ?)
ON CONFLICT(athlete_profile_id) DO UPDATE SET
  peak_xp = excluded.peak_xp,
  peak_level = excluded.peak_level,
  model_version = excluded.model_version,
  updated_at = excluded.updated_at
''',
      <Object?>[
        row['athlete_profile_id'],
        row['peak_xp'],
        row['peak_level'],
        row['model_version'],
        row['updated_at'],
      ],
    );
  }

  @override
  Future<void> upsertWeeklyGrowthReportRow(Map<String, Object?> row) async {
    await _database.rawInsert(
      '''
INSERT INTO weekly_reports(
  id, athlete_profile_id, week_key, week_starts_on, week_ends_on,
  completion_rate, training_load, summary, payload_json, created_at,
  updated_at, locked_at, regenerated_at, model_version
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(athlete_profile_id, week_key) DO UPDATE SET
  id = excluded.id,
  week_ends_on = excluded.week_ends_on,
  completion_rate = excluded.completion_rate,
  training_load = excluded.training_load,
  summary = excluded.summary,
  payload_json = excluded.payload_json,
  updated_at = excluded.updated_at,
  locked_at = excluded.locked_at,
  regenerated_at = excluded.regenerated_at,
  model_version = excluded.model_version
''',
      <Object?>[
        row['id'],
        row['athlete_profile_id'],
        row['week_key'],
        row['week_starts_on'],
        row['week_ends_on'],
        row['completion_rate'],
        row['training_load'],
        row['summary'],
        row['payload_json'],
        row['created_at'],
        row['updated_at'],
        row['locked_at'],
        row['regenerated_at'],
        row['model_version'],
      ],
    );
  }

  @override
  Future<List<Map<String, Object?>>> listWeeklyGrowthReportRows({
    required String athleteProfileId,
    required int limit,
    required int offset,
  }) {
    return _database.query(
      'weekly_reports',
      where: 'athlete_profile_id = ?',
      whereArgs: <Object?>[athleteProfileId],
      orderBy: 'week_starts_on DESC',
      limit: limit.clamp(1, 100).toInt(),
      offset: offset < 0 ? 0 : offset,
    );
  }

  static Future<void> _upsertAthleteProfileOnExecutor(
    DatabaseExecutor executor,
    Map<String, Object?> row,
  ) async {
    await executor.rawInsert(
      '''
INSERT INTO athlete_profiles(
  id, name, age, birth_date, biological_sex, height_cm, weight_kg,
  experience_level, payload_json, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  name = excluded.name,
  age = excluded.age,
  birth_date = excluded.birth_date,
  biological_sex = excluded.biological_sex,
  height_cm = excluded.height_cm,
  weight_kg = excluded.weight_kg,
  experience_level = excluded.experience_level,
  payload_json = excluded.payload_json,
  updated_at = excluded.updated_at
''',
      <Object?>[
        row['id'],
        row['name'],
        row['age'],
        row['birth_date'],
        row['biological_sex'],
        row['height_cm'],
        row['weight_kg'],
        row['experience_level'],
        row['payload_json'],
        row['created_at'],
        row['updated_at'],
      ],
    );
  }

  Future<void> _verifyDatabase() async {
    final int userVersion = await _database.getVersion();
    if (userVersion != TrainFlowDatabaseSchema.version) {
      throw StateError(
        '数据库版本校验失败：期望 ${TrainFlowDatabaseSchema.version}，'
        '实际 $userVersion',
      );
    }
    final List<Map<String, Object?>> foreignKeyEnabledRows =
        await _database.rawQuery('PRAGMA foreign_keys');
    final Object? foreignKeyEnabled = foreignKeyEnabledRows.isEmpty
        ? null
        : foreignKeyEnabledRows.first.values.firstOrNull;
    if (foreignKeyEnabled != 1) {
      throw StateError('数据库外键约束未启用');
    }
    final List<Map<String, Object?>> tableRows = await _database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final Set<String> actualTables = tableRows
        .map((Map<String, Object?> row) => row['name'])
        .whereType<String>()
        .toSet();
    final Set<String> missingTables =
        TrainFlowDatabaseSchema.requiredTables.difference(actualTables);
    if (missingTables.isNotEmpty) {
      throw StateError('数据库结构不完整，缺少表：${missingTables.join('、')}');
    }

    final List<Map<String, Object?>> indexRows = await _database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    final Set<String> actualIndexes = indexRows
        .map((Map<String, Object?> row) => row['name'])
        .whereType<String>()
        .toSet();
    final Set<String> missingIndexes =
        TrainFlowDatabaseSchema.requiredIndexes.difference(actualIndexes);
    if (missingIndexes.isNotEmpty) {
      throw StateError('数据库索引不完整，缺少：${missingIndexes.join('、')}');
    }

    final List<Map<String, Object?>> foreignKeyViolations =
        await _database.rawQuery('PRAGMA foreign_key_check');
    if (foreignKeyViolations.isNotEmpty) {
      throw StateError('数据库外键完整性检查失败');
    }

    final List<Map<String, Object?>> integrityRows =
        await _database.rawQuery('PRAGMA quick_check');
    final Object? integrityValue =
        integrityRows.isEmpty ? null : integrityRows.first.values.firstOrNull;
    if (integrityValue != 'ok') {
      throw StateError('数据库完整性检查失败');
    }
  }
}

Future<Map<String, Object?>?> _readScheduledWorkoutResultRow(
  DatabaseExecutor executor, {
  required String athleteProfileId,
  required String resultId,
}) async {
  final List<Map<String, Object?>> rows = await executor.rawQuery(
    '''
SELECT r.*,
       sw.source_workout_id AS source_scheduled_workout_id,
       COALESCE(sw.scheduled_date, w.local_date) AS result_local_date
FROM scheduled_workout_results r
LEFT JOIN scheduled_workouts sw ON sw.id = r.scheduled_workout_id
LEFT JOIN workouts w ON w.id = r.workout_id
WHERE r.id = ? AND r.athlete_profile_id = ?
LIMIT 1
''',
    <Object?>[resultId, athleteProfileId],
  );
  return rows.isEmpty ? null : rows.single;
}

StructuredScheduledWorkoutResult _scheduledWorkoutResultFromRow(
  Map<String, Object?> row,
) {
  final String? localDateText = row['result_local_date'] as String?;
  final DateTime? localDate = DateTime.tryParse(localDateText ?? '');
  final DateTime? decidedAt =
      DateTime.tryParse(row['decided_at'] as String? ?? '');
  if (localDate == null || decidedAt == null) {
    throw StateError('L1 判定缺少有效的本地日期或系统判定时间。');
  }
  final WorkoutCompletionStatus systemStatus = _completionStatusFromDatabase(
    row['system_status'],
    label: '系统判定',
  );
  final Object? rawManualStatus = row['manual_override_status'];
  final WorkoutCompletionStatus? manualStatus = rawManualStatus == null
      ? null
      : _completionStatusFromDatabase(rawManualStatus, label: '人工覆盖');
  final String? overrideReason = row['override_reason'] as String?;
  final DateTime? overrideUpdatedAt = overrideReason == null
      ? null
      : DateTime.tryParse(row['updated_at'] as String? ?? '');
  return StructuredScheduledWorkoutResult(
    id: row['id']! as String,
    athleteProfileId: row['athlete_profile_id']! as String,
    scheduledWorkoutId: row['scheduled_workout_id'] as String?,
    sourceScheduledWorkoutId: row['source_scheduled_workout_id'] as String?,
    workoutId: row['workout_id'] as String?,
    localDate: localDate,
    systemStatus: systemStatus,
    systemCompletionRatio: (row['system_completion_ratio'] as num?)?.toDouble(),
    manualOverrideStatus: manualStatus,
    overrideReason: overrideReason,
    matchingBasis: row['matching_basis'] as String? ?? '',
    systemDecidedAt: decidedAt,
    overrideUpdatedAt: overrideUpdatedAt,
  );
}

WorkoutCompletionStatus _completionStatusFromDatabase(
  Object? value, {
  required String label,
}) {
  for (final WorkoutCompletionStatus status in WorkoutCompletionStatus.values) {
    if (status.name == value) return status;
  }
  throw StateError('$label包含未知状态：${value ?? '空'}。');
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _localDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class _SqfliteStructuredStorageTransaction
    implements StructuredStorageTransaction {
  const _SqfliteStructuredStorageTransaction(this._transaction);

  final Transaction _transaction;

  @override
  Future<void> upsertTrainingPlanVersion(Map<String, Object?> row) async {
    await _transaction.rawInsert(
      '''
INSERT INTO training_plan_versions(
  id, athlete_profile_id, primary_goal_id, secondary_goal_id, race_id,
  version_number, starts_on, ends_on, status, generation_reason,
  payload_json, created_at, activated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  starts_on = excluded.starts_on,
  ends_on = excluded.ends_on,
  status = excluded.status,
  generation_reason = excluded.generation_reason,
  payload_json = excluded.payload_json,
  activated_at = excluded.activated_at
''',
      <Object?>[
        row['id'],
        row['athlete_profile_id'],
        row['primary_goal_id'],
        row['secondary_goal_id'],
        row['race_id'],
        row['version_number'],
        row['starts_on'],
        row['ends_on'],
        row['status'],
        row['generation_reason'],
        row['payload_json'],
        row['created_at'],
        row['activated_at'],
      ],
    );
  }

  @override
  Future<void> upsertScheduledWorkout(Map<String, Object?> row) async {
    await _transaction.rawInsert(
      '''
INSERT INTO scheduled_workouts(
  id, plan_version_id, source_workout_id, title, discipline,
  scheduled_date, week_index, phase, status, estimated_minutes,
  intensity, content_json, created_at, updated_at, started_at, completed_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  plan_version_id = excluded.plan_version_id,
  source_workout_id = excluded.source_workout_id,
  title = excluded.title,
  discipline = excluded.discipline,
  scheduled_date = excluded.scheduled_date,
  week_index = excluded.week_index,
  phase = excluded.phase,
  status = excluded.status,
  estimated_minutes = excluded.estimated_minutes,
  intensity = excluded.intensity,
  content_json = excluded.content_json,
  updated_at = excluded.updated_at
''',
      <Object?>[
        row['id'],
        row['plan_version_id'],
        row['source_workout_id'],
        row['title'],
        row['discipline'],
        row['scheduled_date'],
        row['week_index'],
        row['phase'],
        row['status'],
        row['estimated_minutes'],
        row['intensity'],
        row['content_json'],
        row['created_at'],
        row['updated_at'],
        row['started_at'],
        row['completed_at'],
      ],
    );
  }

  @override
  Future<void> supersedeMissingScheduledWorkouts({
    required String planVersionId,
    required List<String> activeScheduledWorkoutIds,
    required String updatedAt,
  }) async {
    if (activeScheduledWorkoutIds.isEmpty) {
      await _transaction.update(
        'scheduled_workouts',
        <String, Object?>{'status': 'superseded', 'updated_at': updatedAt},
        where: 'plan_version_id = ?',
        whereArgs: <Object?>[planVersionId],
      );
      return;
    }
    final String placeholders =
        List<String>.filled(activeScheduledWorkoutIds.length, '?').join(', ');
    await _transaction.update(
      'scheduled_workouts',
      <String, Object?>{'status': 'superseded', 'updated_at': updatedAt},
      where: 'plan_version_id = ? AND id NOT IN ($placeholders)',
      whereArgs: <Object?>[planVersionId, ...activeScheduledWorkoutIds],
    );
  }

  @override
  Future<void> upsertLocalWorkout(Map<String, Object?> row) async {
    final Object? sourceKind = row['source_kind'];
    if (sourceKind is! String || !sourceKind.startsWith('local_')) {
      throw const FormatException('本地训练事实来源类型无效。');
    }
    final List<Map<String, Object?>> existingRows = await _transaction.query(
      'workouts',
      where: 'id = ?',
      whereArgs: <Object?>[row['id']],
      limit: 1,
    );
    if (existingRows.isEmpty) {
      await _transaction.insert('workouts', row);
      return;
    }
    final Map<String, Object?> existing = existingRows.single;
    final String existingSourceKind = existing['source_kind'] as String? ?? '';
    if (existing['athlete_profile_id'] != row['athlete_profile_id'] ||
        existing['external_uuid'] != null ||
        !existingSourceKind.startsWith('local_')) {
      throw StateError('本地 workout ID 已被其他训练事实占用。');
    }
    final Map<String, Object?> normalized = Map<String, Object?>.from(row)
      ..['created_at'] = existing['created_at'];
    await _transaction.update(
      'workouts',
      normalized,
      where: 'id = ?',
      whereArgs: <Object?>[row['id']],
    );
  }

  @override
  Future<void> upsertScheduledWorkoutResult(
    Map<String, Object?> row,
  ) async {
    final List<Map<String, Object?>> existingRows = await _transaction.query(
      'scheduled_workout_results',
      where: 'id = ?',
      whereArgs: <Object?>[row['id']],
      limit: 1,
    );
    if (existingRows.isEmpty) {
      await _transaction.insert('scheduled_workout_results', row);
      return;
    }
    final Map<String, Object?> existing = existingRows.single;
    if (existing['athlete_profile_id'] != row['athlete_profile_id']) {
      throw StateError('L1 判定不能移动到其他运动员账号。');
    }
    final bool hasOverrideAudit = existing['manual_override_status'] != null ||
        existing['override_reason'] != null;
    await _transaction.update(
      'scheduled_workout_results',
      <String, Object?>{
        'scheduled_workout_id': row['scheduled_workout_id'],
        'workout_id': row['workout_id'],
        'system_status': row['system_status'],
        'system_completion_ratio': row['system_completion_ratio'],
        'matching_basis': row['matching_basis'],
        'decided_at': row['decided_at'],
        'updated_at':
            hasOverrideAudit ? existing['updated_at'] : row['updated_at'],
      },
      where: 'id = ?',
      whereArgs: <Object?>[row['id']],
    );
  }

  @override
  Future<void> deleteUnplannedResultsForWorkout({
    required String athleteId,
    required String workoutId,
    required String exceptResultId,
  }) async {
    await _transaction.delete(
      'scheduled_workout_results',
      where: '''
athlete_profile_id = ? AND workout_id = ? AND scheduled_workout_id IS NULL
AND id <> ?
''',
      whereArgs: <Object?>[athleteId, workoutId, exceptResultId],
    );
  }

  @override
  Future<void> replaceStrengthSets({
    required String athleteId,
    required String workoutId,
    required List<Map<String, Object?>> rows,
  }) async {
    await _transaction.delete(
      'strength_sets',
      where: 'athlete_profile_id = ? AND workout_id = ?',
      whereArgs: <Object?>[athleteId, workoutId],
    );
    for (final Map<String, Object?> row in rows) {
      await _transaction.insert('strength_sets', row);
    }
  }

  @override
  Future<void> beginSyncRun(Map<String, Object?> row) async {
    await _transaction.rawInsert(
      '''
INSERT INTO health_sync_runs(
  id, athlete_profile_id, object_type, query_version, sync_mode, started_at,
  completed_at, upsert_count, deleted_count, status, error_message
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  athlete_profile_id = excluded.athlete_profile_id,
  object_type = excluded.object_type,
  query_version = excluded.query_version,
  sync_mode = excluded.sync_mode,
  started_at = excluded.started_at,
  completed_at = NULL,
  upsert_count = 0,
  deleted_count = 0,
  status = 'running',
  error_message = NULL
''',
      <Object?>[
        row['id'],
        row['athlete_profile_id'],
        row['object_type'],
        row['query_version'],
        row['sync_mode'],
        row['started_at'],
        row['completed_at'],
        row['upsert_count'],
        row['deleted_count'],
        row['status'],
        row['error_message'],
      ],
    );
  }

  @override
  Future<void> completeSyncRun(Map<String, Object?> row) async {
    final int updated = await _transaction.update(
      'health_sync_runs',
      <String, Object?>{
        'completed_at': row['completed_at'],
        'upsert_count': row['upsert_count'],
        'deleted_count': row['deleted_count'],
        'status': row['status'],
        'error_message': row['error_message'],
      },
      where: 'id = ?',
      whereArgs: <Object?>[row['id']],
    );
    if (updated != 1) throw StateError('健康数据同步运行记录不存在。');
  }

  @override
  Future<StructuredFactUpsertResult> upsertWorkout(
    Map<String, Object?> row,
  ) async {
    final List<Map<String, Object?>> existingRows = await _transaction.query(
      'workouts',
      where: '''
athlete_profile_id = ? AND source_bundle_id = ? AND external_uuid = ?
''',
      whereArgs: <Object?>[
        row['athlete_profile_id'],
        row['source_bundle_id'],
        row['external_uuid'],
      ],
      limit: 1,
    );
    final Map<String, Object?> normalized = Map<String, Object?>.from(row);
    if (existingRows.isEmpty) {
      normalized['route_status'] ??= 'unavailable';
      normalized['heart_rate_sample_count'] ??= 0;
      await _transaction.insert('workouts', normalized);
      return StructuredFactUpsertResult(
        sourceType: 'workouts',
        sourceId: normalized['id']! as String,
        changedExistingFact: false,
        localDate: normalized['local_date'] as String?,
        timeZoneName: normalized['time_zone_name'] as String?,
      );
    }

    final Map<String, Object?> existing = existingRows.single;
    final String existingId = existing['id']! as String;
    final bool changed =
        existing['payload_json'] != normalized['payload_json'] ||
            existing['source_deleted_at'] != null;
    normalized
      ..['id'] = existingId
      ..['created_at'] = existing['created_at']
      ..['route_status'] =
          normalized['route_status'] ?? existing['route_status']
      ..['route_external_uuid'] =
          normalized['route_external_uuid'] ?? existing['route_external_uuid']
      ..['heart_rate_sample_count'] = normalized['heart_rate_sample_count'] ??
          existing['heart_rate_sample_count'] ??
          0;
    await _transaction.update(
      'workouts',
      normalized,
      where: 'id = ?',
      whereArgs: <Object?>[existingId],
    );
    return StructuredFactUpsertResult(
      sourceType: 'workouts',
      sourceId: existingId,
      changedExistingFact: changed,
      localDate: normalized['local_date'] as String?,
      timeZoneName: normalized['time_zone_name'] as String?,
    );
  }

  @override
  Future<StructuredFactUpsertResult> upsertHealthObservation(
    Map<String, Object?> row,
  ) async {
    final List<Map<String, Object?>> existingRows = await _transaction.query(
      'health_observations',
      where: '''
athlete_profile_id = ? AND source_bundle_id = ? AND external_uuid = ?
''',
      whereArgs: <Object?>[
        row['athlete_profile_id'],
        row['source_bundle_id'],
        row['external_uuid'],
      ],
      limit: 1,
    );
    final Map<String, Object?> normalized = Map<String, Object?>.from(row);
    if (existingRows.isEmpty) {
      await _transaction.insert('health_observations', normalized);
      return StructuredFactUpsertResult(
        sourceType: 'health_observations',
        sourceId: normalized['id']! as String,
        changedExistingFact: false,
        localDate: normalized['local_date'] as String?,
        timeZoneName: normalized['time_zone_name'] as String?,
      );
    }

    final Map<String, Object?> existing = existingRows.single;
    final String existingId = existing['id']! as String;
    final bool changed =
        existing['payload_json'] != normalized['payload_json'] ||
            existing['source_deleted_at'] != null;
    normalized
      ..['id'] = existingId
      ..['created_at'] = existing['created_at'];
    await _transaction.update(
      'health_observations',
      normalized,
      where: 'id = ?',
      whereArgs: <Object?>[existingId],
    );
    return StructuredFactUpsertResult(
      sourceType: 'health_observations',
      sourceId: existingId,
      changedExistingFact: changed,
      localDate: normalized['local_date'] as String?,
      timeZoneName: normalized['time_zone_name'] as String?,
    );
  }

  @override
  Future<List<StructuredSourceReference>> markExternalIdDeleted({
    required String athleteId,
    required String externalId,
    required DateTime deletedAt,
  }) async {
    final List<StructuredSourceReference> affected =
        <StructuredSourceReference>[];
    final String timestamp = deletedAt.toUtc().toIso8601String();
    for (final ({String table, String type}) target in <({
      String table,
      String type,
    })>[
      (table: 'workouts', type: 'workouts'),
      (table: 'health_observations', type: 'health_observations'),
    ]) {
      final List<Map<String, Object?>> rows = await _transaction.query(
        target.table,
        columns: const <String>[
          'id',
          'local_date',
          'time_zone_name',
          'source_deleted_at',
        ],
        where: 'athlete_profile_id = ? AND external_uuid = ?',
        whereArgs: <Object?>[athleteId, externalId],
      );
      for (final Map<String, Object?> row in rows) {
        final String id = row['id']! as String;
        if (row['source_deleted_at'] == null) {
          await _transaction.update(
            target.table,
            <String, Object?>{
              'source_deleted_at': timestamp,
              'updated_at': timestamp,
            },
            where: 'id = ?',
            whereArgs: <Object?>[id],
          );
        }
        affected.add(StructuredSourceReference(
          target.type,
          id,
          localDate: row['local_date'] as String?,
          timeZoneName: row['time_zone_name'] as String?,
        ));
      }
    }
    return affected;
  }

  @override
  Future<List<StructuredSourceReference>> markRoutePending(
    Map<String, Object?> routeRow,
  ) async {
    final List<Map<String, Object?>> alreadyLinked = await _transaction.query(
      'workouts',
      columns: const <String>[
        'id',
        'route_status',
        'route_external_uuid',
        'local_date',
        'time_zone_name',
      ],
      where: 'athlete_profile_id = ? AND route_external_uuid = ?',
      whereArgs: <Object?>[
        routeRow['athlete_profile_id'],
        routeRow['external_uuid'],
      ],
      orderBy: 'id ASC',
      limit: 1,
    );
    final List<String> clauses = <String>[
      'athlete_profile_id = ?',
      'started_at_utc <= ?',
      'ended_at_utc >= ?',
    ];
    final List<Object?> arguments = <Object?>[
      routeRow['athlete_profile_id'],
      routeRow['started_at_utc'],
      routeRow['ended_at_utc'],
    ];
    final String sourceBundleId = routeRow['source_bundle_id']! as String;
    if (sourceBundleId.isNotEmpty) {
      clauses.add('source_bundle_id = ?');
      arguments.add(sourceBundleId);
    }
    final List<Map<String, Object?>> candidateRows = alreadyLinked.isNotEmpty
        ? alreadyLinked
        : await _transaction.query(
            'workouts',
            columns: const <String>[
              'id',
              'route_status',
              'route_external_uuid',
              'local_date',
              'time_zone_name',
              'elapsed_duration_seconds',
              'started_at_utc',
            ],
            where: clauses.join(' AND '),
            whereArgs: arguments,
          );
    final Map<String, Object?>? selected = alreadyLinked.isNotEmpty
        ? alreadyLinked.single
        : selectRouteWorkoutCandidate(candidateRows);
    final List<Map<String, Object?>> rows = selected == null
        ? const <Map<String, Object?>>[]
        : <Map<String, Object?>>[selected];
    if (rows.isEmpty) {
      throw StateError('路线通知尚未找到关联训练，已保留批次等待重试。');
    }

    final Map<String, Object?> row = rows.single;
    if (row['route_status'] == 'pending' &&
        row['route_external_uuid'] == routeRow['external_uuid']) {
      return const <StructuredSourceReference>[];
    }
    final String workoutId = row['id']! as String;
    await _transaction.update(
      'workouts',
      <String, Object?>{
        'route_status': 'pending',
        'route_external_uuid': routeRow['external_uuid'],
        'updated_at': routeRow['updated_at'],
      },
      where: 'id = ?',
      whereArgs: <Object?>[workoutId],
    );
    return <StructuredSourceReference>[
      StructuredSourceReference(
        'workouts',
        workoutId,
        localDate: row['local_date'] as String?,
        timeZoneName: row['time_zone_name'] as String?,
      ),
    ];
  }

  @override
  Future<List<StructuredSourceReference>> markRouteDeleted({
    required String athleteId,
    required String routeExternalId,
    required DateTime deletedAt,
  }) async {
    final List<Map<String, Object?>> rows = await _transaction.query(
      'workouts',
      columns: const <String>[
        'id',
        'local_date',
        'time_zone_name',
        'route_status',
      ],
      where: 'athlete_profile_id = ? AND route_external_uuid = ?',
      whereArgs: <Object?>[athleteId, routeExternalId],
    );
    final String timestamp = deletedAt.toUtc().toIso8601String();
    final List<StructuredSourceReference> affected =
        <StructuredSourceReference>[];
    for (final Map<String, Object?> row in rows) {
      final String workoutId = row['id']! as String;
      if (row['route_status'] != 'deleted') {
        await _transaction.update(
          'workouts',
          <String, Object?>{
            'route_status': 'deleted',
            'updated_at': timestamp,
          },
          where: 'id = ?',
          whereArgs: <Object?>[workoutId],
        );
      }
      affected.add(StructuredSourceReference(
        'workouts',
        workoutId,
        localDate: row['local_date'] as String?,
        timeZoneName: row['time_zone_name'] as String?,
      ));
    }
    return affected;
  }

  @override
  Future<void> invalidateSource({
    required String athleteId,
    required StructuredSourceReference source,
    required DateTime invalidatedAt,
  }) async {
    final String timestamp = invalidatedAt.toUtc().toIso8601String();
    if (source.sourceType == 'workouts') {
      await _transaction.update(
        'workout_analysis_runs',
        <String, Object?>{
          'status': 'invalidated',
          'invalidated_at': timestamp,
        },
        where: '''
athlete_profile_id = ? AND workout_id = ? AND invalidated_at IS NULL
''',
        whereArgs: <Object?>[athleteId, source.sourceId],
      );
    }
    final List<String> metricIds = await _invalidateMetricRowsOnExecutor(
      _transaction,
      athleteProfileId: athleteId,
      sourceType: source.sourceType,
      sourceId: source.sourceId,
      invalidatedAt: timestamp,
    );
    await _revokeGrowthEvidenceOnExecutor(
      _transaction,
      athleteProfileId: athleteId,
      sourceType: source.sourceType,
      sourceId: source.sourceId,
      revokedAt: timestamp,
    );
    for (final String metricId in metricIds) {
      await _revokeGrowthEvidenceOnExecutor(
        _transaction,
        athleteProfileId: athleteId,
        sourceType: 'metric_aggregates',
        sourceId: metricId,
        revokedAt: timestamp,
      );
    }
  }

  @override
  Future<Map<String, Object?>?> readAnchor({
    required String athleteId,
    required String objectType,
    required int queryVersion,
  }) async {
    final List<Map<String, Object?>> rows = await _transaction.query(
      'health_sync_anchors',
      where: 'athlete_profile_id = ? AND object_type = ? AND query_version = ?',
      whereArgs: <Object?>[athleteId, objectType, queryVersion],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  @override
  Future<void> commitAnchor(Map<String, Object?> row) async {
    await _transaction.rawInsert(
      '''
INSERT INTO health_sync_anchors(
  athlete_profile_id, object_type, query_version, anchor_payload, committed_at
) VALUES (?, ?, ?, ?, ?)
ON CONFLICT(athlete_profile_id, object_type, query_version) DO UPDATE SET
  anchor_payload = excluded.anchor_payload,
  committed_at = excluded.committed_at
''',
      <Object?>[
        row['athlete_profile_id'],
        row['object_type'],
        row['query_version'],
        row['anchor_payload'],
        row['committed_at'],
      ],
    );
  }

  @override
  Future<void> clearAthleteData(String athleteId) async {
    await _transaction.delete(
      'metric_lineage',
      where: '''
metric_aggregate_id IN (
  SELECT id FROM metric_aggregates WHERE athlete_profile_id = ?
)
''',
      whereArgs: <Object?>[athleteId],
    );
    await _transaction.delete(
      'plan_adjustments',
      where: '''
plan_version_id IN (
  SELECT id FROM training_plan_versions WHERE athlete_profile_id = ?
)
''',
      whereArgs: <Object?>[athleteId],
    );
    for (final String table in const <String>[
      'adjustment_proposals',
      'report_revisions',
      'metric_aggregates',
      'workout_analysis_runs',
      'scheduled_workout_results',
      'strength_sets',
      'health_sync_anchors',
      'health_sync_runs',
      'health_observations',
      'workouts',
      'growth_evidence_events',
      'growth_level_state',
      'weekly_reports',
      'health_snapshots',
      'recovery_scores',
    ]) {
      await _transaction.delete(
        table,
        where: 'athlete_profile_id = ?',
        whereArgs: <Object?>[athleteId],
      );
    }
  }

  @override
  Future<List<Map<String, Object?>>> foreignKeyCheck() =>
      _transaction.rawQuery('PRAGMA foreign_key_check');
}

Future<List<String>> _invalidateMetricRowsOnExecutor(
  DatabaseExecutor executor, {
  required String athleteProfileId,
  required String sourceType,
  required String sourceId,
  required String invalidatedAt,
}) async {
  final List<String> sourceTypes = _sourceTypeAliases(sourceType);
  final String sourcePlaceholders =
      List<String>.filled(sourceTypes.length, '?').join(', ');
  final List<Map<String, Object?>> rows = await executor.rawQuery(
    '''
SELECT DISTINCT ml.metric_aggregate_id AS metric_id
FROM metric_lineage ml
JOIN metric_aggregates ma ON ma.id = ml.metric_aggregate_id
WHERE ma.athlete_profile_id = ?
  AND ml.source_table IN ($sourcePlaceholders)
  AND ml.source_id = ?
  AND ml.invalidated_at IS NULL
''',
    <Object?>[athleteProfileId, ...sourceTypes, sourceId],
  );
  final List<String> metricIds = rows
      .map((Map<String, Object?> row) => row['metric_id'])
      .whereType<String>()
      .toSet()
      .toList()
    ..sort();
  for (final String metricId in metricIds) {
    await executor.update(
      'metric_aggregates',
      <String, Object?>{
        'status': 'invalidated',
        'invalidated_at': invalidatedAt,
      },
      where: 'id = ? AND athlete_profile_id = ?',
      whereArgs: <Object?>[metricId, athleteProfileId],
    );
    await executor.rawUpdate(
      '''
UPDATE metric_lineage
SET invalidated_at = ?
WHERE metric_aggregate_id = ?
  AND source_table IN ($sourcePlaceholders)
  AND source_id = ?
  AND invalidated_at IS NULL
''',
      <Object?>[invalidatedAt, metricId, ...sourceTypes, sourceId],
    );
  }
  return List<String>.unmodifiable(metricIds);
}

Future<void> _revokeGrowthEvidenceOnExecutor(
  DatabaseExecutor executor, {
  required String athleteProfileId,
  required String sourceType,
  required String sourceId,
  required String revokedAt,
}) async {
  final List<String> sourceTypes = _sourceTypeAliases(sourceType);
  final String placeholders =
      List<String>.filled(sourceTypes.length, '?').join(', ');
  await executor.rawUpdate(
    '''
UPDATE growth_evidence_events
SET revoked_at = ?, updated_at = ?
WHERE athlete_profile_id = ?
  AND source_table IN ($placeholders)
  AND source_id = ?
  AND revoked_at IS NULL
''',
    <Object?>[
      revokedAt,
      revokedAt,
      athleteProfileId,
      ...sourceTypes,
      sourceId,
    ],
  );
}

List<String> _sourceTypeAliases(String sourceType) {
  return switch (sourceType) {
    'workout' || 'workouts' => const <String>['workout', 'workouts'],
    'health_observation' || 'health_observations' => const <String>[
        'health_observation',
        'health_observations',
      ],
    'metric_aggregate' || 'metric_aggregates' => const <String>[
        'metric_aggregate',
        'metric_aggregates',
      ],
    _ => <String>[sourceType],
  };
}

bool _sameReportRevisionRow(
  Map<String, Object?> persisted,
  Map<String, Object?> candidate,
) {
  for (final String column in const <String>[
    'id',
    'athlete_profile_id',
    'report_type',
    'period_key',
    'revision_number',
    'input_fingerprint',
    'algorithm_version',
    'content_json',
    'created_at',
    'supersedes_revision_id',
  ]) {
    if (persisted[column] != candidate[column]) return false;
  }
  return true;
}

class _SqfliteTrainFlowDatabaseTransaction
    implements TrainFlowDatabaseTransaction {
  const _SqfliteTrainFlowDatabaseTransaction(this._transaction);

  final Transaction _transaction;

  @override
  Future<void> upsertAthleteProfileRow(Map<String, Object?> row) {
    return SqfliteTrainFlowDatabaseGateway._upsertAthleteProfileOnExecutor(
      _transaction,
      row,
    );
  }

  @override
  Future<void> markStorageCutover({
    required int schemaVersion,
    required DateTime completedAt,
  }) async {
    await _transaction.rawInsert(
      '''
INSERT INTO storage_cutover_state(id, schema_version, status, completed_at)
VALUES ('local_primary', ?, 'completed', ?)
ON CONFLICT(id) DO UPDATE SET
  schema_version = excluded.schema_version,
  status = excluded.status,
  completed_at = excluded.completed_at
''',
      <Object?>[schemaVersion, completedAt.toUtc().toIso8601String()],
    );
  }

  @override
  Future<MigrationCheckpoint?> readMigrationCheckpoint(
    String migrationId,
  ) async {
    final List<Map<String, Object?>> rows = await _transaction.query(
      'migration_state',
      where: 'migration_id = ? AND status = ?',
      whereArgs: <Object?>[migrationId, 'completed'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final Map<String, Object?> row = rows.single;
    return MigrationCheckpoint(
      migrationId: row['migration_id']! as String,
      version: row['version']! as int,
      sourceDocumentCount: row['source_document_count']! as int,
      migratedDocumentCount: row['migrated_document_count']! as int,
      completedAt: DateTime.parse(row['completed_at']! as String),
    );
  }

  @override
  Future<void> upsertLegacyDocument(
    String key,
    Map<String, dynamic> value,
    DateTime migratedAt,
  ) async {
    final String timestamp = migratedAt.toUtc().toIso8601String();
    await _transaction.rawInsert(
      '''
INSERT INTO legacy_documents(
  storage_key, payload_json, migrated_at, updated_at
) VALUES (?, ?, ?, ?)
ON CONFLICT(storage_key) DO UPDATE SET
  payload_json = excluded.payload_json,
  migrated_at = excluded.migrated_at,
  updated_at = excluded.updated_at
''',
      <Object?>[key, jsonEncode(value), timestamp, timestamp],
    );
  }

  @override
  Future<Map<String, dynamic>?> readLegacyDocument(String key) async {
    final List<Map<String, Object?>> rows = await _transaction.query(
      'legacy_documents',
      columns: const <String>['payload_json'],
      where: 'storage_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _decodeDocument(key, rows.single['payload_json']);
  }

  @override
  Future<void> markMigrationCompleted(MigrationCheckpoint checkpoint) async {
    await _transaction.insert(
      'migration_state',
      <String, Object?>{
        'migration_id': checkpoint.migrationId,
        'version': checkpoint.version,
        'status': 'completed',
        'source_document_count': checkpoint.sourceDocumentCount,
        'migrated_document_count': checkpoint.migratedDocumentCount,
        'completed_at': checkpoint.completedAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

/// 仅删除当前数据库同目录下严格匹配 `.v<正整数>.bak` 的普通文件。
///
/// 符号链接、子目录、其他数据库备份和后缀近似文件一律保留。
Future<int> removeControlledVersionedDatabaseBackups(
  String databasePath,
) async {
  if (!p.isAbsolute(databasePath)) {
    throw ArgumentError.value(
      databasePath,
      'databasePath',
      '数据库路径必须为绝对路径',
    );
  }
  final String normalizedDatabasePath = p.normalize(databasePath);
  final String databaseName = p.basename(normalizedDatabasePath);
  if (databaseName.isEmpty || databaseName == p.separator) {
    throw ArgumentError.value(databasePath, 'databasePath', '数据库文件名无效');
  }
  final Directory directory = Directory(p.dirname(normalizedDatabasePath));
  if (!await directory.exists()) return 0;

  final RegExp allowedName = RegExp(
    '^${RegExp.escape(databaseName)}\\.v[1-9][0-9]*\\.bak\$',
  );
  final List<FileSystemEntity> candidates = await directory
      .list(followLinks: false)
      .where((FileSystemEntity entity) =>
          p.equals(p.dirname(p.normalize(entity.path)), directory.path) &&
          allowedName.hasMatch(p.basename(entity.path)))
      .toList();
  candidates.sort(
    (FileSystemEntity first, FileSystemEntity second) =>
        first.path.compareTo(second.path),
  );

  int removed = 0;
  try {
    for (final FileSystemEntity candidate in candidates) {
      final FileSystemEntityType type =
          await FileSystemEntity.type(candidate.path, followLinks: false);
      if (type != FileSystemEntityType.file) continue;
      await File(candidate.path).delete();
      removed += 1;
    }
  } catch (error) {
    throw StateError('清理数据库版本化备份失败：$error');
  }
  return removed;
}

Future<void> _createConsistentPreMigrationBackup(String databasePath) async {
  if (!await databaseExists(databasePath)) return;
  Database? sourceDatabase;
  try {
    sourceDatabase = await openDatabase(
      databasePath,
      singleInstance: false,
    );
    final int sourceVersion = await sourceDatabase.getVersion();
    if (sourceVersion <= 0 ||
        sourceVersion >= TrainFlowDatabaseSchema.version) {
      return;
    }
    final File backupFile = File('$databasePath.v$sourceVersion.bak');
    if (await backupFile.exists()) return;
    await backupFile.parent.create(recursive: true);
    await sourceDatabase.execute(
      'VACUUM INTO ?',
      <Object?>[backupFile.path],
    );
    if (!await backupFile.exists() || await backupFile.length() == 0) {
      throw StateError('数据库一致性备份未生成有效文件');
    }
  } catch (error) {
    throw StateError('数据库一致性备份失败，已停止迁移：$error');
  } finally {
    await sourceDatabase?.close();
  }
}

Map<String, dynamic> _decodeDocument(String key, Object? rawPayload) {
  if (rawPayload is! String || rawPayload.isEmpty) {
    throw FormatException('数据库文档内容为空：$key');
  }
  final Object? decoded = jsonDecode(rawPayload);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('数据库文档格式无效：$key');
  }
  return decoded;
}

/// 从已经通过运动员、来源和完整时间包含条件筛选的训练中选择唯一父训练。
///
/// 优先持续时间更短的记录；持续时间相同时取开始更晚、ID 更小的一条，避免
/// 同来源并行训练被同一路线同时绑定。不会修改调用方传入列表。
Map<String, Object?>? selectRouteWorkoutCandidate(
  List<Map<String, Object?>> candidates,
) {
  if (candidates.isEmpty) return null;
  final List<Map<String, Object?>> sorted = List<Map<String, Object?>>.from(
      candidates)
    ..sort((Map<String, Object?> first, Map<String, Object?> second) {
      final int firstDuration =
          (first['elapsed_duration_seconds'] as num?)?.round() ?? 0x7fffffff;
      final int secondDuration =
          (second['elapsed_duration_seconds'] as num?)?.round() ?? 0x7fffffff;
      final int byDuration = firstDuration.compareTo(secondDuration);
      if (byDuration != 0) return byDuration;
      final DateTime firstStart = DateTime.tryParse(
            first['started_at_utc'] as String? ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final DateTime secondStart = DateTime.tryParse(
            second['started_at_utc'] as String? ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final int byStart = secondStart.compareTo(firstStart);
      return byStart != 0
          ? byStart
          : (first['id'] as String? ?? '')
              .compareTo(second['id'] as String? ?? '');
    });
  return sorted.first;
}
