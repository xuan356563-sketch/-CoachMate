import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/cloud_sync.dart';
import 'package:trainflow_ai/features/auth/application/auth_controller.dart';
import 'package:trainflow_ai/features/auth/data/auth_api.dart';
import 'package:trainflow_ai/features/cloud_sync/application/cloud_sync_controller.dart';
import 'package:trainflow_ai/features/cloud_sync/data/cloud_sync_api.dart';
import 'package:trainflow_ai/features/cloud_sync/data/cloud_sync_local_store.dart';

void main() {
  test('登录后只读取同步状态，不经确认不会启用或访问云端', () async {
    final _ControllerLocalStore store = _ControllerLocalStore();
    final _ControllerRemoteGateway remote = _ControllerRemoteGateway();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_AuthenticatedController.new),
        cloudSyncLocalStoreProvider.overrideWithValue(store),
        cloudSyncRemoteGatewayProvider.overrideWithValue(remote),
      ],
    );
    addTearDown(container.dispose);

    final CloudSyncUiState initial =
        await container.read(cloudSyncControllerProvider.future);

    expect(initial.available, isTrue);
    expect(initial.enabled, isFalse);
    expect(remote.events, isEmpty);

    await container
        .read(cloudSyncControllerProvider.notifier)
        .enable(confirmed: true);

    expect(store.enableCalls, 1);
    expect(remote.events, <String>['snapshot', 'changes']);
    expect(
      container.read(cloudSyncControllerProvider).value?.enabled,
      isTrue,
    );
  });

  test('待处理冲突会展示且只有明确确认后才按用户选择解决', () async {
    final _ControllerLocalStore store = _ControllerLocalStore()
      ..conflicts = <CloudSyncConflict>[
        const CloudSyncConflict(
          id: 'conflict-1',
          entityType: CloudSyncEntityType.trainingPreferences,
          entityId: 'preferences-1',
          cloudVersion: 2,
        ),
      ];
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_AuthenticatedController.new),
        cloudSyncLocalStoreProvider.overrideWithValue(store),
        cloudSyncRemoteGatewayProvider.overrideWithValue(
          _ControllerRemoteGateway(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final CloudSyncUiState initial =
        await container.read(cloudSyncControllerProvider.future);
    expect(initial.conflicts.single.id, 'conflict-1');

    await container.read(cloudSyncControllerProvider.notifier).resolveConflict(
          conflictId: 'conflict-1',
          resolution: CloudSyncConflictResolution.useCloud,
          confirmed: true,
        );

    expect(store.resolvedConflicts, <String>['conflict-1:useCloud']);
    expect(
      container.read(cloudSyncControllerProvider).value?.conflicts,
      isEmpty,
    );
  });
}

class _AuthenticatedController extends AuthController {
  @override
  Future<AuthState> build() async {
    return const AuthState.authenticated(
      AuthUser(
        userId: 'account-a',
        sessionId: 'session-a',
        maskedEmail: 'a***@example.com',
        hasRequiredConsents: true,
      ),
    );
  }
}

class _ControllerRemoteGateway implements CloudSyncRemoteGateway {
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
    return const <CloudSyncMutationResult>[];
  }
}

class _ControllerLocalStore implements CloudSyncLocalStore {
  bool enabled = false;
  int enableCalls = 0;
  List<CloudSyncConflict> conflicts = <CloudSyncConflict>[];
  final List<String> resolvedConflicts = <String>[];

  @override
  Future<CloudSyncAccountState> readAccountState(String accountId) async {
    return CloudSyncAccountState(
      enabled: enabled,
      snapshotRequired: enabled,
      cursor: 0,
      hasExistingLocalData: false,
    );
  }

  @override
  Future<void> setEnabled(String accountId, bool enabled) async {
    this.enabled = enabled;
    enableCalls += 1;
  }

  @override
  Future<List<CloudSyncMutation>> readPendingMutations(
    String accountId, {
    int limit = 100,
  }) async {
    return const <CloudSyncMutation>[];
  }

  @override
  Future<int> applySnapshot(
    String accountId,
    CloudSyncSnapshot snapshot,
  ) async {
    return 0;
  }

  @override
  Future<void> applyMutationResults(
    String accountId,
    List<CloudSyncMutationResult> results,
  ) async {}

  @override
  Future<void> applyChanges(
    String accountId,
    CloudSyncChangePage page,
  ) async {}

  @override
  Future<void> markMutationsForRetry({
    required String accountId,
    required List<CloudSyncMutation> mutations,
    required String errorCode,
  }) async {}

  @override
  Future<void> resolveConflict({
    required String accountId,
    required String conflictId,
    required CloudSyncConflictResolution resolution,
  }) async {
    resolvedConflicts.add('$conflictId:${resolution.name}');
    conflicts.removeWhere((CloudSyncConflict item) => item.id == conflictId);
  }

  @override
  Future<List<CloudSyncConflict>> readPendingConflicts(
    String accountId,
  ) async {
    return List<CloudSyncConflict>.unmodifiable(conflicts);
  }
}
