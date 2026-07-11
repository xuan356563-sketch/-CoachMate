enum BodyMetricGoalType {
  weight,
  restingHeartRate,
  hrv,
  consistency,
}

extension BodyMetricGoalTypeLabel on BodyMetricGoalType {
  String get label {
    switch (this) {
      case BodyMetricGoalType.weight:
        return '体重趋势';
      case BodyMetricGoalType.restingHeartRate:
        return '静息心率';
      case BodyMetricGoalType.hrv:
        return 'HRV 恢复';
      case BodyMetricGoalType.consistency:
        return '记录连续性';
    }
  }
}

class BodyMetricGoal {
  final BodyMetricGoalType type;
  final String title;
  final String currentLabel;
  final String targetLabel;
  final double progress;
  final String milestoneLabel;
  final String guidance;
  final bool achieved;
  final bool needsProtection;

  const BodyMetricGoal({
    required this.type,
    required this.title,
    required this.currentLabel,
    required this.targetLabel,
    required this.progress,
    required this.milestoneLabel,
    required this.guidance,
    required this.achieved,
    required this.needsProtection,
  });
}

class BodyMetricGoalReport {
  final List<BodyMetricGoal> goals;
  final String summary;
  final String protectionMessage;

  const BodyMetricGoalReport({
    required this.goals,
    required this.summary,
    required this.protectionMessage,
  });

  int get achievedCount {
    return goals.where((BodyMetricGoal goal) => goal.achieved).length;
  }

  bool get hasProtectionWarning {
    return goals.any((BodyMetricGoal goal) => goal.needsProtection);
  }
}
