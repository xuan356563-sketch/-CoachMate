import '../data/models/body_metric.dart';
import '../data/models/starter_graduation_report.dart';
import '../data/models/starter_program.dart';
import '../data/models/training_log.dart';

class StarterGraduationService {
  StarterGraduationReport buildReport({
    required StarterProgramGoal goal,
    required int starterProgramStreak,
    required int starterProgramDayIndex,
    required String starterProgramStatusMessage,
    required List<BodyMetric> bodyMetrics,
    required List<TrainingLog> logs,
    required int? readinessScore,
    required String readinessLabel,
    required String trainingStatusLabel,
  }) {
    final DateTime now = DateTime.now();
    const int totalDays = 30;
    final int completedDays = starterProgramStreak.clamp(0, totalDays).toInt();
    final bool readyForFormalPlan = completedDays >= totalDays;
    final _HeartRateTrend heartRateTrend = _buildHeartRateTrend(bodyMetrics);
    final _SubjectiveTrend subjectiveTrend = _buildSubjectiveTrend(
      logs: logs,
      starterProgramStreak: starterProgramStreak,
      starterProgramStatusMessage: starterProgramStatusMessage,
    );

    return StarterGraduationReport(
      id: 'starter-graduation-${now.millisecondsSinceEpoch}',
      generatedAt: now,
      completedDays: completedDays,
      totalDays: totalDays,
      completionRate: completedDays / totalDays,
      goalLabel: goal.label,
      abilitySummary: _abilitySummary(
        completedDays: completedDays,
        starterProgramDayIndex: starterProgramDayIndex,
        readyForFormalPlan: readyForFormalPlan,
      ),
      heartRateTrendLabel: heartRateTrend.label,
      heartRateTrendDetail: heartRateTrend.detail,
      subjectiveTrendLabel: subjectiveTrend.label,
      subjectiveTrendDetail: subjectiveTrend.detail,
      readinessLabel: readinessLabel,
      readinessScore: readinessScore,
      recommendedNextPlan: _recommendedNextPlan(goal, trainingStatusLabel),
      transitionSummary: _transitionSummary(
        readyForFormalPlan: readyForFormalPlan,
        trainingStatusLabel: trainingStatusLabel,
        readinessScore: readinessScore,
      ),
      readyForFormalPlan: readyForFormalPlan,
    );
  }

  String _abilitySummary({
    required int completedDays,
    required int starterProgramDayIndex,
    required bool readyForFormalPlan,
  }) {
    if (readyForFormalPlan) {
      return '已完成 30 天渐进引导和毕业测试，具备进入正式 AI 个性化周期的基础。';
    }
    if (completedDays >= 21) {
      return '已进入第 4 周成型阶段，剩余重点是完成 28-30 天毕业测试。';
    }
    if (completedDays >= 7) {
      return '已建立基本执行节奏，当前第 $starterProgramDayIndex 天仍以稳定执行优先。';
    }
    return '当前还在冷启动阶段，能力评估先保守，只看完成率和恢复信号。';
  }

  _HeartRateTrend _buildHeartRateTrend(List<BodyMetric> bodyMetrics) {
    if (bodyMetrics.isEmpty) {
      return const _HeartRateTrend(
        label: '等待数据',
        detail: '还没有心率或 HRV 记录，毕业报告会先用完成率和主观反馈做保守判断。',
      );
    }

    final List<BodyMetric> sortedMetrics = [...bodyMetrics]..sort(
        (BodyMetric a, BodyMetric b) => a.measuredAt.compareTo(b.measuredAt),
      );
    final BodyMetric earliest = sortedMetrics.first;
    final BodyMetric latest = sortedMetrics.last;

    if (sortedMetrics.length == 1) {
      return _HeartRateTrend(
        label: '已有基线',
        detail:
            '当前静息心率 ${latest.restingHeartRate} bpm，HRV ${latest.hrvMs} ms；再记录一次后可判断变化趋势。',
      );
    }

    final int restingHrChange =
        latest.restingHeartRate - earliest.restingHeartRate;
    final int hrvChange = latest.hrvMs - earliest.hrvMs;

    if (restingHrChange <= -2 && hrvChange >= 2) {
      return _HeartRateTrend(
        label: '恢复改善',
        detail:
            '静息心率下降 ${restingHrChange.abs()} bpm，HRV 上升 $hrvChange ms，恢复信号支持进入正式周期。',
      );
    }
    if (restingHrChange >= 4 || hrvChange <= -4) {
      return _HeartRateTrend(
        label: '压力上升',
        detail:
            '静息心率变化 $restingHrChange bpm，HRV 变化 $hrvChange ms，正式周期应先安排 1 周恢复过渡。',
      );
    }
    return _HeartRateTrend(
      label: '基本稳定',
      detail: '静息心率变化 $restingHrChange bpm，HRV 变化 $hrvChange ms，当前恢复趋势适合小坡度衔接。',
    );
  }

  _SubjectiveTrend _buildSubjectiveTrend({
    required List<TrainingLog> logs,
    required int starterProgramStreak,
    required String starterProgramStatusMessage,
  }) {
    if (starterProgramStatusMessage.contains('太累了') ||
        starterProgramStatusMessage.contains('疲劳')) {
      return const _SubjectiveTrend(
        label: '压力偏高',
        detail: '最近反馈出现“太累了”或疲劳信号，正式周期首周应降低强度。',
      );
    }
    if (starterProgramStatusMessage.contains('刚好') ||
        starterProgramStatusMessage.contains('毕业测试')) {
      return const _SubjectiveTrend(
        label: '可持续',
        detail: '最近反馈接近“刚好”，说明当前坡度能被稳定执行。',
      );
    }
    if (starterProgramStatusMessage.contains('太轻松')) {
      return const _SubjectiveTrend(
        label: '可小幅加量',
        detail: '最近反馈偏轻松，正式周期可以只增加一个变量：时长、组数或动作难度三选一。',
      );
    }

    if (logs.isEmpty) {
      if (starterProgramStreak > 0) {
        return _SubjectiveTrend(
          label: '执行积累',
          detail: '已累计完成 $starterProgramStreak 天；主观量表记录不足，仍按保守坡度衔接。',
        );
      }
      return const _SubjectiveTrend(
        label: '等待反馈',
        detail: '还没有足够的训练后反馈，先不把强度判断说满。',
      );
    }

    final Iterable<TrainingLog> recentLogs = logs.take(10);
    final double averageRpe =
        recentLogs.fold<double>(0, (double total, TrainingLog log) {
              return total + log.rpe;
            }) /
            recentLogs.length;

    if (averageRpe >= 8) {
      return _SubjectiveTrend(
        label: '压力偏高',
        detail: '最近训练平均 RPE ${averageRpe.toStringAsFixed(1)}，正式周期先降强度。',
      );
    }
    if (averageRpe <= 5.5) {
      return _SubjectiveTrend(
        label: '可小幅加量',
        detail: '最近训练平均 RPE ${averageRpe.toStringAsFixed(1)}，可尝试小幅渐进。',
      );
    }
    return _SubjectiveTrend(
      label: '可持续',
      detail: '最近训练平均 RPE ${averageRpe.toStringAsFixed(1)}，主观压力处在可持续区间。',
    );
  }

  String _recommendedNextPlan(
    StarterProgramGoal goal,
    String trainingStatusLabel,
  ) {
    final String basePlan = switch (goal) {
      StarterProgramGoal.habit => '正式 AI 个性化基础周期',
      StarterProgramGoal.fatLoss => '正式 AI 减脂基础周期',
      StarterProgramGoal.runningIntro => '正式 AI 跑步入门周期',
    };

    if (trainingStatusLabel == '过度风险' || trainingStatusLabel == '恢复中') {
      return '恢复过渡 + $basePlan';
    }
    return basePlan;
  }

  String _transitionSummary({
    required bool readyForFormalPlan,
    required String trainingStatusLabel,
    required int? readinessScore,
  }) {
    if (!readyForFormalPlan) {
      return '当前是毕业报告预览；完成第 30 天后，系统会按完成率、心率变化和主观趋势解锁正式周期。';
    }
    if (trainingStatusLabel == '过度风险' || (readinessScore != null && readinessScore < 60)) {
      return '已达到毕业门槛，但恢复压力偏高，正式周期首周从恢复过渡开始，不直接加量。';
    }
    return '已达到毕业门槛，正式周期从当前能力和恢复状态无缝接上，不重新问一遍基础问题。';
  }
}

class _HeartRateTrend {
  final String label;
  final String detail;

  const _HeartRateTrend({
    required this.label,
    required this.detail,
  });
}

class _SubjectiveTrend {
  final String label;
  final String detail;

  const _SubjectiveTrend({
    required this.label,
    required this.detail,
  });
}
