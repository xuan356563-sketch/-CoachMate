import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/companion/application/companion_arbitrator.dart';
import 'package:trainflow_ai/features/companion/domain/companion_models.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 11, 9);

  CompanionContext context({
    DisturbTier disturbTier = DisturbTier.normal,
    int consecutiveUnopened = 0,
    bool notificationDetailEnabled = false,
    Set<CompanionBoundaryTopic> boundaries = const <CompanionBoundaryTopic>{},
  }) {
    return CompanionContext(
      relationshipDays: 12,
      daysSinceLastActivity: 0,
      missedInLast7Days: 0,
      currentStreak: 0,
      wasAwayYesterday: false,
      hasSignalToday: true,
      disturbTier: disturbTier,
      consecutiveUnopened: consecutiveUnopened,
      notificationDetailEnabled: notificationDetailEnabled,
      boundaries: boundaries,
    );
  }

  CompanionCandidate candidate({
    String id = 'candidate',
    CompanionIntent intent = CompanionIntent.morningBrief,
    int urgency = 50,
    int value = 70,
    PrivacyLevel privacy = PrivacyLevel.l1,
    Set<CompanionBoundaryTopic> topics = const <CompanionBoundaryTopic>{},
    bool safetyCritical = false,
    List<CompanionFact> facts = const <CompanionFact>[],
    List<CompanionAction> actions = const <CompanionAction>[],
    DateTime? preferredAt,
  }) {
    return CompanionCandidate(
      copyVariantId: id,
      intent: intent,
      body: '搭子消息',
      urgency: urgency,
      baseValue: value,
      defaultPrivacy: privacy,
      deliveryKind: CompanionDeliveryKind.proactive,
      preferredAt: preferredAt ?? now.add(const Duration(hours: 1)),
      boundaryTopics: topics,
      safetyCritical: safetyCritical,
      facts: facts,
      actions: actions,
    );
  }

  test('连续三条未读降频，连续六条未读停止主动触达', () {
    final List<CompanionCandidate> candidates = <CompanionCandidate>[
      candidate(id: 'one', urgency: 70),
      candidate(id: 'two', urgency: 60),
    ];

    expect(
      arbitrateCompanionCandidates(
        context: context(consecutiveUnopened: 3),
        relationshipState: RelationshipState.steady,
        candidates: candidates,
        history: const <CompanionMessage>[],
        planningAt: now,
      ).selected,
      hasLength(1),
    );
    expect(
      arbitrateCompanionCandidates(
        context: context(consecutiveUnopened: 6),
        relationshipState: RelationshipState.steady,
        candidates: candidates,
        history: const <CompanionMessage>[],
        planningAt: now,
      ).selected,
      isEmpty,
    );
  });

  test('边界会屏蔽普通候选，七分疼痛安全消息不受屏蔽', () {
    final CompanionCandidate sleep = candidate(
      id: 'sleep',
      topics: const <CompanionBoundaryTopic>{CompanionBoundaryTopic.sleep},
    );
    final CompanionCandidate injury = candidate(
      id: 'injury',
      intent: CompanionIntent.injuryCare,
      safetyCritical: true,
      topics: const <CompanionBoundaryTopic>{CompanionBoundaryTopic.pain},
      actions: const <CompanionAction>[],
    );

    final CompanionArbitrationResult result = arbitrateCompanionCandidates(
      context: context(
        disturbTier: DisturbTier.silent,
        boundaries: const <CompanionBoundaryTopic>{
          CompanionBoundaryTopic.sleep,
          CompanionBoundaryTopic.pain,
        },
      ),
      relationshipState: RelationshipState.injured,
      candidates: <CompanionCandidate>[sleep, injury],
      history: const <CompanionMessage>[],
      planningAt: now,
    );

    expect(
        result.selected
            .map((PlannedCompanionCandidate item) => item.copyVariantId),
        <String>['injury']);
  });

  test('同一变体三十天内不重复，静默期不补发未读', () {
    final CompanionMessage delivered = CompanionMessage(
      messageId: 'old',
      athleteProfileId: 'athlete',
      localDate: '2026-07-20',
      intent: CompanionIntent.morningBrief,
      copyVariantId: 'repeat',
      relationshipState: RelationshipState.steady,
      deliveryKind: CompanionDeliveryKind.proactive,
      privacyLevel: PrivacyLevel.l0,
      body: '旧消息',
      createdAt: DateTime(2026, 7, 20),
    );
    final CompanionCandidate repeated = candidate(id: 'repeat');

    expect(
      arbitrateCompanionCandidates(
        context: context(),
        relationshipState: RelationshipState.steady,
        candidates: <CompanionCandidate>[repeated],
        history: <CompanionMessage>[delivered],
        planningAt: now,
      ).selected,
      isEmpty,
    );
    expect(
      arbitrateCompanionCandidates(
        context: context(disturbTier: DisturbTier.silent),
        relationshipState: RelationshipState.steady,
        candidates: <CompanionCandidate>[candidate(id: 'fresh')],
        history: <CompanionMessage>[delivered],
        planningAt: now,
      ).selected,
      isEmpty,
    );
  });

  test('锁屏默认及敏感、伤病场景均强制 L0', () {
    final CompanionCandidate normal =
        candidate(id: 'normal', privacy: PrivacyLevel.l2);
    final CompanionCandidate sensitive = candidate(
      id: 'sensitive',
      facts: const <CompanionFact>[
        CompanionFact(
          label: '睡眠',
          value: '6 小时',
          source: CompanionFactSource.healthKit,
          isSensitive: true,
        ),
      ],
    );
    final CompanionCandidate injury = candidate(
      id: 'injury',
      intent: CompanionIntent.injuryCare,
      safetyCritical: true,
      privacy: PrivacyLevel.l2,
    );

    final CompanionArbitrationResult defaults = arbitrateCompanionCandidates(
      context: context(),
      relationshipState: RelationshipState.steady,
      candidates: <CompanionCandidate>[normal],
      history: const <CompanionMessage>[],
      planningAt: now,
    );
    expect(defaults.selected.single.privacyLevel, PrivacyLevel.l0);

    final CompanionArbitrationResult details = arbitrateCompanionCandidates(
      context: context(notificationDetailEnabled: true),
      relationshipState: RelationshipState.injured,
      candidates: <CompanionCandidate>[sensitive, injury],
      history: const <CompanionMessage>[],
      planningAt: now,
    );
    expect(
      details.selected
          .map((PlannedCompanionCandidate item) => item.privacyLevel),
      everyElement(PrivacyLevel.l0),
    );
  });

  test('疼痛七分只保留安全消息且没有训练入口', () {
    final CompanionCandidate safety = candidate(
      id: 'ic-03',
      intent: CompanionIntent.injuryCare,
      safetyCritical: true,
      actions: const <CompanionAction>[
        CompanionAction(
          actionId: 'open-pain-log',
          label: '看看记录',
          kind: CompanionActionKind.primary,
          effect: CompanionActionEffect.openExistingRoute,
          route: '/data-center',
        ),
      ],
    );
    final CompanionCandidate training = candidate(
      id: 'pre',
      intent: CompanionIntent.preWorkout,
      actions: const <CompanionAction>[
        CompanionAction(
          actionId: 'start',
          label: '开始',
          kind: CompanionActionKind.primary,
          effect: CompanionActionEffect.openExistingRoute,
          route: '/guided-workout',
        ),
      ],
    );
    final CompanionArbitrationResult result = arbitrateCompanionCandidates(
      context: context(),
      relationshipState: RelationshipState.injured,
      candidates: <CompanionCandidate>[training, safety],
      history: const <CompanionMessage>[],
      planningAt: now,
    );

    expect(result.selected, hasLength(1));
    expect(result.selected.single.intent, CompanionIntent.injuryCare);
    expect(
      result.selected.single.actions
          .where((CompanionAction action) => action.route == '/guided-workout'),
      isEmpty,
    );
  });

  test('回归日只保留一条欢迎消息，普通消息至少错峰九十分钟', () {
    final CompanionCandidate returning = candidate(
      id: 'returning',
      intent: CompanionIntent.returning,
      preferredAt: now.add(const Duration(hours: 1)),
    );
    final CompanionCandidate morning = candidate(
      id: 'morning',
      preferredAt: now.add(const Duration(hours: 1)),
    );
    final CompanionCandidate second = candidate(
      id: 'second',
      intent: CompanionIntent.preWorkout,
      preferredAt: now.add(const Duration(hours: 1, minutes: 10)),
    );

    final CompanionArbitrationResult returningResult =
        arbitrateCompanionCandidates(
      context: context(),
      relationshipState: RelationshipState.returning,
      candidates: <CompanionCandidate>[morning, returning],
      history: const <CompanionMessage>[],
      planningAt: now,
    );
    expect(
        returningResult.selected
            .map((PlannedCompanionCandidate item) => item.intent),
        <CompanionIntent>[CompanionIntent.returning]);

    final CompanionArbitrationResult steadyResult =
        arbitrateCompanionCandidates(
      context: context(notificationDetailEnabled: true),
      relationshipState: RelationshipState.steady,
      candidates: <CompanionCandidate>[morning, second],
      history: const <CompanionMessage>[],
      planningAt: now,
    );
    expect(steadyResult.selected, hasLength(2));
    expect(
      steadyResult.selected[1].scheduledAt
          .difference(steadyResult.selected[0].scheduledAt)
          .inMinutes,
      greaterThanOrEqualTo(90),
    );
  });
}
