enum TrainingRuleAuditSeverity {
  pass,
  warning,
  fail,
}

extension TrainingRuleAuditSeverityLabel on TrainingRuleAuditSeverity {
  String get label {
    switch (this) {
      case TrainingRuleAuditSeverity.pass:
        return '通过';
      case TrainingRuleAuditSeverity.warning:
        return '提醒';
      case TrainingRuleAuditSeverity.fail:
        return '阻断';
    }
  }
}

class TrainingRuleAuditItem {
  final String title;
  final String description;
  final TrainingRuleAuditSeverity severity;

  const TrainingRuleAuditItem({
    required this.title,
    required this.description,
    required this.severity,
  });
}

class TrainingRuleAuditReport {
  final String planId;
  final List<TrainingRuleAuditItem> items;
  final int checkedWorkoutCount;
  final int citationCount;
  final int runningModuleCount;
  final int maxEstimatedMinutes;

  const TrainingRuleAuditReport({
    required this.planId,
    required this.items,
    required this.checkedWorkoutCount,
    required this.citationCount,
    required this.runningModuleCount,
    required this.maxEstimatedMinutes,
  });

  int get passCount {
    return items
        .where(
          (TrainingRuleAuditItem item) =>
              item.severity == TrainingRuleAuditSeverity.pass,
        )
        .length;
  }

  int get warningCount {
    return items
        .where(
          (TrainingRuleAuditItem item) =>
              item.severity == TrainingRuleAuditSeverity.warning,
        )
        .length;
  }

  int get failCount {
    return items
        .where(
          (TrainingRuleAuditItem item) =>
              item.severity == TrainingRuleAuditSeverity.fail,
        )
        .length;
  }

  String get statusLabel {
    if (failCount > 0) {
      return '需修复';
    }
    if (warningCount > 0) {
      return '有提醒';
    }
    return '可落库';
  }
}
