import '../../../data/models/cloud_sync.dart';
import '../data/cloud_sync_api.dart';
import '../data/cloud_sync_local_store.dart';

enum CloudSyncRunStatus { disabled, synced, offline, conflicts }

class CloudSyncRunResult {
  const CloudSyncRunResult({
    required this.status,
    this.conflictCount = 0,
    this.localTrainingAvailable = true,
  });

  final CloudSyncRunStatus status;
  final int conflictCount;
  final bool localTrainingAvailable;
}

class CloudSyncConfirmationRequiredException implements Exception {
  const CloudSyncConfirmationRequiredException();

  @override
  String toString() => '启用云同步前需要用户明确确认';
}

class CloudSyncCoordinator {
  const CloudSyncCoordinator({
    required CloudSyncLocalStore localStore,
    required CloudSyncRemoteGateway remoteGateway,
  })  : _localStore = localStore,
        _remoteGateway = remoteGateway;

  final CloudSyncLocalStore _localStore;
  final CloudSyncRemoteGateway _remoteGateway;

  Future<void> enable({
    required String accountId,
    required bool confirmed,
  }) async {
    if (!confirmed) {
      throw const CloudSyncConfirmationRequiredException();
    }
    await _localStore.setEnabled(accountId, true);
  }

  Future<void> disable({required String accountId}) {
    return _localStore.setEnabled(accountId, false);
  }

  Future<void> resolveConflict({
    required String accountId,
    required String conflictId,
    required CloudSyncConflictResolution resolution,
    required bool confirmed,
  }) async {
    if (!confirmed) {
      throw const CloudSyncConfirmationRequiredException();
    }
    await _localStore.resolveConflict(
      accountId: accountId,
      conflictId: conflictId,
      resolution: resolution,
    );
  }

  Future<CloudSyncRunResult> synchronize({
    required String accountId,
  }) async {
    CloudSyncAccountState state = await _localStore.readAccountState(accountId);
    if (!state.enabled) {
      return const CloudSyncRunResult(status: CloudSyncRunStatus.disabled);
    }

    List<CloudSyncMutation> pending = const <CloudSyncMutation>[];
    try {
      if (state.snapshotRequired) {
        final CloudSyncSnapshot snapshot = await _remoteGateway.fetchSnapshot();
        final int conflicts =
            await _localStore.applySnapshot(accountId, snapshot);
        if (conflicts > 0) {
          return CloudSyncRunResult(
            status: CloudSyncRunStatus.conflicts,
            conflictCount: conflicts,
          );
        }
        state = await _localStore.readAccountState(accountId);
      }

      pending = await _localStore.readPendingMutations(accountId);
      if (pending.isNotEmpty) {
        final List<CloudSyncMutationResult> results =
            await _remoteGateway.sendMutations(pending);
        await _localStore.applyMutationResults(accountId, results);
        final int conflicts = results
            .where(
              (CloudSyncMutationResult result) =>
                  result.status == CloudSyncMutationStatus.conflict,
            )
            .length;
        if (conflicts > 0) {
          return CloudSyncRunResult(
            status: CloudSyncRunStatus.conflicts,
            conflictCount: conflicts,
          );
        }
      }

      bool hasMore = true;
      int cursor = state.cursor;
      while (hasMore) {
        final CloudSyncChangePage page =
            await _remoteGateway.fetchChanges(after: cursor);
        await _localStore.applyChanges(accountId, page);
        cursor = page.nextCursor;
        hasMore = page.hasMore;
      }
      return const CloudSyncRunResult(status: CloudSyncRunStatus.synced);
    } on CloudSyncTransportException {
      await _localStore.markMutationsForRetry(
        accountId: accountId,
        mutations: pending,
        errorCode: 'transport_unavailable',
      );
      return const CloudSyncRunResult(
        status: CloudSyncRunStatus.offline,
        localTrainingAvailable: true,
      );
    }
  }
}
