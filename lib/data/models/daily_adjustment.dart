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

class DailyAdjustmentContext {
  final int availableMinutes;
  final WorkStressLevel workStress;
  final TrainingEnvironment environment;
  final WeatherCondition weather;
  final String statusMessage;

  const DailyAdjustmentContext({
    required this.availableMinutes,
    required this.workStress,
    required this.environment,
    required this.weather,
    required this.statusMessage,
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
    );
  }

  factory DailyAdjustmentContext.fromJson(Map<String, dynamic> json) {
    return DailyAdjustmentContext(
      availableMinutes: (json['availableMinutes'] as num?)?.toInt() ?? 45,
      workStress: workStressLevelFromJson(json['workStress'] as String?),
      environment: trainingEnvironmentFromJson(json['environment'] as String?),
      weather: weatherConditionFromJson(json['weather'] as String?),
      statusMessage: json['statusMessage'] as String? ?? '尚未应用今日现实约束调整。',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'availableMinutes': availableMinutes,
      'workStress': workStress.jsonValue,
      'environment': environment.jsonValue,
      'weather': weather.jsonValue,
      'statusMessage': statusMessage,
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
