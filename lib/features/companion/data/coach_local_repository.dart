import 'dart:convert';

import 'package:trainflow_ai/data/local/coach_database_gateway.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';

class CoachTurnTraceV1 {
  const CoachTurnTraceV1({
    required this.traceId,
    required this.athleteProfileId,
    required this.turnId,
    required this.intent,
    required this.emotion,
    required this.inputDigest,
    required this.localDecisionDigest,
    required this.finalDecisionDigest,
    required this.verificationState,
    required this.reasonCodes,
    required this.createdAt,
    required this.expiresAt,
    this.snapshotId,
    this.remoteDecisionDigest,
  });

  final String traceId;
  final String athleteProfileId;
  final String turnId;
  final CoachIntent intent;
  final CoachEmotion emotion;
  final String? snapshotId;
  final String inputDigest;
  final String localDecisionDigest;
  final String? remoteDecisionDigest;
  final String finalDecisionDigest;
  final CoachVerificationState verificationState;
  final List<String> reasonCodes;
  final DateTime createdAt;
  final DateTime expiresAt;
}

class CoachLocalRepository {
  CoachLocalRepository(this._database, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final CoachDatabaseGateway _database;
  final DateTime Function() _clock;

  Future<void> saveSnapshot(TrainingStateSnapshotV1 snapshot) {
    final List<String> issues = snapshot
        .validateAt(snapshot.generatedAt)
        .where((String issue) => issue != 'snapshot_source_required')
        .toList(growable: false);
    if (issues.isNotEmpty) {
      throw CoachContractException(
        'snapshot_invalid',
        '训练快照不符合契约：${issues.join(', ')}',
      );
    }
    return _database.upsertStateSnapshotRow(<String, Object?>{
      'snapshot_id': snapshot.snapshotId,
      'athlete_profile_id': snapshot.athleteProfileId,
      'contract_version': snapshot.contractVersion,
      'contract_hash': snapshot.contractHash,
      'rule_set_version': snapshot.ruleSetVersion,
      'source_digest': snapshot.sourceDigest,
      'local_date': snapshot.localDate,
      'time_zone_name': snapshot.timeZoneName,
      'generated_at': snapshot.generatedAt.toUtc().toIso8601String(),
      'valid_until': snapshot.validUntil.toUtc().toIso8601String(),
      'payload_json': jsonEncode(snapshot.toJson()),
      'missing_fields_json': jsonEncode(snapshot.missingFields),
      'quality_codes_json': jsonEncode(snapshot.qualityCodes),
      'created_at': _clock().toUtc().toIso8601String(),
    });
  }

  Future<TrainingStateSnapshotV1?> latestSnapshot(
      String athleteProfileId) async {
    final Map<String, Object?>? row = await _database
        .readLatestStateSnapshotRow(athleteProfileId: athleteProfileId);
    if (row == null) return null;
    return TrainingStateSnapshotV1.fromJson(
      Map<String, Object?>.from(
          jsonDecode(row['payload_json']! as String) as Map),
    );
  }

  Future<void> saveMemory(CoachMemoryV1 memory, {bool inferred = false}) {
    final List<String> issues = memory.validate(inferred: inferred);
    if (issues.isNotEmpty) {
      throw CoachContractException(
        'memory_invalid',
        'Coach 记忆不符合治理规则：${issues.join(', ')}',
      );
    }
    return _writeMemory(memory);
  }

  Future<CoachMemoryV1?> loadMemory({
    required String athleteProfileId,
    required String memoryId,
  }) async {
    final Map<String, Object?>? row = await _database.readMemoryRow(
      memoryId: memoryId,
      athleteProfileId: athleteProfileId,
    );
    return row == null ? null : _memoryFromRow(row);
  }

  Future<List<CoachMemoryV1>> listMemories(String athleteProfileId) async {
    final List<Map<String, Object?>> rows =
        await _database.listMemoryRows(athleteProfileId: athleteProfileId);
    final List<CoachMemoryV1> result = <CoachMemoryV1>[];
    for (final Map<String, Object?> row in rows) {
      result.add(await _memoryFromRow(row));
    }
    return result;
  }

  Future<CoachMemoryV1> confirmMemory({
    required String athleteProfileId,
    required String memoryId,
    bool syncAllowed = false,
  }) async {
    final CoachMemoryV1? current = await loadMemory(
      athleteProfileId: athleteProfileId,
      memoryId: memoryId,
    );
    if (current == null ||
        current.status == CoachMemoryStatus.deleted ||
        current.status == CoachMemoryStatus.superseded) {
      throw StateError('未找到可确认的 Coach 记忆');
    }
    final CoachMemoryV1 confirmed = current.copyWith(
      status: CoachMemoryStatus.active,
      userConfirmed: true,
      syncAllowed: syncAllowed,
      confirmationBasis: CoachMemoryConfirmationBasis.panelConfirmation,
      updatedAt: _clock().toUtc(),
    );
    await _writeMemory(confirmed);
    return confirmed;
  }

  Future<CoachMemoryV1> correctMemory({
    required String athleteProfileId,
    required String memoryId,
    required String replacementMemoryId,
    required Map<String, Object?> value,
    required String displayText,
    required CoachSourceRef correctionSource,
  }) async {
    final CoachMemoryV1? current = await loadMemory(
      athleteProfileId: athleteProfileId,
      memoryId: memoryId,
    );
    if (current == null || !current.isUsable(_clock())) {
      throw StateError('未找到可纠正的 Coach 记忆');
    }
    final DateTime now = _clock().toUtc();
    final CoachMemoryV1 replacement = current.copyWith(
      memoryId: replacementMemoryId,
      version: current.version + 1,
      value: value,
      displayText: displayText,
      sources: <CoachSourceRef>[correctionSource],
      confirmationBasis: CoachMemoryConfirmationBasis.panelConfirmation,
      validFrom: now,
      createdAt: now,
      updatedAt: now,
    );
    await _writeMemory(replacement, supersedesMemoryId: current.memoryId);
    return replacement;
  }

  Future<void> forgetMemory({
    required String athleteProfileId,
    required String memoryId,
  }) {
    final DateTime now = _clock().toUtc();
    return _database.tombstoneMemory(
      memoryId: memoryId,
      athleteProfileId: athleteProfileId,
      deletedAt: now,
      tombstoneExpiresAt: now.add(const Duration(days: 30)),
    );
  }

  Future<void> saveTrace(CoachTurnTraceV1 trace) {
    if (trace.expiresAt
        .isAfter(trace.createdAt.add(const Duration(days: 90)))) {
      throw const CoachContractException(
        'trace_retention_exceeded',
        'Coach 决策追踪最多保留 90 天。',
      );
    }
    return _database.upsertTurnTraceRow(<String, Object?>{
      'trace_id': trace.traceId,
      'athlete_profile_id': trace.athleteProfileId,
      'turn_id': trace.turnId,
      'intent': trace.intent.storageValue,
      'emotion': trace.emotion.name,
      'snapshot_id': trace.snapshotId,
      'input_digest': trace.inputDigest,
      'local_decision_digest': trace.localDecisionDigest,
      'remote_decision_digest': trace.remoteDecisionDigest,
      'final_decision_digest': trace.finalDecisionDigest,
      'verification_state': trace.verificationState.storageValue,
      'reason_codes_json': jsonEncode(trace.reasonCodes),
      'created_at': trace.createdAt.toUtc().toIso8601String(),
      'expires_at': trace.expiresAt.toUtc().toIso8601String(),
    });
  }

  Future<void> _writeMemory(
    CoachMemoryV1 memory, {
    String? supersedesMemoryId,
  }) {
    final Map<String, Object?> row = <String, Object?>{
      'memory_id': memory.memoryId,
      'athlete_profile_id': memory.athleteProfileId,
      'category': memory.category.storageValue,
      'subject': memory.subject,
      'value_json': jsonEncode(memory.value),
      'display_text': memory.displayText,
      'confidence_bps': memory.confidenceBps,
      'importance_bps': memory.importanceBps,
      'sensitivity': memory.sensitivity.name,
      'status': memory.status.storageValue,
      'version': memory.version,
      'validity_policy':
          memory.validityPolicy == CoachMemoryValidityPolicy.expiresAt
              ? 'expires_at'
              : 'until_revoked',
      'valid_from': memory.validFrom.toUtc().toIso8601String(),
      'valid_until': memory.validUntil?.toUtc().toIso8601String(),
      'may_mention': memory.mayMention ? 1 : 0,
      'user_confirmed': memory.userConfirmed ? 1 : 0,
      'sync_allowed': memory.syncAllowed ? 1 : 0,
      'confirmation_basis': memory.confirmationBasis.storageValue,
      'surfaced_count_30d': memory.surfacedCount30d,
      'superseded_by': memory.supersededBy,
      'deleted_at': memory.deletedAt?.toUtc().toIso8601String(),
      'created_at': memory.createdAt.toUtc().toIso8601String(),
      'updated_at': memory.updatedAt.toUtc().toIso8601String(),
    };
    final List<Map<String, Object?>> sources = memory.sources
        .map((CoachSourceRef source) => <String, Object?>{
              'source_id': CoachDigest.sha256(<String, Object?>{
                'memory_id': memory.memoryId,
                'source_kind': source.sourceKind,
                'source_local_id': source.sourceLocalId,
              }),
              'memory_id': memory.memoryId,
              'source_kind': source.sourceKind,
              'source_local_id': source.sourceLocalId,
              'source_digest': source.sourceDigest,
              'source_summary': source.summaryKey,
              'observed_at': source.observedAt.toUtc().toIso8601String(),
              'created_at': _clock().toUtc().toIso8601String(),
            })
        .toList(growable: false);
    return _database.writeMemory(
      memoryRow: row,
      sourceRows: sources,
      supersedesMemoryId: supersedesMemoryId,
    );
  }

  Future<CoachMemoryV1> _memoryFromRow(Map<String, Object?> row) async {
    final String memoryId = row['memory_id']! as String;
    final List<Map<String, Object?>> sourceRows =
        await _database.listMemorySourceRows(memoryId);
    return CoachMemoryV1.fromJson(<String, Object?>{
      'memory_id': memoryId,
      'athlete_profile_id': row['athlete_profile_id'],
      'category': row['category'],
      'subject': row['subject'],
      'value': Map<String, Object?>.from(
        jsonDecode(row['value_json']! as String) as Map,
      ),
      'display_text': row['display_text'],
      'sources': sourceRows
          .map((Map<String, Object?> source) => <String, Object?>{
                'source_kind': source['source_kind'],
                'source_local_id': source['source_local_id'],
                'source_digest': source['source_digest'],
                'observed_at': source['observed_at'],
                'summary_key': source['source_summary'],
              })
          .toList(growable: false),
      'confidence_bps': row['confidence_bps'],
      'importance_bps': row['importance_bps'],
      'sensitivity': row['sensitivity'],
      'status': row['status'],
      'version': row['version'],
      'validity_policy': row['validity_policy'],
      'valid_from': row['valid_from'],
      'valid_until': row['valid_until'],
      'may_mention': row['may_mention'] == 1,
      'user_confirmed': row['user_confirmed'] == 1,
      'sync_allowed': row['sync_allowed'] == 1,
      'confirmation_basis': row['confirmation_basis'],
      'superseded_by': row['superseded_by'],
      'deleted_at': row['deleted_at'],
      'surfaced_count_30d': row['surfaced_count_30d'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    });
  }
}
