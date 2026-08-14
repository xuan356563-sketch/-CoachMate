import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/guided_workout/application/guided_workout_engine.dart';
import 'package:trainflow_ai/features/guided_workout/domain/guided_workout_course.dart';

void main() {
  late DateTime now;
  late GuidedWorkoutEngine engine;

  setUp(() {
    now = DateTime(2026, 7, 28, 9);
    engine = GuidedWorkoutEngine(
      course: _course(),
      now: () => now,
    );
  });

  test('按绝对时间进入休息并立即预告下一动作', () {
    engine.start();
    engine.takePendingVoiceEvents();
    now = now.add(const Duration(seconds: 10));

    engine.reconcile();

    expect(engine.state.segment.kind, GuidedWorkoutSegmentKind.rest);
    expect(engine.state.completedExerciseCount, 1);
    expect(engine.state.remainingMilliseconds, 5000);
    expect(
      engine.takePendingVoiceEvents().single.text,
      contains('下一组：左右脚交替跳'),
    );
  });

  test('后台跨过多个时间段后只保留当前状态播报', () {
    engine.start();
    engine.takePendingVoiceEvents();
    now = now.add(const Duration(seconds: 20));

    engine.reconcile();

    expect(engine.state.segment.exercise.name, '左右脚交替跳');
    expect(engine.state.segment.kind, GuidedWorkoutSegmentKind.exercise);
    expect(engine.state.remainingMilliseconds, 3000);
    final List<GuidedWorkoutVoiceEvent> events =
        engine.takePendingVoiceEvents();
    expect(events, hasLength(1));
    expect(events.single.text, contains('左右脚交替跳'));
  });

  test('暂停期间不推进，继续后从冻结时间恢复', () {
    engine.start();
    engine.takePendingVoiceEvents();
    now = now.add(const Duration(seconds: 4));
    engine.pause();
    expect(engine.state.remainingMilliseconds, 6000);

    now = now.add(const Duration(minutes: 2));
    engine.reconcile();
    expect(engine.state.remainingMilliseconds, 6000);

    engine.resume();
    now = now.add(const Duration(seconds: 2));
    engine.reconcile();
    expect(engine.state.remainingMilliseconds, 4000);
  });

  test('动作最后五秒和休息最后三秒使用稳定事件 ID 去重', () {
    engine.start();
    engine.takePendingVoiceEvents();
    now = now.add(const Duration(seconds: 5));

    engine.reconcile();
    final List<GuidedWorkoutVoiceEvent> five = engine.takePendingVoiceEvents();
    expect(five.single.text, '5');

    engine.reconcile();
    expect(engine.takePendingVoiceEvents(), isEmpty);

    now = now.add(const Duration(seconds: 5));
    engine.reconcile();
    engine.takePendingVoiceEvents();
    now = now.add(const Duration(seconds: 2));
    engine.reconcile();
    expect(engine.takePendingVoiceEvents().single.text, '3');
  });

  test('跳过计入跳过数，上一步遵循三秒规则', () {
    engine.start();
    engine.takePendingVoiceEvents();
    now = now.add(const Duration(seconds: 4));
    engine.goToPrevious();
    expect(engine.state.segment.exercise.name, '基础跳');
    expect(engine.state.remainingMilliseconds, 10000);

    engine.skipCurrent();
    expect(engine.state.skippedExerciseCount, 1);
    expect(engine.state.segment.exercise.name, '左右脚交替跳');

    now = now.add(const Duration(seconds: 2));
    engine.goToPrevious();
    expect(engine.state.segment.exercise.name, '基础跳');
    expect(engine.state.remainingMilliseconds, 10000);
  });

  test('最后动作完成后生成完成统计', () {
    engine.start();
    engine.takePendingVoiceEvents();
    now = now.add(const Duration(seconds: 23));

    engine.reconcile();

    expect(engine.state.status, GuidedWorkoutStatus.completed);
    expect(engine.state.completedExerciseCount, 2);
    expect(engine.state.completionPercentage, 100);
    expect(engine.state.elapsedMilliseconds, 23000);
  });
}

GuidedWorkoutCourse _course() {
  return GuidedWorkoutCourse(
    id: 'test-course',
    title: '测试跳绳课',
    level: 'standard',
    description: '',
    expectedDurationSeconds: 23,
    phases: const <GuidedWorkoutPhase>[
      GuidedWorkoutPhase(
        id: 'main',
        name: '主训',
        exercises: <GuidedWorkoutExercise>[
          GuidedWorkoutExercise(
            id: 'basic',
            name: '基础跳',
            durationSeconds: 10,
            restSeconds: 5,
            repeat: 1,
            announce: '基础跳，轻柔落地',
            cues: <String>['手腕发力'],
          ),
          GuidedWorkoutExercise(
            id: 'alternate',
            name: '左右脚交替跳',
            durationSeconds: 8,
            restSeconds: 0,
            repeat: 1,
            announce: '左右脚交替跳',
            cues: <String>['身体直立'],
          ),
        ],
      ),
    ],
    voice: const GuidedWorkoutVoiceConfig(
      countdownLast: 5,
      preAnnounceOnRest: true,
      rate: 1,
      enabled: true,
      voiceName: null,
    ),
  );
}
