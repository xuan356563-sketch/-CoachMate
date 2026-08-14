import '../data/models/body_metric.dart';
import '../data/models/imported_workout.dart';
import '../data/models/pain_log.dart';
import '../data/models/plan_adjustment.dart';
import '../data/models/training_log.dart';
import '../data/models/user_insight.dart';
import '../data/models/user_profile.dart';

class UserInsightService {
  List<ProfileEvent> buildEvents({
    required UserProfile profile,
    required List<TrainingLog> logs,
    required List<BodyMetric> bodyMetrics,
    required List<PainLog> painLogs,
    required List<ImportedWorkout> importedWorkouts,
    required List<PlanAdjustment> planAdjustments,
    required int starterProgramStreak,
  }) {
    final List<ProfileEvent> events = [
      ProfileEvent(
        id: 'event-onboarding-${profile.id}',
        type: ProfileEventType.onboarding,
        title: '已建立基础画像',
        detail:
            '${profile.workerProfileType.label} · ${profile.workScheduleType.label} · 每周 ${profile.weeklyTrainingDays} 练 · 单次 ${profile.dailyAvailableMinutes} 分钟',
        occurredAt: profile.updatedAt,
      ),
      if (starterProgramStreak > 0)
        ProfileEvent(
          id: 'event-starter-$starterProgramStreak',
          type: ProfileEventType.starterProgress,
          title: '30 天引导进度',
          detail: '已累计完成 $starterProgramStreak 天。',
          occurredAt: DateTime.now(),
        ),
      for (final TrainingLog log in logs.take(6))
        ProfileEvent(
          id: 'event-log-${log.id}',
          type: log.completed
              ? ProfileEventType.workoutCompleted
              : ProfileEventType.workoutSkipped,
          title: log.completed ? '记录一次完成' : '记录一次跳过',
          detail: 'RPE ${log.rpe} · ${log.userNote ?? '无备注'}',
          occurredAt: log.createdAt,
        ),
      for (final TrainingLog log in logs.where(
        (TrainingLog item) => (item.userNote ?? '').contains('太累了'),
      ))
        ProfileEvent(
          id: 'event-deload-${log.id}',
          type: ProfileEventType.deloadUsed,
          title: '主动选择降级',
          detail: '系统记录到“太累了”，后续安排会更保守。',
          occurredAt: log.createdAt,
        ),
      for (final BodyMetric metric in bodyMetrics.take(3))
        ProfileEvent(
          id: 'event-body-${metric.id}',
          type: ProfileEventType.bodyMetric,
          title: '身体数据更新',
          detail:
              '睡眠 ${metric.sleepHours.toStringAsFixed(1)} h · HRV ${metric.hrvMs} ms · 疲劳 ${metric.fatigueLevel}/10',
          occurredAt: metric.measuredAt,
        ),
      for (final PainLog log in painLogs.where(
        (PainLog item) => item.requiresMedicalAttention,
      ))
        ProfileEvent(
          id: 'event-pain-${log.id}',
          type: ProfileEventType.painRedline,
          title: '安全红线触发',
          detail: '${log.medicalAttentionReason}，训练自动切换为休息/就医提示。',
          occurredAt: log.createdAt,
        ),
      for (final ImportedWorkout workout in importedWorkouts.take(3))
        ProfileEvent(
          id: 'event-import-${workout.id}',
          type: ProfileEventType.activityImport,
          title: '导入真实训练',
          detail: '${workout.source.label} · ${workout.summary}',
          occurredAt: workout.startedAt,
        ),
      for (final PlanAdjustment adjustment in planAdjustments.take(6))
        ProfileEvent(
          id: 'event-plan-adjustment-${adjustment.id}',
          type: ProfileEventType.planAdjustment,
          title: adjustment.kind.label,
          detail: adjustment.isActive
              ? '${adjustment.workoutTitle}：${adjustment.originalEstimatedMinutes} 分钟 / ${adjustment.originalIntensity} 调整为 ${adjustment.adjustedEstimatedMinutes} 分钟 / ${adjustment.adjustedIntensity}；${adjustment.reason}'
              : '${adjustment.workoutTitle}：已恢复 ${adjustment.originalEstimatedMinutes} 分钟 / ${adjustment.originalIntensity}；${adjustment.reason}',
          occurredAt: adjustment.adjustedAt,
        ),
    ];

    events.sort((ProfileEvent a, ProfileEvent b) {
      return b.occurredAt.compareTo(a.occurredAt);
    });
    return events;
  }

  List<UserProfileInsight> buildInsights({
    required UserProfile profile,
    required List<TrainingLog> logs,
    required List<BodyMetric> bodyMetrics,
    required List<PainLog> painLogs,
    required List<ImportedWorkout> importedWorkouts,
    required int starterProgramStreak,
    required int readinessScore,
    required String trainingStatusLabel,
  }) {
    final int signalCount = logs.length +
        bodyMetrics.length +
        painLogs.length +
        importedWorkouts.length +
        starterProgramStreak;
    final double baseConfidence = _confidence(signalCount, min: 0.42);
    final int completedLogs =
        logs.where((TrainingLog log) => log.completed).length;
    final double completionConfidence = _confidence(logs.length, min: 0.35);
    final double completionRate =
        logs.isEmpty ? 0 : completedLogs / logs.length;
    final double averageFatigue = bodyMetrics.isEmpty
        ? 0
        : bodyMetrics
                .map((BodyMetric metric) => metric.fatigueLevel)
                .reduce((int a, int b) => a + b) /
            bodyMetrics.length;
    final bool hasPainRedline =
        painLogs.any((PainLog log) => log.requiresMedicalAttention);

    return [
      UserProfileInsight(
        id: 'basic-schedule',
        dimension: UserInsightDimension.basic,
        title: '现实训练窗口',
        conclusion:
            '你当前属于${profile.workerProfileType.label}，更适合每周 ${profile.weeklyTrainingDays} 次、单次 ${profile.dailyAvailableMinutes} 分钟以内的安排。',
        confidence: baseConfidence,
        evidenceLabels: [
          '初始问卷',
          profile.workerProfileType.label,
          profile.workScheduleType.label,
          '目标：${profile.trainingGoal}',
        ],
        conservativeAction:
            baseConfidence < 0.65 ? '数据还少，先不自动增加训练天数。' : '可在完成率稳定后尝试小幅加量。',
      ),
      UserProfileInsight(
        id: 'behavior-completion',
        dimension: UserInsightDimension.behavior,
        title: '执行稳定性',
        conclusion: logs.isEmpty
            ? '还没有足够训练记录，暂不判断你的执行节奏。'
            : completionRate >= 0.7
                ? '最近训练完成率较稳定，适合保持当前节奏。'
                : '最近执行记录仍偏少，先降低计划摩擦比加量更重要。',
        confidence: completionConfidence,
        evidenceLabels: [
          'workout_logs ${logs.length} 条',
          '完成 $completedLogs 次',
          '状态：$trainingStatusLabel',
        ],
        conservativeAction: completionConfidence < 0.65
            ? '继续收集完成/跳过信号，不做高置信度判断。'
            : '下周只增加一个变量，避免过快堆量。',
      ),
      UserProfileInsight(
        id: 'physiology-recovery',
        dimension: UserInsightDimension.physiology,
        title: '恢复敏感度',
        conclusion: bodyMetrics.isEmpty
            ? '还缺少恢复指标，系统会按保守规则安排。'
            : averageFatigue >= 5.5
                ? '近期疲劳偏高，对加班和强度叠加较敏感。'
                : '近期睡眠、HRV 和疲劳相对稳定。',
        confidence: _confidence(bodyMetrics.length, min: 0.38),
        evidenceLabels: [
          'body_metrics ${bodyMetrics.length} 条',
          if (bodyMetrics.isNotEmpty)
            '平均疲劳 ${averageFatigue.toStringAsFixed(1)}/10',
          '准备度 $readinessScore',
        ],
        conservativeAction: '置信度不足或疲劳偏高时，优先给恢复/技术课。',
      ),
      UserProfileInsight(
        id: 'preference-guided',
        dimension: UserInsightDimension.preference,
        title: '偏好：少决策跟练',
        conclusion: importedWorkouts.isNotEmpty || logs.isNotEmpty
            ? '你已经开始用跟练或导入记录强化执行闭环，适合继续把入口前置。'
            : '还没有足够行为信号，暂不收起其他模块。',
        confidence:
            _confidence(logs.length + importedWorkouts.length, min: 0.32),
        evidenceLabels: [
          '跟练/日志 ${logs.length} 条',
          '导入 ${importedWorkouts.length} 条',
          '30 天引导 $starterProgramStreak 天',
        ],
        conservativeAction: '在偏好确认前，继续保留完整入口，不自动隐藏功能。',
      ),
      if (hasPainRedline)
        UserProfileInsight(
          id: 'safety-redline',
          dimension: UserInsightDimension.physiology,
          title: '安全优先级',
          conclusion: '你曾触发疼痛红线，安全红线会优先于任何硬性训练模块。',
          confidence: 0.9,
          evidenceLabels: [
            'rehab_logs 红线',
            '安全 > 康复 > 硬性模块 > 偏好',
          ],
          conservativeAction: '相关部位疼痛未下降前，不恢复高强度或专项训练。',
        ),
    ];
  }

  List<PredictionLog> buildPredictionLogs({
    required int recommendedRecoveryHours,
    required int remainingRecoveryHours,
    required bool hasLatestLog,
    required TrainingLog? latestLog,
    required List<BodyMetric> bodyMetrics,
  }) {
    final DateTime now = DateTime.now();
    final PredictionLog recoveryPrediction = _buildRecoveryPrediction(
      now: now,
      recommendedRecoveryHours: recommendedRecoveryHours,
      remainingRecoveryHours: remainingRecoveryHours,
      hasLatestLog: hasLatestLog,
      latestLog: latestLog,
    );
    final PredictionLog? bodyTrendPrediction =
        _buildBodyTrendPrediction(bodyMetrics);

    return [
      recoveryPrediction,
      if (bodyTrendPrediction != null) bodyTrendPrediction,
    ];
  }

  PredictionLog _buildRecoveryPrediction({
    required DateTime now,
    required int recommendedRecoveryHours,
    required int remainingRecoveryHours,
    required bool hasLatestLog,
    required TrainingLog? latestLog,
  }) {
    final DateTime predictedAt = latestLog?.createdAt ?? now;
    final DateTime dueAt =
        predictedAt.add(Duration(hours: recommendedRecoveryHours));
    final bool due = hasLatestLog && !now.isBefore(dueAt);
    return PredictionLog(
      id: 'prediction-recovery-current',
      predictionType: '恢复时间',
      predictedValue: '建议恢复 $recommendedRecoveryHours 小时',
      actualValue: due
          ? remainingRecoveryHours == 0
              ? '已自动回填：已恢复到可评估'
              : '已自动回填：仍需约 $remainingRecoveryHours 小时'
          : null,
      status: due
          ? remainingRecoveryHours == 0
              ? PredictionStatus.hit
              : PredictionStatus.missed
          : PredictionStatus.pending,
      predictedAt: predictedAt,
      dueAt: dueAt,
    );
  }

  PredictionLog? _buildBodyTrendPrediction(List<BodyMetric> bodyMetrics) {
    if (bodyMetrics.length < 4) {
      return null;
    }
    final List<BodyMetric> sortedMetrics = [...bodyMetrics]..sort(
        (BodyMetric a, BodyMetric b) => a.measuredAt.compareTo(b.measuredAt),
      );
    final List<BodyMetric> anchorMetrics = sortedMetrics.take(3).toList();
    final BodyMetric predictionStart = anchorMetrics.first;
    final BodyMetric predictionEnd = anchorMetrics.last;
    final BodyMetric latestMetric = sortedMetrics.last;
    final double predictedChange =
        predictionEnd.weightKg - predictionStart.weightKg;
    final double actualChange = latestMetric.weightKg - predictionEnd.weightKg;
    final String predictedTrend = _weightTrendLabel(predictedChange);
    final String actualTrend = _weightTrendLabel(actualChange);

    return PredictionLog(
      id: 'prediction-weight-trend-backfilled',
      predictionType: '体重趋势',
      predictedValue: '7 日窗口预期：$predictedTrend',
      actualValue: '已自动回填：$actualTrend（${actualChange.toStringAsFixed(1)} kg）',
      status: predictedTrend == actualTrend
          ? PredictionStatus.hit
          : PredictionStatus.missed,
      predictedAt: predictionEnd.measuredAt,
      dueAt: latestMetric.measuredAt,
    );
  }

  String _weightTrendLabel(double change) {
    if (change <= -0.2) {
      return '缓慢下降';
    }
    if (change >= 0.2) {
      return '缓慢上升';
    }
    return '基本稳定';
  }

  double _confidence(int signalCount, {required double min}) {
    final double value = min + signalCount * 0.06;
    return value.clamp(min, 0.92).toDouble();
  }
}
