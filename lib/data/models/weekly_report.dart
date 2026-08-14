import 'weekly_psych_check_in.dart';
import 'exercise_training_profile.dart';

class TrainingDimensionExposure {
  const TrainingDimensionExposure({
    required this.dimension,
    required this.plannedSessions,
    required this.completedSessions,
  });

  final TrainingDimension dimension;
  final int plannedSessions;
  final int completedSessions;

  factory TrainingDimensionExposure.fromJson(Map<String, dynamic> json) {
    return TrainingDimensionExposure(
      dimension: trainingDimensionFromJson(json['dimension'] as String?) ??
          TrainingDimension.stability,
      plannedSessions: (json['plannedSessions'] as num?)?.toInt() ?? 0,
      completedSessions: (json['completedSessions'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'dimension': dimension.jsonValue,
        'plannedSessions': plannedSessions,
        'completedSessions': completedSessions,
      };
}

class WeeklyReport {
  final String id;
  final String weekLabel;
  final DateTime generatedAt;
  final int completedWorkouts;
  final int plannedWorkouts;
  final double completionRate;
  final String loadTrendLabel;
  final String decisionReview;
  final String recoverySummary;
  final List<String> highlights;
  final List<String> nextWeekFocus;
  final String goalSummary;
  final String realityObservation;
  final List<WeeklyReportOption> options;
  final String reflectionQuestion;
  final String? selectedOptionId;
  final WeeklyPsychCheckIn? psychCheckIn;
  final PsychRiskLevel psychRiskLevel;
  final List<TrainingDimensionExposure> dimensionExposure;

  const WeeklyReport({
    required this.id,
    required this.weekLabel,
    required this.generatedAt,
    required this.completedWorkouts,
    required this.plannedWorkouts,
    required this.completionRate,
    required this.loadTrendLabel,
    required this.decisionReview,
    required this.recoverySummary,
    required this.highlights,
    required this.nextWeekFocus,
    this.goalSummary = '',
    this.realityObservation = '',
    this.options = const <WeeklyReportOption>[],
    this.reflectionQuestion = '',
    this.selectedOptionId,
    this.psychCheckIn,
    this.psychRiskLevel = PsychRiskLevel.normal,
    this.dimensionExposure = const <TrainingDimensionExposure>[],
  });

  factory WeeklyReport.fromJson(Map<String, dynamic> json) {
    return WeeklyReport(
      id: json['id'] as String? ?? '',
      weekLabel: json['weekLabel'] as String? ?? '',
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      completedWorkouts: (json['completedWorkouts'] as num?)?.toInt() ?? 0,
      plannedWorkouts: (json['plannedWorkouts'] as num?)?.toInt() ?? 0,
      completionRate: (json['completionRate'] as num?)?.toDouble() ?? 0,
      loadTrendLabel: json['loadTrendLabel'] as String? ?? '',
      decisionReview: json['decisionReview'] as String? ?? '',
      recoverySummary: json['recoverySummary'] as String? ?? '',
      highlights: (json['highlights'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      nextWeekFocus: (json['nextWeekFocus'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      goalSummary: json['goalSummary'] as String? ?? '',
      realityObservation: json['realityObservation'] as String? ?? '',
      options: (json['options'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(WeeklyReportOption.fromJson)
          .toList(growable: false),
      reflectionQuestion: json['reflectionQuestion'] as String? ?? '',
      selectedOptionId: json['selectedOptionId'] as String?,
      psychCheckIn: json['psychCheckIn'] is Map<String, dynamic>
          ? WeeklyPsychCheckIn.fromJson(
              json['psychCheckIn'] as Map<String, dynamic>,
            )
          : null,
      psychRiskLevel:
          PsychRiskLevel.fromJson(json['psychRiskLevel'] as String?),
      dimensionExposure:
          (json['dimensionExposure'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(TrainingDimensionExposure.fromJson)
              .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'weekLabel': weekLabel,
      'generatedAt': generatedAt.toIso8601String(),
      'completedWorkouts': completedWorkouts,
      'plannedWorkouts': plannedWorkouts,
      'completionRate': completionRate,
      'loadTrendLabel': loadTrendLabel,
      'decisionReview': decisionReview,
      'recoverySummary': recoverySummary,
      'highlights': highlights,
      'nextWeekFocus': nextWeekFocus,
      'goalSummary': goalSummary,
      'realityObservation': realityObservation,
      'options': options
          .map((WeeklyReportOption item) => item.toJson())
          .toList(growable: false),
      'selectedOptionId': selectedOptionId,
      'reflectionQuestion': reflectionQuestion,
      'psychCheckIn': psychCheckIn?.toJson(),
      'psychRiskLevel': psychRiskLevel.jsonValue,
      'dimensionExposure': dimensionExposure
          .map((TrainingDimensionExposure item) => item.toJson())
          .toList(growable: false),
    };
  }

  String get completionRateLabel {
    return '${(completionRate * 100).round()}%';
  }

  String get generatedDateLabel {
    return '${generatedAt.year}-${generatedAt.month.toString().padLeft(2, '0')}-${generatedAt.day.toString().padLeft(2, '0')}';
  }

  WeeklyReport copyWith({
    String? selectedOptionId,
    Object? psychCheckIn = _unchangedWeeklyValue,
  }) {
    return WeeklyReport(
      id: id,
      weekLabel: weekLabel,
      generatedAt: generatedAt,
      completedWorkouts: completedWorkouts,
      plannedWorkouts: plannedWorkouts,
      completionRate: completionRate,
      loadTrendLabel: loadTrendLabel,
      decisionReview: decisionReview,
      recoverySummary: recoverySummary,
      highlights: highlights,
      nextWeekFocus: nextWeekFocus,
      goalSummary: goalSummary,
      realityObservation: realityObservation,
      options: options,
      reflectionQuestion: reflectionQuestion,
      selectedOptionId: selectedOptionId ?? this.selectedOptionId,
      psychCheckIn: identical(psychCheckIn, _unchangedWeeklyValue)
          ? this.psychCheckIn
          : psychCheckIn as WeeklyPsychCheckIn?,
      psychRiskLevel: psychRiskLevel,
      dimensionExposure: dimensionExposure,
    );
  }

  String get markdown {
    final StringBuffer buffer = StringBuffer()
      ..writeln('## TrainFlow AI 周报')
      ..writeln()
      ..writeln('- 周期：$weekLabel')
      ..writeln('- 生成日期：$generatedDateLabel')
      ..writeln(
          '- 完成率：$completedWorkouts/$plannedWorkouts（$completionRateLabel）')
      ..writeln('- 负荷趋势：$loadTrendLabel')
      ..writeln('- 决策回顾：$decisionReview')
      ..writeln('- 恢复建议：$recoverySummary')
      ..writeln()
      ..writeln('### 目标')
      ..writeln(goalSummary.isEmpty ? '本周未设置过程目标。' : goalSummary)
      ..writeln()
      ..writeln('### 现状')
      ..writeln(
        realityObservation.isEmpty ? '当前数据不足，等待训练记录。' : realityObservation,
      )
      ..writeln()
      ..writeln('### 五维训练暴露');

    if (dimensionExposure.isEmpty) {
      buffer.writeln('- 数据积累中');
    } else {
      for (final TrainingDimensionExposure exposure in dimensionExposure) {
        buffer.writeln(
          '- ${exposure.dimension.label}：${exposure.completedSessions}/${exposure.plannedSessions} 次',
        );
      }
    }

    buffer
      ..writeln()
      ..writeln('### 本周亮点');

    for (final String item in highlights) {
      buffer.writeln('- $item');
    }

    buffer
      ..writeln()
      ..writeln('### 下周重点');

    for (final String item in nextWeekFocus) {
      buffer.writeln('- $item');
    }
    if (options.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('### 可选方向');
      for (final WeeklyReportOption option in options) {
        buffer.writeln('- ${option.label}');
      }
    }
    if (reflectionQuestion.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('### 复盘问题')
        ..writeln(reflectionQuestion);
    }

    return buffer.toString().trimRight();
  }
}

const Object _unchangedWeeklyValue = Object();
