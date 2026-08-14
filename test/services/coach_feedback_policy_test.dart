import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/coach_feedback.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/services/coach_feedback_policy.dart';

void main() {
  const CoachFeedbackPolicy policy = CoachFeedbackPolicy();

  test('常规完成反馈只描述过程事实，不使用空泛夸奖', () {
    final CoachFeedback feedback = policy.buildTrainingReceipt(
      current: _log(
        completionPercentage: 100,
        rpe: 6,
        sessionFeel: SessionFeel.good,
      ),
      workoutLabel: '轻松跑',
    );

    expect(feedback.scenario, CoachFeedbackScenario.routineCompletion);
    expect(feedback.text, '按计划完成轻松跑。主观强度 RPE 6。');
    expect(feedback.principleCodes, containsAll(<String>['P2', 'P4', 'P8']));
    expect(CoachFeedbackPolicy.containsForbiddenCopy(feedback.text), isFalse);
  });

  test('高疲劳优先输出明确恢复建议，不继续推动训练', () {
    final CoachFeedback feedback = policy.buildTrainingReceipt(
      current: _log(
        completionPercentage: 75,
        rpe: 9,
        fatigueLevel: 9,
        sessionFeel: SessionFeel.veryPoor,
      ),
      workoutLabel: '间歇跑',
    );

    expect(feedback.scenario, CoachFeedbackScenario.fatigueWarning);
    expect(feedback.text, contains('建议下一次改为恢复或低强度训练'));
    expect(feedback.text, isNot(contains('坚持')));
    expect(feedback.text, isNot(contains('加油')));
  });

  test('中断回归不复述离开时长，只降低下一步门槛', () {
    final CoachFeedback feedback = policy.buildTrainingReceipt(
      current: _log(completionPercentage: 50, rpe: 5),
      workoutLabel: '恢复跑',
      isReturnAfterBreak: true,
    );

    expect(feedback.scenario, CoachFeedbackScenario.returnAfterBreak);
    expect(feedback.text, '今天的恢复跑已记录。下一次可以先从短时长开始。');
    expect(feedback.text, isNot(contains('天没练')));
  });

  test('没有足够事实时返回可审计兜底，不生成通用激励', () {
    final CoachFeedback feedback = policy.buildTrainingReceipt(
      current: _log(completionPercentage: 0, rpe: 0),
      workoutLabel: '',
    );

    expect(feedback.scenario, CoachFeedbackScenario.insufficientData);
    expect(feedback.text, '本次训练记录已保存。');
    expect(feedback.fallbackReason, isNotNull);
    expect(feedback.dataDependencies, contains('workout_label'));
  });
}

TrainingLog _log({
  required int completionPercentage,
  required int rpe,
  int? fatigueLevel,
  SessionFeel? sessionFeel,
}) {
  final DateTime now = DateTime(2026, 7, 27, 8);
  return TrainingLog(
    id: 'log-1',
    workoutDayId: 'day-1',
    date: now,
    completed: completionPercentage == 100,
    rpe: rpe,
    fatigueLevel: fatigueLevel ?? rpe,
    sleepQuality: 7,
    painNote: null,
    userNote: null,
    createdAt: now,
    kind: TrainingLogKind.sessionReview,
    completionPercentage: completionPercentage,
    sessionFeel: sessionFeel,
  );
}
