import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/features/guided_workout/application/guided_workout_engine.dart';
import 'package:trainflow_ai/features/guided_workout/application/guided_workout_log_builder.dart';
import 'package:trainflow_ai/features/guided_workout/domain/guided_workout_course.dart';

void main() {
  test('正常结束保存客观完成记录且不推断 RPE', () {
    DateTime now = DateTime(2026, 7, 28, 9);
    final GuidedWorkoutEngine engine = GuidedWorkoutEngine(
      course: _course(),
      now: () => now,
    )..start();
    now = now.add(const Duration(minutes: 1));
    engine.reconcile();

    final TrainingLog log = buildGuidedWorkoutTrainingLog(
      sessionId: 'guided-session-1',
      course: engine.course,
      state: engine.state,
      now: now,
      completedFlow: true,
    );

    expect(log.kind, TrainingLogKind.guidedWorkout);
    expect(log.completed, isTrue);
    expect(log.abortedByUser, isFalse);
    expect(log.rpe, 0);
    expect(log.actualDurationMinutes, 1);
    expect(log.completionPercentage, 100);
  });

  test('中途退出保存部分完成率和中断状态', () {
    DateTime now = DateTime(2026, 7, 28, 9);
    final GuidedWorkoutEngine engine = GuidedWorkoutEngine(
      course: _course(),
      now: () => now,
    )..start();
    now = now.add(const Duration(seconds: 20));
    engine.reconcile();

    final TrainingLog log = buildGuidedWorkoutTrainingLog(
      sessionId: 'guided-session-2',
      course: engine.course,
      state: engine.state,
      now: now,
      completedFlow: false,
    );

    expect(log.completed, isFalse);
    expect(log.abortedByUser, isTrue);
    expect(log.interruptionReason, '用户中途退出');
    expect(log.completionPercentage, 0);
  });
}

GuidedWorkoutCourse _course() {
  return const GuidedWorkoutCourse(
    id: 'one-minute',
    title: '一分钟测试课',
    level: 'beginner',
    description: '',
    expectedDurationSeconds: 60,
    phases: <GuidedWorkoutPhase>[
      GuidedWorkoutPhase(
        id: 'main',
        name: '主训',
        exercises: <GuidedWorkoutExercise>[
          GuidedWorkoutExercise(
            id: 'basic',
            name: '基础跳',
            durationSeconds: 60,
            restSeconds: 0,
            repeat: 1,
            announce: '开始基础跳',
            cues: <String>[],
          ),
        ],
      ),
    ],
    voice: GuidedWorkoutVoiceConfig(
      countdownLast: 5,
      preAnnounceOnRest: true,
      rate: 1,
      enabled: true,
      voiceName: null,
    ),
  );
}
