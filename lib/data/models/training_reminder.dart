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

  String get statusLabel {
    return enabled ? '已启用' : '已暂停';
  }
}

class TrainingReminderSettings {
  final bool enabled;
  final String preferredTimeLabel;

  const TrainingReminderSettings({
    required this.enabled,
    required this.preferredTimeLabel,
  });

  factory TrainingReminderSettings.fromJson(Map<String, dynamic> json) {
    final String rawTimeLabel = json['preferredTimeLabel'] as String? ?? '';
    return TrainingReminderSettings(
      enabled: json['enabled'] as bool? ?? true,
      preferredTimeLabel: rawTimeLabel.trim().isEmpty ? '20:30' : rawTimeLabel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'preferredTimeLabel': preferredTimeLabel,
    };
  }
}
