import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainflow_ai/features/auth/data/authenticated_api_client.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';

final coachApiProvider = Provider<CoachApi>(
  (Ref ref) => CoachApi(ref.watch(authenticatedApiClientProvider)),
);

const String coachCloudConsentStorageKey = 'trainflow.coach_cloud_consent.v1';

abstract interface class CoachApiClient {
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated,
  });

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated,
  });

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    bool authenticated,
  });
}

class CoachProjectionReceipt {
  const CoachProjectionReceipt({
    required this.version,
    required this.snapshotId,
    required this.snapshotDigest,
    required this.memorySetDigest,
  });

  final int version;
  final String snapshotId;
  final String snapshotDigest;
  final String memorySetDigest;
}

class CoachApi {
  CoachApi(AuthenticatedApiClient client)
      : _client = _AuthenticatedCoachApiClient(client);

  const CoachApi.forClient(this._client);

  final CoachApiClient _client;

  Future<void> setCloudConsent({required bool granted}) {
    return _client
        .putJson(
          '/v1/account/consents/coach-cloud-projection',
          <String, dynamic>{
            'granted': granted,
            'document_version': 'coach-cloud-projection-2026-08-12.1',
          },
          authenticated: true,
        )
        .then((_) {});
  }

  Future<CoachProjectionReceipt> replaceProjection({
    required TrainingStateSnapshotV1 snapshot,
    required List<CoachMemoryV1> memories,
    required int? baseVersion,
  }) async {
    final List<Map<String, dynamic>> projectedMemories = memories
        .where((CoachMemoryV1 memory) =>
            memory.isUsable(snapshot.generatedAt) && memory.syncAllowed)
        .map(_projectMemory)
        .toList(growable: false);
    final String memorySetDigest = CoachDigest.sha256(projectedMemories);
    final Map<String, dynamic> response = await _client.putJson(
      '/v1/coach/projections/current',
      <String, dynamic>{
        'base_version': baseVersion,
        'state': _projectState(snapshot),
        'memories': projectedMemories,
        'memory_set_digest': memorySetDigest,
      },
      authenticated: true,
    );
    return CoachProjectionReceipt(
      version: (response['version'] as num).toInt(),
      snapshotId: response['snapshot_id']! as String,
      snapshotDigest: response['snapshot_digest']! as String,
      memorySetDigest: response['memory_set_digest']! as String,
    );
  }

  Future<CoachDecisionEnvelopeV1> evaluate({
    required String turnId,
    required CoachProjectionReceipt projection,
    required CoachIntent intent,
    required CoachEmotion emotion,
    required List<String> requestedActionIds,
  }) async {
    final Map<String, dynamic> response = await _client.postJson(
      '/v1/coach/evaluations',
      <String, dynamic>{
        'turn_id': turnId,
        'snapshot_id': projection.snapshotId,
        'snapshot_digest': projection.snapshotDigest,
        'memory_set_digest': projection.memorySetDigest,
        'intent': intent.storageValue,
        'emotion': emotion.name,
        'contract_version': coachContractVersion,
        'contract_hash': coachContractHash,
        'rule_set_version': coachRuleSetVersion,
        'requested_action_ids': requestedActionIds,
      },
      authenticated: true,
    );
    return _envelopeFromJson(response);
  }

  Future<void> deleteProjection() => _client
      .deleteJson('/v1/coach/projections/current', authenticated: true)
      .then((_) {});
}

class _AuthenticatedCoachApiClient implements CoachApiClient {
  const _AuthenticatedCoachApiClient(this._client);

  final AuthenticatedApiClient _client;

  @override
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    bool authenticated = true,
  }) =>
      _client.deleteJson(path, authenticated: authenticated);

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) =>
      _client.postJson(path, body, authenticated: authenticated);

  @override
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) =>
      _client.putJson(path, body, authenticated: authenticated);
}

Map<String, dynamic> _projectState(TrainingStateSnapshotV1 snapshot) =>
    <String, dynamic>{
      'snapshot_id': snapshot.snapshotId,
      'source_digest': snapshot.sourceDigest,
      'snapshot_digest': CoachDigest.sha256(snapshot.toJson()),
      'contract_version': snapshot.contractVersion,
      'contract_hash': snapshot.contractHash,
      'rule_set_version': snapshot.ruleSetVersion,
      'generated_at': snapshot.generatedAt.toUtc().toIso8601String(),
      'valid_until': snapshot.validUntil.toUtc().toIso8601String(),
      'local_date': snapshot.localDate,
      'planned_action_id': snapshot.plannedActionId,
      'planned_duration_minutes': snapshot.plannedDurationMinutes,
      'available_minutes': snapshot.availableMinutes,
      'recovery_band': snapshot.recoveryBand.name,
      'completed_sessions_7d': snapshot.completedSessions7d,
      'missed_sessions_7d': snapshot.missedSessions7d,
      'safety_flags': snapshot.safetyFlags
          .where(<String>{
            'severe_pain',
            'pain_requires_adjustment',
            'injury_red_flag',
          }.contains)
          .toList(growable: false),
      'quality_codes': snapshot.qualityCodes,
      'missing_fields': snapshot.missingFields,
    };

Map<String, dynamic> _projectMemory(CoachMemoryV1 memory) => <String, dynamic>{
      'memory_id': memory.memoryId,
      'category': memory.category.storageValue,
      'version': memory.version,
      'display_text': memory.displayText,
      'confidence_bps': memory.confidenceBps,
      'valid_until': memory.validUntil?.toUtc().toIso8601String(),
      'until_revoked':
          memory.validityPolicy == CoachMemoryValidityPolicy.untilRevoked,
      'may_mention': memory.mayMention,
      'user_confirmed': memory.userConfirmed,
      'sync_allowed': memory.syncAllowed,
      'source_digests': memory.sources
          .map((CoachSourceRef source) => source.sourceDigest)
          .toList(growable: false),
    };

CoachDecisionEnvelopeV1 _envelopeFromJson(Map<String, dynamic> json) {
  return CoachDecisionEnvelopeV1(
    turnId: json['turn_id']! as String,
    snapshotId: json['snapshot_id']! as String,
    snapshotDigest: json['snapshot_digest']! as String,
    memorySetDigest: json['memory_set_digest']! as String,
    contractVersion: (json['contract_version'] as num).toInt(),
    contractHash: json['contract_hash']! as String,
    ruleSetVersion: json['rule_set_version']! as String,
    allowed: (json['allowed']! as List<Object?>).map((Object? raw) {
      final Map<String, dynamic> item = Map<String, dynamic>.from(raw! as Map);
      return CoachActionOptionV1(
        actionId: item['action_id']! as String,
        intensity: CoachIntensity.values.byName(
          item['intensity']! as String,
        ),
        durationMinutes: (item['duration_minutes'] as num).toInt(),
        requiresConfirmation: item['requires_confirmation']! as bool,
        route: item['route'] as String?,
      );
    }).toList(growable: false),
    forbiddenActionIds:
        List<String>.from(json['forbidden_action_ids']! as List<Object?>),
    riskLevel: CoachRiskLevel.values.byName(json['risk_level']! as String),
    reasonCodes: List<String>.from(json['reason_codes']! as List<Object?>),
    requiredBlocks:
        List<String>.from(json['required_blocks']! as List<Object?>),
  );
}
