import '../data/models/meal_guide.dart';
import '../data/models/pain_log.dart';
import '../data/models/training_log.dart';
import '../data/models/user_profile.dart';
import '../data/models/workout_day.dart';

class AiTrainingService {
  List<String> buildMockCoachAdvice({
    required UserProfile profile,
    required WorkoutDay todayWorkout,
    MealGuide? todayMealGuide,
    TrainingLog? latestLog,
    PainLog? latestPainLog,
  }) {
    final List<String> advice = [
      '今日决策为${todayWorkout.decisionType.label}：依据训练目标、可用时间和当前风险，优先安排 ${todayWorkout.title}。',
      '今天按 ${todayWorkout.intensity} 执行，先保证动作质量和完成率。',
      '你每周计划训练 ${profile.weeklyTrainingDays} 天，建议至少保留 1 天完全恢复。',
      '当前分型：${profile.workerProfileType.label}。${profile.workerProfileType.strategy}',
    ];

    if (_isCompetitiveProfile(profile)) {
      advice.add('竞技型决策口径：优先观察配速、阈值、跑量和比赛表现，不用单次状态推翻整个周期。');
    } else if (_isFatLossProfile(profile)) {
      advice.add('减脂型决策口径：优先看坚持率、关节安全和可持续消耗，不用短期体重波动调整训练。');
    }

    if (profile.injuryHistory.isNotEmpty) {
      advice.add('存在 ${profile.injuryHistory.join('、')}，热身和冷身不要省略。');
    }

    if (todayMealGuide != null) {
      advice.add(
          '今日照吃卡按${todayMealGuide.scenario.label}场景执行：${todayMealGuide.instruction}');
    }

    if (latestPainLog != null) {
      if (latestPainLog.requiresMedicalAttention) {
        advice.add(
          '${latestPainLog.medicalAttentionReason}，已触发就医红线：停止相关训练，优先联系医生或物理治疗师。',
        );
      } else if (latestPainLog.shouldDeloadTraining) {
        advice.add(
          '${latestPainLog.bodyPart}疼痛 ${latestPainLog.painLevel}/10，今日训练已自动降级为恢复课；动作必须保持无痛范围。',
        );
      }
    }

    if (latestLog != null) {
      if (latestLog.rpe >= 8 || latestLog.fatigueLevel >= 7) {
        advice.add('最近反馈强度偏高，下一次训练建议降低一档强度或缩短 10-15 分钟。');
      } else if (latestLog.completed) {
        advice.add('最近训练完成度不错，可以维持当前节奏，不急着加量。');
      }
    }

    return advice;
  }

  bool _isCompetitiveProfile(UserProfile profile) {
    return profile.workerProfileType == WorkerProfileType.racePrepWorker ||
        profile.mainSports.any(
          (MainSport sport) =>
              sport == MainSport.marathon ||
              sport == MainSport.trailRunning ||
              sport == MainSport.hyrox,
        );
  }

  bool _isFatLossProfile(UserProfile profile) {
    return profile.workerProfileType == WorkerProfileType.unstableDiet ||
        profile.mainSports.contains(MainSport.fatLoss) ||
        profile.trainingGoal.contains('减脂');
  }
}
