import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/models/daily_activity_summary.dart';
import 'package:trainflow_ai/data/models/pet.dart';

enum PetDatabaseTable {
  dailyActivitySummaries('daily_activity_summaries'),
  petCollection('pet_collection'),
  petProfile('pet_profile'),
  petDailyEnergy('pet_daily_energy');

  const PetDatabaseTable(this.sqlName);

  final String sqlName;
}

/// 供宠物网关执行行级操作的窄接口，便于在不暴露数据库连接的情况下测试事务。
abstract interface class PetDatabaseRowExecutor {
  Future<List<Map<String, Object?>>> readRows(
    PetDatabaseTable table, {
    Map<String, Object?> where = const <String, Object?>{},
    String? orderByColumn,
    bool descending = false,
    int? limit,
  });

  Future<void> insertRow(
    PetDatabaseTable table,
    Map<String, Object?> row,
  );

  Future<int> updateRows(
    PetDatabaseTable table,
    Map<String, Object?> values, {
    required Map<String, Object?> where,
  });
}

abstract interface class PetDatabaseAdapter implements PetDatabaseRowExecutor {
  Future<T> transaction<T>(
    Future<T> Function(PetDatabaseRowExecutor transaction) action,
  );
}

/// 基于同一 sqflite 连接提供宠物领域的原子事务。
class SqflitePetDatabaseGateway implements PetDatabaseGateway {
  const SqflitePetDatabaseGateway(this._adapter);

  factory SqflitePetDatabaseGateway.fromDatabase(Database database) {
    return SqflitePetDatabaseGateway(SqflitePetDatabaseAdapter(database));
  }

  final PetDatabaseAdapter _adapter;

  @override
  Future<Map<String, Object?>?> readPetProfileRow(
    String athleteProfileId,
  ) async {
    _requireText(athleteProfileId, '运动员账号');
    return _readOne(
      _adapter,
      PetDatabaseTable.petProfile,
      where: <String, Object?>{'athlete_profile_id': athleteProfileId},
    );
  }

  @override
  Future<List<Map<String, Object?>>> listPetCollectionRows(
    String athleteProfileId,
  ) {
    _requireText(athleteProfileId, '运动员账号');
    return _adapter.readRows(
      PetDatabaseTable.petCollection,
      where: <String, Object?>{'athlete_profile_id': athleteProfileId},
      orderByColumn: 'unlocked_at',
    );
  }

  @override
  Future<Map<String, Object?>?> readDailyActivitySummaryRow({
    required String athleteProfileId,
    required String localDate,
  }) async {
    _requireText(athleteProfileId, '运动员账号');
    _validateLocalDate(localDate);
    return _readOne(
      _adapter,
      PetDatabaseTable.dailyActivitySummaries,
      where: <String, Object?>{
        'athlete_profile_id': athleteProfileId,
        'local_date': localDate,
      },
    );
  }

  @override
  Future<List<Map<String, Object?>>> listDailyActivitySummaryRows(
    String athleteProfileId,
  ) {
    _requireText(athleteProfileId, '运动员账号');
    return _adapter.readRows(
      PetDatabaseTable.dailyActivitySummaries,
      where: <String, Object?>{'athlete_profile_id': athleteProfileId},
      orderByColumn: 'local_date',
      descending: true,
    );
  }

  @override
  Future<void> upsertDailyActivitySummaryRow(
    Map<String, Object?> row,
  ) async {
    final Map<String, Object?> normalized = _validatedSummaryRow(row);
    await _adapter.transaction<void>(
      (PetDatabaseRowExecutor transaction) => _upsertSummaryRow(
        transaction,
        normalized,
      ),
    );
  }

  @override
  Future<Map<String, Object?>?> readPetDailyEnergyRow({
    required String athleteProfileId,
    required String localDate,
  }) async {
    _requireText(athleteProfileId, '运动员账号');
    _validateLocalDate(localDate);
    return _readOne(
      _adapter,
      PetDatabaseTable.petDailyEnergy,
      where: <String, Object?>{
        'athlete_profile_id': athleteProfileId,
        'local_date': localDate,
      },
    );
  }

  @override
  Future<List<Map<String, Object?>>> listPetDailyEnergyRows({
    required String athleteProfileId,
    String? recipientPetId,
  }) {
    _requireText(athleteProfileId, '运动员账号');
    final String? normalizedPetId = _nullableText(recipientPetId);
    return _adapter.readRows(
      PetDatabaseTable.petDailyEnergy,
      where: <String, Object?>{
        'athlete_profile_id': athleteProfileId,
        if (normalizedPetId != null) 'recipient_pet_id': normalizedPetId,
      },
      orderByColumn: 'local_date',
      descending: true,
    );
  }

  @override
  Future<void> chooseFirstEgg(PetFirstEggWrite write) async {
    _validatePetWrite(write.companion);
    await _adapter.transaction<void>(
      (PetDatabaseRowExecutor transaction) async {
        final PetCollectionWrite companion = write.companion;
        final Map<String, Object?>? existingProfile = await _readOne(
          transaction,
          PetDatabaseTable.petProfile,
          where: <String, Object?>{
            'athlete_profile_id': companion.athleteProfileId,
          },
        );
        if (existingProfile != null) {
          throw StateError('当前账号已经完成首蛋选择');
        }
        await _ensurePetCanBeInserted(transaction, companion);
        await transaction.insertRow(
          PetDatabaseTable.petCollection,
          _petCollectionRow(companion),
        );
        await transaction.insertRow(
          PetDatabaseTable.petProfile,
          <String, Object?>{
            'athlete_profile_id': companion.athleteProfileId,
            'active_pet_id': companion.petId,
            'first_egg_species_id': companion.species.id,
            'selected_shell_id': _nullableText(write.selectedShellId),
            'created_at': companion.createdAt.toIso8601String(),
            'updated_at': companion.updatedAt.toIso8601String(),
          },
        );
      },
    );
  }

  @override
  Future<void> insertUnlockedPet(PetCollectionWrite write) async {
    _validatePetWrite(write);
    await _adapter.transaction<void>(
      (PetDatabaseRowExecutor transaction) async {
        final Map<String, Object?>? profile = await _readOne(
          transaction,
          PetDatabaseTable.petProfile,
          where: <String, Object?>{
            'athlete_profile_id': write.athleteProfileId,
          },
        );
        if (profile == null) {
          throw StateError('当前账号尚未完成首蛋选择');
        }
        await _ensurePetCanBeInserted(transaction, write);
        await transaction.insertRow(
          PetDatabaseTable.petCollection,
          _petCollectionRow(write),
        );
      },
    );
  }

  @override
  Future<void> switchActivePet({
    required String athleteProfileId,
    required String petId,
    required DateTime updatedAt,
  }) async {
    _requireText(athleteProfileId, '运动员账号');
    _requireText(petId, '宠物编号');
    await _adapter.transaction<void>(
      (PetDatabaseRowExecutor transaction) async {
        final Map<String, Object?>? pet = await _readOne(
          transaction,
          PetDatabaseTable.petCollection,
          where: <String, Object?>{'pet_id': petId},
        );
        if (pet == null || pet['athlete_profile_id'] != athleteProfileId) {
          throw StateError('只能切换当前账号已经解锁的宠物');
        }
        final int updated = await transaction.updateRows(
          PetDatabaseTable.petProfile,
          <String, Object?>{
            'active_pet_id': petId,
            'updated_at': updatedAt.toUtc().toIso8601String(),
          },
          where: <String, Object?>{
            'athlete_profile_id': athleteProfileId,
          },
        );
        if (updated != 1) {
          throw StateError('当前账号尚未完成首蛋选择');
        }
      },
    );
  }

  @override
  Future<PetSettlementResult> settleDay(PetSettlementWrite write) async {
    final _SettlementContext context = _resolveSettlementContext(write);
    _validateBreakdown(write);
    final String sourceSnapshotJson = _stableSnapshotJson(
      write.sourceSnapshot,
    );
    final String updatedAt = write.settledAt.toUtc().toIso8601String();

    return _adapter.transaction<PetSettlementResult>(
      (PetDatabaseRowExecutor transaction) async {
        final Map<String, Object?>? oldLedger = await _readOne(
          transaction,
          PetDatabaseTable.petDailyEnergy,
          where: <String, Object?>{
            'athlete_profile_id': context.athleteProfileId,
            'local_date': context.localDate,
          },
        );

        final DailyActivitySummary? summary = write.summary;
        if (summary != null) {
          await _upsertSummary(
            transaction,
            summary: summary,
            updatedAt: updatedAt,
          );
        }

        if (oldLedger == null && write.breakdown.total == 0) {
          return const PetSettlementResult(
            recipientPetId: null,
            calculatedTotal: 0,
            awardedTotal: 0,
            awardedDelta: 0,
            didLockRecipient: false,
          );
        }

        final String recipientPetId;
        if (oldLedger != null) {
          recipientPetId = oldLedger['recipient_pet_id']! as String;
        } else {
          recipientPetId = await _validateNewRecipient(
            transaction,
            athleteProfileId: context.athleteProfileId,
            activePetId: write.activePetId,
          );
        }

        final int previousAwarded =
            (oldLedger?['awarded_total'] as num?)?.toInt() ?? 0;
        final int awardedTotal =
            write.mode == PetSettlementMode.explicitHealthDeletion
                ? write.breakdown.total
                : math.max(previousAwarded, write.breakdown.total);
        final int awardedDelta = math.max(0, awardedTotal - previousAwarded);
        final Map<String, Object?> energyRow = <String, Object?>{
          'athlete_profile_id': context.athleteProfileId,
          'local_date': context.localDate,
          'recipient_pet_id': recipientPetId,
          'steps_energy': write.breakdown.stepsEnergy,
          'stand_energy': write.breakdown.standEnergy,
          'exercise_energy': write.breakdown.exerciseEnergy,
          'active_energy': write.breakdown.activeEnergy,
          'training_energy': write.breakdown.trainingEnergy,
          'recovery_energy': write.breakdown.recoveryEnergy,
          'calculated_total': write.breakdown.total,
          'awarded_total': awardedTotal,
          'source_snapshot_json': sourceSnapshotJson,
          'model_version': write.modelVersion,
          'settled_at': oldLedger?['settled_at'] ?? updatedAt,
          'updated_at': updatedAt,
        };

        if (oldLedger == null) {
          await transaction.insertRow(
            PetDatabaseTable.petDailyEnergy,
            energyRow,
          );
        } else {
          final int updated = await transaction.updateRows(
            PetDatabaseTable.petDailyEnergy,
            energyRow,
            where: <String, Object?>{
              'athlete_profile_id': context.athleteProfileId,
              'local_date': context.localDate,
            },
          );
          if (updated != 1) {
            throw StateError('宠物当日能量账本更新失败');
          }
        }

        return PetSettlementResult(
          recipientPetId: recipientPetId,
          calculatedTotal: write.breakdown.total,
          awardedTotal: awardedTotal,
          awardedDelta: awardedDelta,
          didLockRecipient: oldLedger == null,
        );
      },
    );
  }

  Future<void> _ensurePetCanBeInserted(
    PetDatabaseRowExecutor transaction,
    PetCollectionWrite write,
  ) async {
    final Map<String, Object?>? sameId = await _readOne(
      transaction,
      PetDatabaseTable.petCollection,
      where: <String, Object?>{'pet_id': write.petId},
    );
    if (sameId != null) {
      throw StateError('宠物编号已经存在');
    }
    final Map<String, Object?>? sameSpecies = await _readOne(
      transaction,
      PetDatabaseTable.petCollection,
      where: <String, Object?>{
        'athlete_profile_id': write.athleteProfileId,
        'species_id': write.species.id,
      },
    );
    if (sameSpecies != null) {
      throw StateError('当前账号已经解锁该宠物物种');
    }
  }

  Future<String> _validateNewRecipient(
    PetDatabaseRowExecutor transaction, {
    required String athleteProfileId,
    required String activePetId,
  }) async {
    _requireText(activePetId, '出战宠物');
    final Map<String, Object?>? pet = await _readOne(
      transaction,
      PetDatabaseTable.petCollection,
      where: <String, Object?>{'pet_id': activePetId},
    );
    if (pet == null || pet['athlete_profile_id'] != athleteProfileId) {
      throw StateError('能量接收者必须属于当前账号');
    }
    final Map<String, Object?>? profile = await _readOne(
      transaction,
      PetDatabaseTable.petProfile,
      where: <String, Object?>{'athlete_profile_id': athleteProfileId},
    );
    if (profile == null || profile['active_pet_id'] != activePetId) {
      throw StateError('能量接收者不是当前出战宠物');
    }
    return activePetId;
  }
}

class SqflitePetDatabaseAdapter implements PetDatabaseAdapter {
  const SqflitePetDatabaseAdapter(this._database);

  final Database _database;

  @override
  Future<void> insertRow(
    PetDatabaseTable table,
    Map<String, Object?> row,
  ) async {
    await _database.insert(table.sqlName, row);
  }

  @override
  Future<List<Map<String, Object?>>> readRows(
    PetDatabaseTable table, {
    Map<String, Object?> where = const <String, Object?>{},
    String? orderByColumn,
    bool descending = false,
    int? limit,
  }) {
    return _readSqfliteRows(
      _database,
      table,
      where: where,
      orderByColumn: orderByColumn,
      descending: descending,
      limit: limit,
    );
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(PetDatabaseRowExecutor transaction) action,
  ) {
    return _database.transaction<T>(
      (Transaction transaction) => action(
        _SqflitePetRowExecutor(transaction),
      ),
    );
  }

  @override
  Future<int> updateRows(
    PetDatabaseTable table,
    Map<String, Object?> values, {
    required Map<String, Object?> where,
  }) {
    final _WhereClause clause = _whereClause(where);
    return _database.update(
      table.sqlName,
      values,
      where: clause.sql,
      whereArgs: clause.arguments,
    );
  }
}

class _SqflitePetRowExecutor implements PetDatabaseRowExecutor {
  const _SqflitePetRowExecutor(this._transaction);

  final Transaction _transaction;

  @override
  Future<void> insertRow(
    PetDatabaseTable table,
    Map<String, Object?> row,
  ) async {
    await _transaction.insert(table.sqlName, row);
  }

  @override
  Future<List<Map<String, Object?>>> readRows(
    PetDatabaseTable table, {
    Map<String, Object?> where = const <String, Object?>{},
    String? orderByColumn,
    bool descending = false,
    int? limit,
  }) {
    return _readSqfliteRows(
      _transaction,
      table,
      where: where,
      orderByColumn: orderByColumn,
      descending: descending,
      limit: limit,
    );
  }

  @override
  Future<int> updateRows(
    PetDatabaseTable table,
    Map<String, Object?> values, {
    required Map<String, Object?> where,
  }) {
    final _WhereClause clause = _whereClause(where);
    return _transaction.update(
      table.sqlName,
      values,
      where: clause.sql,
      whereArgs: clause.arguments,
    );
  }
}

Future<List<Map<String, Object?>>> _readSqfliteRows(
  DatabaseExecutor executor,
  PetDatabaseTable table, {
  required Map<String, Object?> where,
  required String? orderByColumn,
  required bool descending,
  required int? limit,
}) {
  final _WhereClause clause = _whereClause(where);
  final String? orderBy = orderByColumn == null
      ? null
      : '${_sqlIdentifier(orderByColumn)} ${descending ? 'DESC' : 'ASC'}';
  return executor.query(
    table.sqlName,
    where: clause.sql,
    whereArgs: clause.arguments,
    orderBy: orderBy,
    limit: limit,
  );
}

Future<Map<String, Object?>?> _readOne(
  PetDatabaseRowExecutor executor,
  PetDatabaseTable table, {
  required Map<String, Object?> where,
}) async {
  final List<Map<String, Object?>> rows = await executor.readRows(
    table,
    where: where,
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<void> _upsertSummary(
  PetDatabaseRowExecutor transaction, {
  required DailyActivitySummary summary,
  required String updatedAt,
}) async {
  final Map<String, Object?> row = <String, Object?>{
    'athlete_profile_id': summary.athleteProfileId,
    'local_date': summary.localDate,
    'time_zone_name': summary.timeZoneName,
    'time_zone_offset_minutes': summary.timeZoneOffsetMinutes,
    'steps': summary.steps,
    'step_goal': summary.stepGoal,
    'active_energy_kcal': summary.activeEnergyKcal,
    'active_energy_goal_kcal': summary.activeEnergyGoalKcal,
    'exercise_minutes': summary.exerciseMinutes,
    'exercise_goal_minutes': summary.exerciseGoalMinutes,
    'stand_hours': summary.standHours,
    'stand_goal_hours': summary.standGoalHours,
    'field_sources_json': _stableSnapshotJson(<String, Object?>{
      for (final MapEntry<DailyActivityField, ActivityFieldSource> entry
          in summary.fieldSources.entries)
        entry.key.id: entry.value.id,
    }),
    'synced_at': summary.syncedAt.toIso8601String(),
    'updated_at': updatedAt,
  };
  await _upsertSummaryRow(transaction, row);
}

Future<void> _upsertSummaryRow(
  PetDatabaseRowExecutor transaction,
  Map<String, Object?> row,
) async {
  final Map<String, Object?> key = <String, Object?>{
    'athlete_profile_id': row['athlete_profile_id'],
    'local_date': row['local_date'],
  };
  final Map<String, Object?>? existing = await _readOne(
    transaction,
    PetDatabaseTable.dailyActivitySummaries,
    where: key,
  );
  if (existing == null) {
    await transaction.insertRow(
      PetDatabaseTable.dailyActivitySummaries,
      row,
    );
    return;
  }
  final int updated = await transaction.updateRows(
    PetDatabaseTable.dailyActivitySummaries,
    row,
    where: key,
  );
  if (updated != 1) {
    throw StateError('每日活动摘要更新失败');
  }
}

Map<String, Object?> _validatedSummaryRow(Map<String, Object?> row) {
  const Set<String> allowedColumns = <String>{
    'athlete_profile_id',
    'local_date',
    'time_zone_name',
    'time_zone_offset_minutes',
    'steps',
    'step_goal',
    'active_energy_kcal',
    'active_energy_goal_kcal',
    'exercise_minutes',
    'exercise_goal_minutes',
    'stand_hours',
    'stand_goal_hours',
    'field_sources_json',
    'synced_at',
    'updated_at',
  };
  final Set<String> unexpected = row.keys.toSet().difference(allowedColumns);
  if (unexpected.isNotEmpty) {
    throw ArgumentError('每日活动摘要包含不支持的数据库字段');
  }
  final String athleteProfileId = row['athlete_profile_id'] as String? ?? '';
  final String localDate = row['local_date'] as String? ?? '';
  final String timeZoneName = row['time_zone_name'] as String? ?? '';
  final String fieldSourcesJson = row['field_sources_json'] as String? ?? '';
  final String syncedAt = row['synced_at'] as String? ?? '';
  final String updatedAt = row['updated_at'] as String? ?? '';
  _requireText(athleteProfileId, '运动员账号');
  _validateLocalDate(localDate);
  _requireText(timeZoneName, '时区名称');
  if (row['time_zone_offset_minutes'] is! num) {
    throw ArgumentError('每日活动摘要时区偏移无效');
  }
  Object? decodedSources;
  try {
    decodedSources = jsonDecode(fieldSourcesJson);
  } catch (_) {
    throw ArgumentError('每日活动摘要字段来源必须是 JSON 对象');
  }
  if (decodedSources is! Map) {
    throw ArgumentError('每日活动摘要字段来源必须是 JSON 对象');
  }
  if (DateTime.tryParse(syncedAt) == null ||
      DateTime.tryParse(updatedAt) == null) {
    throw ArgumentError('每日活动摘要时间字段无效');
  }
  return <String, Object?>{
    for (final String column in allowedColumns) column: row[column],
  };
}

Map<String, Object?> _petCollectionRow(PetCollectionWrite write) {
  return <String, Object?>{
    'pet_id': write.petId,
    'athlete_profile_id': write.athleteProfileId,
    'species_id': write.species.id,
    'nickname': write.nickname,
    'unlocked_at': write.unlockedAt.toIso8601String(),
    'born_at': write.bornAt.toIso8601String(),
    'selected_accessory_id': _nullableText(write.selectedAccessoryId),
    'selected_badge_id': _nullableText(write.selectedBadgeId),
    'created_at': write.createdAt.toIso8601String(),
    'updated_at': write.updatedAt.toIso8601String(),
  };
}

void _validatePetWrite(PetCollectionWrite write) {
  _requireText(write.petId, '宠物编号');
  _requireText(write.athleteProfileId, '运动员账号');
  _requireText(write.nickname, '宠物昵称');
}

_SettlementContext _resolveSettlementContext(PetSettlementWrite write) {
  final DailyActivitySummary? summary = write.summary;
  final String? explicitAthleteId = _nullableText(write.athleteProfileId);
  final String? explicitLocalDate = _nullableText(write.localDate);
  if (summary != null) {
    _requireText(summary.athleteProfileId, '运动员账号');
    if (explicitAthleteId != null &&
        explicitAthleteId != summary.athleteProfileId) {
      throw ArgumentError('活动摘要与结算请求的运动员账号不一致');
    }
    if (explicitLocalDate != null && explicitLocalDate != summary.localDate) {
      throw ArgumentError('活动摘要与结算请求的自然日不一致');
    }
    return _SettlementContext(
      athleteProfileId: summary.athleteProfileId,
      localDate: summary.localDate,
    );
  }
  if (explicitAthleteId == null || explicitLocalDate == null) {
    throw ArgumentError('没有活动摘要时必须提供运动员账号和自然日');
  }
  _validateLocalDate(explicitLocalDate);
  return _SettlementContext(
    athleteProfileId: explicitAthleteId,
    localDate: explicitLocalDate,
  );
}

void _validateBreakdown(PetSettlementWrite write) {
  final List<int> values = <int>[
    write.breakdown.stepsEnergy,
    write.breakdown.standEnergy,
    write.breakdown.exerciseEnergy,
    write.breakdown.activeEnergy,
    write.breakdown.activityTotal,
    write.breakdown.trainingEnergy,
    write.breakdown.recoveryEnergy,
    write.breakdown.total,
  ];
  if (values.any((int value) => value < 0) || write.breakdown.total > 160) {
    throw ArgumentError('宠物能量必须位于有效范围内');
  }
  if (write.modelVersion <= 0) {
    throw ArgumentError('宠物能量模型版本必须大于零');
  }
}

String _stableSnapshotJson(Map<String, Object?> snapshot) {
  return jsonEncode(_normalizeSnapshot(snapshot));
}

Object? _normalizeSnapshot(Object? value) {
  if (value == null || value is String || value is bool) return value;
  if (value is num) {
    if (!value.isFinite) {
      throw ArgumentError('来源快照不能包含非有限数值');
    }
    return value;
  }
  if (value is List) {
    return value.map<Object?>(_normalizeSnapshot).toList(growable: false);
  }
  if (value is Map) {
    final List<String> keys = <String>[];
    for (final Object? key in value.keys) {
      if (key is! String) {
        throw ArgumentError('来源快照的字段名必须是字符串');
      }
      _rejectSensitiveSnapshotKey(key);
      keys.add(key);
    }
    keys.sort();
    return <String, Object?>{
      for (final String key in keys) key: _normalizeSnapshot(value[key]),
    };
  }
  throw ArgumentError('来源快照只能保存汇总后的基础字段');
}

void _rejectSensitiveSnapshotKey(String key) {
  final String normalized = key.toLowerCase().replaceAll(
        RegExp('[^a-z0-9]'),
        '',
      );
  final bool containsRawHealthPoint = normalized.contains('rawsample') ||
      normalized.contains('heartratesample') ||
      normalized.contains('healthsample');
  final bool containsAudio =
      normalized.contains('audio') || normalized.contains('recording');
  final bool containsLocation = normalized.contains('coordinate') ||
      normalized.contains('location') ||
      normalized.contains('gpstrace') ||
      normalized.contains('gpssample') ||
      normalized == 'route' ||
      normalized == 'routes';
  if (containsRawHealthPoint || containsAudio || containsLocation) {
    throw ArgumentError('来源快照不得保存原始健康点位、音频或位置轨迹');
  }
}

String _sqlIdentifier(String value) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value)) {
    throw ArgumentError('数据库字段名无效');
  }
  return value;
}

_WhereClause _whereClause(Map<String, Object?> where) {
  if (where.isEmpty) return const _WhereClause(sql: null, arguments: null);
  final List<String> keys = where.keys.toList()..sort();
  return _WhereClause(
    sql: keys.map((String key) => '${_sqlIdentifier(key)} = ?').join(' AND '),
    arguments: keys.map<Object?>((String key) => where[key]).toList(),
  );
}

void _requireText(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError('$label不能为空');
  }
}

String? _nullableText(String? value) {
  final String? normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

void _validateLocalDate(String value) {
  final RegExpMatch? match =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  final DateTime? parsed = DateTime.tryParse(value);
  if (match == null ||
      parsed == null ||
      parsed.year.toString().padLeft(4, '0') != match.group(1) ||
      parsed.month.toString().padLeft(2, '0') != match.group(2) ||
      parsed.day.toString().padLeft(2, '0') != match.group(3)) {
    throw const FormatException('本地日期必须是有效的 yyyy-MM-dd 自然日');
  }
}

class _SettlementContext {
  const _SettlementContext({
    required this.athleteProfileId,
    required this.localDate,
  });

  final String athleteProfileId;
  final String localDate;
}

class _WhereClause {
  const _WhereClause({required this.sql, required this.arguments});

  final String? sql;
  final List<Object?>? arguments;
}
