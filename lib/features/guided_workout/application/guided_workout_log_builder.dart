import '../../../data/models/training_log.dart';
import '../domain/guided_workout_course.dart';
import 'guided_workout_engine.dart';

TrainingLog buildGuidedWorkoutTrainingLog({
  required String sessionId,
  required GuidedWorkoutCourse course,
  required GuidedWorkoutState state,
  required DateTime now,
  required bool completedFlow,
}) {
  final int actualMinutes =
      (state.elapsedMilliseconds / Duration.millisecondsPerMinute)
          .ceil()
          .clamp(1, 360);
  final List<ExerciseExecutionRecord> exerciseRecords =
      _buildExerciseRecords(course, state);
  return TrainingLog(
    id: sessionId,
    workoutDayId: 'guided:${course.id}',
    date: now,
    completed: completedFlow && state.completionPercentage == 100,
    rpe: 0,
    fatigueLevel: 0,
    sleepQuality: 0,
    painNote: null,
    userNote: '[配置化跟练] ${course.title} · '
        '完成 ${state.completedExerciseCount}/${state.plannedExerciseCount} · '
        '跳过 ${state.skippedExerciseCount}',
    createdAt: now,
    kind: TrainingLogKind.guidedWorkout,
    actualDurationMinutes: actualMinutes,
    completionPercentage: state.completionPercentage,
    plannedSetCount: state.plannedExerciseCount,
    completedSetCount: state.completedExerciseCount,
    interruptionReason: completedFlow ? null : '用户中途退出',
    abortedByUser: !completedFlow,
    exerciseRecords: exerciseRecords,
  );
}

List<ExerciseExecutionRecord> _buildExerciseRecords(
  GuidedWorkoutCourse course,
  GuidedWorkoutState state,
) {
  final Map<String, GuidedWorkoutExercise> exercisesByLibraryId =
      <String, GuidedWorkoutExercise>{};
  final Map<String, int> plannedSets = <String, int>{};
  final int rounds = course.normalizedRounds(
    course.kind == GuidedWorkoutCourseKind.functionalCircuit
        ? state.plannedExerciseCount ~/ course.exerciseSetCount
        : 1,
  );
  for (int round = 0; round < rounds; round += 1) {
    for (final GuidedWorkoutPhase phase in course.phases) {
      for (final GuidedWorkoutExercise exercise in phase.exercises) {
        final String? libraryId = exercise.libraryExerciseId;
        if (libraryId == null) continue;
        exercisesByLibraryId[libraryId] = exercise;
        plannedSets[libraryId] =
            (plannedSets[libraryId] ?? 0) + exercise.repeat;
      }
    }
  }
  final Map<String, int> completedSets = <String, int>{};
  for (final GuidedWorkoutStepResult result in state.stepResults) {
    final String? libraryId = result.libraryExerciseId;
    if (libraryId == null || !result.completed) continue;
    completedSets[libraryId] = (completedSets[libraryId] ?? 0) + 1;
  }
  return exercisesByLibraryId.entries
      .map((MapEntry<String, GuidedWorkoutExercise> entry) {
        final GuidedWorkoutExercise exercise = entry.value;
        return ExerciseExecutionRecord(
          exerciseId: entry.key,
          exerciseName: exercise.name,
          plannedSetCount: plannedSets[entry.key] ?? 0,
          completedSetCount: completedSets[entry.key] ?? 0,
          repetitionsPerSet: exercise.targetRepetitions ?? 0,
          repetitionUnit: exercise.repetitionUnit,
          weightKg: 0,
        );
      })
      .toList(growable: false);
}
