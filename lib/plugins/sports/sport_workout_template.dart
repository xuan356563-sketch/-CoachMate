import '../../data/models/workout_day.dart';
import '../../data/models/plan_generation_preferences.dart';
import '../../services/abc_strength_cycle_compiler.dart';

class SportWorkoutTemplate {
  const SportWorkoutTemplate({
    required this.title,
    required this.trainingType,
    required this.baseMinutes,
    required this.baseIntensity,
    required this.purpose,
    required this.mainSets,
    this.recovery = false,
    this.preferredIntensity,
    this.abcStrengthSession,
  });

  final String title;
  final TrainingType trainingType;
  final int baseMinutes;
  final String baseIntensity;
  final String purpose;
  final List<String> mainSets;
  final bool recovery;
  final PlanIntensityBand? preferredIntensity;
  final AbcStrengthSessionTemplate? abcStrengthSession;

  SportWorkoutTemplate copyWith({
    String? title,
    String? purpose,
    List<String>? mainSets,
    AbcStrengthSessionTemplate? abcStrengthSession,
  }) {
    return SportWorkoutTemplate(
      title: title ?? this.title,
      trainingType: trainingType,
      baseMinutes: baseMinutes,
      baseIntensity: baseIntensity,
      purpose: purpose ?? this.purpose,
      mainSets: mainSets ?? this.mainSets,
      recovery: recovery,
      preferredIntensity: preferredIntensity,
      abcStrengthSession: abcStrengthSession ?? this.abcStrengthSession,
    );
  }
}
