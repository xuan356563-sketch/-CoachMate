import '../../../data/models/cloud_sync.dart';

abstract interface class CloudSyncLocalStore {
  Future<CloudSyncAccountState> readAccountState(String accountId);

  Future<void> setEnabled(String accountId, bool enabled);

  Future<List<CloudSyncMutation>> readPendingMutations(
    String accountId, {
    int limit = 100,
  });

  Future<int> applySnapshot(
    String accountId,
    CloudSyncSnapshot snapshot,
  );

  Future<void> applyMutationResults(
    String accountId,
    List<CloudSyncMutationResult> results,
  );

  Future<void> applyChanges(
    String accountId,
    CloudSyncChangePage page,
  );

  Future<void> markMutationsForRetry({
    required String accountId,
    required List<CloudSyncMutation> mutations,
    required String errorCode,
  });

  Future<List<CloudSyncConflict>> readPendingConflicts(String accountId);

  Future<void> resolveConflict({
    required String accountId,
    required String conflictId,
    required CloudSyncConflictResolution resolution,
  });
}
