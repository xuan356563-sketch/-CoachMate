class StarterGraduationReport {
  final String id;
  final DateTime generatedAt;
  final int completedDays;
  final int totalDays;
  final double completionRate;
  final String goalLabel;
  final String abilitySummary;
  final String heartRateTrendLabel;
  final String heartRateTrendDetail;
  final String subjectiveTrendLabel;
  final String subjectiveTrendDetail;
  final String readinessLabel;
  final int? readinessScore;
  final String recommendedNextPlan;
  final String transitionSummary;
  final bool readyForFormalPlan;

  const StarterGraduationReport({
    required this.id,
    required this.generatedAt,
    required this.completedDays,
    required this.totalDays,
    required this.completionRate,
    required this.goalLabel,
    required this.abilitySummary,
    required this.heartRateTrendLabel,
    required this.heartRateTrendDetail,
    required this.subjectiveTrendLabel,
    required this.subjectiveTrendDetail,
    required this.readinessLabel,
    required this.readinessScore,
    required this.recommendedNextPlan,
    required this.transitionSummary,
    required this.readyForFormalPlan,
  });

  String get completionRateLabel {
    return '${(completionRate * 100).round()}%';
  }

  String get generatedDateLabel {
    return '${generatedAt.year}-${generatedAt.month.toString().padLeft(2, '0')}-${generatedAt.day.toString().padLeft(2, '0')}';
  }
}
