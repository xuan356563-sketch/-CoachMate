import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 8, 12, 12);

  CoachMemoryV1 memory({
    CoachMemoryStatus status = CoachMemoryStatus.active,
    bool confirmed = true,
    bool mayMention = true,
    DateTime? validUntil,
    List<CoachSourceRef>? sources,
  }) {
    return CoachMemoryV1(
      memoryId: 'memory-1',
      athleteProfileId: 'athlete-1',
      category: CoachMemoryCategory.preference,
      subject: 'communication_style',
      value: const <String, Object?>{'tone': 'calm'},
      displayText: '你更喜欢平静直接的提醒',
      sources: sources ??
          <CoachSourceRef>[
            CoachSourceRef(
              sourceKind: 'conversation',
              sourceLocalId: 'message-1',
              sourceDigest: CoachDigest.sha256('message-1'),
              observedAt: now,
              summaryKey: '你在对话中明确告诉我',
            ),
          ],
      confidenceBps: 9000,
      importanceBps: 7000,
      sensitivity: CoachMemorySensitivity.low,
      status: status,
      version: 1,
      validityPolicy: CoachMemoryValidityPolicy.expiresAt,
      validFrom: now.subtract(const Duration(days: 1)),
      validUntil: validUntil ?? now.add(const Duration(days: 30)),
      mayMention: mayMention,
      userConfirmed: confirmed,
      syncAllowed: confirmed,
      confirmationBasis: CoachMemoryConfirmationBasis.panelConfirmation,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('活跃记忆必须同时具备来源、有效期和用户确认', () {
    expect(memory().validate(), isEmpty);
    expect(memory(sources: const <CoachSourceRef>[]).validate(),
        contains('memory_source_required'));
    expect(memory(confirmed: false).validate(),
        contains('memory_confirmation_required'));
    expect(
      memory(validUntil: now.subtract(const Duration(seconds: 1)))
          .isUsable(now),
      isFalse,
    );
  });

  test('推断记忆必须有两个不同来源且确认前不能进入决策', () {
    final CoachMemoryV1 candidate = memory(
      status: CoachMemoryStatus.readyForReview,
      confirmed: false,
      sources: <CoachSourceRef>[
        CoachSourceRef(
          sourceKind: 'conversation',
          sourceLocalId: 'message-1',
          sourceDigest: CoachDigest.sha256('message-1'),
          observedAt: now,
        ),
        CoachSourceRef(
          sourceKind: 'conversation',
          sourceLocalId: 'message-2',
          sourceDigest: CoachDigest.sha256('message-2'),
          observedAt: now,
        ),
      ],
    );

    expect(candidate.validate(inferred: true), isEmpty);
    expect(candidate.isUsable(now), isFalse);
    expect(
      const CoachMemoryRetriever().retrieve(
        memories: <CoachMemoryV1>[candidate],
        now: now,
      ).decisionMemories,
      isEmpty,
    );
  });

  test('检索最多返回六条且最多明确提起两条', () {
    final List<CoachMemoryV1> memories = List<CoachMemoryV1>.generate(
      8,
      (int index) => memory(mayMention: index != 0).copyWith(
        memoryId: 'memory-$index',
        importanceBps: 9000 - index,
      ),
    );

    final CoachMemoryRetrieval result = const CoachMemoryRetriever().retrieve(
      memories: memories,
      now: now,
    );

    expect(result.decisionMemories, hasLength(6));
    expect(result.surfaceableMemories, hasLength(2));
    expect(result.surfaceableMemories, everyElement(isA<CoachMemoryV1>()));
    expect(result.surfaceableMemories.any((CoachMemoryV1 m) => !m.mayMention),
        isFalse);
  });
}
