import 'sport_plan_skills.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/race.dart';
import '../../data/models/workout_day.dart';
import '../core/plugin_core.dart';
import 'sport_plan_strategy.dart';
import 'sport_workout_template.dart';
import 'sport_display_capabilities.dart';
import 'sport_strategy_plugin.dart';

class HyroxPlanStrategy implements SportPlanStrategy {
  const HyroxPlanStrategy();
  @override
  SportDefinition get definition => SportDefinition(
      sport: MainSport.hyrox,
      pluginRef: PluginRef(id: 'sport.hyrox', version: '1.0.0'),
      cloudSupported: true,
      specialtyDisplaySupported: true,
      display: const SportDisplayCapabilities(
        workout: CardContribution(
            id: 'sport.hyrox.workout',
            label: 'HYROX跟练',
            slot: 'workout_player'),
        weeklyReport: ReportContribution(
            id: 'sport.hyrox.weekly_report',
            label: 'HYROX周报',
            reportId: 'weekly_report'),
        specialty: CardContribution(
            id: 'sport.hyrox.specialty',
            label: 'HYROX 专项进展',
            slot: 'sport_specialty'),
      ));
  @override
  String get planTitle => 'HYROX 基础 4 周计划';
  @override
  bool matchesRace(RaceType type) => type == RaceType.hyrox;
  @override
  List<SportWorkoutTemplate> primaryCandidates(
      SportPlanContext context, SportPreferenceCompiler compilePreferences) {
    if (context.preferences != null) return compilePreferences(context);
    return const <SportWorkoutTemplate>[
      SportWorkoutTemplate(
        title: 'HYROX 有氧基础',
        trainingType: TrainingType.easyRun,
        baseMinutes: 40,
        baseIntensity: 'RPE 4-5',
        purpose: '建立跑段有氧储备',
        mainSets: <String>['轻松跑 30 分钟', '4 次短加速但不冲刺'],
      ),
      SportWorkoutTemplate(
        title: 'HYROX 力量基础',
        trainingType: TrainingType.strength,
        baseMinutes: 50,
        baseIntensity: 'RPE 6',
        purpose: '建立雪橇、弓步和负重行走所需力量',
        mainSets: <String>['深蹲模式 3 组', '负重行走 4 组', '核心抗旋转 3 组'],
      ),
      SportWorkoutTemplate(
        title: 'HYROX 站点技术',
        trainingType: TrainingType.hyrox,
        baseMinutes: 45,
        baseIntensity: 'RPE 6',
        purpose: '提高站点动作效率',
        mainSets: <String>['划船机技术', '墙球分组策略', '波比节奏练习'],
      ),
      SportWorkoutTemplate(
        title: 'HYROX 跑站衔接',
        trainingType: TrainingType.hyrox,
        baseMinutes: 55,
        baseIntensity: 'RPE 6-7',
        purpose: '练习跑后动作转换',
        mainSets: <String>['完成 3 轮短跑 + 功能动作组合', '每轮保留 2 次余量'],
      ),
      SportWorkoutTemplate(
        title: 'HYROX 恢复课',
        trainingType: TrainingType.mobility,
        baseMinutes: 30,
        baseIntensity: 'RPE 2-3',
        purpose: '恢复肩髋和下肢',
        mainSets: <String>['低强度单车或步行', '肩髋活动度循环'],
        recovery: true,
      ),
    ];
  }

  @override
  SportWorkoutTemplate secondaryCandidate(SportPlanContext context) =>
      const SportWorkoutTemplate(
        title: '次目标 HYROX 技术',
        trainingType: TrainingType.hyrox,
        baseMinutes: 40,
        baseIntensity: 'RPE 5-6',
        purpose: '用技术课支持 HYROX 次目标',
        mainSets: <String>['低乳酸站点技术循环'],
      );
}

class HyroxPlugin extends SportStrategyPlugin {
  HyroxPlugin({SportPlanStrategy strategy = const HyroxPlanStrategy()})
      : super(strategy);
  @override
  PluginDescriptor get descriptor => PluginDescriptor(
          id: 'sport.hyrox',
          type: PluginType.sport,
          version: strategy.definition.pluginRef.version,
          name: 'HYROX',
          description: 'HYROX候选训练课程、跟练与周报能力',
          workflows: const [
            PluginWorkflowRef(ownerPluginId: 'feature.resource_library', capabilityId: 'feature.resource_library.catalog', label: '基础评估与训练计划资源'),
            PluginWorkflowRef(
                ownerPluginId: 'feature.motion_check',
                capabilityId: 'feature.motion_check.running_review',
                label: 'HYROX 跑步部分视频分析')
          ],
          skills: [
            localSportPlanSkill(
                'sport.hyrox', strategy.definition.pluginRef.version, 'HYROX'),
            cloudSportPlanSkill('sport.hyrox', 'hyrox', 'HYROX',
                fragmentKey: 'hyrox'),
          ],
          capabilities: [
            'sport.hyrox.strategy'
          ]);
}
