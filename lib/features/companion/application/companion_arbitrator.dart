import 'package:trainflow_ai/features/companion/domain/companion_models.dart';

class CompanionCandidate {
  const CompanionCandidate({
    required this.copyVariantId,
    required this.intent,
    required this.body,
    required this.urgency,
    required this.baseValue,
    required this.defaultPrivacy,
    required this.deliveryKind,
    required this.preferredAt,
    this.cooldown = const Duration(hours: 24),
    this.boundaryTopics = const <CompanionBoundaryTopic>{},
    this.safetyCritical = false,
    this.facts = const <CompanionFact>[],
    this.actions = const <CompanionAction>[],
  });

  final String copyVariantId;
  final CompanionIntent intent;
  final String body;
  final int urgency;
  final int baseValue;
  final PrivacyLevel defaultPrivacy;
  final CompanionDeliveryKind deliveryKind;
  final DateTime preferredAt;
  final Duration cooldown;
  final Set<CompanionBoundaryTopic> boundaryTopics;
  final bool safetyCritical;
  final List<CompanionFact> facts;
  final List<CompanionAction> actions;
}

class PlannedCompanionCandidate {
  const PlannedCompanionCandidate({
    required this.candidate,
    required this.scheduledAt,
    required this.privacyLevel,
  });

  final CompanionCandidate candidate;
  final DateTime scheduledAt;
  final PrivacyLevel privacyLevel;

  String get copyVariantId => candidate.copyVariantId;
  CompanionIntent get intent => candidate.intent;
  List<CompanionAction> get actions => candidate.actions;
}

class CompanionArbitrationResult {
  const CompanionArbitrationResult({
    required this.selected,
    required this.proactiveBudget,
  });

  final List<PlannedCompanionCandidate> selected;
  final int proactiveBudget;
}

/// 纯函数仲裁器：只决定哪些候选可投放、何时投放和锁屏隐私级别。
/// 它不发送通知、不写库，也不修改训练计划。
CompanionArbitrationResult arbitrateCompanionCandidates({
  required CompanionContext context,
  required RelationshipState relationshipState,
  required Iterable<CompanionCandidate> candidates,
  required Iterable<CompanionMessage> history,
  required DateTime planningAt,
}) {
  final List<CompanionMessage> historyList = history.toList(growable: false);
  final int proactiveBudget =
      _resolveProactiveBudget(context, relationshipState);
  final List<CompanionCandidate> eligible = candidates
      .where((CompanionCandidate candidate) =>
          _isEligibleForState(candidate, relationshipState))
      .where((CompanionCandidate candidate) =>
          candidate.safetyCritical ||
          !candidate.boundaryTopics.any(context.boundaries.contains))
      .where((CompanionCandidate candidate) =>
          candidate.safetyCritical || candidate.baseValue >= 30)
      .where((CompanionCandidate candidate) =>
          !_isCoolingDown(candidate, historyList, planningAt))
      .toList()
    ..sort((CompanionCandidate left, CompanionCandidate right) {
      final int byUrgency = right.urgency.compareTo(left.urgency);
      if (byUrgency != 0) return byUrgency;
      final int byValue = right.baseValue.compareTo(left.baseValue);
      if (byValue != 0) return byValue;
      return left.copyVariantId.compareTo(right.copyVariantId);
    });

  final List<PlannedCompanionCandidate> selected =
      <PlannedCompanionCandidate>[];
  int proactiveUsed = _countTodayProactive(historyList, planningAt);
  for (final CompanionCandidate candidate in eligible) {
    final bool proactive =
        candidate.deliveryKind == CompanionDeliveryKind.proactive;
    if (!candidate.safetyCritical &&
        proactive &&
        proactiveUsed >= proactiveBudget) {
      continue;
    }
    final DateTime? scheduledAt = _assignSlot(
      candidate: candidate,
      context: context,
      alreadySelected: selected,
    );
    if (scheduledAt == null) continue;
    selected.add(PlannedCompanionCandidate(
      candidate: candidate,
      scheduledAt: scheduledAt,
      privacyLevel: resolveCompanionPrivacy(
        candidate: candidate,
        detailEnabled: context.notificationDetailEnabled,
      ),
    ));
    if (proactive) proactiveUsed += 1;
  }
  return CompanionArbitrationResult(
    selected: List<PlannedCompanionCandidate>.unmodifiable(selected),
    proactiveBudget: proactiveBudget,
  );
}

PrivacyLevel resolveCompanionPrivacy({
  required CompanionCandidate candidate,
  required bool detailEnabled,
}) {
  if (!detailEnabled || candidate.intent.isStrictL0) return PrivacyLevel.l0;
  if (candidate.facts.any((CompanionFact fact) => fact.isSensitive)) {
    return PrivacyLevel.l0;
  }
  return candidate.defaultPrivacy;
}

int _resolveProactiveBudget(
  CompanionContext context,
  RelationshipState state,
) {
  if (context.disturbTier == DisturbTier.silent ||
      context.consecutiveUnopened >= 6) {
    return 0;
  }
  int budget = switch (state) {
    RelationshipState.slipping ||
    RelationshipState.dormant ||
    RelationshipState.lapsed ||
    RelationshipState.returning =>
      1,
    RelationshipState.peaking => 3,
    _ => 2,
  };
  if (context.consecutiveUnopened >= 3) budget -= 1;
  budget += switch (context.disturbTier) {
    DisturbTier.less => -1,
    DisturbTier.normal || DisturbTier.silent => 0,
    DisturbTier.more => 1,
  };
  return budget.clamp(0, 3);
}

bool _isEligibleForState(
  CompanionCandidate candidate,
  RelationshipState state,
) {
  if (candidate.safetyCritical) return true;
  if (state == RelationshipState.returning) {
    return candidate.intent == CompanionIntent.returning;
  }
  if (state == RelationshipState.injured) {
    return candidate.intent == CompanionIntent.injuryCare;
  }
  if (state == RelationshipState.dormant || state == RelationshipState.lapsed) {
    return candidate.intent == CompanionIntent.quietDay;
  }
  if (state == RelationshipState.onboarding &&
      <CompanionIntent>{
        CompanionIntent.milestone,
        CompanionIntent.weeklyReview,
        CompanionIntent.dataAnomaly,
      }.contains(candidate.intent)) {
    return false;
  }
  if (state == RelationshipState.slipping &&
      <CompanionIntent>{
        CompanionIntent.milestone,
        CompanionIntent.recordBreak,
      }.contains(candidate.intent)) {
    return false;
  }
  if (state == RelationshipState.peaking &&
      candidate.intent == CompanionIntent.quietDay) {
    return false;
  }
  return true;
}

bool _isCoolingDown(
  CompanionCandidate candidate,
  Iterable<CompanionMessage> history,
  DateTime planningAt,
) {
  for (final CompanionMessage message in history) {
    final Duration age = planningAt.difference(message.createdAt);
    if (age.isNegative) continue;
    if (message.copyVariantId == candidate.copyVariantId &&
        age < const Duration(days: 30)) {
      return true;
    }
    if (message.intent == candidate.intent && age < candidate.cooldown) {
      return true;
    }
  }
  return false;
}

int _countTodayProactive(Iterable<CompanionMessage> history, DateTime day) {
  final String localDate = _localDate(day);
  return history
      .where((CompanionMessage message) =>
          message.deliveryKind == CompanionDeliveryKind.proactive &&
          message.localDate == localDate)
      .length;
}

DateTime? _assignSlot({
  required CompanionCandidate candidate,
  required CompanionContext context,
  required Iterable<PlannedCompanionCandidate> alreadySelected,
}) {
  DateTime scheduledAt = candidate.preferredAt;
  if (!candidate.safetyCritical && _inQuietHours(scheduledAt, context)) {
    scheduledAt = _nextQuietHoursEnd(scheduledAt, context);
  }
  if (!candidate.safetyCritical) {
    while (alreadySelected.any((PlannedCompanionCandidate selected) =>
        selected.scheduledAt.difference(scheduledAt).abs() <
        const Duration(minutes: 90))) {
      scheduledAt = scheduledAt.add(const Duration(minutes: 30));
    }
    if (_localDate(scheduledAt) != _localDate(candidate.preferredAt) &&
        candidate.baseValue < 60) {
      return null;
    }
  }
  return scheduledAt;
}

bool _inQuietHours(DateTime value, CompanionContext context) {
  final int minute = value.hour * 60 + value.minute;
  final int start = context.quietHoursStartMinute;
  final int end = context.quietHoursEndMinute;
  if (start == end) return false;
  if (start < end) return minute >= start && minute < end;
  return minute >= start || minute < end;
}

DateTime _nextQuietHoursEnd(DateTime value, CompanionContext context) {
  final int currentMinute = value.hour * 60 + value.minute;
  final bool endIsToday =
      context.quietHoursStartMinute < context.quietHoursEndMinute
          ? currentMinute < context.quietHoursEndMinute
          : currentMinute < context.quietHoursEndMinute;
  final DateTime date = endIsToday ? value : value.add(const Duration(days: 1));
  return DateTime(date.year, date.month, date.day).add(
    Duration(minutes: context.quietHoursEndMinute),
  );
}

String _localDate(DateTime value) {
  final String month = value.month.toString().padLeft(2, '0');
  final String day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
