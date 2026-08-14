import 'dart:convert';

import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/models/daily_activity_summary.dart';

class DailyActivitySummaryRepository {
  const DailyActivitySummaryRepository(this._database);

  final PetDatabaseGateway _database;

  Future<DailyActivitySummary?> read({
    required String athleteProfileId,
    required String localDate,
  }) async {
    final Map<String, Object?>? row =
        await _database.readDailyActivitySummaryRow(
      athleteProfileId: athleteProfileId,
      localDate: localDate,
    );
    return row == null ? null : _summaryFromRow(row);
  }

  Future<List<DailyActivitySummary>> list(String athleteProfileId) async {
    final List<Map<String, Object?>> rows =
        await _database.listDailyActivitySummaryRows(athleteProfileId);
    return List<DailyActivitySummary>.unmodifiable(rows.map(_summaryFromRow));
  }

  Future<DailyActivitySummary> mergeHealthKitSummary(
    DailyActivitySummary incoming,
  ) async {
    final DailyActivitySummary? existing = await read(
      athleteProfileId: incoming.athleteProfileId,
      localDate: incoming.localDate,
    );
    final DailyActivitySummary merged = existing == null
        ? incoming
        : _mergeAutomaticSummary(existing, incoming);
    await _save(merged, updatedAt: incoming.syncedAt);
    return merged;
  }

  Future<DailyActivitySummary> saveManualOverride({
    required String athleteProfileId,
    required String localDate,
    required DailyActivityField field,
    required num value,
    required DateTime updatedAt,
  }) async {
    final DailyActivitySummary existing = await _requiredSummary(
      athleteProfileId: athleteProfileId,
      localDate: localDate,
    );
    final DailyActivitySummary updated = _copyField(
      existing,
      field: field,
      value: value,
      source: ActivityFieldSource.manualOverride,
    );
    await _save(updated, updatedAt: updatedAt);
    return updated;
  }

  Future<DailyActivitySummary> restoreAutomaticField({
    required String athleteProfileId,
    required String localDate,
    required DailyActivityField field,
    required DateTime updatedAt,
  }) async {
    final DailyActivitySummary existing = await _requiredSummary(
      athleteProfileId: athleteProfileId,
      localDate: localDate,
    );
    final DailyActivitySummary updated = _copyField(
      existing,
      field: field,
      value: null,
      source: ActivityFieldSource.unavailable,
    );
    await _save(updated, updatedAt: updatedAt);
    return updated;
  }

  Future<DailyActivitySummary> _requiredSummary({
    required String athleteProfileId,
    required String localDate,
  }) async {
    final DailyActivitySummary? summary = await read(
      athleteProfileId: athleteProfileId,
      localDate: localDate,
    );
    if (summary == null) {
      throw StateError('找不到需要更新的每日活动摘要');
    }
    return summary;
  }

  Future<void> _save(
    DailyActivitySummary summary, {
    required DateTime updatedAt,
  }) {
    return _database.upsertDailyActivitySummaryRow(
      _summaryRow(summary, updatedAt: updatedAt),
    );
  }
}

DailyActivitySummary _mergeAutomaticSummary(
  DailyActivitySummary existing,
  DailyActivitySummary incoming,
) {
  bool preserveExisting(DailyActivityField field) {
    final ActivityFieldSource oldSource = existing.sourceFor(field);
    final ActivityFieldSource newSource = incoming.sourceFor(field);
    return oldSource == ActivityFieldSource.manualOverride ||
        (oldSource == ActivityFieldSource.derivedGoal &&
            newSource == ActivityFieldSource.unavailable);
  }

  T? valueFor<T>(
    DailyActivityField field,
    T? oldValue,
    T? newValue,
  ) {
    return preserveExisting(field) ? oldValue : newValue;
  }

  final Map<DailyActivityField, ActivityFieldSource> sources =
      <DailyActivityField, ActivityFieldSource>{};
  for (final DailyActivityField field in DailyActivityField.values) {
    if (preserveExisting(field)) {
      if (existing.fieldSources.containsKey(field)) {
        sources[field] = existing.sourceFor(field);
      }
    } else if (incoming.fieldSources.containsKey(field)) {
      sources[field] = incoming.sourceFor(field);
    }
  }

  return DailyActivitySummary(
    athleteProfileId: incoming.athleteProfileId,
    localDate: incoming.localDate,
    timeZoneName: incoming.timeZoneName,
    timeZoneOffsetMinutes: incoming.timeZoneOffsetMinutes,
    steps: valueFor(
      DailyActivityField.steps,
      existing.steps,
      incoming.steps,
    ),
    stepGoal: valueFor(
      DailyActivityField.stepGoal,
      existing.stepGoal,
      incoming.stepGoal,
    ),
    activeEnergyKcal: valueFor(
      DailyActivityField.activeEnergyKcal,
      existing.activeEnergyKcal,
      incoming.activeEnergyKcal,
    ),
    activeEnergyGoalKcal: valueFor(
      DailyActivityField.activeEnergyGoalKcal,
      existing.activeEnergyGoalKcal,
      incoming.activeEnergyGoalKcal,
    ),
    exerciseMinutes: valueFor(
      DailyActivityField.exerciseMinutes,
      existing.exerciseMinutes,
      incoming.exerciseMinutes,
    ),
    exerciseGoalMinutes: valueFor(
      DailyActivityField.exerciseGoalMinutes,
      existing.exerciseGoalMinutes,
      incoming.exerciseGoalMinutes,
    ),
    standHours: valueFor(
      DailyActivityField.standHours,
      existing.standHours,
      incoming.standHours,
    ),
    standGoalHours: valueFor(
      DailyActivityField.standGoalHours,
      existing.standGoalHours,
      incoming.standGoalHours,
    ),
    fieldSources: sources,
    syncedAt: incoming.syncedAt,
  );
}

DailyActivitySummary _copyField(
  DailyActivitySummary summary, {
  required DailyActivityField field,
  required num? value,
  required ActivityFieldSource source,
}) {
  int? integerValue(DailyActivityField candidate, int? current) {
    if (field != candidate) return current;
    if (value == null) return null;
    if (value.roundToDouble() != value.toDouble()) {
      throw ArgumentError('该活动字段只接受整数');
    }
    return value.toInt();
  }

  double? decimalValue(DailyActivityField candidate, double? current) {
    if (field != candidate) return current;
    return value?.toDouble();
  }

  return DailyActivitySummary(
    athleteProfileId: summary.athleteProfileId,
    localDate: summary.localDate,
    timeZoneName: summary.timeZoneName,
    timeZoneOffsetMinutes: summary.timeZoneOffsetMinutes,
    steps: integerValue(DailyActivityField.steps, summary.steps),
    stepGoal: integerValue(DailyActivityField.stepGoal, summary.stepGoal),
    activeEnergyKcal: decimalValue(
      DailyActivityField.activeEnergyKcal,
      summary.activeEnergyKcal,
    ),
    activeEnergyGoalKcal: decimalValue(
      DailyActivityField.activeEnergyGoalKcal,
      summary.activeEnergyGoalKcal,
    ),
    exerciseMinutes: integerValue(
      DailyActivityField.exerciseMinutes,
      summary.exerciseMinutes,
    ),
    exerciseGoalMinutes: integerValue(
      DailyActivityField.exerciseGoalMinutes,
      summary.exerciseGoalMinutes,
    ),
    standHours: integerValue(
      DailyActivityField.standHours,
      summary.standHours,
    ),
    standGoalHours: integerValue(
      DailyActivityField.standGoalHours,
      summary.standGoalHours,
    ),
    fieldSources: <DailyActivityField, ActivityFieldSource>{
      ...summary.fieldSources,
      field: source,
    },
    syncedAt: summary.syncedAt,
  );
}

Map<String, Object?> _summaryRow(
  DailyActivitySummary summary, {
  required DateTime updatedAt,
}) {
  final List<MapEntry<DailyActivityField, ActivityFieldSource>> sources =
      summary.fieldSources.entries.toList()
        ..sort(
          (
            MapEntry<DailyActivityField, ActivityFieldSource> left,
            MapEntry<DailyActivityField, ActivityFieldSource> right,
          ) =>
              left.key.id.compareTo(right.key.id),
        );
  return <String, Object?>{
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
    'field_sources_json': jsonEncode(<String, String>{
      for (final MapEntry<DailyActivityField, ActivityFieldSource> entry
          in sources)
        entry.key.id: entry.value.id,
    }),
    'synced_at': summary.syncedAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

DailyActivitySummary _summaryFromRow(Map<String, Object?> row) {
  final Map<DailyActivityField, ActivityFieldSource> sources =
      <DailyActivityField, ActivityFieldSource>{};
  final Map<String, Object?> decoded = _decodeJsonObject(
    row['field_sources_json'],
    '每日活动字段来源',
  );
  for (final MapEntry<String, Object?> entry in decoded.entries) {
    final DailyActivityField? field = DailyActivityField.tryFromId(entry.key);
    if (field != null) {
      sources[field] = ActivityFieldSource.fromId(entry.value);
    }
  }
  return DailyActivitySummary(
    athleteProfileId: _requiredString(row, 'athlete_profile_id', '运动员账号'),
    localDate: _requiredString(row, 'local_date', '本地日期'),
    timeZoneName: _requiredString(row, 'time_zone_name', '时区名称'),
    timeZoneOffsetMinutes:
        _requiredInt(row, 'time_zone_offset_minutes', '时区偏移'),
    steps: (row['steps'] as num?)?.toInt(),
    stepGoal: (row['step_goal'] as num?)?.toInt(),
    activeEnergyKcal: (row['active_energy_kcal'] as num?)?.toDouble(),
    activeEnergyGoalKcal: (row['active_energy_goal_kcal'] as num?)?.toDouble(),
    exerciseMinutes: (row['exercise_minutes'] as num?)?.toInt(),
    exerciseGoalMinutes: (row['exercise_goal_minutes'] as num?)?.toInt(),
    standHours: (row['stand_hours'] as num?)?.toInt(),
    standGoalHours: (row['stand_goal_hours'] as num?)?.toInt(),
    fieldSources: sources,
    syncedAt: _requiredDateTime(row, 'synced_at', '同步时间'),
  );
}

Map<String, Object?> _decodeJsonObject(Object? value, String label) {
  try {
    final Object? decoded = jsonDecode(value as String? ?? '');
    if (decoded is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in decoded.entries)
          if (entry.key is String) entry.key! as String: entry.value,
      };
    }
  } catch (_) {
    // 统一在下方抛出稳定的中文格式错误。
  }
  throw FormatException('$label不是有效的 JSON 对象');
}

String _requiredString(
  Map<String, Object?> row,
  String key,
  String label,
) {
  final String value = row[key] as String? ?? '';
  if (value.trim().isEmpty) throw FormatException('$label不能为空');
  return value;
}

int _requiredInt(Map<String, Object?> row, String key, String label) {
  final num? value = row[key] as num?;
  if (value == null) throw FormatException('$label无效');
  return value.toInt();
}

DateTime _requiredDateTime(
  Map<String, Object?> row,
  String key,
  String label,
) {
  final DateTime? value = DateTime.tryParse(row[key] as String? ?? '');
  if (value == null) throw FormatException('$label无效');
  return value.toUtc();
}
