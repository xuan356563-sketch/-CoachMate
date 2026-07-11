enum BodyDataQualitySeverity {
  info,
  warning,
  risk,
}

extension BodyDataQualitySeverityLabel on BodyDataQualitySeverity {
  String get label {
    switch (this) {
      case BodyDataQualitySeverity.info:
        return '提示';
      case BodyDataQualitySeverity.warning:
        return '需确认';
      case BodyDataQualitySeverity.risk:
        return '高风险';
    }
  }
}

class BodyDataQualityIssue {
  final String title;
  final String description;
  final BodyDataQualitySeverity severity;

  const BodyDataQualityIssue({
    required this.title,
    required this.description,
    required this.severity,
  });
}

class BodyDataQualityReport {
  final int recordCount;
  final int coveredDays;
  final int sourceCount;
  final double qualityScore;
  final String coverageLabel;
  final String sourceLabel;
  final String revisionPolicyLabel;
  final List<BodyDataQualityIssue> issues;

  const BodyDataQualityReport({
    required this.recordCount,
    required this.coveredDays,
    required this.sourceCount,
    required this.qualityScore,
    required this.coverageLabel,
    required this.sourceLabel,
    required this.revisionPolicyLabel,
    required this.issues,
  });

  String get qualityScoreLabel {
    return '${(qualityScore * 100).round()}%';
  }

  String get statusLabel {
    if (issues.any(
      (BodyDataQualityIssue issue) =>
          issue.severity == BodyDataQualitySeverity.risk,
    )) {
      return '需复核';
    }
    if (issues.any(
      (BodyDataQualityIssue issue) =>
          issue.severity == BodyDataQualitySeverity.warning,
    )) {
      return '可用但需确认';
    }
    return '可用';
  }
}
