import 'workout_day.dart';

enum WorkStressLevel {
  normal,
  high,
  extreme,
}

extension WorkStressLevelLabel on WorkStressLevel {
  String get jsonValue {
    switch (this) {
      case WorkStressLevel.normal:
        return 'normal';
      case WorkStressLevel.high:
        return 'high';
      case WorkStressLevel.extreme:
        return 'extreme';
    }
  }

  String get label {
    switch (this) {
      case WorkStressLevel.normal:
        return '正常';
      case WorkStressLevel.high:
        return '高压';
      case WorkStressLevel.extreme:
        return '爆表';
    }
  }
}

WorkStressLevel workStressLevelFromJson(String? value) {
  switch (value) {
    case 'high':
      return WorkStressLevel.high;
    case 'extreme':
      return WorkStressLevel.extreme;
    case 'normal':
    default:
      return WorkStressLevel.normal;
  }
}

enum TrainingEnvironment {
  gym,
  home,
  outdoor,
  noEquipment,
}

extension TrainingEnvironmentLabel on TrainingEnvironment {
  String get jsonValue {
    switch (this) {
      case TrainingEnvironment.gym:
        return 'gym';
      case TrainingEnvironment.home:
        return 'home';
      case TrainingEnvironment.outdoor:
        return 'outdoor';
      case TrainingEnvironment.noEquipment:
        return 'no_equipment';
    }
  }

  String get label {
    switch (this) {
      case TrainingEnvironment.gym:
        return '健身房';
      case TrainingEnvironment.home:
        return '家里';
      case TrainingEnvironment.outdoor:
        return '户外';
      case TrainingEnvironment.noEquipment:
        return '无器械';
    }
  }
}

TrainingEnvironment trainingEnvironmentFromJson(String? value) {
  switch (value) {
    case 'home':
      return TrainingEnvironment.home;
    case 'outdoor':
      return TrainingEnvironment.outdoor;
    case 'no_equipment':
      return TrainingEnvironment.noEquipment;
    case 'gym':
    default:
      return TrainingEnvironment.gym;
  }
}

enum WeatherCondition {
  good,
  hot,
  rain,
  poorAir,
}

extension WeatherConditionLabel on WeatherCondition {
  String get jsonValue {
    switch (this) {
      case WeatherCondition.good:
        return 'good';
      case WeatherCondition.hot:
        return 'hot';
      case WeatherCondition.rain:
        return 'rain';
      case WeatherCondition.poorAir:
        return 'poor_air';
    }
  }

  String get label {
    switch (this) {
      case WeatherCondition.good:
        return '适合';
      case WeatherCondition.hot:
        return '高温';
      case WeatherCondition.rain:
        return '下雨';
      case WeatherCondition.poorAir:
        return '空气差';
    }
  }
}

WeatherCondition weatherConditionFromJson(String? value) {
  switch (value) {
    case 'hot':
      return WeatherCondition.hot;
    case 'rain':
      return WeatherCondition.rain;
    case 'poor_air':
      return WeatherCondition.poorAir;
    case 'good':
    default:
      return WeatherCondition.good;
  }
}

class AppliedDailyDecisionFact {
  AppliedDailyDecisionFact({
    required String localDate,
    required this.decisionType,
    required DateTime confirmedAt,
  })  : localDate = _validatedLocalDate(localDate),
        confirmedAt = confirmedAt.toUtc();

  factory AppliedDailyDecisionFact.fromJson(Map<String, dynamic> json) {
    final TrainingDecisionType? decisionType =
        _trainingDecisionTypeFromJson(json['decisionType']);
    if (decisionType == null) {
      throw const FormatException('每日调整决策类型无效');
    }
    final DateTime? confirmedAt =
        DateTime.tryParse(json['confirmedAt'] as String? ?? '');
    if (confirmedAt == null) {
      throw const FormatException('每日调整确认时间无效');
    }
    return AppliedDailyDecisionFact(
      localDate: json['localDate'] as String? ?? '',
      decisionType: decisionType,
      confirmedAt: confirmedAt,
    );
  }

  final String localDate;
  final TrainingDecisionType decisionType;
  final DateTime confirmedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'localDate': localDate,
        'decisionType': _trainingDecisionTypeJsonValue(decisionType),
        'confirmedAt': confirmedAt.toIso8601String(),
      };
}

class DailyAdjustmentContext {
  final int availableMinutes;
  final WorkStressLevel workStress;
  final TrainingEnvironment environment;
  final WeatherCondition weather;
  final String statusMessage;
  final List<AppliedDailyDecisionFact> appliedDecisions;

  const DailyAdjustmentContext({
    required this.availableMinutes,
    required this.workStress,
    required this.environment,
    required this.weather,
    required this.statusMessage,
    this.appliedDecisions = const <AppliedDailyDecisionFact>[],
  });

  factory DailyAdjustmentContext.defaults({
    required int availableMinutes,
  }) {
    return DailyAdjustmentContext(
      availableMinutes: availableMinutes,
      workStress: WorkStressLevel.normal,
      environment: TrainingEnvironment.gym,
      weather: WeatherCondition.good,
      statusMessage: '尚未应用今日现实约束调整。',
      appliedDecisions: const <AppliedDailyDecisionFact>[],
    );
  }

  factory DailyAdjustmentContext.fromJson(Map<String, dynamic> json) {
    return DailyAdjustmentContext(
      availableMinutes: (json['availableMinutes'] as num?)?.toInt() ?? 45,
      workStress: workStressLevelFromJson(json['workStress'] as String?),
      environment: trainingEnvironmentFromJson(json['environment'] as String?),
      weather: weatherConditionFromJson(json['weather'] as String?),
      statusMessage: json['statusMessage'] as String? ?? '尚未应用今日现实约束调整。',
      appliedDecisions: _appliedDecisionFactsFromJson(json['appliedDecisions']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'availableMinutes': availableMinutes,
      'workStress': workStress.jsonValue,
      'environment': environment.jsonValue,
      'weather': weather.jsonValue,
      'statusMessage': statusMessage,
      'appliedDecisions': appliedDecisions
          .map((AppliedDailyDecisionFact fact) => fact.toJson())
          .toList(growable: false),
    };
  }
}

class DailyAdjustmentDecision {
  final TrainingDecisionType decisionType;
  final int availableMinutes;
  final WorkStressLevel workStress;
  final TrainingEnvironment environment;
  final WeatherCondition weather;
  final String decisionLabel;
  final String reason;
  final int adjustedMinutes;
  final String planChangeSummary;
  final List<String> constraintBadges;
  final List<String> adjustments;

  const DailyAdjustmentDecision({
    required this.decisionType,
    required this.availableMinutes,
    required this.workStress,
    required this.environment,
    required this.weather,
    required this.decisionLabel,
    required this.reason,
    required this.adjustedMinutes,
    required this.planChangeSummary,
    required this.constraintBadges,
    required this.adjustments,
  });

  String get decisionTypeLabel {
    return decisionType.label;
  }
}

List<AppliedDailyDecisionFact> _appliedDecisionFactsFromJson(Object? value) {
  if (value is! List) return const <AppliedDailyDecisionFact>[];
  final List<AppliedDailyDecisionFact> facts = <AppliedDailyDecisionFact>[];
  for (final Object? item in value) {
    if (item is! Map) continue;
    try {
      facts.add(
        AppliedDailyDecisionFact.fromJson(
          Map<String, dynamic>.from(item),
        ),
      );
    } on FormatException {
      continue;
    } on TypeError {
      continue;
    }
  }
  return List<AppliedDailyDecisionFact>.unmodifiable(facts);
}

String _trainingDecisionTypeJsonValue(TrainingDecisionType value) {
  return switch (value) {
    TrainingDecisionType.normal => 'normal',
    TrainingDecisionType.deload => 'deload',
    TrainingDecisionType.recovery => 'recovery',
    TrainingDecisionType.technique => 'technique',
    TrainingDecisionType.rest => 'rest',
  };
}

TrainingDecisionType? _trainingDecisionTypeFromJson(Object? value) {
  return switch (value) {
    'normal' => TrainingDecisionType.normal,
    'deload' => TrainingDecisionType.deload,
    'recovery' => TrainingDecisionType.recovery,
    'technique' => TrainingDecisionType.technique,
    'rest' => TrainingDecisionType.rest,
    _ => null,
  };
}

String _validatedLocalDate(String value) {
  final RegExpMatch? match =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  final DateTime? parsed = DateTime.tryParse(value);
  if (match == null ||
      parsed == null ||
      parsed.year.toString().padLeft(4, '0') != match.group(1) ||
      parsed.month.toString().padLeft(2, '0') != match.group(2) ||
      parsed.day.toString().padLeft(2, '0') != match.group(3)) {
    throw const FormatException('每日调整本地日期必须是有效的 yyyy-MM-dd 自然日');
  }
  return value;
}
