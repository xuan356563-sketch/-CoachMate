import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/local/companion_database_gateway.dart';
import 'package:trainflow_ai/features/companion/data/companion_repository.dart';
import 'package:trainflow_ai/features/companion/domain/companion_models.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 8, 11, 12);

  test('关系名称只存陪伴表，旧默认名在展示时升级为袋小满', () async {
    final _MemoryGateway gateway = _MemoryGateway();
    final CompanionRepository repository = CompanionRepository(
      gateway,
      clock: () => now,
    );

    final CompanionRelationship relation = await repository.ensureRelationship(
      athleteProfileId: 'athlete-1',
      fallbackCompanionName: '衡衡狸',
      startedOn: DateTime.utc(2026, 8, 1),
    );

    expect(relation.companionName, isNull);
    expect(repository.displayNameFor(relation, '衡衡狸'), '袋小满');
    expect(gateway.relationship?['companion_name'], isNull);
    expect(gateway.relationship?['species_id'], 'balance_raccoon');
  });

  test('消息、事实卡与行动仅写入 companion_messages，支持阅读和行动状态', () async {
    final _MemoryGateway gateway = _MemoryGateway();
    final CompanionRepository repository = CompanionRepository(
      gateway,
      clock: () => now,
    );
    final CompanionMessage message = CompanionMessage(
      messageId: 'message-1',
      athleteProfileId: 'athlete-1',
      localDate: '2026-08-11',
      intent: CompanionIntent.morningBrief,
      copyVariantId: 'mb-02',
      relationshipState: RelationshipState.steady,
      deliveryKind: CompanionDeliveryKind.proactive,
      privacyLevel: PrivacyLevel.l0,
      body: '状态看着可以。今天按计划来？',
      facts: const <CompanionFact>[
        CompanionFact(
          label: '训练',
          value: '30 分钟',
          source: CompanionFactSource.trainingLog,
          deepLink: '/plans',
        ),
      ],
      actions: const <CompanionAction>[
        CompanionAction(
          actionId: 'open-plan',
          label: '看看计划',
          kind: CompanionActionKind.primary,
          effect: CompanionActionEffect.openExistingRoute,
          route: '/plans',
        ),
      ],
      createdAt: now,
    );

    await repository.saveMessage(message);
    await repository.markOpened('message-1');
    await repository.recordAction(
        messageId: 'message-1', actionId: 'open-plan');
    final List<CompanionMessage> messages =
        await repository.listMessages('athlete-1');

    expect(messages, hasLength(1));
    expect(messages.single.facts.single.isDerived, isFalse);
    expect(messages.single.actions.single.route, '/plans');
    expect(messages.single.openedAt, now);
    expect(messages.single.actionTakenId, 'open-plan');
    expect(gateway.nonCompanionWrites, isZero);
  });

  test('不可主动提起的长期事件按原样保存，不会被关系设置覆盖', () async {
    final _MemoryGateway gateway = _MemoryGateway();
    final CompanionRepository repository = CompanionRepository(
      gateway,
      clock: () => now,
    );
    await repository.saveEvent(CompanionEvent(
      eventId: 'private-event',
      athleteProfileId: 'athlete-1',
      kind: 'manual_note',
      occurredOn: '2026-08-11',
      payload: <String, Object?>{'note': '仅自己可见'},
      isMentionable: false,
      createdAt: DateTime.utc(2026, 8, 11),
    ));

    final List<CompanionEvent> events =
        await repository.listEvents(athleteProfileId: 'athlete-1');
    expect(events.single.isMentionable, isFalse);
    expect(events.single.payload['note'], '仅自己可见');
  });
}

class _MemoryGateway implements CompanionDatabaseGateway {
  Map<String, Object?>? relationship;
  final Map<String, Map<String, Object?>> messages =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> events =
      <String, Map<String, Object?>>{};
  int nonCompanionWrites = 0;

  @override
  Future<int> purgeExpiredConversationMessageRows({
    required String athleteProfileId,
    required DateTime createdBefore,
  }) async {
    final List<String> expired = messages.entries
        .where((MapEntry<String, Map<String, Object?>> entry) =>
            entry.value['athlete_profile_id'] == athleteProfileId &&
            entry.value['retention_class'] == 'conversation_30d' &&
            DateTime.parse(entry.value['created_at']! as String)
                .isBefore(createdBefore))
        .map((MapEntry<String, Map<String, Object?>> entry) => entry.key)
        .toList(growable: false);
    for (final String messageId in expired) {
      messages.remove(messageId);
    }
    return expired.length;
  }

  @override
  Future<List<Map<String, Object?>>> listEventRows({
    required String athleteProfileId,
    String? kind,
  }) async =>
      events.values
          .where((Map<String, Object?> row) =>
              row['athlete_profile_id'] == athleteProfileId)
          .where(
              (Map<String, Object?> row) => kind == null || row['kind'] == kind)
          .map((Map<String, Object?> row) => Map<String, Object?>.from(row))
          .toList(growable: false);

  @override
  Future<List<Map<String, Object?>>> listMessageRows({
    required String athleteProfileId,
    String? localDate,
    DateTime? createdSince,
    int? limit,
  }) async =>
      messages.values
          .where((Map<String, Object?> row) =>
              row['athlete_profile_id'] == athleteProfileId)
          .where((Map<String, Object?> row) =>
              localDate == null || row['local_date'] == localDate)
          .map((Map<String, Object?> row) => Map<String, Object?>.from(row))
          .toList(growable: false);

  @override
  Future<void> markMessageOpened({
    required String messageId,
    required DateTime openedAt,
  }) async {
    messages[messageId]!['opened_at'] = openedAt.toIso8601String();
  }

  @override
  Future<void> recordMessageAction({
    required String messageId,
    required String actionId,
    required DateTime actedAt,
  }) async {
    messages[messageId]!
      ..['action_taken_id'] = actionId
      ..['opened_at'] = actedAt.toIso8601String();
  }

  @override
  Future<Map<String, Object?>?> readRelationshipRow(
          String athleteProfileId) async =>
      relationship == null ? null : Map<String, Object?>.from(relationship!);

  @override
  Future<void> upsertEventRow(Map<String, Object?> row) async {
    events[row['event_id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<void> upsertMessageRow(Map<String, Object?> row) async {
    messages[row['message_id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<void> upsertRelationshipRow(Map<String, Object?> row) async {
    relationship = Map<String, Object?>.from(row);
  }
}
