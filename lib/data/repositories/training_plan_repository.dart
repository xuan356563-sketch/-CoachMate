import '../models/training_plan.dart';
import '../models/workout_day.dart';
import '../seed/seed_training_plans.dart';

abstract class TrainingPlanRepository {
  List<TrainingPlan> listPlans();

  TrainingPlan? findPlanById(String id);

  WorkoutDay? findWorkoutDayById(String workoutDayId);
}

class InMemoryTrainingPlanRepository implements TrainingPlanRepository {
  final List<TrainingPlan> _plans;

  InMemoryTrainingPlanRepository({List<TrainingPlan>? initialPlans})
      : _plans = List<TrainingPlan>.from(initialPlans ?? seedTrainingPlans);

  @override
  List<TrainingPlan> listPlans() {
    return List<TrainingPlan>.unmodifiable(_plans);
  }

  @override
  TrainingPlan? findPlanById(String id) {
    for (final TrainingPlan plan in _plans) {
      if (plan.id == id) {
        return plan;
      }
    }
    return null;
  }

  @override
  WorkoutDay? findWorkoutDayById(String workoutDayId) {
    for (final TrainingPlan plan in _plans) {
      for (final WorkoutDay day in plan.workoutDays) {
        if (day.id == workoutDayId) {
          return day;
        }
      }
    }
    return null;
  }
}
