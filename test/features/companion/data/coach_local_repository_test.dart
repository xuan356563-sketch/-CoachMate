import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/local/coach_database_gateway.dart';
import 'package:trainflow_ai/features/companion/data/coach_local_repository.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 8, 12, 12);

  CoachSourceRef source(String id) => CoachSourceRef(
        sourceKind: 'conversation',
        sourceLocalId: id,
        sourceDigest: CoachDigest.sha256(id),
        observedAt: now,
        summaryKey: '你在对话中明确告诉我',
      );

  CoachMemoryV1 memory({
    String id = 'memory-1',
    CoachMemoryStatus status = CoachMemoryStatus.candidate,
    bool confirmed = false,
    List<CoachSourceRef>? sources,
  }) =>
      CoachMemoryV1(
        memoryId: id,
        athleteProfileId: 'athlete-1',
        category: CoachMemoryCategory.preference,
        subject: 'tone',
        value: const <String, Object?>{'value': 'calm'},
        displayText: '你偏好平静直接的提醒',
        sources: sources ?? <CoachSourceRef>[source('message-1')],
        confidenceBps: 9000,
        importanceBps: 7000,
        sensitivity: CoachMemorySensitivity.low,
        status: status,
        version: 1,
        validityPolicy: CoachMemoryValidityPolicy.expiresAt,
        validFrom: now,
        validUntil: now.add(const Duration(days: 180)),
        mayMention: true,
        userConfirmed: confirmed,
        syncAllowed: false,
        confirmationBasis: CoachMemoryConfirmationBasis.none,
        createdAt: now,
        updatedAt: now,
      );

  test('记忆与来源在同一仓储边界持久化，候选不会被当作可用记忆', () async {
    final _MemoryCoachGateway gateway = _MemoryCoachGateway();
    final CoachLocalRepository repository =
        CoachLocalRepository(gateway, clock: () => now);

    await repository.saveMemory(memory());
    final CoachMemoryV1 loaded = (await repository.loadMemory(
      athleteProfileId: 'athlete-1',
      memoryId: 'memory-1',
    ))!;

    expect(loaded.sources.single.sourceLocalId, 'message-1');
    expect(loaded.isUsable(now), isFalse);
    expect(gateway.syncWrites, isZero);
  });

  test('推断候选缺少两个独立来源时拒绝落库', () async {
    final CoachLocalRepository repository =
        CoachLocalRepository(_MemoryCoachGateway(), clock: () => now);

    expect(
      () => repository.saveMemory(memory(), inferred: true),
      throwsA(isA<CoachContractException>()),
    );
  });

  test('确认、纠正和忘记保留版本关系并清除墓碑正文', () async {
    final _MemoryCoachGateway gateway = _MemoryCoachGateway();
    final CoachLocalRepository repository =
        CoachLocalRepository(gateway, clock: () => now);
    await repository.saveMemory(memory());

    final CoachMemoryV1 confirmed = await repository.confirmMemory(
      athleteProfileId: 'athlete-1',
      memoryId: 'memory-1',
      syncAllowed: true,
    );
    expect(confirmed.isUsable(now), isTrue);
    expect(confirmed.syncAllowed, isTrue);

    final CoachMemoryV1 replacement = await repository.correctMemory(
      athleteProfileId: 'athlete-1',
      memoryId: 'memory-1',
      replacementMemoryId: 'memory-2',
      value: const <String, Object?>{'value': 'concise'},
      displayText: '你偏好简洁提醒',
      correctionSource: source('message-2'),
    );
    expect(replacement.version, 2);
    expect(gateway.memories['memory-1']!['status'], 'superseded');
    expect(gateway.memories['memory-1']!['superseded_by'], 'memory-2');

    await repository.forgetMemory(
      athleteProfileId: 'athlete-1',
      memoryId: 'memory-2',
    );
    expect(gateway.memories['memory-2']!['status'], 'deleted');
    expect(gateway.memories['memory-2']!['display_text'], isEmpty);
    expect(gateway.sources['memory-2'], isEmpty);
  });
}

class _MemoryCoachGateway implements CoachDatabaseGateway {
  final Map<String, Map<String, Object?>> snapshots =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> memories =
      <String, Map<String, Object?>>{};
  final Map<String, List<Map<String, Object?>>> sources =
      <String, List<Map<String, Object?>>>{};
  final Map<String, Map<String, Object?>> traces =
      <String, Map<String, Object?>>{};
  int syncWrites = 0;

  @override
  Future<List<Map<String, Object?>>> listMemoryRows({
    required String athleteProfileId,
  }) async =>
      memories.values
          .where((Map<String, Object?> row) =>
              row['athlete_profile_id'] == athleteProfileId)
          .map(Map<String, Object?>.from)
          .toList(growable: false);

  @override
  Future<List<Map<String, Object?>>> listMemorySourceRows(
          String memoryId) async =>
      (sources[memoryId] ?? const <Map<String, Object?>>[])
          .map(Map<String, Object?>.from)
          .toList(growable: false);

  @override
  Future<Map<String, Object?>?> readLatestStateSnapshotRow({
    required String athleteProfileId,
  }) async {
    final List<Map<String, Object?>> rows = snapshots.values
        .where((Map<String, Object?> row) =>
            row['athlete_profile_id'] == athleteProfileId)
        .map(Map<String, Object?>.from)
        .toList(growable: false);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<Map<String, Object?>?> readMemoryRow({
    required String memoryId,
    required String athleteProfileId,
  }) async {
    final Map<String, Object?>? row = memories[memoryId];
    return row == null || row['athlete_profile_id'] != athleteProfileId
        ? null
        : Map<String, Object?>.from(row);
  }

  @override
  Future<void> tombstoneMemory({
    required String memoryId,
    required String athleteProfileId,
    required DateTime deletedAt,
    required DateTime tombstoneExpiresAt,
  }) async {
    final Map<String, Object?> row = memories[memoryId]!;
    row
      ..['value_json'] = '{}'
      ..['display_text'] = ''
      ..['status'] = 'deleted'
      ..['may_mention'] = 0
      ..['user_confirmed'] = 0
      ..['sync_allowed'] = 0
      ..['validity_policy'] = 'expires_at'
      ..['valid_until'] = tombstoneExpiresAt.toIso8601String()
      ..['deleted_at'] = deletedAt.toIso8601String()
      ..['updated_at'] = deletedAt.toIso8601String();
    sources[memoryId] = <Map<String, Object?>>[];
  }

  @override
  Future<void> upsertStateSnapshotRow(Map<String, Object?> row) async {
    snapshots[row['snapshot_id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<void> upsertTurnTraceRow(Map<String, Object?> row) async {
    traces[row['trace_id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<void> writeMemory({
    required Map<String, Object?> memoryRow,
    required List<Map<String, Object?>> sourceRows,
    String? supersedesMemoryId,
  }) async {
    if (supersedesMemoryId != null) {
      memories[supersedesMemoryId]!
        ..['status'] = 'superseded'
        ..['superseded_by'] = memoryRow['memory_id']
        ..['sync_allowed'] = 0;
    }
    final String memoryId = memoryRow['memory_id']! as String;
    memories[memoryId] = Map<String, Object?>.from(memoryRow);
    sources[memoryId] = sourceRows.map(Map<String, Object?>.from).toList();
  }
}
