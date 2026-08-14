enum CoachFeedbackScenario {
  routineCompletion,
  fatigueWarning,
  returnAfterBreak,
  insufficientData,
}

/// 一条可审计的教练反馈。
///
/// 动态反馈必须同时保留原理、数据依赖和兜底原因，避免数据不足时
/// 静默退化成通用激励文案。
class CoachFeedback {
  const CoachFeedback({
    required this.scenario,
    required this.text,
    required this.principleCodes,
    required this.dataDependencies,
    this.fallbackReason,
  });

  final CoachFeedbackScenario scenario;
  final String text;
  final List<String> principleCodes;
  final List<String> dataDependencies;
  final String? fallbackReason;
}
