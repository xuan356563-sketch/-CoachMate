import '../../data/models/user_profile.dart';
import '../../data/models/race.dart';
import '../../data/models/plan_generation_preferences.dart';
import '../core/plugin_ref.dart';
import 'sport_workout_template.dart';
import 'sport_display_capabilities.dart';

class SportDefinition {
  const SportDefinition(
      {required this.sport,
      required this.pluginRef,
      this.localSupported = true,
      required this.cloudSupported,
      required this.specialtyDisplaySupported,
      this.display});
  final MainSport sport;
  final PluginRef pluginRef;
  final bool localSupported;
  final bool cloudSupported;
  final bool specialtyDisplaySupported;
  final SportDisplayCapabilities? display;
}

class SportPlanContext {
  const SportPlanContext(
      {required this.profile,
      required this.startsOn,
      required this.race,
      required this.preferences,
      required this.trainingDays,
      this.compileAbcStrengthCycle = false});
  final UserProfile profile;
  final DateTime startsOn;
  final RacePlan? race;
  final PlanGenerationPreferences? preferences;
  final int trainingDays;

  /// 由策略请求既有 ABC 候选编译，公共编译器不判断运动身份。
  final bool compileAbcStrengthCycle;
  SportPlanContext withAbcStrengthCycle(bool enabled) => SportPlanContext(
      profile: profile,
      startsOn: startsOn,
      race: race,
      preferences: preferences,
      trainingDays: trainingDays,
      compileAbcStrengthCycle: enabled);
}

/// 公共编译器拥有偏好排序、器械与 ABC 算法，策略只委托候选生成。
typedef SportPreferenceCompiler = List<SportWorkoutTemplate> Function(
    SportPlanContext context);

abstract interface class SportPlanStrategy {
  SportDefinition get definition;
  String get planTitle;
  bool matchesRace(RaceType type);
  List<SportWorkoutTemplate> primaryCandidates(
      SportPlanContext context, SportPreferenceCompiler compilePreferences);
  SportWorkoutTemplate secondaryCandidate(SportPlanContext context);
}
