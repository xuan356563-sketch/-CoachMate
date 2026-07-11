class DailyCheckInPrompt {
  final String label;
  final String value;
  final String sourceLabel;
  final bool required;
  final int priorityRank;
  final String priorityReason;

  const DailyCheckInPrompt({
    required this.label,
    required this.value,
    required this.sourceLabel,
    required this.required,
    required this.priorityRank,
    required this.priorityReason,
  });
}

class DailyCheckInSummary {
  final String modeLabel;
  final int requiredQuestionCount;
  final String confidenceLabel;
  final String explanation;
  final String sortExplanation;
  final bool canUseYesterday;
  final List<DailyCheckInPrompt> prompts;

  const DailyCheckInSummary({
    required this.modeLabel,
    required this.requiredQuestionCount,
    required this.confidenceLabel,
    required this.explanation,
    required this.sortExplanation,
    required this.canUseYesterday,
    required this.prompts,
  });

  String get questionCountLabel {
    return '$requiredQuestionCount 项';
  }
}
