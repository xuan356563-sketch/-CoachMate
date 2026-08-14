import 'package:sqflite/sqflite.dart';
import 'package:trainflow_ai/data/local/coach_database_gateway.dart';

class SqfliteCoachDatabaseGateway implements CoachDatabaseGateway {
  const SqfliteCoachDatabaseGateway(this._database);

  factory SqfliteCoachDatabaseGateway.fromDatabase(Database database) =>
      SqfliteCoachDatabaseGateway(database);

  final Database _database;

  @override
  Future<void> upsertStateSnapshotRow(Map<String, Object?> row) async {
    _requireFields(row, <String>[
      'snapshot_id',
      'athlete_profile_id',
      'contract_hash',
      'rule_set_version',
      'source_digest',
      'local_date',
      'time_zone_name',
      'generated_at',
      'valid_until',
      'payload_json',
      'created_at',
    ]);
    await _database.insert(
      'coach_state_snapshots',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Map<String, Object?>?> readLatestStateSnapshotRow({
    required String athleteProfileId,
  }) async {
    _requireText(athleteProfileId, '运动员账号');
    final List<Map<String, Object?>> rows = await _database.query(
      'coach_state_snapshots',
      where: 'athlete_profile_id = ?',
      whereArgs: <Object?>[athleteProfileId],
      orderBy: 'generated_at DESC, snapshot_id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  @override
  Future<void> writeMemory({
    required Map<String, Object?> memoryRow,
    required List<Map<String, Object?>> sourceRows,
    String? supersedesMemoryId,
  }) async {
    _requireFields(memoryRow, <String>[
      'memory_id',
      'athlete_profile_id',
      'category',
      'subject',
      'value_json',
      'display_text',
      'status',
      'validity_policy',
      'valid_from',
      'created_at',
      'updated_at',
    ]);
    await _database.transaction((Transaction transaction) async {
      if (supersedesMemoryId != null) {
        final int updated = await transaction.update(
          'coach_memories',
          <String, Object?>{
            'status': 'superseded',
            'superseded_by': memoryRow['memory_id'],
            'sync_allowed': 0,
            'updated_at': memoryRow['updated_at'],
          },
          where:
              'memory_id = ? AND athlete_profile_id = ? AND deleted_at IS NULL',
          whereArgs: <Object?>[
            supersedesMemoryId,
            memoryRow['athlete_profile_id'],
          ],
        );
        if (updated != 1) throw StateError('未找到要纠正的 Coach 记忆');
      }
      await transaction.insert(
        'coach_memories',
        memoryRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.delete(
        'coach_memory_sources',
        where: 'memory_id = ?',
        whereArgs: <Object?>[memoryRow['memory_id']],
      );
      for (final Map<String, Object?> source in sourceRows) {
        await transaction.insert(
          'coach_memory_sources',
          source,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
  }

  @override
  Future<void> tombstoneMemory({
    required String memoryId,
    required String athleteProfileId,
    required DateTime deletedAt,
    required DateTime tombstoneExpiresAt,
  }) async {
    _requireText(memoryId, '记忆编号');
    _requireText(athleteProfileId, '运动员账号');
    await _database.transaction((Transaction transaction) async {
      final int updated = await transaction.update(
        'coach_memories',
        <String, Object?>{
          'value_json': '{}',
          'display_text': '',
          'status': 'deleted',
          'may_mention': 0,
          'user_confirmed': 0,
          'sync_allowed': 0,
          'validity_policy': 'expires_at',
          'valid_until': tombstoneExpiresAt.toUtc().toIso8601String(),
          'deleted_at': deletedAt.toUtc().toIso8601String(),
          'updated_at': deletedAt.toUtc().toIso8601String(),
        },
        where:
            'memory_id = ? AND athlete_profile_id = ? AND deleted_at IS NULL',
        whereArgs: <Object?>[memoryId, athleteProfileId],
      );
      if (updated != 1) throw StateError('未找到要忘记的 Coach 记忆');
      await transaction.delete(
        'coach_memory_sources',
        where: 'memory_id = ?',
        whereArgs: <Object?>[memoryId],
      );
    });
  }

  @override
  Future<Map<String, Object?>?> readMemoryRow({
    required String memoryId,
    required String athleteProfileId,
  }) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'coach_memories',
      where: 'memory_id = ? AND athlete_profile_id = ?',
      whereArgs: <Object?>[memoryId, athleteProfileId],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  @override
  Future<List<Map<String, Object?>>> listMemoryRows({
    required String athleteProfileId,
  }) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'coach_memories',
      where: 'athlete_profile_id = ?',
      whereArgs: <Object?>[athleteProfileId],
      orderBy: 'updated_at DESC, memory_id DESC',
    );
    return rows.map(Map<String, Object?>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, Object?>>> listMemorySourceRows(
      String memoryId) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'coach_memory_sources',
      where: 'memory_id = ?',
      whereArgs: <Object?>[memoryId],
      orderBy: 'observed_at ASC, source_id ASC',
    );
    return rows.map(Map<String, Object?>.from).toList(growable: false);
  }

  @override
  Future<void> upsertTurnTraceRow(Map<String, Object?> row) async {
    _requireFields(row, <String>[
      'trace_id',
      'athlete_profile_id',
      'turn_id',
      'intent',
      'emotion',
      'input_digest',
      'local_decision_digest',
      'final_decision_digest',
      'verification_state',
      'created_at',
      'expires_at',
    ]);
    await _database.insert(
      'coach_turn_traces',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

void _requireFields(Map<String, Object?> row, List<String> fields) {
  for (final String field in fields) {
    _requireText(row[field], field);
  }
}

void _requireText(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError.value(value, field, '$field不能为空');
  }
}
