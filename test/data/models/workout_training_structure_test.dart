import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/exercise_training_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';

void main() {
  test('课程维度和动作执行参数支持旧数据兼容与新数据往返', () {
    const WorkoutExerciseLink link = WorkoutExerciseLink(
      id: 'link-1',
      exerciseId: 'exercise-nordic-curl-eccentric',
      sequence: 1,
      module: WorkoutExerciseModule.mainTraining,
      plannedSetCount: 3,
      repetitionsPerSet: 5,
      plannedWeightOrIntensity: '自重',
      restSeconds: 90,
      tempo: '5-0-1-0',
      executionIntent: ExecutionIntent.controlled,
      breathingCue: '下放时缓慢呼气。',
    );

    final WorkoutExerciseLink restored =
        WorkoutExerciseLink.fromJson(link.toJson());
    final WorkoutExerciseLink legacy =
        WorkoutExerciseLink.fromJson(<String, dynamic>{
      'id': 'legacy',
      'exerciseId': 'exercise-rdl',
      'sequence': 1,
      'module': 'main_training',
      'plannedSetCount': 3,
      'repetitionsPerSet': 8,
      'plannedWeightOrIntensity': 'RPE 6',
      'restSeconds': 60,
    });

    expect(restored.tempo, '5-0-1-0');
    expect(restored.breathingCue, '下放时缓慢呼气。');
    expect(legacy.executionIntent, ExecutionIntent.controlled);
    expect(legacy.tempo, isNull);
  });

  test('维度重点最多保留两个主维度且触达维度不重复', () {
    final DimensionFocus focus = DimensionFocus.fromJson(<String, dynamic>{
      'primary': <String>['strength', 'eccentric', 'neural'],
      'touch': <String>['strength', 'stability', 'breathing'],
    });

    expect(
      focus.primary,
      <TrainingDimension>[
        TrainingDimension.strength,
        TrainingDimension.eccentric,
      ],
    );
    expect(focus.touch, isNot(contains(TrainingDimension.strength)));
    expect(focus.all, contains(TrainingDimension.breathing));
  });
}
