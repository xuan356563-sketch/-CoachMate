import '../data/models/body_metric.dart';
import '../data/models/training_reminder.dart';
import '../data/models/user_profile.dart';
import '../data/models/workout_day.dart';

class TrainingReminderService {
  List<TrainingReminder> buildReminders({
    required bool enabled,
    required String preferredTimeLabel,
    required UserProfile profile,
    required WorkoutDay todayWorkout,
    required int starterProgramStreak,
    required int starterProgramDayIndex,
    required bool formalPlanUnlocked,
    required BodyMetric? latestBodyMetric,
    required int remainingRecoveryHours,
    required String recoveryAdvice,
    required int readinessScore,
    required String trainingStatusLabel,
    required String morningReportAdvice,
  }) {
    final List<TrainingReminder> reminders = [];
    final bool needsLightVersion = _needsLightVersion(
      latestBodyMetric: latestBodyMetric,
      readinessScore: readinessScore,
      trainingStatusLabel: trainingStatusLabel,
    );
    final bool isProtectionState = _isProtectionState(
      readinessScore: readinessScore,
      trainingStatusLabel: trainingStatusLabel,
    );

    if (needsLightVersion) {
      reminders.add(
        TrainingReminder(
          id: 'proactive-deload',
          type: TrainingReminderType.proactiveDeload,
          title: '轻松版确认',
          timeLabel: '现在',
          reason: '睡眠、疲劳或训练状态提示压力偏高：$morningReportAdvice。先让用户一键确认是否切轻松版。',
          actionLabel: '查看今日安排',
          priorityLabel: '高优先级',
          enabled: enabled,
        ),
      );
    }

    if (!isProtectionState) {
      reminders.add(
        TrainingReminder(
          id: 'daily-plan',
          type: TrainingReminderType.dailyPlan,
          title: '今日训练提醒',
          timeLabel: preferredTimeLabel,
          reason:
              '固定时间推送当天安排：${todayWorkout.title}，总时长约 ${todayWorkout.estimatedMinutes} 分钟。',
          actionLabel: '去今日训练',
          priorityLabel: '固定提醒',
          enabled: enabled,
        ),
      );

      reminders.add(
        TrainingReminder(
          id: formalPlanUnlocked ? 'formal-plan' : 'starter-program',
          type: formalPlanUnlocked
              ? TrainingReminderType.formalPlan
              : TrainingReminderType.starterProgram,
          title: formalPlanUnlocked ? '正式周期提醒' : '30 天引导提醒',
          timeLabel: _starterReminderTime(
            preferredTimeLabel: preferredTimeLabel,
            profile: profile,
          ),
          reason: formalPlanUnlocked
              ? '已从 30 天毕业报告切到正式 AI 个性化周期，提醒只保留下一步训练确认。'
              : '当前第 $starterProgramDayIndex/30 天，累计成长日 $starterProgramStreak 天；可按状态顺延或切 5 分钟补救版。',
          actionLabel: formalPlanUnlocked ? '看正式计划' : '打开引导',
          priorityLabel: formalPlanUnlocked ? '周期衔接' : '习惯建立',
          enabled: enabled,
        ),
      );
    }

    if (remainingRecoveryHours > 0) {
      reminders.add(
        TrainingReminder(
          id: 'recovery-check',
          type: TrainingReminderType.recoveryCheck,
          title: '恢复检查提醒',
          timeLabel: '恢复倒计时结束前',
          reason: '$recoveryAdvice 当前距下次高强度课还需约 $remainingRecoveryHours 小时。',
          actionLabel: '查看恢复',
          priorityLabel: '安全约束',
          enabled: enabled,
        ),
      );
    }

    reminders.add(
      TrainingReminder(
        id: 'weekly-report',
        type: TrainingReminderType.weeklyReport,
        title: '周报提醒',
        timeLabel: '周日 20:00',
        reason: '每周固定汇总完成率、负荷趋势、恢复建议和下周重点。',
        actionLabel: '打开周报',
        priorityLabel: '复盘',
        enabled: enabled,
      ),
    );

    return reminders;
  }

  bool _needsLightVersion({
    required BodyMetric? latestBodyMetric,
    required int readinessScore,
    required String trainingStatusLabel,
  }) {
    if (trainingStatusLabel == '过度风险' || readinessScore < 60) {
      return true;
    }
    if (latestBodyMetric == null) {
      return false;
    }
    return latestBodyMetric.sleepHours < 6.5 ||
        latestBodyMetric.fatigueLevel >= 7 ||
        latestBodyMetric.sorenessLevel >= 7;
  }

  bool _isProtectionState({
    required int readinessScore,
    required String trainingStatusLabel,
  }) {
    return trainingStatusLabel == '过度风险' && readinessScore < 50;
  }

  String _starterReminderTime({
    required String preferredTimeLabel,
    required UserProfile profile,
  }) {
    if (profile.workScheduleType == WorkScheduleType.overtimeHeavy) {
      return '21:30';
    }
    return preferredTimeLabel;
  }
}
