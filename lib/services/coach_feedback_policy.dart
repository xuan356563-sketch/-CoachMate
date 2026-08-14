import '../data/models/coach_feedback.dart';
import '../data/models/training_log.dart';

/// TrainMate 用户可见教练反馈的最小安全策略。
///
/// 这里只输出基于事实的单一观察，不负责诊断，也不替代训练安全规则。
class CoachFeedbackPolicy {
  const CoachFeedbackPolicy();

  static const List<String> _forbiddenCopy = <String>[
    '太棒',
    '恭喜',
    '厉害',
    '加油',
    '别放弃',
    '坚持住',
    '即将失去',
    '即将中断',
  ];

  CoachFeedback buildTrainingReceipt({
    required TrainingLog current,
    required String workoutLabel,
    bool isReturnAfterBreak = false,
  }) {
    final String normalizedLabel = workoutLabel.trim();
    if (isReturnAfterBreak && normalizedLabel.isNotEmpty) {
      return CoachFeedback(
        scenario: CoachFeedbackScenario.returnAfterBreak,
        text: '今天的$normalizedLabel已记录。下一次可以先从短时长开始。',
        principleCodes: const <String>['P6', 'P9', 'P11'],
        dataDependencies: const <String>[
          'workout_label',
          'return_after_break',
        ],
      );
    }

    final bool fatigueRisk = current.rpe >= 9 ||
        current.fatigueLevel >= 8 ||
        current.sessionFeel == SessionFeel.veryPoor;
    if (fatigueRisk) {
      final List<String> observations = <String>[];
      if (current.rpe > 0) observations.add('RPE ${current.rpe}');
      if (current.fatigueLevel > 0) {
        observations.add('疲劳 ${current.fatigueLevel}/10');
      }
      final String prefix = observations.isEmpty
          ? '本次主观反馈提示疲劳偏高'
          : '本次记录为${observations.join('、')}';
      return CoachFeedback(
        scenario: CoachFeedbackScenario.fatigueWarning,
        text: '$prefix。建议下一次改为恢复或低强度训练。',
        principleCodes: const <String>['P2', 'P4', 'P7'],
        dataDependencies: const <String>[
          'rpe',
          'fatigue_level',
          'session_feel',
        ],
      );
    }

    if (normalizedLabel.isEmpty ||
        (current.normalizedCompletionPercentage == 0 && current.rpe <= 0)) {
      return const CoachFeedback(
        scenario: CoachFeedbackScenario.insufficientData,
        text: '本次训练记录已保存。',
        principleCodes: <String>['P2', 'P4'],
        dataDependencies: <String>[
          'workout_label',
          'completion_percentage',
          'rpe',
        ],
        fallbackReason: '缺少训练名称或有效完成数据，不生成个性化评价。',
      );
    }

    final String completion = current.normalizedCompletionPercentage >= 100
        ? '按计划完成$normalizedLabel'
        : '本次$normalizedLabel记录为'
            '${current.normalizedCompletionPercentage}% 完成';
    final String intensity = current.rpe > 0 ? '主观强度 RPE ${current.rpe}。' : '';
    return CoachFeedback(
      scenario: CoachFeedbackScenario.routineCompletion,
      text: '$completion。$intensity',
      principleCodes: const <String>['P2', 'P4', 'P8'],
      dataDependencies: const <String>[
        'workout_label',
        'completion_percentage',
        'rpe',
      ],
    );
  }

  static bool containsForbiddenCopy(String text) {
    return _forbiddenCopy.any(text.contains);
  }
}
