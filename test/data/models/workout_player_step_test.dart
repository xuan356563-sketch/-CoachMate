import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/exercise_training_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/models/workout_player_step.dart';

void main() {
  test('主训练语音包含节奏、执行意图、呼吸和最长休息', () {
    final WorkoutDay workout = _workout(<WorkoutExerciseLink>[
      const WorkoutExerciseLink(
        id: 'main-1',
        exerciseId: 'exercise-goblet-squat',
        sequence: 1,
        module: WorkoutExerciseModule.mainTraining,
        plannedSetCount: 3,
        repetitionsPerSet: 8,
        plannedWeightOrIntensity: 'RPE 7',
        restSeconds: 90,
        tempo: '3-1-1',
        executionIntent: ExecutionIntent.fastConcentric,
        breathingCue: '下蹲吸气，起身呼气',
      ),
      const WorkoutExerciseLink(
        id: 'main-2',
        exerciseId: 'exercise-box-jump',
        sequence: 2,
        module: WorkoutExerciseModule.mainTraining,
        plannedSetCount: 3,
        repetitionsPerSet: 5,
        plannedWeightOrIntensity: '自重',
        restSeconds: 120,
      ),
    ]);

    final WorkoutPlayerStep main = buildWorkoutPlayerSteps(
      workout,
      deloaded: false,
    ).singleWhere(
        (WorkoutPlayerStep step) => step.phase == WorkoutPlayerPhase.main);

    expect(main.restSeconds, 120);
    expect(main.voiceCue, contains('动作节奏 3-1-1'));
    expect(main.voiceCue, contains('快速向心'));
    expect(main.voiceCue, contains('下蹲吸气，起身呼气'));
    expect(main.voiceCue, contains('组间休息 120 秒'));
  });

  test('降级流程移除神经和离心高要求动作', () {
    final WorkoutDay workout = _workout(<WorkoutExerciseLink>[
      const WorkoutExerciseLink(
        id: 'safe',
        exerciseId: 'exercise-short-foot',
        sequence: 1,
        module: WorkoutExerciseModule.activation,
        plannedSetCount: 2,
        repetitionsPerSet: 8,
        plannedWeightOrIntensity: '自重',
        restSeconds: 20,
      ),
      const WorkoutExerciseLink(
        id: 'eccentric',
        exerciseId: 'exercise-nordic-curl-eccentric',
        sequence: 2,
        module: WorkoutExerciseModule.mainTraining,
        plannedSetCount: 2,
        repetitionsPerSet: 5,
        plannedWeightOrIntensity: '自重',
        restSeconds: 90,
      ),
      const WorkoutExerciseLink(
        id: 'neural',
        exerciseId: 'exercise-box-jump',
        sequence: 3,
        module: WorkoutExerciseModule.mainTraining,
        plannedSetCount: 3,
        repetitionsPerSet: 5,
        plannedWeightOrIntensity: '自重',
        restSeconds: 120,
      ),
    ]);

    final WorkoutPlayerStep deload = buildWorkoutPlayerSteps(
      workout,
      deloaded: true,
    ).singleWhere(
        (WorkoutPlayerStep step) => step.phase == WorkoutPlayerPhase.deload);

    expect(deload.exerciseIds, <String>['exercise-short-foot']);
    expect(deload.restSeconds, 30);
  });
}

WorkoutDay _workout(List<WorkoutExerciseLink> links) {
  return WorkoutDay(
    id: 'workout-1',
    planId: 'plan-1',
    weekIndex: 1,
    dayIndex: 1,
    title: '腿部结构训练',
    trainingType: TrainingType.strength,
    decisionType: TrainingDecisionType.normal,
    estimatedMinutes: 45,
    intensity: '中等',
    foamRollingSteps: const <String>[],
    dynamicStretchSteps: const <String>[],
    activationSteps: const <String>[],
    warmupSteps: const <String>[],
    mainSets: const <String>['按动作顺序完成'],
    accessoryWork: const <String>[],
    cooldownSteps: const <String>[],
    coachNotes: '保持动作质量',
    evidenceSources: const [],
    workoutExercises: links,
  );
}
