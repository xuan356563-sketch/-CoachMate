import 'dart:convert';

import 'package:trainflow_ai/data/local/companion_database_gateway.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';
import 'package:trainflow_ai/features/companion/domain/companion_models.dart';

/// 陪伴领域的本地仓储。它不持有同步能力，也不向既有业务表写入数据。
class CompanionRepository {
  CompanionRepository(this._database, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final CompanionDatabaseGateway _database;
  final DateTime Function() _clock;

  Future<CompanionRelationship?> loadRelationship(
      String athleteProfileId) async {
    final Map<String, Object?>? row =
        await _database.readRelationshipRow(athleteProfileId);
    return row == null ? null : _relationshipFromRow(row);
  }

  Future<CompanionRelationship> ensureRelationship({
    required String athleteProfileId,
    required String fallbackCompanionName,
    required DateTime startedOn,
  }) async {
    final CompanionRelationship? existing =
        await loadRelationship(athleteProfileId);
    if (existing != null) return existing;
    if (fallbackCompanionName.trim().isEmpty) {
      throw ArgumentError('衡衡狸名称不能为空');
    }
    final DateTime now = _clock().toUtc();
    final CompanionRelationship relationship = CompanionRelationship(
      athleteProfileId: athleteProfileId,
      startedOn: startedOn,
      createdAt: now,
      updatedAt: now,
    );
    await saveRelationship(relationship);
    return relationship;
  }

  String displayNameFor(
    CompanionRelationship relationship,
    String existingPetName,
  ) {
    final String? localName = relationship.companionName?.trim();
    return localName?.isNotEmpty == true ? localName! : existingPetName;
  }

  Future<void> saveRelationship(CompanionRelationship relationship) {
    return _database.upsertRelationshipRow(<String, Object?>{
      'athlete_profile_id': relationship.athleteProfileId,
      'companion_name': relationship.companionName,
      'species_id': 'balance_raccoon',
      'started_on': _localDate(relationship.startedOn),
      'last_resolved_state': relationship.lastResolvedState.name,
      'state_entered_on':
          relationship.stateEnteredOn?.toUtc().toIso8601String(),
      'disturb_tier': relationship.disturbTier.name,
      'quiet_hours_start_minute': relationship.quietHoursStartMinute,
      'quiet_hours_end_minute': relationship.quietHoursEndMinute,
      'notifications_enabled': relationship.notificationsEnabled ? 1 : 0,
      'notification_detail_enabled':
          relationship.notificationDetailEnabled ? 1 : 0,
      'boundaries_json': jsonEncode(
        relationship.boundaries
            .map((CompanionBoundaryTopic item) => item.name)
            .toList(),
      ),
      'consecutive_unopened': relationship.consecutiveUnopened,
      'created_at': relationship.createdAt.toUtc().toIso8601String(),
      'updated_at': relationship.updatedAt.toUtc().toIso8601String(),
    });
  }

  Future<List<CompanionMessage>> listMessages(
    String athleteProfileId, {
    DateTime? createdSince,
    int? limit,
  }) async {
    final List<Map<String, Object?>> rows = await _database.listMessageRows(
      athleteProfileId: athleteProfileId,
      createdSince: createdSince,
      limit: limit,
    );
    return rows.map(_messageFromRow).toList(growable: false);
  }

  Future<void> saveMessage(CompanionMessage message) {
    return _database.upsertMessageRow(<String, Object?>{
      'message_id': message.messageId,
      'athlete_profile_id': message.athleteProfileId,
      'local_date': message.localDate,
      'intent_id': message.intent.storageValue,
      'copy_variant_id': message.copyVariantId,
      'relationship_state': message.relationshipState.name,
      'delivery_kind': message.deliveryKind.name,
      'privacy_level': message.privacyLevel.storageValue,
      'notification_title': message.notificationTitle,
      'notification_body': message.notificationBody,
      'body': message.body,
      'facts_json': jsonEncode(
          message.facts.map((CompanionFact item) => item.toJson()).toList()),
      'actions_json': jsonEncode(message.actions
          .map((CompanionAction item) => item.toJson())
          .toList()),
      'scheduled_at': message.scheduledAt?.toUtc().toIso8601String(),
      'delivered_at': message.deliveredAt?.toUtc().toIso8601String(),
      'opened_at': message.openedAt?.toUtc().toIso8601String(),
      'action_taken_id': message.actionTakenId,
      'notification_id': message.notificationId,
      'model_version': 1,
      'message_role': message.messageRole.name,
      'thread_id': message.threadId,
      'turn_id': message.turnId,
      'source_snapshot_id': message.sourceSnapshotId,
      'trace_id': message.traceId,
      'retention_class':
          message.retention == CompanionMessageRetention.conversation30Days
              ? 'conversation_30d'
              : 'companion_history',
      'verification_state': message.verificationState.storageValue,
      'created_at': message.createdAt.toUtc().toIso8601String(),
      'updated_at': _clock().toUtc().toIso8601String(),
    });
  }

  Future<int> purgeExpiredConversationMessages(String athleteProfileId) {
    return _database.purgeExpiredConversationMessageRows(
      athleteProfileId: athleteProfileId,
      createdBefore: _clock().subtract(const Duration(days: 30)),
    );
  }

  Future<void> markOpened(String messageId) {
    return _database.markMessageOpened(
        messageId: messageId, openedAt: _clock());
  }

  Future<void> recordAction({
    required String messageId,
    required String actionId,
  }) {
    return _database.recordMessageAction(
      messageId: messageId,
      actionId: actionId,
      actedAt: _clock(),
    );
  }

  Future<List<CompanionEvent>> listEvents({
    required String athleteProfileId,
    String? kind,
  }) async {
    final List<Map<String, Object?>> rows = await _database.listEventRows(
      athleteProfileId: athleteProfileId,
      kind: kind,
    );
    return rows.map(_eventFromRow).toList(growable: false);
  }

  Future<void> saveEvent(CompanionEvent event) {
    return _database.upsertEventRow(<String, Object?>{
      'event_id': event.eventId,
      'athlete_profile_id': event.athleteProfileId,
      'kind': event.kind,
      'occurred_on': event.occurredOn,
      'payload_json': jsonEncode(event.payload),
      'is_mentionable': event.isMentionable ? 1 : 0,
      'last_mentioned_at': event.lastMentionedAt?.toUtc().toIso8601String(),
      'created_at': event.createdAt.toUtc().toIso8601String(),
    });
  }
}

CompanionRelationship _relationshipFromRow(Map<String, Object?> row) {
  return CompanionRelationship(
    athleteProfileId: _text(row, 'athlete_profile_id'),
    companionName: row['companion_name'] as String?,
    startedOn: DateTime.parse(_text(row, 'started_on')),
    lastResolvedState: _relationshipState(row['last_resolved_state']),
    stateEnteredOn: _dateTime(row['state_entered_on']),
    disturbTier: _disturbTier(row['disturb_tier']),
    quietHoursStartMinute: (row['quiet_hours_start_minute'] as int?) ?? 1320,
    quietHoursEndMinute: (row['quiet_hours_end_minute'] as int?) ?? 420,
    notificationsEnabled: row['notifications_enabled'] == 1,
    notificationDetailEnabled: row['notification_detail_enabled'] == 1,
    boundaries: _boundaries(row['boundaries_json']),
    consecutiveUnopened: (row['consecutive_unopened'] as int?) ?? 0,
    createdAt: DateTime.parse(_text(row, 'created_at')),
    updatedAt: DateTime.parse(_text(row, 'updated_at')),
  );
}

CompanionMessage _messageFromRow(Map<String, Object?> row) {
  return CompanionMessage(
    messageId: _text(row, 'message_id'),
    athleteProfileId: _text(row, 'athlete_profile_id'),
    localDate: _text(row, 'local_date'),
    intent: _intent(row['intent_id']),
    copyVariantId: _text(row, 'copy_variant_id'),
    relationshipState: _relationshipState(row['relationship_state']),
    deliveryKind: _deliveryKind(row['delivery_kind']),
    privacyLevel: _privacyLevel(row['privacy_level']),
    notificationTitle: row['notification_title'] as String?,
    notificationBody: row['notification_body'] as String?,
    body: _text(row, 'body'),
    facts: _facts(row['facts_json']),
    actions: _actions(row['actions_json']),
    scheduledAt: _dateTime(row['scheduled_at']),
    deliveredAt: _dateTime(row['delivered_at']),
    openedAt: _dateTime(row['opened_at']),
    actionTakenId: row['action_taken_id'] as String?,
    notificationId: row['notification_id'] as int?,
    messageRole: CompanionMessageRole.values.firstWhere(
      (CompanionMessageRole item) => item.name == row['message_role'],
      orElse: () => CompanionMessageRole.companion,
    ),
    threadId: (row['thread_id'] as String?) ?? 'default',
    turnId: row['turn_id'] as String?,
    sourceSnapshotId: row['source_snapshot_id'] as String?,
    traceId: row['trace_id'] as String?,
    retention: row['retention_class'] == 'conversation_30d'
        ? CompanionMessageRetention.conversation30Days
        : CompanionMessageRetention.companionHistory,
    verificationState: CoachVerificationState.values.firstWhere(
      (CoachVerificationState item) =>
          item.storageValue == row['verification_state'],
      orElse: () => CoachVerificationState.localOnly,
    ),
    createdAt: DateTime.parse(_text(row, 'created_at')),
  );
}

CompanionEvent _eventFromRow(Map<String, Object?> row) => CompanionEvent(
      eventId: _text(row, 'event_id'),
      athleteProfileId: _text(row, 'athlete_profile_id'),
      kind: _text(row, 'kind'),
      occurredOn: _text(row, 'occurred_on'),
      payload: Map<String, Object?>.from(_jsonMap(row['payload_json'])),
      isMentionable: row['is_mentionable'] == 1,
      lastMentionedAt: _dateTime(row['last_mentioned_at']),
      createdAt: DateTime.parse(_text(row, 'created_at')),
    );

List<CompanionFact> _facts(Object? raw) => _jsonList(raw).map((Object? value) {
      final Map<String, Object?> item =
          Map<String, Object?>.from(value! as Map);
      return CompanionFact(
        label: _text(item, 'label'),
        value: _text(item, 'value'),
        baseline: item['baseline'] as String?,
        delta: item['delta'] as String?,
        source: CompanionFactSource.values.firstWhere(
          (CompanionFactSource source) => source.storageValue == item['source'],
          orElse: () => CompanionFactSource.derived,
        ),
        deepLink: item['deepLink'] as String?,
        isSensitive: item['isSensitive'] == true,
        sourceLocalId: item['sourceLocalId'] as String?,
        sourceDigest: item['sourceDigest'] as String?,
        observedAt: _dateTime(item['observedAt']),
        sourceSummary: item['sourceSummary'] as String?,
      );
    }).toList(growable: false);

List<CompanionAction> _actions(Object? raw) =>
    _jsonList(raw).map((Object? value) {
      final Map<String, Object?> item =
          Map<String, Object?>.from(value! as Map);
      return CompanionAction(
        actionId: _text(item, 'actionId'),
        label: _text(item, 'label'),
        kind: CompanionActionKind.values.byName(_text(item, 'kind')),
        route: item['route'] as String?,
        effect: CompanionActionEffect.values.byName(_text(item, 'effect')),
      );
    }).toList(growable: false);

List<Object?> _jsonList(Object? raw) {
  if (raw is! String || raw.isEmpty) return const <Object?>[];
  final Object? decoded = jsonDecode(raw);
  return decoded is List ? List<Object?>.from(decoded) : const <Object?>[];
}

Map<String, Object?> _jsonMap(Object? raw) {
  if (raw is! String || raw.isEmpty) return const <String, Object?>{};
  final Object? decoded = jsonDecode(raw);
  return decoded is Map
      ? Map<String, Object?>.from(decoded)
      : const <String, Object?>{};
}

Set<CompanionBoundaryTopic> _boundaries(Object? raw) => _jsonList(raw)
    .whereType<String>()
    .map((String item) => CompanionBoundaryTopic.values
        .where((CompanionBoundaryTopic topic) => topic.name == item))
    .where((Iterable<CompanionBoundaryTopic> items) => items.isNotEmpty)
    .map((Iterable<CompanionBoundaryTopic> items) => items.first)
    .toSet();

RelationshipState _relationshipState(Object? raw) =>
    RelationshipState.values.firstWhere(
      (RelationshipState state) => state.name == raw,
      orElse: () => RelationshipState.onboarding,
    );

DisturbTier _disturbTier(Object? raw) => DisturbTier.values.firstWhere(
      (DisturbTier tier) => tier.name == raw,
      orElse: () => DisturbTier.normal,
    );

CompanionIntent _intent(Object? raw) => CompanionIntent.values.firstWhere(
      (CompanionIntent intent) => intent.storageValue == raw,
      orElse: () => CompanionIntent.morningBrief,
    );

CompanionDeliveryKind _deliveryKind(Object? raw) =>
    CompanionDeliveryKind.values.firstWhere(
      (CompanionDeliveryKind kind) => kind.name == raw,
      orElse: () => CompanionDeliveryKind.proactive,
    );

PrivacyLevel _privacyLevel(Object? raw) => PrivacyLevel.values.firstWhere(
      (PrivacyLevel level) => level.storageValue == raw,
      orElse: () => PrivacyLevel.l0,
    );

DateTime? _dateTime(Object? raw) =>
    raw is String && raw.isNotEmpty ? DateTime.parse(raw) : null;

String _text(Map<String, Object?> row, String key) {
  final String? value = row[key] as String?;
  if (value == null || value.isEmpty) throw StateError('陪伴本地数据缺少$key');
  return value;
}

String _localDate(DateTime value) {
  final String month = value.month.toString().padLeft(2, '0');
  final String day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
