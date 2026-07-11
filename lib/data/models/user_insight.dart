import 'user_profile.dart';

enum ProfileEventType {
  onboarding,
  workoutCompleted,
  workoutSkipped,
  deloadUsed,
  bodyMetric,
  painRedline,
  starterProgress,
  activityImport,
  planAdjustment,
}

extension ProfileEventTypeLabel on ProfileEventType {
  String get label {
    switch (this) {
      case ProfileEventType.onboarding:
        return '初始问卷';
      case ProfileEventType.workoutCompleted:
        return '训练完成';
      case ProfileEventType.workoutSkipped:
        return '训练跳过';
      case ProfileEventType.deloadUsed:
        return '主动降级';
      case ProfileEventType.bodyMetric:
        return '身体数据';
      case ProfileEventType.painRedline:
        return '安全红线';
      case ProfileEventType.starterProgress:
        return '新手引导';
      case ProfileEventType.activityImport:
        return '训练导入';
      case ProfileEventType.planAdjustment:
        return '计划调整';
    }
  }

  String get jsonValue {
    switch (this) {
      case ProfileEventType.onboarding:
        return 'onboarding';
      case ProfileEventType.workoutCompleted:
        return 'workout_completed';
      case ProfileEventType.workoutSkipped:
        return 'workout_skipped';
      case ProfileEventType.deloadUsed:
        return 'deload_used';
      case ProfileEventType.bodyMetric:
        return 'body_metric';
      case ProfileEventType.painRedline:
        return 'pain_redline';
      case ProfileEventType.starterProgress:
        return 'starter_progress';
      case ProfileEventType.activityImport:
        return 'activity_import';
      case ProfileEventType.planAdjustment:
        return 'plan_adjustment';
    }
  }
}

ProfileEventType profileEventTypeFromJson(String? value) {
  switch (value) {
    case 'workout_completed':
      return ProfileEventType.workoutCompleted;
    case 'workout_skipped':
      return ProfileEventType.workoutSkipped;
    case 'deload_used':
      return ProfileEventType.deloadUsed;
    case 'body_metric':
      return ProfileEventType.bodyMetric;
    case 'pain_redline':
      return ProfileEventType.painRedline;
    case 'starter_progress':
      return ProfileEventType.starterProgress;
    case 'activity_import':
      return ProfileEventType.activityImport;
    case 'plan_adjustment':
      return ProfileEventType.planAdjustment;
    case 'onboarding':
    default:
      return ProfileEventType.onboarding;
  }
}

enum UserInsightDimension {
  basic,
  behavior,
  physiology,
  preference,
}

extension UserInsightDimensionLabel on UserInsightDimension {
  String get label {
    switch (this) {
      case UserInsightDimension.basic:
        return '基础层';
      case UserInsightDimension.behavior:
        return '行为层';
      case UserInsightDimension.physiology:
        return '生理层';
      case UserInsightDimension.preference:
        return '偏好层';
    }
  }

  String get jsonValue {
    switch (this) {
      case UserInsightDimension.basic:
        return 'basic';
      case UserInsightDimension.behavior:
        return 'behavior';
      case UserInsightDimension.physiology:
        return 'physiology';
      case UserInsightDimension.preference:
        return 'preference';
    }
  }
}

UserInsightDimension userInsightDimensionFromJson(String? value) {
  switch (value) {
    case 'behavior':
      return UserInsightDimension.behavior;
    case 'physiology':
      return UserInsightDimension.physiology;
    case 'preference':
      return UserInsightDimension.preference;
    case 'basic':
    default:
      return UserInsightDimension.basic;
  }
}

enum PredictionStatus {
  pending,
  hit,
  missed,
}

extension PredictionStatusLabel on PredictionStatus {
  String get label {
    switch (this) {
      case PredictionStatus.pending:
        return '待对账';
      case PredictionStatus.hit:
        return '命中';
      case PredictionStatus.missed:
        return '偏差';
    }
  }

  String get jsonValue {
    switch (this) {
      case PredictionStatus.pending:
        return 'pending';
      case PredictionStatus.hit:
        return 'hit';
      case PredictionStatus.missed:
        return 'missed';
    }
  }
}

PredictionStatus predictionStatusFromJson(String? value) {
  switch (value) {
    case 'hit':
      return PredictionStatus.hit;
    case 'missed':
      return PredictionStatus.missed;
    case 'pending':
    default:
      return PredictionStatus.pending;
  }
}

class ProfileEvent {
  final String id;
  final ProfileEventType type;
  final String title;
  final String detail;
  final DateTime occurredAt;

  const ProfileEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.detail,
    required this.occurredAt,
  });

  factory ProfileEvent.fromJson(Map<String, dynamic> json) {
    return ProfileEvent(
      id: json['id'] as String? ?? '',
      type: profileEventTypeFromJson(json['type'] as String?),
      title: json['title'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      occurredAt: _dateTimeFromJson(json['occurredAt'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.jsonValue,
      'title': title,
      'detail': detail,
      'occurredAt': occurredAt.toIso8601String(),
    };
  }

  String get dateLabel {
    return '${occurredAt.month}/${occurredAt.day}';
  }
}

class UserProfileInsight {
  final String id;
  final UserInsightDimension dimension;
  final String title;
  final String conclusion;
  final double confidence;
  final List<String> evidenceLabels;
  final String conservativeAction;

  const UserProfileInsight({
    required this.id,
    required this.dimension,
    required this.title,
    required this.conclusion,
    required this.confidence,
    required this.evidenceLabels,
    required this.conservativeAction,
  });

  factory UserProfileInsight.fromJson(Map<String, dynamic> json) {
    return UserProfileInsight(
      id: json['id'] as String? ?? '',
      dimension: userInsightDimensionFromJson(json['dimension'] as String?),
      title: json['title'] as String? ?? '',
      conclusion: json['conclusion'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      evidenceLabels:
          List<String>.from(json['evidenceLabels'] as List<dynamic>? ?? []),
      conservativeAction: json['conservativeAction'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dimension': dimension.jsonValue,
      'title': title,
      'conclusion': conclusion,
      'confidence': confidence,
      'evidenceLabels': evidenceLabels,
      'conservativeAction': conservativeAction,
    };
  }

  String get confidenceLabel {
    return '${(confidence * 100).round()}%';
  }

  bool get lowConfidence {
    return confidence < 0.65;
  }
}

class PredictionLog {
  final String id;
  final String predictionType;
  final String predictedValue;
  final String? actualValue;
  final PredictionStatus status;
  final DateTime predictedAt;
  final DateTime dueAt;

  const PredictionLog({
    required this.id,
    required this.predictionType,
    required this.predictedValue,
    required this.actualValue,
    required this.status,
    required this.predictedAt,
    required this.dueAt,
  });

  factory PredictionLog.fromJson(Map<String, dynamic> json) {
    return PredictionLog(
      id: json['id'] as String? ?? '',
      predictionType: json['predictionType'] as String? ?? '',
      predictedValue: json['predictedValue'] as String? ?? '',
      actualValue: json['actualValue'] as String?,
      status: predictionStatusFromJson(json['status'] as String?),
      predictedAt: _dateTimeFromJson(json['predictedAt'] as String?),
      dueAt: _dateTimeFromJson(json['dueAt'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'predictionType': predictionType,
      'predictedValue': predictedValue,
      'actualValue': actualValue,
      'status': status.jsonValue,
      'predictedAt': predictedAt.toIso8601String(),
      'dueAt': dueAt.toIso8601String(),
    };
  }

  String get dueDateLabel {
    return '${dueAt.month}/${dueAt.day}';
  }

  bool get isSettled {
    return status != PredictionStatus.pending;
  }

  String get settlementLabel {
    return isSettled ? '已自动回填' : '等待到期';
  }
}

class UserInsightWeeklyTask {
  final String id;
  final String weekLabel;
  final DateTime generatedAt;
  final int profileEventCount;
  final int userProfileCount;
  final int predictionLogCount;
  final String statusLabel;

  const UserInsightWeeklyTask({
    required this.id,
    required this.weekLabel,
    required this.generatedAt,
    required this.profileEventCount,
    required this.userProfileCount,
    required this.predictionLogCount,
    required this.statusLabel,
  });

  factory UserInsightWeeklyTask.fromJson(Map<String, dynamic> json) {
    return UserInsightWeeklyTask(
      id: json['id'] as String? ?? '',
      weekLabel: json['weekLabel'] as String? ?? '',
      generatedAt: _dateTimeFromJson(json['generatedAt'] as String?),
      profileEventCount: (json['profileEventCount'] as num?)?.toInt() ?? 0,
      userProfileCount: (json['userProfileCount'] as num?)?.toInt() ?? 0,
      predictionLogCount: (json['predictionLogCount'] as num?)?.toInt() ?? 0,
      statusLabel: json['statusLabel'] as String? ?? '已生成',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'weekLabel': weekLabel,
      'generatedAt': generatedAt.toIso8601String(),
      'profileEventCount': profileEventCount,
      'userProfileCount': userProfileCount,
      'predictionLogCount': predictionLogCount,
      'statusLabel': statusLabel,
    };
  }

  String get generatedAtLabel {
    final String hour = generatedAt.hour.toString().padLeft(2, '0');
    final String minute = generatedAt.minute.toString().padLeft(2, '0');
    return '${generatedAt.month}/${generatedAt.day} $hour:$minute';
  }
}

class UserInsightTableState {
  final UserProfile? profileSnapshot;
  final List<ProfileEvent> profileEvents;
  final List<UserProfileInsight> userProfiles;
  final List<PredictionLog> predictionLogs;
  final List<UserInsightWeeklyTask> weeklyTasks;

  const UserInsightTableState({
    required this.profileSnapshot,
    required this.profileEvents,
    required this.userProfiles,
    required this.predictionLogs,
    required this.weeklyTasks,
  });

  const UserInsightTableState.empty()
      : profileSnapshot = null,
        profileEvents = const [],
        userProfiles = const [],
        predictionLogs = const [],
        weeklyTasks = const [];

  factory UserInsightTableState.fromJson(Map<String, dynamic> json) {
    final Object? profileJson = json['profileSnapshot'];
    return UserInsightTableState(
      profileSnapshot: profileJson is Map<String, dynamic>
          ? UserProfile.fromJson(profileJson)
          : null,
      profileEvents: (json['profileEvents'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProfileEvent.fromJson)
          .toList(),
      userProfiles: (json['userProfiles'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(UserProfileInsight.fromJson)
          .toList(),
      predictionLogs: (json['predictionLogs'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PredictionLog.fromJson)
          .toList(),
      weeklyTasks: (json['weeklyTasks'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(UserInsightWeeklyTask.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profileSnapshot': profileSnapshot?.toJson(),
      'profileEvents':
          profileEvents.map((ProfileEvent event) => event.toJson()).toList(),
      'userProfiles': userProfiles
          .map((UserProfileInsight insight) => insight.toJson())
          .toList(),
      'predictionLogs': predictionLogs
          .map((PredictionLog prediction) => prediction.toJson())
          .toList(),
      'weeklyTasks': weeklyTasks
          .map((UserInsightWeeklyTask task) => task.toJson())
          .toList(),
    };
  }

  UserInsightWeeklyTask? get latestWeeklyTask {
    if (weeklyTasks.isEmpty) {
      return null;
    }
    return weeklyTasks.first;
  }

  int get totalTableRows {
    return profileEvents.length + userProfiles.length + predictionLogs.length;
  }
}

DateTime _dateTimeFromJson(String? value) {
  if (value == null || value.isEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
}
