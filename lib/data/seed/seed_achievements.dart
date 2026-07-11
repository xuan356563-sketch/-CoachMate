import '../models/achievement.dart';

const List<AchievementDefinition> seedAchievements = [
  AchievementDefinition(
    id: 'first_workout_player',
    title: '首次跟练',
    description: '完成一次跟练播放器步骤，训练不再停留在文字清单。',
    category: AchievementCategory.execution,
    targetValue: 1,
  ),
  AchievementDefinition(
    id: 'listen_to_body',
    title: '听身体的',
    description: '练中主动选择“太累了”，把剩余内容降级。',
    category: AchievementCategory.safety,
    targetValue: 1,
  ),
  AchievementDefinition(
    id: 'starter_day_one',
    title: '新手第一天',
    description: '完成 30 天渐进引导的第一天。',
    category: AchievementCategory.consistency,
    targetValue: 1,
  ),
  AchievementDefinition(
    id: 'seven_day_streak',
    title: '连续 7 天',
    description: '30 天引导连续完成 7 天。',
    category: AchievementCategory.consistency,
    targetValue: 7,
  ),
  AchievementDefinition(
    id: 'thirty_day_streak',
    title: '连续 30 天',
    description: '完成 30 天渐进引导，准备进入正式 AI 计划。',
    category: AchievementCategory.consistency,
    targetValue: 30,
  ),
  AchievementDefinition(
    id: 'body_data_first',
    title: '身体数据起步',
    description: '完成一次身体数据记录，让训练决策有数据地基。',
    category: AchievementCategory.bodyData,
    targetValue: 1,
  ),
  AchievementDefinition(
    id: 'safety_redline',
    title: '安全红线识别',
    description: '疼痛达到红线时停止相关训练并切换就医提示。',
    category: AchievementCategory.safety,
    targetValue: 1,
  ),
];
