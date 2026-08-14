import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';

/// P1 运动搭子的本地数据契约。
///
/// 所有行动仅描述既有入口或确认动作；搭子不直接修改训练计划、健康数据或云端数据。
enum RelationshipState {
  onboarding,
  steady,
  streak,
  slipping,
  dormant,
  lapsed,
  returning,
  injured,
  peaking;

  String get label => switch (this) {
        RelationshipState.onboarding => '初识',
        RelationshipState.steady => '日常',
        RelationshipState.streak => '连贯',
        RelationshipState.slipping => '节奏变慢',
        RelationshipState.dormant => '安静',
        RelationshipState.lapsed => '沉默',
        RelationshipState.returning => '回来了',
        RelationshipState.injured => '身体优先',
        RelationshipState.peaking => '冲刺',
      };
}

/// P1 的 13 个选题；「今天算了」回复复用 missedWorkout 的响应式变体。
enum CompanionIntent {
  morningBrief,
  preWorkout,
  postWorkout,
  missedWorkout,
  dataAnomaly,
  milestone,
  recordBreak,
  weeklyReview,
  quietDay,
  planAdjust,
  returning,
  injuryCare,
  checkinAck;

  String get storageValue => switch (this) {
        CompanionIntent.morningBrief => 'morning_brief',
        CompanionIntent.preWorkout => 'pre_workout',
        CompanionIntent.postWorkout => 'post_workout',
        CompanionIntent.missedWorkout => 'missed_workout',
        CompanionIntent.dataAnomaly => 'data_anomaly',
        CompanionIntent.milestone => 'milestone',
        CompanionIntent.recordBreak => 'record_break',
        CompanionIntent.weeklyReview => 'weekly_review',
        CompanionIntent.quietDay => 'quiet_day',
        CompanionIntent.planAdjust => 'plan_adjust',
        CompanionIntent.returning => 'returning',
        CompanionIntent.injuryCare => 'injury_care',
        CompanionIntent.checkinAck => 'checkin_ack',
      };

  bool get isStrictL0 => this == CompanionIntent.injuryCare;

  bool get isReactive => switch (this) {
        CompanionIntent.postWorkout || CompanionIntent.checkinAck => true,
        _ => false,
      };
}

enum CompanionDeliveryKind { proactive, reactive }

enum CompanionMessageRole { companion, user, system }

enum CompanionMessageRetention { companionHistory, conversation30Days }

enum PrivacyLevel {
  l0,
  l1,
  l2;

  String get storageValue => name.toUpperCase();
}

enum DisturbTier { less, normal, more, silent }

enum CompanionFactSource {
  healthKit,
  manualEntry,
  trainingLog,
  checkIn,
  derived;

  String get storageValue => switch (this) {
        CompanionFactSource.healthKit => 'health_kit',
        CompanionFactSource.manualEntry => 'manual_entry',
        CompanionFactSource.trainingLog => 'training_log',
        CompanionFactSource.checkIn => 'check_in',
        CompanionFactSource.derived => 'derived',
      };
}

enum CompanionActionKind { primary, secondary, dismiss }

enum CompanionActionEffect {
  openExistingRoute,
  requestExistingAdjustment,
  recordDismissal,
}

enum CompanionBoundaryTopic {
  weight,
  bodyComposition,
  appearance,
  pain,
  diet,
  sleep,
  comparison;
}

class CompanionFact {
  const CompanionFact({
    required this.label,
    required this.value,
    required this.source,
    this.baseline,
    this.delta,
    this.deepLink,
    this.isSensitive = false,
    this.sourceLocalId,
    this.sourceDigest,
    this.observedAt,
    this.sourceSummary,
  });

  final String label;
  final String value;
  final String? baseline;
  final String? delta;
  final CompanionFactSource source;
  final String? deepLink;
  final bool isSensitive;
  final String? sourceLocalId;
  final String? sourceDigest;
  final DateTime? observedAt;
  final String? sourceSummary;

  bool get isDerived => source == CompanionFactSource.derived;

  Map<String, Object?> toJson() => <String, Object?>{
        'label': label,
        'value': value,
        'baseline': baseline,
        'delta': delta,
        'source': source.storageValue,
        'deepLink': deepLink,
        'isSensitive': isSensitive,
        'sourceLocalId': sourceLocalId,
        'sourceDigest': sourceDigest,
        'observedAt': observedAt?.toUtc().toIso8601String(),
        'sourceSummary': sourceSummary,
      };
}

class CompanionAction {
  const CompanionAction({
    required this.actionId,
    required this.label,
    required this.kind,
    required this.effect,
    this.route,
  }) : assert(label.length <= 5, '搭子行动按钮不能超过五个字');

  final String actionId;
  final String label;
  final CompanionActionKind kind;
  final String? route;
  final CompanionActionEffect effect;

  Map<String, Object?> toJson() => <String, Object?>{
        'actionId': actionId,
        'label': label,
        'kind': kind.name,
        'route': route,
        'effect': effect.name,
      };
}

class CompanionMessage {
  const CompanionMessage({
    required this.messageId,
    required this.athleteProfileId,
    required this.localDate,
    required this.intent,
    required this.copyVariantId,
    required this.relationshipState,
    required this.deliveryKind,
    required this.privacyLevel,
    required this.body,
    required this.createdAt,
    this.notificationTitle,
    this.notificationBody,
    this.facts = const <CompanionFact>[],
    this.actions = const <CompanionAction>[],
    this.scheduledAt,
    this.deliveredAt,
    this.openedAt,
    this.actionTakenId,
    this.notificationId,
    this.messageRole = CompanionMessageRole.companion,
    this.threadId = 'default',
    this.turnId,
    this.sourceSnapshotId,
    this.traceId,
    this.retention = CompanionMessageRetention.companionHistory,
    this.verificationState = CoachVerificationState.localOnly,
  }) : assert(actions.length <= 3, '一条搭子消息最多三个行动');

  final String messageId;
  final String athleteProfileId;
  final String localDate;
  final CompanionIntent intent;
  final String copyVariantId;
  final RelationshipState relationshipState;
  final CompanionDeliveryKind deliveryKind;
  final PrivacyLevel privacyLevel;
  final String? notificationTitle;
  final String? notificationBody;
  final String body;
  final List<CompanionFact> facts;
  final List<CompanionAction> actions;
  final DateTime? scheduledAt;
  final DateTime? deliveredAt;
  final DateTime? openedAt;
  final String? actionTakenId;
  final int? notificationId;
  final CompanionMessageRole messageRole;
  final String threadId;
  final String? turnId;
  final String? sourceSnapshotId;
  final String? traceId;
  final CompanionMessageRetention retention;
  final CoachVerificationState verificationState;
  final DateTime createdAt;

  bool get isUnread => deliveredAt != null && openedAt == null;
  bool get isConversation =>
      messageRole == CompanionMessageRole.user ||
      retention == CompanionMessageRetention.conversation30Days;
}

class CompanionRelationship {
  const CompanionRelationship({
    required this.athleteProfileId,
    required this.startedOn,
    required this.createdAt,
    required this.updatedAt,
    this.companionName,
    this.lastResolvedState = RelationshipState.onboarding,
    this.stateEnteredOn,
    this.disturbTier = DisturbTier.normal,
    this.quietHoursStartMinute = 22 * 60,
    this.quietHoursEndMinute = 7 * 60,
    this.notificationsEnabled = false,
    this.notificationDetailEnabled = false,
    this.boundaries = const <CompanionBoundaryTopic>{},
    this.consecutiveUnopened = 0,
  });

  final String athleteProfileId;
  final String? companionName;
  final DateTime startedOn;
  final RelationshipState lastResolvedState;
  final DateTime? stateEnteredOn;
  final DisturbTier disturbTier;
  final int quietHoursStartMinute;
  final int quietHoursEndMinute;

  /// 系统通知必须由用户单独开启；详细锁屏内容不是其替代开关。
  final bool notificationsEnabled;
  final bool notificationDetailEnabled;
  final Set<CompanionBoundaryTopic> boundaries;
  final int consecutiveUnopened;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// 可被搭子引用的本地长期事件。不可播报事件仍可保留，但必须标记为 false。
class CompanionEvent {
  const CompanionEvent({
    required this.eventId,
    required this.athleteProfileId,
    required this.kind,
    required this.occurredOn,
    required this.createdAt,
    this.payload = const <String, Object?>{},
    this.isMentionable = true,
    this.lastMentionedAt,
  });

  final String eventId;
  final String athleteProfileId;
  final String kind;
  final String occurredOn;
  final Map<String, Object?> payload;
  final bool isMentionable;
  final DateTime? lastMentionedAt;
  final DateTime createdAt;
}

/// 由既有训练、活动、恢复和宠物账本组装的只读快照。
class CompanionContext {
  const CompanionContext({
    required this.relationshipDays,
    required this.daysSinceLastActivity,
    required this.missedInLast7Days,
    required this.currentStreak,
    required this.wasAwayYesterday,
    required this.hasSignalToday,
    this.daysToRace,
    this.latestPainScore,
    this.hasUnresolvedSeverePain = false,
    this.disturbTier = DisturbTier.normal,
    this.consecutiveUnopened = 0,
    this.notificationDetailEnabled = false,
    this.quietHoursStartMinute = 22 * 60,
    this.quietHoursEndMinute = 7 * 60,
    this.boundaries = const <CompanionBoundaryTopic>{},
  });

  final int relationshipDays;
  final int daysSinceLastActivity;
  final int missedInLast7Days;
  final int currentStreak;
  final bool wasAwayYesterday;
  final bool hasSignalToday;
  final int? daysToRace;
  final int? latestPainScore;
  final bool hasUnresolvedSeverePain;
  final DisturbTier disturbTier;
  final int consecutiveUnopened;
  final bool notificationDetailEnabled;
  final int quietHoursStartMinute;
  final int quietHoursEndMinute;
  final Set<CompanionBoundaryTopic> boundaries;

  bool get isInjured =>
      hasUnresolvedSeverePain ||
      (latestPainScore != null && latestPainScore! >= 4);
}
