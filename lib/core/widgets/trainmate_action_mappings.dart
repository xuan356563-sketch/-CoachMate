import '../../data/models/exercise.dart';
import '../../data/models/workout_day.dart';
import '../../data/models/workout_player_step.dart';
import 'trainmate_action_character.dart';

TrainMateAction trainMateActionForTrainingType(TrainingType type) {
  return switch (type) {
    TrainingType.easyRun ||
    TrainingType.tempoRun ||
    TrainingType.longRun =>
      TrainMateAction.running,
    TrainingType.intervalRun => TrainMateAction.sprint,
    TrainingType.strength => TrainMateAction.dumbbellOverheadPress,
    TrainingType.hyrox => TrainMateAction.mountainClimber,
    TrainingType.mobility => TrainMateAction.sideLungeStretch,
    TrainingType.rehab || TrainingType.rest => TrainMateAction.seatedMeditation,
    TrainingType.crossTraining => TrainMateAction.jumpRope,
  };
}

TrainMateAction trainMateActionForExercise(Exercise exercise) {
  return switch (exercise.category) {
    ExerciseCategory.runningDrill ||
    ExerciseCategory.endurance =>
      TrainMateAction.running,
    ExerciseCategory.strength => _hasEquipment(exercise.equipment)
        ? TrainMateAction.dumbbellCurl
        : TrainMateAction.pushUp,
    ExerciseCategory.mobility ||
    ExerciseCategory.warmup =>
      TrainMateAction.standingSideStretch,
    ExerciseCategory.activation => TrainMateAction.highKnees,
    ExerciseCategory.rehab ||
    ExerciseCategory.cooldown =>
      TrainMateAction.seatedForwardFold,
    ExerciseCategory.core => TrainMateAction.sitUpCrunch,
    ExerciseCategory.hyrox => TrainMateAction.burpee,
  };
}

TrainMateAction trainMateActionForWorkoutPhase(
  WorkoutPlayerPhase phase,
  TrainingType trainingType,
) {
  return switch (phase) {
    WorkoutPlayerPhase.dynamicStretch ||
    WorkoutPlayerPhase.foamRolling =>
      TrainMateAction.standingSideStretch,
    WorkoutPlayerPhase.activation => TrainMateAction.highKnees,
    WorkoutPlayerPhase.deload ||
    WorkoutPlayerPhase.cooldown =>
      TrainMateAction.seatedForwardFold,
    WorkoutPlayerPhase.main => trainMateActionForTrainingType(trainingType),
  };
}

bool _hasEquipment(List<String> equipment) {
  if (equipment.isEmpty) return false;
  return equipment.any((String item) {
    final String normalized = item.trim().toLowerCase();
    return normalized.isNotEmpty &&
        normalized != '无' &&
        !normalized.contains('无器械') &&
        !normalized.contains('徒手') &&
        normalized != 'bodyweight';
  });
}
