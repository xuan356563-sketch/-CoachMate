enum TrainingReminderType {
  dailyPlan,
  starterProgram,
  formalPlan,
  recoveryCheck,
  proactiveDeload,
  weeklyReport,
}

extension TrainingReminderTypeLabel on TrainingReminderType {
  String get label {
    switch (this) {
      case TrainingReminderType.dailyPlan:
        return '今日训练';
      case TrainingReminderType.starterProgram:
        return '30 天引导';
      case TrainingReminderType.formalPlan:
        return '正式周期';
      case TrainingReminderType.recoveryCheck:
        return '恢复检查';
      case TrainingReminderType.proactiveDeload:
        return '轻松版确认';
      case TrainingReminderType.weeklyReport:
        return '自动周报';
    }
  }
}

class TrainingReminder {
  final String id;
  final TrainingReminderType type;
  final String title;
  final String timeLabel;
  final String reason;
  final String actionLabel;
  final String priorityLabel;
  final bool enabled;

  const TrainingReminder({
    required this.id,
    required this.type,
    required this.title,
    required this.timeLabel,
    required this.reason,
    required this.actionLabel,
    required this.priorityLabel,
    required this.enabled,
  });

  /// 这些提醒只在 App 内展示，不会进入系统通知调度；系统推送按已确认的
  /// 训练日程单独发送。状态文案不使用「已启用」，避免让用户以为到点会收到推送。
  String get statusLabel {
    return enabled ? 'App 内提示' : '已暂停';
  }
}

class TrainingReminderSettings {
  final bool enabled;
  final String preferredTimeLabel;
  final bool followSchedule;
  final int leadMinutes;

  const TrainingReminderSettings({
    required this.enabled,
    required this.preferredTimeLabel,
    this.followSchedule = true,
    this.leadMinutes = 30,
  });

  factory TrainingReminderSettings.fromJson(Map<String, dynamic> json) {
    final String rawTimeLabel = json['preferredTimeLabel'] as String? ?? '';
    return TrainingReminderSettings(
      enabled: json['enabled'] as bool? ?? true,
      preferredTimeLabel: rawTimeLabel.trim().isEmpty ? '20:30' : rawTimeLabel,
      followSchedule: json['followSchedule'] as bool? ?? true,
      leadMinutes: (json['leadMinutes'] as num?)?.toInt() ?? 30,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'preferredTimeLabel': preferredTimeLabel,
      'followSchedule': followSchedule,
      'leadMinutes': leadMinutes,
    };
  }
}
