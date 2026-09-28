import 'sport_plan_skills.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/race.dart';
import '../core/plugin_core.dart';
import 'sport_plan_strategy.dart';
import 'sport_workout_template.dart';
import 'sport_display_capabilities.dart';
import 'sport_strategy_plugin.dart';
import 'shared_workout_templates.dart';

class GeneralFitnessPlanStrategy implements SportPlanStrategy {
  const GeneralFitnessPlanStrategy();
  @override
  SportDefinition get definition => SportDefinition(
      sport: MainSport.generalFitness,
      pluginRef: PluginRef(id: 'goal.general_fitness', version: '1.0.0'),
      cloudSupported: true,
      specialtyDisplaySupported: false,
      display: const SportDisplayCapabilities(
        workout: CardContribution(
            id: 'goal.general_fitness.workout',
            label: '综合健身跟练',
            slot: 'workout_player'),
        weeklyReport: ReportContribution(
            id: 'goal.general_fitness.weekly_report',
            label: '综合健身周报',
            reportId: 'weekly_report'),
      ));
  @override
  String get planTitle => '基础体能 4 周计划';
  @override
  bool matchesRace(RaceType type) => false;
  @override
  List<SportWorkoutTemplate> primaryCandidates(
      SportPlanContext context, SportPreferenceCompiler compilePreferences) {
    if (context.preferences != null) return compilePreferences(context);
    return fitnessPrimaryTemplates;
  }

  @override
  SportWorkoutTemplate secondaryCandidate(SportPlanContext context) =>
      fitnessSecondaryTemplate;
}

class GeneralFitnessPlugin extends SportStrategyPlugin {
  GeneralFitnessPlugin(
      {SportPlanStrategy strategy = const GeneralFitnessPlanStrategy()})
      : super(strategy);
  @override
  PluginDescriptor get descriptor => PluginDescriptor(
          id: 'goal.general_fitness',
          type: PluginType.goal,
          version: strategy.definition.pluginRef.version,
          name: '综合健身',
          description: '综合健身候选训练课程、跟练与周报能力',
          skills: [
            localSportPlanSkill('goal.general_fitness',
                strategy.definition.pluginRef.version, '综合健身'),
            cloudSportPlanSkill(
                'goal.general_fitness', 'general_fitness', '综合健身'),
          ],
          capabilities: [
            'goal.general_fitness.strategy'
          ]);
}
