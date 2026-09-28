import '../../data/models/workout_day.dart';
import 'sport_workout_template.dart';

/// 首期保留既有跑步素材，马拉松与越野分别拥有身份和赛事策略。
final runningPrimaryTemplates = const <SportWorkoutTemplate>[
  SportWorkoutTemplate(
    title: '低强度有氧跑',
    trainingType: TrainingType.easyRun,
    baseMinutes: 45,
    baseIntensity: 'RPE 4-5',
    purpose: '建立有氧基础',
    mainSets: <String>['轻松跑，保持可以完整说话的强度'],
  ),
  SportWorkoutTemplate(
    title: '跑步质量课',
    trainingType: TrainingType.tempoRun,
    baseMinutes: 45,
    baseIntensity: 'RPE 6-7',
    purpose: '提高稳定配速能力',
    mainSets: <String>['热身后完成 3 组可控节奏跑', '组间慢跑恢复'],
  ),
  SportWorkoutTemplate(
    title: '跑者力量基础',
    trainingType: TrainingType.strength,
    baseMinutes: 45,
    baseIntensity: 'RPE 6',
    purpose: '提高髋膝踝力量耐受',
    mainSets: <String>['深蹲模式 3 组', '髋铰链模式 3 组', '单腿稳定 2 组'],
  ),
  SportWorkoutTemplate(
    title: '周末耐力跑',
    trainingType: TrainingType.longRun,
    baseMinutes: 70,
    baseIntensity: 'RPE 4-6',
    purpose: '积累持续运动时间',
    mainSets: <String>['全程保守完成，不在后半程追配速'],
  ),
  SportWorkoutTemplate(
    title: '跑步活动度恢复',
    trainingType: TrainingType.mobility,
    baseMinutes: 30,
    baseIntensity: 'RPE 2-3',
    purpose: '促进恢复并维护活动度',
    mainSets: <String>['低强度步行', '踝、髋活动度循环'],
    recovery: true,
  ),
];
final runningSecondaryTemplate = const SportWorkoutTemplate(
  title: '次目标跑步技术',
  trainingType: TrainingType.easyRun,
  baseMinutes: 35,
  baseIntensity: 'RPE 4-5',
  purpose: '用低成本跑步支持次目标',
  mainSets: <String>['轻松跑与跑姿技术练习'],
);

/// 减脂与综合健身沿用原基础体能素材，各自仍是独立目标插件。
final fitnessPrimaryTemplates = const <SportWorkoutTemplate>[
  SportWorkoutTemplate(
    title: '全身基础力量',
    trainingType: TrainingType.strength,
    baseMinutes: 45,
    baseIntensity: 'RPE 6',
    purpose: '建立全身力量基础',
    mainSets: <String>['蹲、推、拉各 3 组', '核心稳定 2 组'],
  ),
  SportWorkoutTemplate(
    title: '低强度心肺',
    trainingType: TrainingType.crossTraining,
    baseMinutes: 40,
    baseIntensity: 'RPE 4-5',
    purpose: '建立可恢复的心肺基础',
    mainSets: <String>['选择跑步、单车或椭圆机持续完成'],
  ),
  SportWorkoutTemplate(
    title: '基础体能循环',
    trainingType: TrainingType.crossTraining,
    baseMinutes: 40,
    baseIntensity: 'RPE 5-6',
    purpose: '提高日常体能和动作耐受',
    mainSets: <String>['完成 3 轮低冲击全身循环'],
  ),
  SportWorkoutTemplate(
    title: '活动度恢复',
    trainingType: TrainingType.mobility,
    baseMinutes: 25,
    baseIntensity: 'RPE 2-3',
    purpose: '促进恢复并维持活动度',
    mainSets: <String>['全身活动度循环 3 轮'],
    recovery: true,
  ),
];
final fitnessSecondaryTemplate = const SportWorkoutTemplate(
  title: '次目标基础体能',
  trainingType: TrainingType.crossTraining,
  baseMinutes: 35,
  baseIntensity: 'RPE 4-5',
  purpose: '用基础体能课支持次目标',
  mainSets: <String>['低冲击全身循环 3 轮'],
);
