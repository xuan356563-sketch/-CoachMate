import 'coach_common.dart';
import 'coach_memory.dart';

export 'coach_common.dart';
export 'coach_memory.dart';

enum CoachIntent {
  todayTraining,
  explainPlan,
  recovery,
  checkIn,
  emotionalSupport,
  manageMemory;

  String get storageValue => switch (this) {
        CoachIntent.todayTraining => 'today_training',
        CoachIntent.explainPlan => 'explain_plan',
        CoachIntent.recovery => 'recovery',
        CoachIntent.checkIn => 'check_in',
        CoachIntent.emotionalSupport => 'emotional_support',
        CoachIntent.manageMemory => 'manage_memory',
      };

  bool get requiresTrainingState => switch (this) {
        CoachIntent.todayTraining ||
        CoachIntent.explainPlan ||
        CoachIntent.recovery ||
        CoachIntent.checkIn =>
          true,
        _ => false,
      };
}

enum CoachEmotion { neutral, low, anxious, frustrated, positive }

enum CoachRecoveryBand { unknown, green, amber, red }

enum CoachRiskLevel { low, medium, high, critical }

enum CoachIntensity { rest, recovery, low, moderate, high }

enum CoachTone { calm, warm, concise }

enum CoachVerificationState {
  localOnly,
  dualVerified,
  contractMismatch,
  snapshotMismatch,
  memoryMismatch,
  remoteUnavailable;

  String get storageValue => switch (this) {
        CoachVerificationState.localOnly => 'local_only',
        CoachVerificationState.dualVerified => 'dual_verified',
        CoachVerificationState.contractMismatch => 'contract_mismatch',
        CoachVerificationState.snapshotMismatch => 'snapshot_mismatch',
        CoachVerificationState.memoryMismatch => 'memory_mismatch',
        CoachVerificationState.remoteUnavailable => 'remote_unavailable',
      };
}

class TrainingStateSnapshotV1 {
  const TrainingStateSnapshotV1({
    required this.snapshotId,
    required this.athleteProfileId,
    required this.contractVersion,
    required this.contractHash,
    required this.ruleSetVersion,
    required this.generatedAt,
    required this.validUntil,
    required this.localDate,
    required this.timeZoneName,
    required this.sourceDigest,
    required this.sourceRefs,
    required this.recoveryBand,
    required this.completedSessions7d,
    required this.missedSessions7d,
    this.plannedActionId,
    this.plannedDurationMinutes,
    this.availableMinutes,
    this.maxPainScore,
    this.severePain = false,
    this.safetyFlags = const <String>[],
    this.qualityCodes = const <String>[],
    this.missingFields = const <String>[],
  });

  factory TrainingStateSnapshotV1.create({
    required String snapshotId,
    required String athleteProfileId,
    required DateTime generatedAt,
    required DateTime validUntil,
    required String localDate,
    required String timeZoneName,
    required List<CoachSourceRef> sourceRefs,
    required CoachRecoveryBand recoveryBand,
    required int completedSessions7d,
    required int missedSessions7d,
    String? plannedActionId,
    int? plannedDurationMinutes,
    int? availableMinutes,
    int? maxPainScore,
    bool severePain = false,
    List<String> safetyFlags = const <String>[],
    List<String> qualityCodes = const <String>[],
    List<String> missingFields = const <String>[],
  }) {
    final DateTime maximum = generatedAt.add(const Duration(hours: 6));
    final DateTime boundedValidUntil =
        validUntil.isAfter(maximum) ? maximum : validUntil;
    final Map<String, Object?> sourceValues = _snapshotSourceValues(
      sourceRefs: sourceRefs,
      plannedActionId: plannedActionId,
      plannedDurationMinutes: plannedDurationMinutes,
      availableMinutes: availableMinutes,
      maxPainScore: maxPainScore,
      severePain: severePain,
      recoveryBand: recoveryBand,
      completedSessions7d: completedSessions7d,
      missedSessions7d: missedSessions7d,
      safetyFlags: safetyFlags,
      qualityCodes: qualityCodes,
      missingFields: missingFields,
    );
    return TrainingStateSnapshotV1(
      snapshotId: snapshotId,
      athleteProfileId: athleteProfileId,
      contractVersion: coachContractVersion,
      contractHash: coachContractHash,
      ruleSetVersion: coachRuleSetVersion,
      generatedAt: generatedAt,
      validUntil: boundedValidUntil,
      localDate: localDate,
      timeZoneName: timeZoneName,
      sourceDigest: CoachDigest.sha256(sourceValues),
      sourceRefs: List<CoachSourceRef>.unmodifiable(sourceRefs),
      plannedActionId: plannedActionId,
      plannedDurationMinutes: plannedDurationMinutes,
      availableMinutes: availableMinutes,
      maxPainScore: maxPainScore,
      severePain: severePain,
      recoveryBand: recoveryBand,
      completedSessions7d: completedSessions7d,
      missedSessions7d: missedSessions7d,
      safetyFlags: List<String>.unmodifiable(safetyFlags.toSet()),
      qualityCodes: List<String>.unmodifiable(qualityCodes.toSet()),
      missingFields: List<String>.unmodifiable(missingFields.toSet()),
    );
  }

  final String snapshotId;
  final String athleteProfileId;
  final int contractVersion;
  final String contractHash;
  final String ruleSetVersion;
  final DateTime generatedAt;
  final DateTime validUntil;
  final String localDate;
  final String timeZoneName;
  final String sourceDigest;
  final List<CoachSourceRef> sourceRefs;
  final String? plannedActionId;
  final int? plannedDurationMinutes;
  final int? availableMinutes;
  final int? maxPainScore;
  final bool severePain;
  final CoachRecoveryBand recoveryBand;
  final int completedSessions7d;
  final int missedSessions7d;
  final List<String> safetyFlags;
  final List<String> qualityCodes;
  final List<String> missingFields;

  factory TrainingStateSnapshotV1.fromJson(Map<String, Object?> json) {
    return TrainingStateSnapshotV1(
      snapshotId: json['snapshot_id']! as String,
      athleteProfileId: json['athlete_profile_id']! as String,
      contractVersion: json['contract_version']! as int,
      contractHash: json['contract_hash']! as String,
      ruleSetVersion: json['rule_set_version']! as String,
      generatedAt: DateTime.parse(json['generated_at']! as String),
      validUntil: DateTime.parse(json['valid_until']! as String),
      localDate: json['local_date']! as String,
      timeZoneName: json['time_zone_name']! as String,
      sourceDigest: json['source_digest']! as String,
      sourceRefs: (json['source_refs']! as List<Object?>)
          .map((Object? item) => CoachSourceRef.fromJson(
                Map<String, Object?>.from(item! as Map),
              ))
          .toList(growable: false),
      plannedActionId: json['planned_action_id'] as String?,
      plannedDurationMinutes: json['planned_duration_minutes'] as int?,
      availableMinutes: json['available_minutes'] as int?,
      maxPainScore: json['max_pain_score'] as int?,
      severePain: (json['safety_flags'] as List<Object?>? ?? const <Object?>[])
          .contains('severe_pain'),
      recoveryBand: CoachRecoveryBand.values.firstWhere(
        (CoachRecoveryBand item) => item.name == json['recovery_band'],
        orElse: () => CoachRecoveryBand.unknown,
      ),
      completedSessions7d: json['completed_sessions_7d']! as int,
      missedSessions7d: json['missed_sessions_7d']! as int,
      safetyFlags: List<String>.from(
        json['safety_flags'] as List<Object?>? ?? const <Object?>[],
      ),
      qualityCodes: List<String>.from(
        json['quality_codes'] as List<Object?>? ?? const <Object?>[],
      ),
      missingFields: List<String>.from(
        json['missing_fields'] as List<Object?>? ?? const <Object?>[],
      ),
    );
  }

  List<String> validateAt(DateTime now) {
    final List<String> issues = <String>[];
    if (contractVersion != coachContractVersion ||
        contractHash != coachContractHash ||
        ruleSetVersion != coachRuleSetVersion) {
      issues.add('snapshot_contract_mismatch');
    }
    if (snapshotId.trim().isEmpty || athleteProfileId.trim().isEmpty) {
      issues.add('snapshot_identity_missing');
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(localDate)) {
      issues.add('snapshot_local_date_invalid');
    }
    if (generatedAt.isAfter(now.add(const Duration(minutes: 5)))) {
      issues.add('snapshot_generated_in_future');
    }
    if (!validUntil.isAfter(now)) issues.add('snapshot_expired');
    if (validUntil.isAfter(generatedAt.add(const Duration(hours: 6)))) {
      issues.add('snapshot_ttl_exceeded');
    }
    if (sourceRefs.isEmpty) issues.add('snapshot_source_required');
    for (final CoachSourceRef source in sourceRefs) {
      issues.addAll(source.validate());
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceDigest)) {
      issues.add('snapshot_source_digest_invalid');
    } else if (CoachDigest.sha256(_snapshotSourceValues(
          sourceRefs: sourceRefs,
          plannedActionId: plannedActionId,
          plannedDurationMinutes: plannedDurationMinutes,
          availableMinutes: availableMinutes,
          maxPainScore: maxPainScore,
          severePain: severePain,
          recoveryBand: recoveryBand,
          completedSessions7d: completedSessions7d,
          missedSessions7d: missedSessions7d,
          safetyFlags: safetyFlags,
          qualityCodes: qualityCodes,
          missingFields: missingFields,
        )) !=
        sourceDigest) {
      issues.add('snapshot_source_digest_mismatch');
    }
    if (maxPainScore != null && (maxPainScore! < 0 || maxPainScore! > 10)) {
      issues.add('snapshot_pain_invalid');
    }
    return issues.toSet().toList(growable: false);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'snapshot_id': snapshotId,
        'athlete_profile_id': athleteProfileId,
        'contract_version': contractVersion,
        'contract_hash': contractHash,
        'rule_set_version': ruleSetVersion,
        'generated_at': generatedAt.toUtc().toIso8601String(),
        'valid_until': validUntil.toUtc().toIso8601String(),
        'local_date': localDate,
        'time_zone_name': timeZoneName,
        'source_digest': sourceDigest,
        'source_refs':
            sourceRefs.map((CoachSourceRef item) => item.toJson()).toList(),
        'planned_action_id': plannedActionId,
        'planned_duration_minutes': plannedDurationMinutes,
        'available_minutes': availableMinutes,
        'max_pain_score': maxPainScore,
        'recovery_band': recoveryBand.name,
        'completed_sessions_7d': completedSessions7d,
        'missed_sessions_7d': missedSessions7d,
        'safety_flags': <String>{
          ...safetyFlags,
          if (severePain) 'severe_pain',
        }.toList(growable: false),
        'quality_codes': qualityCodes,
        'missing_fields': missingFields,
      };
}

Map<String, Object?> _snapshotSourceValues({
  required List<CoachSourceRef> sourceRefs,
  required String? plannedActionId,
  required int? plannedDurationMinutes,
  required int? availableMinutes,
  required int? maxPainScore,
  required bool severePain,
  required CoachRecoveryBand recoveryBand,
  required int completedSessions7d,
  required int missedSessions7d,
  required List<String> safetyFlags,
  required List<String> qualityCodes,
  required List<String> missingFields,
}) {
  return <String, Object?>{
    'source_refs':
        sourceRefs.map((CoachSourceRef item) => item.toJson()).toList(),
    'planned_action_id': plannedActionId,
    'planned_duration_minutes': plannedDurationMinutes,
    'available_minutes': availableMinutes,
    'max_pain_score': maxPainScore,
    'severe_pain': severePain,
    'recovery_band': recoveryBand.name,
    'completed_sessions_7d': completedSessions7d,
    'missed_sessions_7d': missedSessions7d,
    'safety_flags': safetyFlags.toSet().toList()..sort(),
    'quality_codes': qualityCodes.toSet().toList()..sort(),
    'missing_fields': missingFields.toSet().toList()..sort(),
  };
}

class CoachActionOptionV1 {
  const CoachActionOptionV1({
    required this.actionId,
    required this.intensity,
    required this.durationMinutes,
    required this.requiresConfirmation,
    this.route,
  });

  final String actionId;
  final CoachIntensity intensity;
  final int durationMinutes;
  final bool requiresConfirmation;
  final String? route;

  CoachActionOptionV1 tightenWith(CoachActionOptionV1 other) {
    if (actionId != other.actionId) {
      throw const CoachContractException(
        'action_identity_mismatch',
        '不能合并不同的 Coach 行动。',
      );
    }
    return CoachActionOptionV1(
      actionId: actionId,
      intensity: intensity.index <= other.intensity.index
          ? intensity
          : other.intensity,
      durationMinutes: durationMinutes <= other.durationMinutes
          ? durationMinutes
          : other.durationMinutes,
      requiresConfirmation: requiresConfirmation || other.requiresConfirmation,
      route: route == other.route ? route : null,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'action_id': actionId,
        'intensity': intensity.name,
        'duration_minutes': durationMinutes,
        'requires_confirmation': requiresConfirmation,
        'route': route,
      };
}

class TrainingDecisionV1 {
  const TrainingDecisionV1({
    required this.allowed,
    required this.maxIntensity,
    required this.maxDurationMinutes,
    required this.riskLevel,
    this.forbiddenActionIds = const <String>[],
    this.reasonCodes = const <String>[],
    this.needsMoreInfo = const <String>[],
  });

  final List<CoachActionOptionV1> allowed;
  final CoachIntensity maxIntensity;
  final int? maxDurationMinutes;
  final CoachRiskLevel riskLevel;
  final List<String> forbiddenActionIds;
  final List<String> reasonCodes;
  final List<String> needsMoreInfo;
}

/// 训练引擎只从结构化快照产生允许集合，不读取用户自由文本或关系记忆。
class CoachKernel {
  const CoachKernel();

  TrainingDecisionV1 evaluate({
    required TrainingStateSnapshotV1 snapshot,
    required CoachIntent intent,
    required DateTime now,
  }) {
    final List<String> issues = snapshot.validateAt(now);
    if (intent.requiresTrainingState && issues.isNotEmpty) {
      return TrainingDecisionV1(
        allowed: const <CoachActionOptionV1>[],
        maxIntensity: CoachIntensity.rest,
        maxDurationMinutes: 0,
        riskLevel: CoachRiskLevel.high,
        forbiddenActionIds: const <String>['all_training_actions'],
        reasonCodes: issues,
        needsMoreInfo: snapshot.missingFields,
      );
    }
    if (!intent.requiresTrainingState) {
      return const TrainingDecisionV1(
        allowed: <CoachActionOptionV1>[],
        maxIntensity: CoachIntensity.rest,
        maxDurationMinutes: 0,
        riskLevel: CoachRiskLevel.low,
        reasonCodes: <String>['non_training_intent'],
      );
    }
    if (snapshot.missingFields.isNotEmpty) {
      return TrainingDecisionV1(
        allowed: const <CoachActionOptionV1>[],
        maxIntensity: CoachIntensity.rest,
        maxDurationMinutes: 0,
        riskLevel: CoachRiskLevel.high,
        forbiddenActionIds: const <String>['all_training_actions'],
        reasonCodes: const <String>['snapshot_critical_fact_missing'],
        needsMoreInfo: snapshot.missingFields,
      );
    }
    if (_hasSafetyRedline(snapshot)) {
      return const TrainingDecisionV1(
        allowed: <CoachActionOptionV1>[],
        maxIntensity: CoachIntensity.rest,
        maxDurationMinutes: 0,
        riskLevel: CoachRiskLevel.critical,
        forbiddenActionIds: <String>['all_training_actions'],
        reasonCodes: <String>['pain_redline'],
      );
    }
    final String? actionId = snapshot.plannedActionId;
    final int? plannedDuration = snapshot.plannedDurationMinutes;
    if (actionId == null || plannedDuration == null) {
      return const TrainingDecisionV1(
        allowed: <CoachActionOptionV1>[],
        maxIntensity: CoachIntensity.rest,
        maxDurationMinutes: 0,
        riskLevel: CoachRiskLevel.medium,
        reasonCodes: <String>['existing_plan_missing'],
        needsMoreInfo: <String>['planned_action'],
      );
    }
    final bool mustAdjust = (snapshot.maxPainScore ?? 0) >= 4 ||
        snapshot.safetyFlags.contains('pain_requires_adjustment') ||
        snapshot.recoveryBand == CoachRecoveryBand.red;
    final int available = snapshot.availableMinutes ?? plannedDuration;
    final int duration =
        plannedDuration < available ? plannedDuration : available;
    final CoachActionOptionV1 option = mustAdjust
        ? const CoachActionOptionV1(
            actionId: 'request-existing-adjustment',
            intensity: CoachIntensity.recovery,
            durationMinutes: 0,
            requiresConfirmation: true,
            route: '/daily-adjustment',
          )
        : CoachActionOptionV1(
            actionId: actionId,
            intensity: snapshot.recoveryBand == CoachRecoveryBand.amber
                ? CoachIntensity.low
                : CoachIntensity.moderate,
            durationMinutes: duration,
            requiresConfirmation: false,
            route: '/plans',
          );
    return TrainingDecisionV1(
      allowed: <CoachActionOptionV1>[option],
      maxIntensity: option.intensity,
      maxDurationMinutes: option.durationMinutes,
      riskLevel: mustAdjust ? CoachRiskLevel.medium : CoachRiskLevel.low,
      reasonCodes: <String>[
        mustAdjust ? 'existing_adjustment_required' : 'existing_plan_available',
      ],
    );
  }
}

class CoachDecisionEnvelopeV1 {
  const CoachDecisionEnvelopeV1({
    required this.turnId,
    required this.snapshotId,
    required this.snapshotDigest,
    required this.memorySetDigest,
    required this.allowed,
    required this.riskLevel,
    this.contractVersion = coachContractVersion,
    this.contractHash = coachContractHash,
    this.ruleSetVersion = coachRuleSetVersion,
    this.forbiddenActionIds = const <String>[],
    this.reasonCodes = const <String>[],
    this.requiredBlocks = const <String>[],
  });

  final String turnId;
  final String snapshotId;
  final String snapshotDigest;
  final String memorySetDigest;
  final int contractVersion;
  final String contractHash;
  final String ruleSetVersion;
  final List<CoachActionOptionV1> allowed;
  final List<String> forbiddenActionIds;
  final CoachRiskLevel riskLevel;
  final List<String> reasonCodes;
  final List<String> requiredBlocks;

  CoachDecisionEnvelopeV1 copyWith({
    String? contractHash,
    List<CoachActionOptionV1>? allowed,
    List<String>? forbiddenActionIds,
    CoachRiskLevel? riskLevel,
    List<String>? reasonCodes,
    List<String>? requiredBlocks,
  }) =>
      CoachDecisionEnvelopeV1(
        turnId: turnId,
        snapshotId: snapshotId,
        snapshotDigest: snapshotDigest,
        memorySetDigest: memorySetDigest,
        contractVersion: contractVersion,
        contractHash: contractHash ?? this.contractHash,
        ruleSetVersion: ruleSetVersion,
        allowed: allowed ?? this.allowed,
        forbiddenActionIds: forbiddenActionIds ?? this.forbiddenActionIds,
        riskLevel: riskLevel ?? this.riskLevel,
        reasonCodes: reasonCodes ?? this.reasonCodes,
        requiredBlocks: requiredBlocks ?? this.requiredBlocks,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'turn_id': turnId,
        'snapshot_id': snapshotId,
        'snapshot_digest': snapshotDigest,
        'memory_set_digest': memorySetDigest,
        'contract_version': contractVersion,
        'contract_hash': contractHash,
        'rule_set_version': ruleSetVersion,
        'allowed':
            allowed.map((CoachActionOptionV1 item) => item.toJson()).toList(),
        'forbidden_action_ids': forbiddenActionIds,
        'risk_level': riskLevel.name,
        'reason_codes': reasonCodes,
        'required_blocks': requiredBlocks,
      };
}

/// 安全层只允许删除动作、降低上限或提高风险等级。
class CoachSafetyGate {
  const CoachSafetyGate();

  CoachDecisionEnvelopeV1 apply({
    required TrainingStateSnapshotV1 snapshot,
    required TrainingDecisionV1 training,
    required String turnId,
    required String memorySetDigest,
  }) {
    final bool redline = _hasSafetyRedline(snapshot);
    final List<CoachActionOptionV1> allowed = redline
        ? const <CoachActionOptionV1>[]
        : training.allowed
            .where((CoachActionOptionV1 option) =>
                option.intensity.index <= training.maxIntensity.index &&
                (training.maxDurationMinutes == null ||
                    option.durationMinutes <= training.maxDurationMinutes!))
            .toList(growable: false);
    return CoachDecisionEnvelopeV1(
      turnId: turnId,
      snapshotId: snapshot.snapshotId,
      snapshotDigest: CoachDigest.sha256(snapshot.toJson()),
      memorySetDigest: memorySetDigest,
      allowed: allowed,
      forbiddenActionIds: <String>{
        ...training.forbiddenActionIds,
        if (redline) 'all_training_actions',
      }.toList(growable: false)
        ..sort(),
      riskLevel: redline ? CoachRiskLevel.critical : training.riskLevel,
      reasonCodes: <String>{
        ...training.reasonCodes,
        if (redline) 'pain_redline',
      }.toList(growable: false)
        ..sort(),
      requiredBlocks:
          redline ? const <String>['pain_redline_guidance'] : const <String>[],
    );
  }
}

bool _hasSafetyRedline(TrainingStateSnapshotV1 snapshot) =>
    snapshot.severePain ||
    (snapshot.maxPainScore ?? 0) >= 7 ||
    snapshot.safetyFlags.contains('severe_pain') ||
    snapshot.safetyFlags.contains('injury_red_flag');

class CoachMergeResult {
  const CoachMergeResult({
    required this.envelope,
    required this.verificationState,
    this.fixedFallbackText,
  });

  final CoachDecisionEnvelopeV1 envelope;
  final CoachVerificationState verificationState;
  final String? fixedFallbackText;
}

/// 双端仲裁只取交集，并对强度、时长和风险采用更保守值。
class CoachDecisionMerger {
  const CoachDecisionMerger();

  CoachMergeResult intersect({
    required CoachDecisionEnvelopeV1 local,
    required CoachDecisionEnvelopeV1 remote,
  }) {
    if (local.contractVersion != remote.contractVersion ||
        local.contractHash != remote.contractHash ||
        local.ruleSetVersion != remote.ruleSetVersion) {
      return _mismatch(local, CoachVerificationState.contractMismatch);
    }
    if (local.snapshotId != remote.snapshotId ||
        local.snapshotDigest != remote.snapshotDigest) {
      return _mismatch(local, CoachVerificationState.snapshotMismatch);
    }
    if (local.memorySetDigest != remote.memorySetDigest) {
      return _mismatch(local, CoachVerificationState.memoryMismatch);
    }
    final Map<String, CoachActionOptionV1> remoteById =
        <String, CoachActionOptionV1>{
      for (final CoachActionOptionV1 option in remote.allowed)
        option.actionId: option,
    };
    final List<CoachActionOptionV1> intersection = local.allowed
        .where(
            (CoachActionOptionV1 item) => remoteById.containsKey(item.actionId))
        .map((CoachActionOptionV1 item) =>
            item.tightenWith(remoteById[item.actionId]!))
        .toList(growable: false);
    final CoachRiskLevel risk = local.riskLevel.index >= remote.riskLevel.index
        ? local.riskLevel
        : remote.riskLevel;
    final bool blocked = risk == CoachRiskLevel.critical;
    return CoachMergeResult(
      envelope: CoachDecisionEnvelopeV1(
        turnId: local.turnId,
        snapshotId: local.snapshotId,
        snapshotDigest: local.snapshotDigest,
        memorySetDigest: local.memorySetDigest,
        allowed: blocked ? const <CoachActionOptionV1>[] : intersection,
        forbiddenActionIds: <String>{
          ...local.forbiddenActionIds,
          ...remote.forbiddenActionIds,
        }.toList(growable: false)
          ..sort(),
        riskLevel: risk,
        reasonCodes: <String>{...local.reasonCodes, ...remote.reasonCodes}
            .toList(growable: false)
          ..sort(),
        requiredBlocks: <String>{
          ...local.requiredBlocks,
          ...remote.requiredBlocks,
        }.toList(growable: false)
          ..sort(),
      ),
      verificationState: CoachVerificationState.dualVerified,
      fixedFallbackText:
          intersection.isEmpty ? '两端规则没有得到一致的安全行动，今天先不推训练，由你查看已有记录。' : null,
    );
  }

  CoachMergeResult _mismatch(
    CoachDecisionEnvelopeV1 local,
    CoachVerificationState state,
  ) {
    return CoachMergeResult(
      envelope: local.copyWith(
        allowed: const <CoachActionOptionV1>[],
        riskLevel: CoachRiskLevel.high,
        reasonCodes: <String>{...local.reasonCodes, state.storageValue}
            .toList(growable: false),
      ),
      verificationState: state,
      fixedFallbackText: '规则校验暂时没有对齐，今天先不推训练；本机记录没有被修改。',
    );
  }
}

class CommunicationPlanV1 {
  const CommunicationPlanV1({
    required this.chosenActionId,
    required this.tone,
    this.fallbackActionId,
    this.memoryIdsToSurface = const <String>[],
  });

  final String? chosenActionId;
  final String? fallbackActionId;
  final CoachTone tone;
  final List<String> memoryIdsToSurface;
}

class CoachRenderedAction {
  const CoachRenderedAction({
    required this.actionId,
    required this.label,
    this.route,
    required this.requiresConfirmation,
  });

  final String actionId;
  final String label;
  final String? route;
  final bool requiresConfirmation;
}

class CoachRenderedReply {
  const CoachRenderedReply({
    required this.text,
    required this.actions,
    required this.verificationState,
    this.memoryIds = const <String>[],
  });

  final String text;
  final List<CoachRenderedAction> actions;
  final CoachVerificationState verificationState;
  final List<String> memoryIds;
}

abstract interface class CompanionTextRenderer {
  CoachRenderedReply render({
    required CoachDecisionEnvelopeV1 envelope,
    required CommunicationPlanV1 communication,
    required List<CoachMemoryV1> memories,
    required CoachVerificationState verificationState,
  });
}

class DeterministicCompanionRenderer implements CompanionTextRenderer {
  const DeterministicCompanionRenderer();

  @override
  CoachRenderedReply render({
    required CoachDecisionEnvelopeV1 envelope,
    required CommunicationPlanV1 communication,
    required List<CoachMemoryV1> memories,
    required CoachVerificationState verificationState,
  }) {
    final Map<String, CoachActionOptionV1> allowed =
        <String, CoachActionOptionV1>{
      for (final CoachActionOptionV1 option in envelope.allowed)
        option.actionId: option,
    };
    final String? chosenId = communication.chosenActionId;
    if (chosenId != null && !allowed.containsKey(chosenId)) {
      throw const CoachContractException(
        'companion_action_outside_aas',
        '陪伴层选择了训练允许集合之外的行动。',
      );
    }
    if (envelope.riskLevel == CoachRiskLevel.critical || allowed.isEmpty) {
      return CoachRenderedReply(
        text: envelope.reasonCodes.contains('pain_redline')
            ? '这次先不安排训练。请停止会加重疼痛的活动，并考虑联系医生或康复专业人员。'
            : '当前事实不足以安全给出训练行动，我先陪你查看已有记录。',
        actions: const <CoachRenderedAction>[],
        verificationState: verificationState,
      );
    }
    final CoachActionOptionV1 option =
        chosenId == null ? envelope.allowed.first : allowed[chosenId]!;
    final bool adjustment = option.actionId == 'request-existing-adjustment';
    final List<String> surfaceableIds = memories
        .where((CoachMemoryV1 item) => item.mayMention)
        .map((CoachMemoryV1 item) => item.memoryId)
        .where(communication.memoryIdsToSurface.contains)
        .take(2)
        .toList(growable: false);
    return CoachRenderedReply(
      text: adjustment
          ? '我只根据当前结构化事实建议打开既有调整流程，是否采用仍由你确认。'
          : '我核对了当前结构化训练事实。可以先查看已有计划，再由你决定是否开始。',
      actions: <CoachRenderedAction>[
        CoachRenderedAction(
          actionId: option.actionId,
          label: adjustment ? '看看调整' : '看看计划',
          route: option.route,
          requiresConfirmation: option.requiresConfirmation,
        ),
      ],
      verificationState: verificationState,
      memoryIds: surfaceableIds,
    );
  }
}

/// 首期明确关闭生成式渲染；即便被误调用也不会把 Prompt 当作权限边界。
class DisabledDeepSeekRenderer implements CompanionTextRenderer {
  const DisabledDeepSeekRenderer();

  @override
  CoachRenderedReply render({
    required CoachDecisionEnvelopeV1 envelope,
    required CommunicationPlanV1 communication,
    required List<CoachMemoryV1> memories,
    required CoachVerificationState verificationState,
  }) {
    throw StateError('生成式 Coach 渲染当前未启用');
  }
}
