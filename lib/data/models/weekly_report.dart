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
    };
  }

  String get completionRateLabel {
    return '${(completionRate * 100).round()}%';
  }

  String get generatedDateLabel {
    return '${generatedAt.year}-${generatedAt.month.toString().padLeft(2, '0')}-${generatedAt.day.toString().padLeft(2, '0')}';
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

    return buffer.toString().trimRight();
  }
}
