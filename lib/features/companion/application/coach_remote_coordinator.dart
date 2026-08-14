import 'package:trainflow_ai/features/companion/data/coach_api.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';

enum CoachCloudMode { disabled, shadow, strictIntersection }

class CoachRemoteResult {
  const CoachRemoteResult({
    required this.envelope,
    required this.verificationState,
    this.remoteDigest,
  });

  final CoachDecisionEnvelopeV1 envelope;
  final CoachVerificationState verificationState;
  final String? remoteDigest;
}

class CoachRemoteCoordinator {
  CoachRemoteCoordinator(
    this._api, {
    required this.mode,
    required bool Function() cloudConsentGranted,
  }) : _cloudConsentGranted = cloudConsentGranted;

  final CoachApi _api;
  final bool Function() _cloudConsentGranted;
  final CoachCloudMode mode;
  int? _projectionVersion;

  Future<CoachRemoteResult> evaluate({
    required TrainingStateSnapshotV1 snapshot,
    required List<CoachMemoryV1> memories,
    required CoachDecisionEnvelopeV1 local,
    required CoachIntent intent,
    required CoachEmotion emotion,
  }) async {
    if (mode == CoachCloudMode.disabled || !_cloudConsentGranted()) {
      return CoachRemoteResult(
        envelope: local,
        verificationState: CoachVerificationState.localOnly,
      );
    }
    try {
      final CoachProjectionReceipt projection = await _api.replaceProjection(
        snapshot: snapshot,
        memories: memories,
        baseVersion: _projectionVersion,
      );
      _projectionVersion = projection.version;
      final CoachDecisionEnvelopeV1 remote = await _api.evaluate(
        turnId: local.turnId,
        projection: projection,
        intent: intent,
        emotion: emotion,
        requestedActionIds: local.allowed
            .map((CoachActionOptionV1 action) => action.actionId)
            .toList(growable: false),
      );
      final String remoteDigest = CoachDigest.sha256(remote.toJson());
      if (mode == CoachCloudMode.shadow) {
        return CoachRemoteResult(
          envelope: local,
          verificationState: CoachVerificationState.localOnly,
          remoteDigest: remoteDigest,
        );
      }
      final CoachMergeResult merged = const CoachDecisionMerger().intersect(
        local: local,
        remote: remote,
      );
      return CoachRemoteResult(
        envelope: merged.envelope,
        verificationState: merged.verificationState,
        remoteDigest: remoteDigest,
      );
    } on Object {
      return CoachRemoteResult(
        envelope: local,
        verificationState: CoachVerificationState.remoteUnavailable,
      );
    }
  }
}
