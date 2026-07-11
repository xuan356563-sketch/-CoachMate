import '../data/models/body_metric.dart';
import '../data/models/training_log.dart';
import '../data/models/user_profile.dart';
import '../data/models/weekly_report.dart';
import '../data/models/workout_day.dart';

class WeeklyReportService {
  WeeklyReport buildWeeklyReport({
    required UserProfile profile,
    required WorkoutDay todayWorkout,
    required List<TrainingLog> logs,
    required List<BodyMetric> bodyMetrics,
    required int readinessScore,
    required String trainingStatusLabel,
    required String trainingStatusReason,
    required String recoveryCountdownLabel,
    required String recoveryAdvice,
    required String achievementSummaryLabel,
  }) {
    final DateTime now = DateTime.now();
    final DateTime weekStart = now.subtract(Duration(days: now.weekday - 1));
    final List<TrainingLog> recentLogs = logs
        .where(
          (TrainingLog log) =>
              log.isSessionRecord && now.difference(log.createdAt).inDays < 7,
        )
        .toList();
    final int plannedWorkouts = profile.weeklyTrainingDays.clamp(1, 7).toInt();
    final double completedWorkoutUnits = recentLogs.fold<double>(
      0,
      (double total, TrainingLog log) =>
          total + log.normalizedCompletionPercentage / 100,
    );
    final int completedWorkouts =
        completedWorkoutUnits.round().clamp(0, plannedWorkouts).toInt();
    final double completionRate =
        (completedWorkoutUnits / plannedWorkouts).clamp(0, 1);
    final String loadTrendLabel = _loadTrendLabel(
      statusLabel: trainingStatusLabel,
      completionRate: completionRate,
      recentLogs: recentLogs,
      bodyMetrics: bodyMetrics,
    );

    return WeeklyReport(
      id: 'weekly-report-${now.millisecondsSinceEpoch}',
      weekLabel: _weekLabel(weekStart),
      generatedAt: now,
      completedWorkouts: completedWorkouts,
      plannedWorkouts: plannedWorkouts,
      completionRate: completionRate,
      loadTrendLabel: loadTrendLabel,
      decisionReview:
          '本周主判断为${todayWorkout.decisionType.label}：$trainingStatusReason',
      recoverySummary: '$recoveryCountdownLabel。$recoveryAdvice',
      highlights: _highlights(
        recentLogs: recentLogs,
        bodyMetrics: bodyMetrics,
        achievementSummaryLabel: achievementSummaryLabel,
      ),
      nextWeekFocus: _nextWeekFocus(
        statusLabel: trainingStatusLabel,
        readinessScore: readinessScore,
        completionRate: completionRate,
        todayWorkout: todayWorkout,
      ),
    );
  }

  String _loadTrendLabel({
    required String statusLabel,
    required double completionRate,
    required List<TrainingLog> recentLogs,
    required List<BodyMetric> bodyMetrics,
  }) {
    final bool hasHardLog = recentLogs.any((TrainingLog log) => log.rpe >= 8);
    final bool fatigueHigh = bodyMetrics
        .take(3)
        .any((BodyMetric metric) => metric.fatigueLevel >= 6);

    if (statusLabel == '过度风险' || hasHardLog || fatigueHigh) {
      return '负荷偏高';
    }
    if (completionRate >= 0.75 && statusLabel == '进步中') {
      return '稳步上升';
    }
    if (completionRate == 0) {
      return '等待执行记录';
    }
    return '维持稳定';
  }

  List<String> _highlights({
    required List<TrainingLog> recentLogs,
    required List<BodyMetric> bodyMetrics,
    required String achievementSummaryLabel,
  }) {
    final List<String> items = [
      achievementSummaryLabel,
      '身体数据已有 ${bodyMetrics.length} 条，可支撑 7 日趋势判断。',
    ];

    if (recentLogs.isEmpty) {
      items.add('本周还缺少执行记录，完成跟练后周报会更准确。');
    } else {
      items.add('本周记录了 ${recentLogs.length} 条训练会话。');
      if (recentLogs
          .any((TrainingLog log) => log.userNote?.contains('太累了') ?? false)) {
        items.add('练中出现疲劳反馈时已触发降级，安全优先。');
      }
    }

    return items;
  }

  List<String> _nextWeekFocus({
    required String statusLabel,
    required int readinessScore,
    required double completionRate,
    required WorkoutDay todayWorkout,
  }) {
    if (statusLabel == '过度风险' || readinessScore < 60) {
      return [
        '下周先把高强度课减少 1 次，保留低强度有氧和灵活性。',
        '每次训练后继续记录 RPE、睡眠和疼痛，优先把恢复拉回稳定。',
        '正式训练仍从泡沫轴、动态拉伸和激活开始。',
      ];
    }

    if (completionRate < 0.5) {
      return [
        '先把完成率拉到 50% 以上，不急着加量。',
        '保留 30 天引导或 5 分钟补救版，减少漏练后的挫败感。',
        '下周主训练继续围绕 ${todayWorkout.trainingType.label}，但时长保持可执行。',
      ];
    }

    return [
      '保持当前节奏，下周只增加一个变量：时长、组数或动作难度三选一。',
      '高强度课前先看恢复倒计时，未恢复时改为技术或恢复课。',
      '继续让跟练记录进入日志，为用户画像积累信号。',
    ];
  }

  String _weekLabel(DateTime weekStart) {
    final DateTime weekEnd = weekStart.add(const Duration(days: 6));
    return '${weekStart.month}/${weekStart.day} - ${weekEnd.month}/${weekEnd.day}';
  }
}
