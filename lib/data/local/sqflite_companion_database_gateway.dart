import 'package:sqflite/sqflite.dart';
import 'package:trainflow_ai/data/local/companion_database_gateway.dart';

/// 陪伴数据的 sqflite 实现。所有写入仅落在 v7 的三张 companion 表。
class SqfliteCompanionDatabaseGateway implements CompanionDatabaseGateway {
  const SqfliteCompanionDatabaseGateway(this._database);

  factory SqfliteCompanionDatabaseGateway.fromDatabase(Database database) {
    return SqfliteCompanionDatabaseGateway(database);
  }

  final Database _database;

  @override
  Future<Map<String, Object?>?> readRelationshipRow(
    String athleteProfileId,
  ) async {
    _requireText(athleteProfileId, '运动员账号');
    final List<Map<String, Object?>> rows = await _database.query(
      'companion_relationship',
      where: 'athlete_profile_id = ?',
      whereArgs: <Object?>[athleteProfileId],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  @override
  Future<void> upsertRelationshipRow(Map<String, Object?> row) async {
    final Map<String, Object?> normalized = _relationshipRow(row);
    await _database.insert(
      'companion_relationship',
      normalized,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<Map<String, Object?>>> listMessageRows({
    required String athleteProfileId,
    String? localDate,
    DateTime? createdSince,
    int? limit,
  }) async {
    _requireText(athleteProfileId, '运动员账号');
    if (localDate != null) {
      _requireLocalDate(localDate);
    }
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(limit, 'limit', '条数必须大于零');
    }
    final List<String> clauses = <String>['athlete_profile_id = ?'];
    final List<Object?> values = <Object?>[athleteProfileId];
    if (localDate != null) {
      clauses.add('local_date = ?');
      values.add(localDate);
    }
    if (createdSince != null) {
      clauses.add('created_at >= ?');
      values.add(createdSince.toUtc().toIso8601String());
    }
    final List<Map<String, Object?>> rows = await _database.query(
      'companion_messages',
      where: clauses.join(' AND '),
      whereArgs: values,
      orderBy: 'created_at DESC, message_id DESC',
      limit: limit,
    );
    return rows
        .map((Map<String, Object?> row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  @override
  Future<void> upsertMessageRow(Map<String, Object?> row) async {
    final Map<String, Object?> normalized = _messageRow(row);
    await _database.insert(
      'companion_messages',
      normalized,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<int> purgeExpiredConversationMessageRows({
    required String athleteProfileId,
    required DateTime createdBefore,
  }) {
    _requireText(athleteProfileId, '运动员账号');
    return _database.delete(
      'companion_messages',
      where:
          'athlete_profile_id = ? AND retention_class = ? AND created_at < ?',
      whereArgs: <Object?>[
        athleteProfileId,
        'conversation_30d',
        createdBefore.toUtc().toIso8601String(),
      ],
    );
  }

  @override
  Future<void> markMessageOpened({
    required String messageId,
    required DateTime openedAt,
  }) async {
    _requireText(messageId, '消息编号');
    final int updated = await _database.update(
      'companion_messages',
      <String, Object?>{
        'opened_at': openedAt.toUtc().toIso8601String(),
        'updated_at': openedAt.toUtc().toIso8601String(),
      },
      where: 'message_id = ? AND opened_at IS NULL',
      whereArgs: <Object?>[messageId],
    );
    if (updated > 1) throw StateError('陪伴消息打开状态更新异常');
  }

  @override
  Future<void> recordMessageAction({
    required String messageId,
    required String actionId,
    required DateTime actedAt,
  }) async {
    _requireText(messageId, '消息编号');
    _requireText(actionId, '行动编号');
    final String timestamp = actedAt.toUtc().toIso8601String();
    final int updated = await _database.update(
      'companion_messages',
      <String, Object?>{
        'action_taken_id': actionId,
        'opened_at': timestamp,
        'updated_at': timestamp,
      },
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
    );
    if (updated != 1) throw StateError('未找到要处理的陪伴消息');
  }

  @override
  Future<List<Map<String, Object?>>> listEventRows({
    required String athleteProfileId,
    String? kind,
  }) async {
    _requireText(athleteProfileId, '运动员账号');
    if (kind != null) _requireText(kind, '事件类型');
    final List<Map<String, Object?>> rows = await _database.query(
      'companion_events',
      where: kind == null
          ? 'athlete_profile_id = ?'
          : 'athlete_profile_id = ? AND kind = ?',
      whereArgs: kind == null
          ? <Object?>[athleteProfileId]
          : <Object?>[athleteProfileId, kind],
      orderBy: 'occurred_on DESC, created_at DESC, event_id DESC',
    );
    return rows
        .map((Map<String, Object?> row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  @override
  Future<void> upsertEventRow(Map<String, Object?> row) async {
    final Map<String, Object?> normalized = _eventRow(row);
    await _database.insert(
      'companion_events',
      normalized,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

Map<String, Object?> _relationshipRow(Map<String, Object?> row) {
  final Map<String, Object?> value = Map<String, Object?>.from(row);
  _requireText(value['athlete_profile_id'], '运动员账号');
  _requireLocalDate(_requiredText(value['started_on'], '关系开始日期'));
  _requireText(value['created_at'], '创建时间');
  _requireText(value['updated_at'], '更新时间');
  value.putIfAbsent('species_id', () => 'balance_raccoon');
  value.putIfAbsent('last_resolved_state', () => 'onboarding');
  value.putIfAbsent('disturb_tier', () => 'normal');
  value.putIfAbsent('quiet_hours_start_minute', () => 22 * 60);
  value.putIfAbsent('quiet_hours_end_minute', () => 7 * 60);
  value.putIfAbsent('notifications_enabled', () => 0);
  value.putIfAbsent('notification_detail_enabled', () => 0);
  value.putIfAbsent('boundaries_json', () => '[]');
  value.putIfAbsent('consecutive_unopened', () => 0);
  return value;
}

Map<String, Object?> _messageRow(Map<String, Object?> row) {
  final Map<String, Object?> value = Map<String, Object?>.from(row);
  for (final String field in <String>[
    'message_id',
    'athlete_profile_id',
    'intent_id',
    'copy_variant_id',
    'relationship_state',
    'delivery_kind',
    'privacy_level',
    'body',
    'created_at',
    'updated_at',
  ]) {
    _requireText(value[field], field);
  }
  _requireLocalDate(_requiredText(value['local_date'], '归属日期'));
  value.putIfAbsent('facts_json', () => '[]');
  value.putIfAbsent('actions_json', () => '[]');
  value.putIfAbsent('model_version', () => 1);
  value.putIfAbsent('message_role', () => 'companion');
  value.putIfAbsent('thread_id', () => 'default');
  value.putIfAbsent('retention_class', () => 'companion_history');
  value.putIfAbsent('verification_state', () => 'local_only');
  return value;
}

Map<String, Object?> _eventRow(Map<String, Object?> row) {
  final Map<String, Object?> value = Map<String, Object?>.from(row);
  for (final String field in <String>[
    'event_id',
    'athlete_profile_id',
    'kind',
    'occurred_on',
    'created_at',
  ]) {
    _requireText(value[field], field);
  }
  _requireLocalDate(_requiredText(value['occurred_on'], '发生日期'));
  value.putIfAbsent('payload_json', () => '{}');
  value.putIfAbsent('is_mentionable', () => 1);
  return value;
}

String _requiredText(Object? value, String field) {
  _requireText(value, field);
  return (value! as String).trim();
}

void _requireText(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError.value(value, field, '$field不能为空');
  }
}

void _requireLocalDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw ArgumentError.value(value, '日期', '日期必须使用 YYYY-MM-DD 格式');
  }
}
