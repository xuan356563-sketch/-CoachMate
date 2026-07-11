import '../data/models/user_insight.dart';
import '../data/models/user_trust_review.dart';

class UserTrustReviewService {
  UserTrustReviewReport buildReport({
    required List<PredictionLog> predictionLogs,
    required List<UserProfileInsight> insights,
    required List<ProfileEvent> events,
    required String recoveryAdvice,
    required String achievementSummaryLabel,
  }) {
    final List<PredictionLog> settledPredictions = predictionLogs
        .where(
          (PredictionLog log) => log.status != PredictionStatus.pending,
        )
        .toList();
    final int hitCount = settledPredictions
        .where((PredictionLog log) => log.status == PredictionStatus.hit)
        .length;
    final int lowConfidenceCount = insights
        .where((UserProfileInsight insight) => insight.lowConfidence)
        .length;

    return UserTrustReviewReport(
      predictionAccuracyLabel: settledPredictions.isEmpty
          ? '样本不足'
          : '${((hitCount / settledPredictions.length) * 100).round()}%',
      predictionAccuracyDetail: settledPredictions.isEmpty
          ? '预测对账还没有到期样本，当前只展示待回填记录，不伪装准确率。'
          : '已对账 ${settledPredictions.length} 条预测，命中 $hitCount 条，偏差会继续保留给用户查看。',
      uncertaintyLabel:
          lowConfidenceCount == 0 ? '置信度稳定' : '$lowConfidenceCount 条仍不确定',
      uncertaintyDetail: lowConfidenceCount == 0
          ? '当前画像结论已有较多证据，仍会保留“不准可改”的入口。'
          : '系统会明确标出低置信结论，并用保守策略替代自信判断。',
      dataOwnershipLabel: '本地保存',
      dataOwnershipDetail: '画像、预测对账和兑现回顾均来自本机状态；当前 MVP 不上传用户画像。',
      reviewItems: _buildReviewItems(
        events: events,
        recoveryAdvice: recoveryAdvice,
        achievementSummaryLabel: achievementSummaryLabel,
      ),
    );
  }

  List<TrustReviewItem> _buildReviewItems({
    required List<ProfileEvent> events,
    required String recoveryAdvice,
    required String achievementSummaryLabel,
  }) {
    final bool hasDeload = events.any(
      (ProfileEvent event) => event.type == ProfileEventType.deloadUsed,
    );
    final bool hasPainRedline = events.any(
      (ProfileEvent event) => event.type == ProfileEventType.painRedline,
    );
    final bool hasBodyMetric = events.any(
      (ProfileEvent event) => event.type == ProfileEventType.bodyMetric,
    );

    return [
      TrustReviewItem(
        title: hasDeload ? '系统尊重了疲劳反馈' : '保留疲劳降级入口',
        detail: hasDeload
            ? '你反馈“太累了”后，系统已把后续安排转为更保守的版本。'
            : '跟练和今日训练仍保留“太累了”入口，避免用户硬扛。',
        evidenceLabel: hasDeload
            ? 'profile_events: deload_used'
            : 'workout_player controls',
      ),
      TrustReviewItem(
        title: hasPainRedline ? '安全红线已生效' : '安全红线待触发',
        detail: hasPainRedline
            ? '疼痛红线优先于训练计划，相关部位会停止训练并提示就医。'
            : '当前没有高等级疼痛事件；若疼痛 ≥7，康复约束会优先接管。',
        evidenceLabel:
            hasPainRedline ? 'rehab_logs pain_redline' : 'rehab rule',
      ),
      TrustReviewItem(
        title: hasBodyMetric ? '身体数据正在被消费' : '等待身体数据',
        detail: hasBodyMetric
            ? '晨间报告、恢复倒计时、趋势洞察和精简签到都在读取身体数据。'
            : '完成一次身体数据记录后，系统才会减少问题并更新趋势判断。',
        evidenceLabel: hasBodyMetric
            ? 'body_metrics + daily_checkins'
            : 'body_metrics missing',
      ),
      TrustReviewItem(
        title: '恢复建议可复核',
        detail: recoveryAdvice,
        evidenceLabel: 'prediction_logs recovery_time',
      ),
      TrustReviewItem(
        title: '成就兑现',
        detail: achievementSummaryLabel,
        evidenceLabel: 'achievements progress',
      ),
    ];
  }
}
