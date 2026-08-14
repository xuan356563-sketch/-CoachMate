import 'dart:convert';

enum RhythmFactor {
  sleep('睡眠规律'),
  activity('日常活动'),
  training('主动训练'),
  restingHeartRate('静息心率');

  const RhythmFactor(this.label);

  final String label;
}

class RhythmTimedValue {
  const RhythmTimedValue({
    required this.dayOffset,
    required this.value,
  });

  final double dayOffset;
  final double value;
}

class RhythmFactorResult {
  const RhythmFactorResult({
    required this.factor,
    required this.contribution,
    required this.isSufficient,
    required this.summary,
  });

  final RhythmFactor factor;
  final double contribution;
  final bool isSufficient;
  final String summary;

  String get statusLabel => isSufficient ? contributionLabel : '暂时没影响';

  String get contributionLabel {
    if (contribution.abs() < 0.0001) return '维持稳定';
    final String sign = contribution > 0 ? '+' : '';
    return '让节奏${contribution > 0 ? '快' : '慢'} '
        '$sign${contribution.toStringAsFixed(2)}×';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'factor': factor.name,
        'contribution': contribution,
        'isSufficient': isSufficient,
        'summary': summary,
      };

  factory RhythmFactorResult.fromJson(Map<String, dynamic> json) {
    final RhythmFactor factor = RhythmFactor.values.firstWhere(
      (RhythmFactor item) => item.name == json['factor'],
      orElse: () => RhythmFactor.sleep,
    );
    return RhythmFactorResult(
      factor: factor,
      contribution: (json['contribution'] as num?)?.toDouble() ?? 0,
      isSufficient: json['isSufficient'] == true,
      summary: json['summary'] as String? ?? '暂无数据',
    );
  }
}

class RhythmInput {
  const RhythmInput({
    required this.calculatedOn,
    this.birthDate,
    this.averageSleepHours,
    this.sleepSampleDays = 0,
    this.averageDailySteps,
    this.activitySampleDays = 0,
    this.trainingDays,
    this.strengthMinutes,
    this.noTrainingDays = 0,
    this.restingHeartRateSamples = const <RhythmTimedValue>[],
  });

  final DateTime calculatedOn;
  final DateTime? birthDate;
  final double? averageSleepHours;
  final int sleepSampleDays;
  final double? averageDailySteps;
  final int activitySampleDays;
  final int? trainingDays;
  final int? strengthMinutes;
  final int noTrainingDays;
  final List<RhythmTimedValue> restingHeartRateSamples;
}

class RhythmCalculation {
  const RhythmCalculation({
    required this.speed,
    required this.actualAge,
    required this.stateAge,
    required this.factors,
    required this.minimumSufficientFactors,
  });

  final double speed;
  final double? actualAge;
  final double? stateAge;
  final Map<RhythmFactor, RhythmFactorResult> factors;
  final int minimumSufficientFactors;

  int get sufficientFactorCount =>
      factors.values.where((RhythmFactorResult item) => item.isSufficient).length;

  bool get hasBaseline => sufficientFactorCount >= minimumSufficientFactors;

  String get paceLabel {
    if (speed < 0.95) return '近期偏慢';
    if (speed > 1.05) return '近期偏快';
    return '近期稳定';
  }
}

class RhythmSnapshot {
  const RhythmSnapshot({
    required this.id,
    required this.athleteProfileId,
    required this.weekStart,
    required this.timeZoneName,
    required this.utcOffsetMinutes,
    required this.speed,
    required this.actualAge,
    required this.stateAge,
    required this.factors,
    required this.configVersion,
    required this.createdAt,
  });

  final String id;
  final String athleteProfileId;
  final DateTime weekStart;
  final String timeZoneName;
  final int utcOffsetMinutes;
  final double speed;
  final double? actualAge;
  final double? stateAge;
  final Map<RhythmFactor, RhythmFactorResult> factors;
  final String configVersion;
  final DateTime createdAt;

  int get sufficientFactorCount =>
      factors.values.where((RhythmFactorResult item) => item.isSufficient).length;

  bool get hasBaseline => sufficientFactorCount >= 2;

  String get paceLabel {
    if (speed < 0.95) return '近期偏慢';
    if (speed > 1.05) return '近期偏快';
    return '近期稳定';
  }

  Map<String, Object?> toDatabaseRow() => <String, Object?>{
        'id': id,
        'athlete_profile_id': athleteProfileId,
        'week_start': _dateKey(weekStart),
        'time_zone_name': timeZoneName,
        'utc_offset_minutes': utcOffsetMinutes,
        'rhythm_speed': speed,
        'actual_age': actualAge,
        'state_age': stateAge,
        'factor_json': jsonEncode(<String, Object?>{
          for (final MapEntry<RhythmFactor, RhythmFactorResult> entry
              in factors.entries)
            entry.key.name: entry.value.toJson(),
        }),
        'config_version': configVersion,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory RhythmSnapshot.fromDatabaseRow(Map<String, Object?> row) {
    final Object? rawFactors = row['factor_json'];
    final Map<String, dynamic> factorJson = rawFactors is String
        ? Map<String, dynamic>.from(jsonDecode(rawFactors) as Map)
        : <String, dynamic>{};
    return RhythmSnapshot(
      id: row['id'] as String? ?? '',
      athleteProfileId: row['athlete_profile_id'] as String? ?? '',
      weekStart: DateTime.parse(row['week_start']! as String),
      timeZoneName: row['time_zone_name'] as String? ?? '',
      utcOffsetMinutes: (row['utc_offset_minutes'] as num?)?.toInt() ?? 0,
      speed: (row['rhythm_speed'] as num?)?.toDouble() ?? 1,
      actualAge: (row['actual_age'] as num?)?.toDouble(),
      stateAge: (row['state_age'] as num?)?.toDouble(),
      factors: <RhythmFactor, RhythmFactorResult>{
        for (final RhythmFactor factor in RhythmFactor.values)
          factor: RhythmFactorResult.fromJson(
            Map<String, dynamic>.from(
              factorJson[factor.name] as Map? ?? <String, dynamic>{},
            ),
          ),
      },
      configVersion: row['config_version'] as String? ?? 'unknown',
      createdAt: DateTime.parse(row['created_at']! as String).toLocal(),
    );
  }
}

enum MealType {
  breakfast('早餐'),
  lunch('午餐'),
  dinner('晚餐'),
  snack('加餐');

  const MealType(this.label);

  final String label;
}

class MealRecord {
  const MealRecord({
    required this.id,
    required this.athleteProfileId,
    required this.localDate,
    required this.mealType,
    required this.summary,
    required this.createdAt,
    this.revokedAt,
  });

  final String id;
  final String athleteProfileId;
  final DateTime localDate;
  final MealType mealType;
  final String summary;
  final DateTime createdAt;
  final DateTime? revokedAt;

  Map<String, Object?> toDatabaseRow() => <String, Object?>{
        'id': id,
        'athlete_profile_id': athleteProfileId,
        'local_date': _dateKey(localDate),
        'meal_type': mealType.name,
        'summary': summary,
        'created_at': createdAt.toUtc().toIso8601String(),
        'revoked_at': revokedAt?.toUtc().toIso8601String(),
      };

  factory MealRecord.fromDatabaseRow(Map<String, Object?> row) => MealRecord(
        id: row['id'] as String? ?? '',
        athleteProfileId: row['athlete_profile_id'] as String? ?? '',
        localDate: DateTime.parse(row['local_date']! as String),
        mealType: MealType.values.firstWhere(
          (MealType item) => item.name == row['meal_type'],
          orElse: () => MealType.snack,
        ),
        summary: row['summary'] as String? ?? '',
        createdAt: DateTime.parse(row['created_at']! as String).toLocal(),
        revokedAt: DateTime.tryParse(row['revoked_at'] as String? ?? ''),
      );
}

class ReviewEligibilityInput {
  const ReviewEligibilityInput({
    required this.windowEnd,
    required this.mealDates,
    required this.weightDates,
    required this.trainingDates,
  });

  final DateTime windowEnd;
  final List<DateTime> mealDates;
  final List<DateTime> weightDates;
  final List<DateTime> trainingDates;
}

class ReviewUnlockStatus {
  const ReviewUnlockStatus({
    required this.isUnlocked,
    required this.dietDays,
    required this.weightRecords,
    required this.weightSpanDays,
    required this.trainingDays,
    required this.gaps,
  });

  final bool isUnlocked;
  final int dietDays;
  final int weightRecords;
  final int weightSpanDays;
  final int trainingDays;
  final List<String> gaps;
}

String _dateKey(DateTime value) {
  final DateTime local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
