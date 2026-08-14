import '../data/models/body_metric.dart';
import '../data/models/exercise_training_profile.dart';
import '../data/models/training_log.dart';
import '../data/models/user_profile.dart';
import '../data/models/weekly_report.dart';
import '../data/models/weekly_psych_check_in.dart';
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
    WeeklyPsychCheckIn? psychCheckIn,
    List<WorkoutDay> plannedWorkoutsForWeek = const <WorkoutDay>[],
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
    final PsychRiskLevel psychRiskLevel = _psychRiskLevel(
      trainingStatusLabel: trainingStatusLabel,
      readinessScore: readinessScore,
      recentLogs: recentLogs,
      psychCheckIn: psychCheckIn,
    );
    final List<WeeklyReportOption> options = _optionsForRisk(
      psychRiskLevel,
      todayWorkout: todayWorkout,
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
      goalSummary: '本周过程目标：完成计划中的 $plannedWorkouts 次训练或计划恢复。',
      realityObservation: '本周记录 $completedWorkouts/$plannedWorkouts 次完成单位，'
          '完成率 ${(completionRate * 100).round()}%。',
      options: options,
      reflectionQuestion: psychCheckIn?.weekNote?.trim().isNotEmpty == true
          ? '你记录的“${psychCheckIn!.weekNote!.trim()}”，下周想保留哪一部分？'
          : '这周哪一次训练或恢复最符合你的状态？',
      psychCheckIn: psychCheckIn,
      psychRiskLevel: psychRiskLevel,
      dimensionExposure: _dimensionExposure(
        recentLogs: recentLogs,
        plannedWorkouts: plannedWorkoutsForWeek.isEmpty &&
                !todayWorkout.dimensionFocus.isEmpty
            ? <WorkoutDay>[todayWorkout]
            : plannedWorkoutsForWeek,
      ),
    );
  }

  List<TrainingDimensionExposure> _dimensionExposure({
    required List<TrainingLog> recentLogs,
    required List<WorkoutDay> plannedWorkouts,
  }) {
    final Map<TrainingDimension, int> planned = <TrainingDimension, int>{};
    final Map<TrainingDimension, int> completed = <TrainingDimension, int>{};
    final Map<String, WorkoutDay> workoutsById = <String, WorkoutDay>{
      for (final WorkoutDay workout in plannedWorkouts) workout.id: workout,
    };
    for (final WorkoutDay workout in plannedWorkouts) {
      for (final TrainingDimension dimension in workout.dimensionFocus.all) {
        planned.update(dimension, (int value) => value + 1, ifAbsent: () => 1);
      }
    }
    for (final TrainingLog log in recentLogs) {
      final Set<TrainingDimension> dimensions = <TrainingDimension>{};
      final WorkoutDay? workout = workoutsById[log.workoutDayId];
      if (workout != null) {
        dimensions.addAll(workout.dimensionFocus.all);
      } else {
        for (final ExerciseExecutionRecord record in log.exerciseRecords) {
          final String? exerciseId = record.exerciseId;
          if (exerciseId != null) {
            dimensions.addAll(
              trainingProfileForExercise(exerciseId).dimensions,
            );
          }
        }
      }
      for (final TrainingDimension dimension in dimensions) {
        completed.update(dimension, (int value) => value + 1,
            ifAbsent: () => 1);
      }
    }
    return <TrainingDimensionExposure>[
      for (final TrainingDimension dimension in TrainingDimension.values)
        TrainingDimensionExposure(
          dimension: dimension,
          plannedSessions: planned[dimension] ?? 0,
          completedSessions: completed[dimension] ?? 0,
        ),
    ];
  }

  PsychRiskLevel _psychRiskLevel({
    required String trainingStatusLabel,
    required int readinessScore,
    required List<TrainingLog> recentLogs,
    required WeeklyPsychCheckIn? psychCheckIn,
  }) {
    if (trainingStatusLabel == '过度风险' || readinessScore < 50) {
      return PsychRiskLevel.protect;
    }
    int signalCount = 0;
    if (recentLogs.any(
      (TrainingLog log) => log.rpe >= 9 || log.fatigueLevel >= 8,
    )) {
      signalCount += 1;
    }
    if ((psychCheckIn?.motivation ?? 5) <= 2) signalCount += 1;
    if ((psychCheckIn?.perceivedStress ?? 1) >= 4) signalCount += 1;
    if ((psychCheckIn?.recoveryFeel ?? 5) <= 2) signalCount += 1;
    if (readinessScore < 60) signalCount += 1;
    if (signalCount >= 2) return PsychRiskLevel.advise;
    if (signalCount == 1) return PsychRiskLevel.observe;
    return PsychRiskLevel.normal;
  }

  List<WeeklyReportOption> _optionsForRisk(
    PsychRiskLevel riskLevel, {
    required WorkoutDay todayWorkout,
  }) {
    if (riskLevel == PsychRiskLevel.protect) {
      return const <WeeklyReportOption>[
        WeeklyReportOption(
          id: 'protect_pause',
          label: '暂停高强度安排，只保留恢复记录',
        ),
        WeeklyReportOption(
          id: 'protect_review',
          label: '先复核疼痛、疲劳与恢复状态',
        ),
      ];
    }
    if (riskLevel == PsychRiskLevel.advise) {
      return const <WeeklyReportOption>[
        WeeklyReportOption(
          id: 'recovery_first',
          label: '优先安排恢复或低强度训练',
        ),
        WeeklyReportOption(
          id: 'reduce_one_session',
          label: '减少一次高强度训练',
        ),
      ];
    }
    return <WeeklyReportOption>[
      const WeeklyReportOption(
        id: 'keep_schedule',
        label: '保持当前周训练频率',
      ),
      WeeklyReportOption(
        id: 'keep_one_focus',
        label: '只围绕${todayWorkout.trainingType.label}保留一个训练焦点',
      ),
    ];
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
        '建议预览：可将下周一项高强度训练降低一级；确认后才会调整计划。',
        '每次训练后继续记录 RPE、睡眠和疼痛，优先把恢复拉回稳定。',
        '正式训练仍从泡沫轴、动态拉伸和激活开始。',
      ];
    }

    if (completionRate < 0.5) {
      return [
        '本周完成率低于 50%，下周可选择减少一次计划或缩短单次时长。',
        '保留 5 分钟低门槛版本，未完成不会触发惩罚。',
        '下周可继续围绕 ${todayWorkout.trainingType.label}，由你确认是否保持。',
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
