import 'sport_plan_skills.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/race.dart';
import '../core/plugin_core.dart';
import 'sport_plan_strategy.dart';
import 'sport_workout_template.dart';
import 'shared_workout_templates.dart';
import 'sport_display_capabilities.dart';
import 'sport_strategy_plugin.dart';

class MarathonPlanStrategy implements SportPlanStrategy {
  const MarathonPlanStrategy();
  @override
  SportDefinition get definition => SportDefinition(
      sport: MainSport.marathon,
      pluginRef: PluginRef(id: 'sport.marathon', version: '1.0.0'),
      cloudSupported: true,
      specialtyDisplaySupported: false,
      display: const SportDisplayCapabilities(
        workout: CardContribution(
            id: 'sport.marathon.workout',
            label: '马拉松跟练',
            slot: 'workout_player'),
        weeklyReport: ReportContribution(
            id: 'sport.marathon.weekly_report',
            label: '马拉松周报',
            reportId: 'weekly_report'),
      ));
  @override
  String get planTitle => '跑步 4 周计划';
  @override
  bool matchesRace(RaceType type) =>
      type == RaceType.marathon || type == RaceType.roadRunning;
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

class MarathonPlugin extends SportStrategyPlugin {
  MarathonPlugin({SportPlanStrategy strategy = const MarathonPlanStrategy()})
      : super(strategy);
  @override
  PluginDescriptor get descriptor => PluginDescriptor(
          id: 'sport.marathon',
          type: PluginType.sport,
          version: strategy.definition.pluginRef.version,
          name: '马拉松',
          description: '马拉松候选训练课程、跟练与周报能力',
          workflows: const [
            PluginWorkflowRef(ownerPluginId: 'feature.resource_library', capabilityId: 'feature.resource_library.catalog', label: '基础评估与训练计划资源'),
            PluginWorkflowRef(
                ownerPluginId: 'feature.motion_check',
                capabilityId: 'feature.motion_check.running_review',
                label: '侧面跑姿视频分析')
          ],
          skills: [
            localSportPlanSkill(
                'sport.marathon', strategy.definition.pluginRef.version, '马拉松'),
            cloudSportPlanSkill('sport.marathon', 'marathon', '马拉松',
                fragmentKey: 'marathon'),
          ],
          capabilities: [
            'sport.marathon.strategy'
          ]);
}
