import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/companion/application/coach_remote_coordinator.dart';
import 'package:trainflow_ai/features/companion/data/coach_api.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 8, 12, 8);

  TrainingStateSnapshotV1 snapshot() => TrainingStateSnapshotV1.create(
        snapshotId: 'snapshot-1',
        athleteProfileId: 'athlete-local-only',
        generatedAt: now,
        validUntil: now.add(const Duration(hours: 5)),
        localDate: '2026-08-12',
        timeZoneName: 'Asia/Shanghai',
        sourceRefs: <CoachSourceRef>[
          CoachSourceRef(
            sourceKind: 'pain_log',
            sourceLocalId: 'private-local-id',
            sourceDigest: List<String>.filled(64, 'a').join(),
            observedAt: now,
            summaryKey: '本机健康来源',
          ),
        ],
        plannedActionId: 'follow-existing-plan',
        plannedDurationMinutes: 30,
        availableMinutes: 30,
        maxPainScore: 5,
        recoveryBand: CoachRecoveryBand.green,
        completedSessions7d: 3,
        missedSessions7d: 0,
        safetyFlags: const <String>['pain_requires_adjustment'],
      );

  test('最小云投影不包含账号、来源编号、原始健康值或完整对话', () async {
    final _FakeCoachApiClient client = _FakeCoachApiClient();
    final CoachProjectionReceipt receipt = await CoachApi.forClient(client)
        .replaceProjection(
            snapshot: snapshot(), memories: const [], baseVersion: null);

    expect(receipt.version, 1);
    final Map<String, dynamic> body = client.lastPutBody!;
    expect(body.containsKey('profile'), isFalse);
    expect(body.toString(), isNot(contains('athlete-local-only')));
    expect(body.toString(), isNot(contains('private-local-id')));
    expect(body.toString(), isNot(contains('max_pain_score')));
    expect(body.toString(), isNot(contains('source_refs')));
    expect(body.toString(), isNot(contains('raw')));
  });

  test('评估请求只发送编号、摘要和枚举码', () async {
    final _FakeCoachApiClient client = _FakeCoachApiClient();
    final CoachApi api = CoachApi.forClient(client);
    final CoachProjectionReceipt receipt = await api.replaceProjection(
      snapshot: snapshot(),
      memories: const <CoachMemoryV1>[],
      baseVersion: null,
    );

    await api.evaluate(
      turnId: 'turn-1',
      projection: receipt,
      intent: CoachIntent.todayTraining,
      emotion: CoachEmotion.neutral,
      requestedActionIds: const <String>['request-existing-adjustment'],
    );

    final Map<String, dynamic> body = client.lastPostBody!;
    expect(body.keys.toSet(), <String>{
      'turn_id',
      'snapshot_id',
      'snapshot_digest',
      'memory_set_digest',
      'intent',
      'emotion',
      'contract_version',
      'contract_hash',
      'rule_set_version',
      'requested_action_ids',
    });
  });

  test('严格双端仲裁不会接受远端提高强度或延长时长', () async {
    final _FakeCoachApiClient client = _FakeCoachApiClient(
      remoteIntensity: 'high',
      remoteDuration: 90,
      remoteActionId: 'follow-existing-plan',
    );
    final CoachRemoteCoordinator coordinator = CoachRemoteCoordinator(
      CoachApi.forClient(client),
      mode: CoachCloudMode.strictIntersection,
      cloudConsentGranted: () => true,
    );
    final TrainingStateSnapshotV1 value = snapshot();
    final String digest = CoachDigest.sha256(value.toJson());
    final CoachDecisionEnvelopeV1 local = CoachDecisionEnvelopeV1(
      turnId: 'turn-1',
      snapshotId: value.snapshotId,
      snapshotDigest: digest,
      memorySetDigest: CoachDigest.sha256(const <Object>[]),
      allowed: const <CoachActionOptionV1>[
        CoachActionOptionV1(
          actionId: 'follow-existing-plan',
          intensity: CoachIntensity.low,
          durationMinutes: 30,
          requiresConfirmation: false,
        ),
      ],
      riskLevel: CoachRiskLevel.medium,
    );

    final CoachRemoteResult result = await coordinator.evaluate(
      snapshot: value,
      memories: const <CoachMemoryV1>[],
      local: local,
      intent: CoachIntent.todayTraining,
      emotion: CoachEmotion.neutral,
    );

    expect(result.envelope.allowed.single.intensity, CoachIntensity.low);
    expect(result.envelope.allowed.single.durationMinutes, 30);
    expect(result.envelope.riskLevel, CoachRiskLevel.medium);
  });

  test('未取得独立同意时即使灰度模式开启也不发送云投影', () async {
    final _FakeCoachApiClient client = _FakeCoachApiClient();
    final CoachRemoteCoordinator coordinator = CoachRemoteCoordinator(
      CoachApi.forClient(client),
      mode: CoachCloudMode.strictIntersection,
      cloudConsentGranted: () => false,
    );
    final TrainingStateSnapshotV1 value = snapshot();
    final CoachDecisionEnvelopeV1 local = CoachDecisionEnvelopeV1(
      turnId: 'turn-without-consent',
      snapshotId: value.snapshotId,
      snapshotDigest: CoachDigest.sha256(value.toJson()),
      memorySetDigest: CoachDigest.sha256(const <Object>[]),
      allowed: const <CoachActionOptionV1>[],
      riskLevel: CoachRiskLevel.low,
    );

    final CoachRemoteResult result = await coordinator.evaluate(
      snapshot: value,
      memories: const <CoachMemoryV1>[],
      local: local,
      intent: CoachIntent.todayTraining,
      emotion: CoachEmotion.neutral,
    );

    expect(client.lastPutBody, isNull);
    expect(result.envelope, same(local));
    expect(result.verificationState, CoachVerificationState.localOnly);
  });
}

class _FakeCoachApiClient implements CoachApiClient {
  _FakeCoachApiClient({
    this.remoteIntensity = 'recovery',
    this.remoteDuration = 0,
    this.remoteActionId = 'request-existing-adjustment',
  });

  final String remoteIntensity;
  final int remoteDuration;
  final String remoteActionId;
  Map<String, dynamic>? lastPutBody;
  Map<String, dynamic>? lastPostBody;

  @override
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) async {
    lastPutBody = body;
    if (path.contains('/consents/')) return <String, dynamic>{};
    return <String, dynamic>{
      'version': 1,
      'snapshot_id': body['state']['snapshot_id'],
      'snapshot_digest': body['state']['snapshot_digest'],
      'memory_set_digest': body['memory_set_digest'],
    };
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) async {
    lastPostBody = body;
    return <String, dynamic>{
      'turn_id': body['turn_id'],
      'snapshot_id': body['snapshot_id'],
      'snapshot_digest': body['snapshot_digest'],
      'memory_set_digest': body['memory_set_digest'],
      'contract_version': coachContractVersion,
      'contract_hash': coachContractHash,
      'rule_set_version': coachRuleSetVersion,
      'allowed': <Map<String, dynamic>>[
        <String, dynamic>{
          'action_id': remoteActionId,
          'intensity': remoteIntensity,
          'duration_minutes': remoteDuration,
          'requires_confirmation': false,
          'route': '/plans',
        },
      ],
      'forbidden_action_ids': <String>[],
      'risk_level': 'low',
      'reason_codes': <String>['remote_fixture'],
      'required_blocks': <String>[],
    };
  }

  @override
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    bool authenticated = true,
  }) async =>
      <String, dynamic>{};
}
