import 'sport_plan_skills.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/race.dart';
import '../core/plugin_core.dart';
import 'sport_plan_strategy.dart';
import 'sport_workout_template.dart';
import 'sport_display_capabilities.dart';
import 'sport_strategy_plugin.dart';
import 'shared_workout_templates.dart';

class TrailRunningPlanStrategy implements SportPlanStrategy {
  const TrailRunningPlanStrategy();
  @override
  SportDefinition get definition => SportDefinition(
      sport: MainSport.trailRunning,
      pluginRef: PluginRef(id: 'sport.trail_running', version: '1.0.0'),
      cloudSupported: true,
      specialtyDisplaySupported: false,
      display: const SportDisplayCapabilities(
        workout: CardContribution(
            id: 'sport.trail_running.workout',
            label: '越野跑跟练',
            slot: 'workout_player'),
        weeklyReport: ReportContribution(
            id: 'sport.trail_running.weekly_report',
            label: '越野跑周报',
            reportId: 'weekly_report'),
      ));
  @override
  String get planTitle => '跑步 4 周计划';
  @override
  bool matchesRace(RaceType type) => type == RaceType.trailRunning;
  @override
  List<SportWorkoutTemplate> primaryCandidates(
      SportPlanContext context, SportPreferenceCompiler compilePreferences) {
    if (context.preferences != null) return compilePreferences(context);
    return runningPrimaryTemplates;
  }

  @override
  SportWorkoutTemplate secondaryCandidate(SportPlanContext context) =>
      runningSecondaryTemplate;
}

class TrailRunningPlugin extends SportStrategyPlugin {
  TrailRunningPlugin(
      {SportPlanStrategy strategy = const TrailRunningPlanStrategy()})
      : super(strategy);
  @override
  PluginDescriptor get descriptor => PluginDescriptor(
          id: 'sport.trail_running',
          type: PluginType.sport,
          version: strategy.definition.pluginRef.version,
          name: '越野跑',
          description: '越野跑候选训练课程、跟练与周报能力',
          workflows: const [
            PluginWorkflowRef(ownerPluginId: 'feature.resource_library', capabilityId: 'feature.resource_library.catalog', label: '基础评估与训练计划资源'),
            PluginWorkflowRef(
                ownerPluginId: 'feature.motion_check',
                capabilityId: 'feature.motion_check.running_review',
                label: '平整场地跑姿视频分析')
          ],
          skills: [
            localSportPlanSkill('sport.trail_running',
                strategy.definition.pluginRef.version, '越野跑'),
            cloudSportPlanSkill('sport.trail_running', 'trail_running', '越野跑',
                fragmentKey: 'trail_running'),
          ],
          capabilities: [
            'sport.trail_running.strategy'
          ]);
}
