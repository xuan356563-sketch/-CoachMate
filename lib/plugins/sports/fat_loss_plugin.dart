import 'sport_plan_skills.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/race.dart';
import '../core/plugin_core.dart';
import 'sport_plan_strategy.dart';
import 'sport_workout_template.dart';
import 'sport_display_capabilities.dart';
import 'sport_strategy_plugin.dart';
import 'shared_workout_templates.dart';

class FatLossPlanStrategy implements SportPlanStrategy {
  const FatLossPlanStrategy();
  @override
  SportDefinition get definition => SportDefinition(
      sport: MainSport.fatLoss,
      pluginRef: PluginRef(id: 'goal.fat_loss', version: '1.0.0'),
      cloudSupported: true,
      specialtyDisplaySupported: false,
      display: const SportDisplayCapabilities(
        workout: CardContribution(
            id: 'goal.fat_loss.workout', label: '减脂跟练', slot: 'workout_player'),
        weeklyReport: ReportContribution(
            id: 'goal.fat_loss.weekly_report',
            label: '减脂周报',
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

class FatLossPlugin extends SportStrategyPlugin {
  FatLossPlugin({SportPlanStrategy strategy = const FatLossPlanStrategy()})
      : super(strategy);
  @override
  PluginDescriptor get descriptor => PluginDescriptor(
          id: 'goal.fat_loss',
          type: PluginType.goal,
          version: strategy.definition.pluginRef.version,
          name: '减脂',
          description: '减脂候选训练课程、跟练与周报能力',
          skills: [
            localSportPlanSkill(
                'goal.fat_loss', strategy.definition.pluginRef.version, '减脂'),
            cloudSportPlanSkill('goal.fat_loss', 'fat_loss', '减脂'),
          ],
          capabilities: [
            'goal.fat_loss.strategy'
          ]);
}
