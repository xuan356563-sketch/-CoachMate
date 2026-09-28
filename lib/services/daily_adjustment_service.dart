import '../data/models/body_metric.dart';
import '../data/models/daily_adjustment.dart';
import '../data/models/motion_check.dart';
import '../data/models/pain_log.dart';
import '../data/models/workout_day.dart';

class DailyAdjustmentService {
  DailyAdjustmentDecision buildDecision({
    required WorkoutDay baseWorkout,
    required int availableMinutes,
    required WorkStressLevel workStress,
    required TrainingEnvironment environment,
    required WeatherCondition weather,
    required BodyMetric? latestBodyMetric,
    required PainLog? latestPainLog,
    required MotionAnalysisResult? latestMotionAnalysisResult,
    required int? readinessScore,
  }) {
    // 历史、演示和不完整分析仍可阅读，但不得成为训练调整证据。
    if (!(latestMotionAnalysisResult?.usableForDecision ?? false)) {
      latestMotionAnalysisResult = null;
    }
    final List<String> badges = [
      '$availableMinutes 分钟',
      workStress.label,
      environment.label,
      weather.label,
    ];
    final int baseMinutes = baseWorkout.estimatedMinutes;
    final int fatigueLevel = latestBodyMetric?.hasValue('fatigueLevel') == true ? latestBodyMetric!.fatigueLevel : 0;

    if (latestPainLog?.requiresMedicalAttention ?? false) {
      return DailyAdjustmentDecision(
        decisionType: TrainingDecisionType.rest,
        availableMinutes: availableMinutes,
        workStress: workStress,
        environment: environment,
        weather: weather,
        decisionLabel: '疼痛红线',
        reason: '${latestPainLog!.medicalAttentionReason}，安全规则优先于训练目标。',
        adjustedMinutes: 0,
        planChangeSummary: '停止相关训练，保留记录和就医/康复评估提醒。',
        constraintBadges: badges,
        adjustments: const [
          '取消今日主训练和高冲击动作',
          '只记录疼痛位置、等级和出现时机',
          '疼痛持续或加重时联系医生或物理治疗师',
        ],
      );
    }

    if ((latestPainLog?.painLevel ?? 0) >= 4 ||
        (readinessScore != null && readinessScore < 55) ||
        fatigueLevel >= 7) {
      return DailyAdjustmentDecision(
        decisionType: TrainingDecisionType.recovery,
        availableMinutes: availableMinutes,
        workStress: workStress,
        environment: environment,
        weather: weather,
        decisionLabel: '恢复版',
        reason: '疼痛、准备度或疲劳信号提示今天不适合硬推。',
        adjustedMinutes: availableMinutes.clamp(15, 30).toInt(),
        planChangeSummary: '把主训练改为低强度恢复、活动度和轻松有氧。',
        constraintBadges: badges,
        adjustments: const [
          '主训练强度压到 RPE 2-3',
          '保留无痛活动度和呼吸放松',
          '训练后复测疼痛和疲劳',
        ],
      );
    }

    if (environment == TrainingEnvironment.outdoor &&
        weather != WeatherCondition.good) {
      return DailyAdjustmentDecision(
        decisionType: TrainingDecisionType.recovery,
        availableMinutes: availableMinutes,
        workStress: workStress,
        environment: environment,
        weather: weather,
        decisionLabel: '室内替代',
        reason: '户外场景叠加${weather.label}，今天先规避环境风险。',
        adjustedMinutes: availableMinutes.clamp(20, 35).toInt(),
        planChangeSummary: '改为室内低压有氧、灵活性或技术练习。',
        constraintBadges: badges,
        adjustments: const [
          '取消户外强度段',
          '使用室内低冲击替代',
          '保留热身、激活和冷身',
        ],
      );
    }

    if (workStress == WorkStressLevel.extreme) {
      return DailyAdjustmentDecision(
        decisionType: TrainingDecisionType.recovery,
        availableMinutes: availableMinutes,
        workStress: workStress,
        environment: environment,
        weather: weather,
        decisionLabel: '高压恢复',
        reason: '工作压力已爆表，今天优先降低总压力而不是叠加强刺激。',
        adjustedMinutes: availableMinutes.clamp(15, 30).toInt(),
        planChangeSummary: '保留最低剂量训练，跳过高强度和复杂动作。',
        constraintBadges: badges,
        adjustments: const [
          '总时长控制在 30 分钟内',
          '用轻松有氧或灵活性替代强度课',
          '完成后不补课，只记录状态',
        ],
      );
    }

    if (latestMotionAnalysisResult != null &&
        latestMotionAnalysisResult.suggestedImpact ==
            TrainingDecisionImpact.technique) {
      return DailyAdjustmentDecision(
        decisionType: TrainingDecisionType.technique,
        availableMinutes: availableMinutes,
        workStress: workStress,
        environment: environment,
        weather: weather,
        decisionLabel: '动作技术日',
        reason: latestMotionAnalysisResult.decisionImpact,
        adjustedMinutes: availableMinutes.clamp(20, baseMinutes).toInt(),
        planChangeSummary: '暂停高风险动作强度，改做纠错、退阶和低冲击替代。',
        constraintBadges: [
          ...badges,
          latestMotionAnalysisResult.riskLevel.label,
        ],
        adjustments: [
          '处理${latestMotionAnalysisResult.detectedErrors.join('、')}',
          '重点区域：${latestMotionAnalysisResult.involvedAreas.join('、')}',
          '替代动作：${latestMotionAnalysisResult.replacementActions.join(' / ')}',
        ],
      );
    }

    if (latestMotionAnalysisResult != null &&
        latestMotionAnalysisResult.suggestedImpact ==
            TrainingDecisionImpact.deload) {
      return DailyAdjustmentDecision(
        decisionType: TrainingDecisionType.deload,
        availableMinutes: availableMinutes,
        workStress: workStress,
        environment: environment,
        weather: weather,
        decisionLabel: '动作降级',
        reason: latestMotionAnalysisResult.decisionImpact,
        adjustedMinutes: availableMinutes.clamp(20, baseMinutes).toInt(),
        planChangeSummary: '保留训练结构，但按动作纠错结果降低组数、强度或动作难度。',
        constraintBadges: [
          ...badges,
          latestMotionAnalysisResult.riskLevel.label,
        ],
        adjustments: [
          '先做${latestMotionAnalysisResult.replacementActions.join(' / ')}',
          '主训练保持可控节奏',
          '训练后复盘动作质量和疼痛变化',
        ],
      );
    }

    if (workStress == WorkStressLevel.high) {
      return DailyAdjustmentDecision(
        decisionType: TrainingDecisionType.deload,
        availableMinutes: availableMinutes,
        workStress: workStress,
        environment: environment,
        weather: weather,
        decisionLabel: '降级版',
        reason: '工作压力偏高，今天降低训练刺激，避免把生活压力和训练压力叠满。',
        adjustedMinutes: availableMinutes.clamp(20, baseMinutes).toInt(),
        planChangeSummary: '保留训练结构，把主训练组数和强度下调一级。',
        constraintBadges: badges,
        adjustments: const [
          '主训练组数减少一组',
          '目标强度下调到可完整说话',
          '辅助训练只保留最关键动作',
        ],
      );
    }

    if (availableMinutes < baseMinutes * 0.6) {
      return DailyAdjustmentDecision(
        decisionType: TrainingDecisionType.technique,
        availableMinutes: availableMinutes,
        workStress: workStress,
        environment: environment,
        weather: weather,
        decisionLabel: '缩短版',
        reason: '今日可用时间不足原计划 60%，需要保留关键动作而不是压缩休息。',
        adjustedMinutes: availableMinutes.clamp(15, baseMinutes).toInt(),
        planChangeSummary: '只做热身、一个主训练重点和冷身反馈。',
        constraintBadges: badges,
        adjustments: const [
          '删除辅助训练',
          '主训练只保留一个重点',
          '不压缩必要热身和冷身',
        ],
      );
    }

    if (environment == TrainingEnvironment.noEquipment) {
      return DailyAdjustmentDecision(
        decisionType: TrainingDecisionType.technique,
        availableMinutes: availableMinutes,
        workStress: workStress,
        environment: environment,
        weather: weather,
        decisionLabel: '无器械版',
        reason: '当前没有器械，训练目标改为动作质量和连续性。',
        adjustedMinutes: availableMinutes.clamp(20, baseMinutes).toInt(),
        planChangeSummary: '用自重动作替代器械动作，保留训练五步。',
        constraintBadges: badges,
        adjustments: const [
          '器械力量改为自重版本',
          '增加节奏控制和动作质量提示',
          '跳过无法安全替代的动作',
        ],
      );
    }

    if ((readinessScore != null && readinessScore >= 82) && workStress == WorkStressLevel.normal) {
      return DailyAdjustmentDecision(
        decisionType: TrainingDecisionType.normal,
        availableMinutes: availableMinutes,
        workStress: workStress,
        environment: environment,
        weather: weather,
        decisionLabel: '小幅推进',
        reason: '准备度充足且现实约束可控，可以按计划推进但不追求额外加量。',
        adjustedMinutes: baseMinutes.clamp(0, availableMinutes).toInt(),
        planChangeSummary: '按原计划执行，最多只增加一个很小变量。',
        constraintBadges: badges,
        adjustments: const [
          '按原训练五步执行',
          '主训练保持动作质量优先',
          '如果 RPE 提前升高，立即回到原计划',
        ],
      );
    }

    return DailyAdjustmentDecision(
      decisionType: TrainingDecisionType.normal,
      availableMinutes: availableMinutes,
      workStress: workStress,
      environment: environment,
      weather: weather,
      decisionLabel: readinessScore == null ? '待确认状态' : '按计划',
      reason: readinessScore == null ? '缺少当日确认或有效身体记录，无法评估准备度；计划未改变。' : '当前身体状态和现实约束没有触发降级规则。',
      adjustedMinutes: baseMinutes.clamp(0, availableMinutes).toInt(),
      planChangeSummary: '保持今日训练内容，按反馈决定是否记录降级。',
      constraintBadges: badges,
      adjustments: const [
        '按今日训练五步执行',
        '保留训练后反馈',
        '若疼痛或疲劳上升，切回恢复版',
      ],
    );
  }
}
