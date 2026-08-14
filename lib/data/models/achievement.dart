enum AchievementCategory {
  consistency,
  execution,
  bodyData,
  safety,
}

extension AchievementCategoryLabel on AchievementCategory {
  String get label {
    switch (this) {
      case AchievementCategory.consistency:
        return '连续性';
      case AchievementCategory.execution:
        return '执行';
      case AchievementCategory.bodyData:
        return '数据';
      case AchievementCategory.safety:
        return '安全';
    }
  }

  String get jsonValue {
    switch (this) {
      case AchievementCategory.consistency:
        return 'consistency';
      case AchievementCategory.execution:
        return 'execution';
      case AchievementCategory.bodyData:
        return 'body_data';
      case AchievementCategory.safety:
        return 'safety';
    }
  }
}

AchievementCategory achievementCategoryFromJson(String? value) {
  switch (value) {
    case 'execution':
      return AchievementCategory.execution;
    case 'body_data':
      return AchievementCategory.bodyData;
    case 'safety':
      return AchievementCategory.safety;
    case 'consistency':
    default:
      return AchievementCategory.consistency;
  }
}

class AchievementDefinition {
  final String id;
  final String title;
  final String description;
  final AchievementCategory category;
  final int targetValue;

  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.targetValue,
  });

  factory AchievementDefinition.fromJson(Map<String, dynamic> json) {
    return AchievementDefinition(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: achievementCategoryFromJson(json['category'] as String?),
      targetValue: (json['targetValue'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category.jsonValue,
      'targetValue': targetValue,
    };
  }
}

class AchievementProgress {
  final AchievementDefinition definition;
  final int currentValue;

  const AchievementProgress({
    required this.definition,
    required this.currentValue,
  });

  bool get unlocked {
    return currentValue >= definition.targetValue;
  }

  double get progress {
    if (definition.targetValue <= 0) {
      return unlocked ? 1 : 0;
    }
    return (currentValue / definition.targetValue).clamp(0, 1).toDouble();
  }

  String get progressLabel {
    return '${currentValue.clamp(0, definition.targetValue)}/${definition.targetValue}';
  }
}

class AchievementRecord {
  final String id;
  final String definitionId;
  final String title;
  final String description;
  final AchievementCategory category;
  final int currentValue;
  final int targetValue;
  final DateTime unlockedAt;
  final String sourceLabel;

  const AchievementRecord({
    required this.id,
    required this.definitionId,
    required this.title,
    required this.description,
    required this.category,
    required this.currentValue,
    required this.targetValue,
    required this.unlockedAt,
    required this.sourceLabel,
  });

  factory AchievementRecord.fromProgress(
    AchievementProgress progress, {
    DateTime? unlockedAt,
  }) {
    return AchievementRecord(
      id: 'achievement-record-${progress.definition.id}',
      definitionId: progress.definition.id,
      title: progress.definition.title,
      description: progress.definition.description,
      category: progress.definition.category,
      currentValue: progress.currentValue
          .clamp(0, progress.definition.targetValue)
          .toInt(),
      targetValue: progress.definition.targetValue,
      unlockedAt: unlockedAt ?? DateTime.now(),
      sourceLabel: '本地状态派生成就',
    );
  }

  factory AchievementRecord.fromJson(Map<String, dynamic> json) {
    final String definitionId = json['definitionId'] as String? ?? '';
    return AchievementRecord(
      id: json['id'] as String? ?? '',
      definitionId: definitionId,
      title: _currentAchievementTitle(
        definitionId,
        json['title'] as String? ?? '',
      ),
      description: _currentAchievementDescription(
        definitionId,
        json['description'] as String? ?? '',
      ),
      category: achievementCategoryFromJson(json['category'] as String?),
      currentValue: (json['currentValue'] as num?)?.toInt() ?? 0,
      targetValue: (json['targetValue'] as num?)?.toInt() ?? 1,
      unlockedAt: _dateTimeFromJson(json['unlockedAt'] as String?),
      sourceLabel: json['sourceLabel'] as String? ?? '本地状态派生成就',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'definitionId': definitionId,
      'title': title,
      'description': description,
      'category': category.jsonValue,
      'currentValue': currentValue,
      'targetValue': targetValue,
      'unlockedAt': unlockedAt.toIso8601String(),
      'sourceLabel': sourceLabel,
    };
  }

  String get unlockedAtLabel {
    final String hour = unlockedAt.hour.toString().padLeft(2, '0');
    final String minute = unlockedAt.minute.toString().padLeft(2, '0');
    return '${unlockedAt.month}/${unlockedAt.day} $hour:$minute';
  }
}

String _currentAchievementTitle(String definitionId, String storedTitle) {
  return switch (definitionId) {
    'seven_day_streak' => '累计成长 7 天',
    'thirty_day_streak' => '累计成长 30 天',
    _ => storedTitle,
  };
}

String _currentAchievementDescription(
  String definitionId,
  String storedDescription,
) {
  return switch (definitionId) {
    'seven_day_streak' => '30 天引导累计完成 7 天。',
    'thirty_day_streak' => '累计完成 30 天渐进引导，准备进入正式 AI 计划。',
    _ => storedDescription,
  };
}

DateTime _dateTimeFromJson(String? value) {
  if (value == null || value.isEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
}
