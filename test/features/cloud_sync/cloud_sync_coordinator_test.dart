import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/cloud_sync.dart';
import 'package:trainflow_ai/features/cloud_sync/application/cloud_sync_coordinator.dart';
import 'package:trainflow_ai/features/cloud_sync/data/cloud_sync_api.dart';
import 'package:trainflow_ai/features/cloud_sync/data/cloud_sync_local_store.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';

void main() {
  test('未明确确认时不能启用云同步且不会上传既有数据', () async {
    final _FakeLocalStore store = _FakeLocalStore();
    final _FakeRemoteGateway remote = _FakeRemoteGateway();
    final CloudSyncCoordinator coordinator = CloudSyncCoordinator(
      localStore: store,
      remoteGateway: remote,
    );

    await expectLater(
      coordinator.enable(accountId: 'account-a', confirmed: false),
      throwsA(isA<CloudSyncConfirmationRequiredException>()),
    );
    expect(store.enableCalls, 0);
    expect(remote.events, isEmpty);

    await coordinator.enable(accountId: 'account-a', confirmed: true);

    expect(store.enableCalls, 1);
    expect(store.pending, isEmpty);
    expect(remote.events, isEmpty);
  });

  test('明确启用后才允许把既有白名单投影放入 outbox', () async {
    final CloudSyncMutation existingProjection = CloudSyncMutation.appSettings(
      mutationId: 'existing-settings',
      entityId: 'settings-1',
      baseVersion: null,
      locale: 'zh-CN',
      weekStartsOn: 1,
      notificationsEnabled: true,
    );
    final _FakeLocalStore store = _FakeLocalStore(
      pendingOnEnable: <CloudSyncMutation>[existingProjection],
    );
    final CloudSyncCoordinator coordinator = CloudSyncCoordinator(
      localStore: store,
      remoteGateway: _FakeRemoteGateway(),
    );

    await expectLater(
      coordinator.enable(accountId: 'account-a', confirmed: false),
      throwsA(isA<CloudSyncConfirmationRequiredException>()),
    );
    expect(store.pending, isEmpty);

    await coordinator.enable(accountId: 'account-a', confirmed: true);

    expect(store.pending, <CloudSyncMutation>[existingProjection]);
  });

  test('新设备必须先应用快照再发送 outbox', () async {
    final CloudSyncMutation mutation = CloudSyncMutation.trainingPreferences(
      mutationId: 'mutation-1',
      entityId: 'preferences-1',
      baseVersion: null,
      goal: '提升综合体能',
      sportTypes: const <String>['running'],
      experienceLevel: 'beginner',
      weeklyAvailability: const <int>[2, 4],
      equipment: const <String>[],
    );
    final _FakeLocalStore store = _FakeLocalStore(
      state: const CloudSyncAccountState(
        enabled: true,
        snapshotRequired: true,
        cursor: 0,
        hasExistingLocalData: false,
      ),
      pending: <CloudSyncMutation>[mutation],
    );
    final _FakeRemoteGateway remote = _FakeRemoteGateway();
    store.sharedEvents = remote.events;
    final CloudSyncCoordinator coordinator = CloudSyncCoordinator(
      localStore: store,
      remoteGateway: remote,
    );

    final CloudSyncRunResult result =
        await coordinator.synchronize(accountId: 'account-a');

    expect(
      remote.events.take(3),
      <String>['snapshot', 'apply_snapshot', 'mutations'],
    );
    expect(result.status, CloudSyncRunStatus.synced);
    expect(store.pending, isEmpty);
  });

  test('本地和云端同时有数据时保留冲突且不自动覆盖或上传', () async {
    final _FakeLocalStore store = _FakeLocalStore(
      state: const CloudSyncAccountState(
        enabled: true,
        snapshotRequired: true,
        cursor: 0,
        hasExistingLocalData: true,
      ),
      snapshotConflictCount: 1,
      pending: <CloudSyncMutation>[
        CloudSyncMutation.appSettings(
          mutationId: 'mutation-settings',
          entityId: 'settings-1',
          baseVersion: 1,
          locale: 'zh-CN',
          weekStartsOn: 1,
          notificationsEnabled: true,
        ),
      ],
    );
    final _FakeRemoteGateway remote = _FakeRemoteGateway();
    final CloudSyncCoordinator coordinator = CloudSyncCoordinator(
      localStore: store,
      remoteGateway: remote,
    );

    final CloudSyncRunResult result =
        await coordinator.synchronize(accountId: 'account-a');

    expect(result.status, CloudSyncRunStatus.conflicts);
    expect(result.conflictCount, 1);
    expect(remote.events, <String>['snapshot']);
    expect(store.pending, hasLength(1));
  });

  test('网络故障不删除 outbox 且返回本地可继续状态', () async {
    final CloudSyncMutation mutation = CloudSyncMutation.appSettings(
      mutationId: 'mutation-offline',
      entityId: 'settings-1',
      baseVersion: null,
      locale: 'zh-CN',
      weekStartsOn: 1,
      notificationsEnabled: false,
    );
    final _FakeLocalStore store = _FakeLocalStore(
      state: const CloudSyncAccountState(
        enabled: true,
        snapshotRequired: false,
        cursor: 3,
        hasExistingLocalData: false,
      ),
      pending: <CloudSyncMutation>[mutation],
    );
    final _FakeRemoteGateway remote = _FakeRemoteGateway(failMutations: true);
    final CloudSyncCoordinator coordinator = CloudSyncCoordinator(
      localStore: store,
      remoteGateway: remote,
    );

    final CloudSyncRunResult result =
        await coordinator.synchronize(accountId: 'account-a');

    expect(result.status, CloudSyncRunStatus.offline);
    expect(result.localTrainingAvailable, isTrue);
    expect(store.pending, <CloudSyncMutation>[mutation]);
    expect(store.retryMutationIds, <String>['mutation-offline']);
    expect(store.lastRetryErrorCode, 'transport_unavailable');
  });

  test('冲突只能在用户明确确认后按所选版本解决', () async {
    final _FakeLocalStore store = _FakeLocalStore();
    final CloudSyncCoordinator coordinator = CloudSyncCoordinator(
      localStore: store,
      remoteGateway: _FakeRemoteGateway(),
    );

    await expectLater(
      coordinator.resolveConflict(
        accountId: 'account-a',
        conflictId: 'conflict-1',
        resolution: CloudSyncConflictResolution.keepLocal,
        confirmed: false,
      ),
      throwsA(isA<CloudSyncConfirmationRequiredException>()),
    );
    expect(store.resolvedConflicts, isEmpty);

    await coordinator.resolveConflict(
      accountId: 'account-a',
      conflictId: 'conflict-1',
      resolution: CloudSyncConflictResolution.useCloud,
      confirmed: true,
    );

    expect(
      store.resolvedConflicts,
      <String>['conflict-1:useCloud'],
    );
  });

  test('同步序列化只接受固定白名单并拒绝身体与健康字段', () {
    final CloudSyncMutation safe = CloudSyncMutation.completionSummary(
      mutationId: 'completion-1',
      entityId: 'log-1',
      planVersionId: 'plan-1',
      scheduledWorkoutId: 'workout-1',
      startedAt: DateTime.utc(2026, 7, 28, 8),
      endedAt: DateTime.utc(2026, 7, 28, 9),
      durationSeconds: 3600,
      completionPercentage: 100,
      revoked: false,
    );
    final Map<String, Object?> request = safe.toRequestJson();
    final String serialized = jsonEncode(request).toLowerCase();
    final Set<String> serializedKeys = <String>{
      ...request.keys,
      ...(request['payload']! as Map<String, Object?>).keys,
    };
    for (final String forbidden in <String>[
      'name',
      'age',
      'gender',
      'height',
      'weight',
      'healthkit',
      'pain',
      'rpe',
      'notes',
      'heart_rate',
      'route',
      'image',
      'voice',
    ]) {
      expect(serializedKeys, isNot(contains(forbidden)));
    }
    expect(serialized, isNot(contains('healthkit')));

    expect(
      () => CloudSyncMutation.fromPayload(
        mutationId: 'unsafe-1',
        entityType: CloudSyncEntityType.trainingPreferences,
        entityId: 'preferences-1',
        baseVersion: null,
        payload: <String, Object?>{
          'goal': '提升综合体能',
          'sport_types': <String>['running'],
          'experience_level': 'beginner',
          'weekly_availability': <int>[2],
          'equipment': <String>[],
          'weight_kg': 70,
        },
      ),
      throwsFormatException,
    );
  });

  test('停用期间到达的分页结果不会推进游标或写入本机', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final Completer<CloudSyncChangePage> page =
        Completer<CloudSyncChangePage>();
    final _FakeLocalStore store = _FakeLocalStore(
      state: const CloudSyncAccountState(
        enabled: true,
        snapshotRequired: false,
        cursor: 7,
        hasExistingLocalData: false,
      ),
    );
    final _FakeRemoteGateway remote = _FakeRemoteGateway(deferredPage: page);
    final Future<CloudSyncRunResult> pending = CloudSyncCoordinator(
      localStore: store,
      remoteGateway: remote,
    ).synchronize(
      accountId: 'account-a',
      operation: runtime.beginOperation('feature.cloud_sync'),
    );
    while (!remote.events.contains('changes')) {
      await Future<void>.delayed(Duration.zero);
    }

    await runtime.disable('feature.cloud_sync');
    page.complete(const CloudSyncChangePage(
      changes: <CloudSyncChange>[],
      nextCursor: 99,
      hasMore: false,
    ));

    await expectLater(pending, throwsStateError);
    expect(store.applyChangesCount, 0);
    expect(store.state.cursor, 7);
  });
}

class _FakeRemoteGateway implements CloudSyncRemoteGateway {
  _FakeRemoteGateway({
    this.failMutations = false,
    this.deferredPage,
  });

  final bool failMutations;
  final Completer<CloudSyncChangePage>? deferredPage;
  final List<String> events = <String>[];

  @override
  Future<CloudSyncSnapshot> fetchSnapshot() async {
    events.add('snapshot');
    return const CloudSyncSnapshot(cursor: 0, entities: <CloudSyncEntity>[]);
  }

  @override
  Future<CloudSyncChangePage> fetchChanges({
    required int after,
    int limit = 100,
  }) async {
    events.add('changes');
    if (deferredPage != null) return deferredPage!.future;
    return CloudSyncChangePage(
      changes: const <CloudSyncChange>[],
      nextCursor: after,
      hasMore: false,
    );
  }

  @override
  Future<List<CloudSyncMutationResult>> sendMutations(
    List<CloudSyncMutation> mutations,
  ) async {
    events.add('mutations');
    if (failMutations) throw const CloudSyncTransportException();
    return mutations
        .map(
          (CloudSyncMutation mutation) => CloudSyncMutationResult(
            mutationId: mutation.mutationId,
            entityType: mutation.entityType,
            entityId: mutation.entityId,
            status: CloudSyncMutationStatus.applied,
            version: (mutation.baseVersion ?? 0) + 1,
            cursor: 1,
          ),
        )
        .toList(growable: false);
  }
}

class _FakeLocalStore implements CloudSyncLocalStore {
  _FakeLocalStore({
    this.state = const CloudSyncAccountState(
      enabled: false,
      snapshotRequired: true,
      cursor: 0,
      hasExistingLocalData: false,
    ),
    List<CloudSyncMutation> pending = const <CloudSyncMutation>[],
    this.pendingOnEnable = const <CloudSyncMutation>[],
    this.snapshotConflictCount = 0,
  }) : pending = List<CloudSyncMutation>.of(pending);

  CloudSyncAccountState state;
  final List<CloudSyncMutation> pending;
  final List<CloudSyncMutation> pendingOnEnable;
  final int snapshotConflictCount;
  int enableCalls = 0;
  List<String>? sharedEvents;
  final List<String> retryMutationIds = <String>[];
  String? lastRetryErrorCode;
  final List<String> resolvedConflicts = <String>[];
  int applyChangesCount = 0;

  @override
  Future<CloudSyncAccountState> readAccountState(String accountId) async {
    return state;
  }

  @override
  Future<void> setEnabled(String accountId, bool enabled) async {
    enableCalls += 1;
    if (enabled) pending.addAll(pendingOnEnable);
    state = CloudSyncAccountState(
      enabled: enabled,
      snapshotRequired: true,
      cursor: 0,
      hasExistingLocalData: state.hasExistingLocalData,
    );
  }

  @override
  Future<List<CloudSyncMutation>> readPendingMutations(
    String accountId, {
    int limit = 100,
  }) async {
    return pending.take(limit).toList(growable: false);
  }

  @override
  Future<int> applySnapshot(
    String accountId,
    CloudSyncSnapshot snapshot,
  ) async {
    sharedEvents?.add('apply_snapshot');
    if (snapshotConflictCount == 0) {
      state = CloudSyncAccountState(
        enabled: true,
        snapshotRequired: false,
        cursor: snapshot.cursor,
        hasExistingLocalData: state.hasExistingLocalData,
      );
    }
    return snapshotConflictCount;
  }

  @override
  Future<void> applyMutationResults(
    String accountId,
    List<CloudSyncMutationResult> results,
  ) async {
    final Set<String> applied = results
        .where(
          (CloudSyncMutationResult result) =>
              result.status == CloudSyncMutationStatus.applied,
        )
        .map((CloudSyncMutationResult result) => result.mutationId)
        .toSet();
    pending.removeWhere(
      (CloudSyncMutation mutation) => applied.contains(mutation.mutationId),
    );
  }

  @override
  Future<void> applyChanges(
    String accountId,
    CloudSyncChangePage page,
  ) async {
    applyChangesCount += 1;
    state = CloudSyncAccountState(
      enabled: state.enabled,
      snapshotRequired: false,
      cursor: page.nextCursor,
      hasExistingLocalData: state.hasExistingLocalData,
    );
  }

  @override
  Future<void> markMutationsForRetry({
    required String accountId,
    required List<CloudSyncMutation> mutations,
    required String errorCode,
  }) async {
    retryMutationIds
      ..clear()
      ..addAll(
        mutations.map((CloudSyncMutation mutation) => mutation.mutationId),
      );
    lastRetryErrorCode = errorCode;
  }

  @override
  Future<List<CloudSyncConflict>> readPendingConflicts(
    String accountId,
  ) async {
    return const <CloudSyncConflict>[];
  }

  @override
  Future<void> resolveConflict({
    required String accountId,
    required String conflictId,
    required CloudSyncConflictResolution resolution,
  }) async {
    resolvedConflicts.add('$conflictId:${resolution.name}');
  }
}
