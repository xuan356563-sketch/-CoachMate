import 'sport_plan_skills.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/race.dart';
import '../../data/models/workout_day.dart';
import '../core/plugin_core.dart';
import 'sport_plan_strategy.dart';
import 'sport_workout_template.dart';
import 'sport_display_capabilities.dart';
import 'sport_strategy_plugin.dart';

class StrengthPlanStrategy implements SportPlanStrategy {
  const StrengthPlanStrategy();
  @override
  SportDefinition get definition => SportDefinition(
      sport: MainSport.strength,
      pluginRef: PluginRef(id: 'sport.strength', version: '1.0.0'),
      cloudSupported: true,
      specialtyDisplaySupported: false,
      display: const SportDisplayCapabilities(
        workout: CardContribution(
            id: 'sport.strength.workout',
            label: '力量训练跟练',
            slot: 'workout_player'),
        weeklyReport: ReportContribution(
            id: 'sport.strength.weekly_report',
            label: '力量训练周报',
            reportId: 'weekly_report'),
      ));
  @override
  String get planTitle => '健身力量 4 周计划';
  @override
  bool matchesRace(RaceType type) => false;
  @override
  List<SportWorkoutTemplate> primaryCandidates(
      SportPlanContext context, SportPreferenceCompiler compilePreferences) {
    if (context.preferences != null) {
      return compilePreferences(context.withAbcStrengthCycle(
          context.preferences!.usesAbcStrengthCycle &&
              (context.profile.equipmentAccessType == EquipmentAccessType.gym ||
                  context.profile.equipmentAccessType ==
                      EquipmentAccessType.mixed)));
    }
    return const <SportWorkoutTemplate>[
      SportWorkoutTemplate(
        title: '下肢力量基础',
        trainingType: TrainingType.strength,
        baseMinutes: 50,
        baseIntensity: 'RPE 6',
        purpose: '建立下肢动作质量和力量基础',
        mainSets: <String>['深蹲模式 4 组', '髋铰链模式 3 组', '核心稳定 3 组'],
      ),
      SportWorkoutTemplate(
        title: '上肢推拉基础',
        trainingType: TrainingType.strength,
        baseMinutes: 45,
        baseIntensity: 'RPE 6',
        purpose: '建立上肢推拉平衡',
        mainSets: <String>['水平推 3 组', '水平拉 3 组', '肩胛稳定 2 组'],
      ),
      SportWorkoutTemplate(
        title: '全身力量整合',
        trainingType: TrainingType.strength,
        baseMinutes: 50,
        baseIntensity: 'RPE 6-7',
        purpose: '整合全身力量动作',
        mainSets: <String>['下肢主动作 3 组', '上肢主动作 3 组', '负重行走 3 组'],
      ),
      SportWorkoutTemplate(
        title: '力量恢复与活动度',
        trainingType: TrainingType.mobility,
        baseMinutes: 30,
        baseIntensity: 'RPE 2-3',
        purpose: '维持关节活动度并促进恢复',
        mainSets: <String>['全身活动度循环 3 轮'],
        recovery: true,
      ),
    ];
  }

  @override
  SportWorkoutTemplate secondaryCandidate(SportPlanContext context) =>
      const SportWorkoutTemplate(
        title: '次目标全身力量',
        trainingType: TrainingType.strength,
        baseMinutes: 40,
        baseIntensity: 'RPE 6',
        purpose: '用全身力量支持次目标',
        mainSets: <String>['蹲、推、拉各 3 组'],
      );
}

class StrengthPlugin extends SportStrategyPlugin {
  StrengthPlugin({SportPlanStrategy strategy = const StrengthPlanStrategy()})
      : super(strategy);
  @override
  PluginDescriptor get descriptor => PluginDescriptor(
          id: 'sport.strength',
          type: PluginType.sport,
          version: strategy.definition.pluginRef.version,
          name: '力量训练',
          description: '力量训练候选训练课程、跟练与周报能力',
          workflows: [const PluginWorkflowRef(ownerPluginId: 'feature.resource_library', capabilityId: 'feature.resource_library.catalog', label: '基础评估与训练计划资源'),],
          skills: [
            localSportPlanSkill('sport.strength',
                strategy.definition.pluginRef.version, '力量训练'),
            cloudSportPlanSkill('sport.strength', 'strength', '力量训练',
                fragmentKey: 'strength'),
          ],
          capabilities: [
            'sport.strength.strategy'
          ]);
}
