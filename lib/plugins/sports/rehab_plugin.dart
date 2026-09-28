import 'sport_plan_skills.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/race.dart';
import '../../data/models/workout_day.dart';
import '../core/plugin_core.dart';
import 'sport_plan_strategy.dart';
import 'sport_workout_template.dart';
import 'sport_display_capabilities.dart';
import 'sport_strategy_plugin.dart';

class RehabPlanStrategy implements SportPlanStrategy {
  const RehabPlanStrategy();
  @override
  SportDefinition get definition => SportDefinition(
      sport: MainSport.rehab,
      pluginRef: PluginRef(id: 'support.rehab', version: '1.0.0'),
      cloudSupported: false,
      specialtyDisplaySupported: false,
      display: const SportDisplayCapabilities(
        workout: CardContribution(
            id: 'support.rehab.workout',
            label: '康复支持跟练',
            slot: 'workout_player'),
        weeklyReport: ReportContribution(
            id: 'support.rehab.weekly_report',
            label: '康复支持周报',
            reportId: 'weekly_report'),
      ));
  @override
  String get planTitle => '恢复基础 4 周计划';
  @override
  bool matchesRace(RaceType type) => false;
  @override
  List<SportWorkoutTemplate> primaryCandidates(
      SportPlanContext context, SportPreferenceCompiler compilePreferences) {
    if (context.preferences != null) return compilePreferences(context);
    return const <SportWorkoutTemplate>[
      SportWorkoutTemplate(
        title: '无痛活动度',
        trainingType: TrainingType.rehab,
        baseMinutes: 25,
        baseIntensity: 'RPE 2-3',
        purpose: '在无痛范围内恢复活动能力',
        mainSets: <String>['无痛活动度循环', '低强度稳定练习'],
        recovery: true,
      ),
      SportWorkoutTemplate(
        title: '低强度基础体能',
        trainingType: TrainingType.crossTraining,
        baseMinutes: 30,
        baseIntensity: 'RPE 3-4',
        purpose: '维持基础体能且避免刺激疼痛',
        mainSets: <String>['无痛步行、单车或椭圆机'],
        recovery: true,
      ),
    ];
  }

  @override
  SportWorkoutTemplate secondaryCandidate(SportPlanContext context) =>
      const SportWorkoutTemplate(
        title: '次目标恢复维护',
        trainingType: TrainingType.rehab,
        baseMinutes: 25,
        baseIntensity: 'RPE 2-3',
        purpose: '把恢复要求纳入当前计划',
        mainSets: <String>['无痛活动度和稳定练习'],
        recovery: true,
      );
}

class RehabPlugin extends SportStrategyPlugin {
  RehabPlugin({SportPlanStrategy strategy = const RehabPlanStrategy()})
      : super(strategy);
  @override
  PluginDescriptor get descriptor => PluginDescriptor(
          id: 'support.rehab',
          type: PluginType.support,
          version: strategy.definition.pluginRef.version,
          name: '康复支持',
          description: '康复支持候选训练课程、跟练与周报能力',
          skills: [
            localSportPlanSkill(
                'support.rehab', strategy.definition.pluginRef.version, '康复支持'),
          ],
          capabilities: [
            'support.rehab.strategy'
          ]);
}
