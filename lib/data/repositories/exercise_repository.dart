import '../models/exercise.dart';
import '../seed/seed_exercises.dart';

abstract class ExerciseRepository {
  List<Exercise> listExercises();

  Exercise? findExerciseById(String id);
}

class InMemoryExerciseRepository implements ExerciseRepository {
  final List<Exercise> _exercises;

  InMemoryExerciseRepository({List<Exercise>? initialExercises})
      : _exercises = List<Exercise>.from(initialExercises ?? seedExercises);

  @override
  List<Exercise> listExercises() {
    return List<Exercise>.unmodifiable(_exercises);
  }

  @override
  Exercise? findExerciseById(String id) {
    for (final Exercise exercise in _exercises) {
      if (exercise.id == id) {
        return exercise;
      }
    }
    return null;
  }
}
