enum ActivityFieldSource {
  healthKit('health_kit'),
  manualOverride('manual_override'),
  derivedGoal('derived_goal'),
  unavailable('unavailable');

  const ActivityFieldSource(this.id);

  final String id;

  static ActivityFieldSource fromId(Object? value) {
    return ActivityFieldSource.values.firstWhere(
      (ActivityFieldSource source) => source.id == value,
      orElse: () => ActivityFieldSource.unavailable,
    );
  }
}

enum DailyActivityField {
  steps('steps'),
  stepGoal('step_goal'),
  activeEnergyKcal('active_energy_kcal'),
  activeEnergyGoalKcal('active_energy_goal_kcal'),
  exerciseMinutes('exercise_minutes'),
  exerciseGoalMinutes('exercise_goal_minutes'),
  standHours('stand_hours'),
  standGoalHours('stand_goal_hours');

  const DailyActivityField(this.id);

  final String id;

  static DailyActivityField? tryFromId(Object? value) {
    for (final DailyActivityField field in DailyActivityField.values) {
      if (field.id == value) return field;
    }
    return null;
  }
}

/// 按用户所在自然日聚合的活动摘要。
///
/// 缺失值保持为 `null`，以便界面区分“没有授权”和真实的零活动。
class DailyActivitySummary {
  DailyActivitySummary({
    required this.athleteProfileId,
    required String localDate,
    required this.timeZoneName,
    required this.timeZoneOffsetMinutes,
    int? steps,
    int? stepGoal,
    double? activeEnergyKcal,
    double? activeEnergyGoalKcal,
    int? exerciseMinutes,
    int? exerciseGoalMinutes,
    int? standHours,
    int? standGoalHours,
    Map<DailyActivityField, ActivityFieldSource> fieldSources =
        const <DailyActivityField, ActivityFieldSource>{},
    required DateTime syncedAt,
  })  : localDate = _validatedLocalDate(localDate),
        steps = _nonNegativeInt(steps),
        stepGoal = _nonNegativeInt(stepGoal),
        activeEnergyKcal = _nonNegativeDouble(activeEnergyKcal),
        activeEnergyGoalKcal = _nonNegativeDouble(activeEnergyGoalKcal),
        exerciseMinutes = _nonNegativeInt(exerciseMinutes),
        exerciseGoalMinutes = _nonNegativeInt(exerciseGoalMinutes),
        standHours = _nonNegativeInt(standHours),
        standGoalHours = _nonNegativeInt(standGoalHours),
        fieldSources =
            Map<DailyActivityField, ActivityFieldSource>.unmodifiable(
          fieldSources,
        ),
        syncedAt = syncedAt.toUtc();

  factory DailyActivitySummary.fromJson(Map<String, dynamic> json) {
    final Map<DailyActivityField, ActivityFieldSource> sources =
        <DailyActivityField, ActivityFieldSource>{};
    final Object? rawSources = json['fieldSources'];
    if (rawSources is Map) {
      for (final MapEntry<Object?, Object?> entry in rawSources.entries) {
        final DailyActivityField? field =
            DailyActivityField.tryFromId(entry.key);
        if (field == null) continue;
        sources[field] = ActivityFieldSource.fromId(entry.value);
      }
    }

    return DailyActivitySummary(
      athleteProfileId: json['athleteProfileId'] as String? ?? '',
      localDate: json['localDate'] as String? ?? '',
      timeZoneName: json['timeZoneName'] as String? ?? '',
      timeZoneOffsetMinutes:
          (json['timeZoneOffsetMinutes'] as num?)?.toInt() ?? 0,
      steps: (json['steps'] as num?)?.toInt(),
      stepGoal: (json['stepGoal'] as num?)?.toInt(),
      activeEnergyKcal: (json['activeEnergyKcal'] as num?)?.toDouble(),
      activeEnergyGoalKcal: (json['activeEnergyGoalKcal'] as num?)?.toDouble(),
      exerciseMinutes: (json['exerciseMinutes'] as num?)?.toInt(),
      exerciseGoalMinutes: (json['exerciseGoalMinutes'] as num?)?.toInt(),
      standHours: (json['standHours'] as num?)?.toInt(),
      standGoalHours: (json['standGoalHours'] as num?)?.toInt(),
      fieldSources: sources,
      syncedAt: _requiredDateTime(json['syncedAt'], '同步时间'),
    );
  }

  final String athleteProfileId;
  final String localDate;
  final String timeZoneName;
  final int timeZoneOffsetMinutes;
  final int? steps;
  final int? stepGoal;
  final double? activeEnergyKcal;
  final double? activeEnergyGoalKcal;
  final int? exerciseMinutes;
  final int? exerciseGoalMinutes;
  final int? standHours;
  final int? standGoalHours;
  final Map<DailyActivityField, ActivityFieldSource> fieldSources;
  final DateTime syncedAt;

  ActivityFieldSource sourceFor(DailyActivityField field) {
    return fieldSources[field] ?? ActivityFieldSource.unavailable;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'athleteProfileId': athleteProfileId,
        'localDate': localDate,
        'timeZoneName': timeZoneName,
        'timeZoneOffsetMinutes': timeZoneOffsetMinutes,
        'steps': steps,
        'stepGoal': stepGoal,
        'activeEnergyKcal': activeEnergyKcal,
        'activeEnergyGoalKcal': activeEnergyGoalKcal,
        'exerciseMinutes': exerciseMinutes,
        'exerciseGoalMinutes': exerciseGoalMinutes,
        'standHours': standHours,
        'standGoalHours': standGoalHours,
        'fieldSources': <String, String>{
          for (final MapEntry<DailyActivityField, ActivityFieldSource> entry
              in fieldSources.entries)
            entry.key.id: entry.value.id,
        },
        'syncedAt': syncedAt.toIso8601String(),
      };
}

int? _nonNegativeInt(int? value) {
  if (value == null) return null;
  return value < 0 ? 0 : value;
}

double? _nonNegativeDouble(double? value) {
  if (value == null) return null;
  return value < 0 ? 0 : value;
}

String _validatedLocalDate(String value) {
  final RegExpMatch? match =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw const FormatException('本地日期必须使用 yyyy-MM-dd 格式');
  }
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null ||
      parsed.year.toString().padLeft(4, '0') != match.group(1) ||
      parsed.month.toString().padLeft(2, '0') != match.group(2) ||
      parsed.day.toString().padLeft(2, '0') != match.group(3)) {
    throw const FormatException('本地日期不是有效的自然日');
  }
  return value;
}

DateTime _requiredDateTime(Object? value, String fieldLabel) {
  final DateTime? parsed = value is DateTime
      ? value
      : DateTime.tryParse(value is String ? value : '');
  if (parsed == null) {
    throw FormatException('$fieldLabel 无效');
  }
  return parsed.toUtc();
}
