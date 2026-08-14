import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/cloud_sync.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/authenticated_api_client.dart';
import '../data/cloud_sync_api.dart';
import '../data/cloud_sync_local_store.dart';
import 'cloud_sync_coordinator.dart';

final cloudSyncLocalStoreProvider = Provider<CloudSyncLocalStore?>(
  (Ref ref) => null,
);

final cloudSyncRemoteGatewayProvider = Provider<CloudSyncRemoteGateway>(
  (Ref ref) => CloudSyncApi(ref.watch(authenticatedApiClientProvider)),
);

final cloudSyncControllerProvider =
    AsyncNotifierProvider<CloudSyncController, CloudSyncUiState>(
  CloudSyncController.new,
  retry: (int _, Object __) => null,
);

class CloudSyncUiState {
  const CloudSyncUiState({
    required this.available,
    required this.enabled,
    required this.busy,
    required this.statusMessage,
    this.conflictCount = 0,
    this.conflicts = const <CloudSyncConflict>[],
  });

  const CloudSyncUiState.unavailable()
      : this(
          available: false,
          enabled: false,
          busy: false,
          statusMessage: '当前设备仅使用本地存储',
        );

  final bool available;
  final bool enabled;
  final bool busy;
  final String statusMessage;
  final int conflictCount;
  final List<CloudSyncConflict> conflicts;

  CloudSyncUiState copyWith({
    bool? available,
    bool? enabled,
    bool? busy,
    String? statusMessage,
    int? conflictCount,
    List<CloudSyncConflict>? conflicts,
  }) {
    return CloudSyncUiState(
      available: available ?? this.available,
      enabled: enabled ?? this.enabled,
      busy: busy ?? this.busy,
      statusMessage: statusMessage ?? this.statusMessage,
      conflictCount: conflictCount ?? this.conflictCount,
      conflicts: conflicts ?? this.conflicts,
    );
  }
}

class CloudSyncController extends AsyncNotifier<CloudSyncUiState> {
  CloudSyncLocalStore? _localStore;
  CloudSyncRemoteGateway? _remoteGateway;
  String? _accountId;

  @override
  Future<CloudSyncUiState> build() async {
    final AuthState auth = await ref.watch(authControllerProvider.future);
    final CloudSyncLocalStore? localStore =
        ref.watch(cloudSyncLocalStoreProvider);
    final String? accountId = auth.isAuthenticated ? auth.user?.userId : null;
    if (localStore == null || accountId == null) {
      return const CloudSyncUiState.unavailable();
    }
    _localStore = localStore;
    _remoteGateway = ref.watch(cloudSyncRemoteGatewayProvider);
    _accountId = accountId;
    final CloudSyncAccountState accountState =
        await localStore.readAccountState(accountId);
    final List<CloudSyncConflict> conflicts =
        await localStore.readPendingConflicts(accountId);
    return CloudSyncUiState(
      available: true,
      enabled: accountState.enabled,
      busy: false,
      conflictCount: conflicts.length,
      conflicts: conflicts,
      statusMessage:
          accountState.enabled ? '云同步已启用，训练仍以本机数据为准' : '云同步未启用，现有数据不会自动上传',
    );
  }

  Future<void> enable({required bool confirmed}) async {
    final CloudSyncUiState current = _current;
    final CloudSyncCoordinator coordinator = _coordinator();
    state = AsyncData<CloudSyncUiState>(
      current.copyWith(busy: true, statusMessage: '正在建立加密同步状态…'),
    );
    try {
      await coordinator.enable(
        accountId: _requiredAccountId,
        confirmed: confirmed,
      );
      await _runSync(coordinator, current.copyWith(enabled: true));
    } catch (error) {
      state = AsyncData<CloudSyncUiState>(
        current.copyWith(
          busy: false,
          statusMessage: error is CloudSyncConfirmationRequiredException
              ? error.toString()
              : '云同步启用失败，本地训练不受影响',
        ),
      );
    }
  }

  Future<void> disable() async {
    final CloudSyncUiState current = _current;
    state = AsyncData<CloudSyncUiState>(current.copyWith(busy: true));
    await _coordinator().disable(accountId: _requiredAccountId);
    state = AsyncData<CloudSyncUiState>(
      current.copyWith(
        enabled: false,
        busy: false,
        statusMessage: '云同步已关闭，本机训练数据保持不变',
      ),
    );
  }

  Future<void> synchronize() async {
    final CloudSyncUiState current = _current;
    state = AsyncData<CloudSyncUiState>(
      current.copyWith(busy: true, statusMessage: '正在同步允许的数据…'),
    );
    await _runSync(_coordinator(), current);
  }

  Future<void> resolveConflict({
    required String conflictId,
    required CloudSyncConflictResolution resolution,
    required bool confirmed,
  }) async {
    final CloudSyncUiState current = _current;
    state = AsyncData<CloudSyncUiState>(
      current.copyWith(busy: true, statusMessage: '正在保存冲突选择…'),
    );
    try {
      await _coordinator().resolveConflict(
        accountId: _requiredAccountId,
        conflictId: conflictId,
        resolution: resolution,
        confirmed: confirmed,
      );
      final List<CloudSyncConflict> conflicts =
          await _localStore!.readPendingConflicts(_requiredAccountId);
      state = AsyncData<CloudSyncUiState>(
        current.copyWith(
          busy: false,
          conflictCount: conflicts.length,
          conflicts: conflicts,
          statusMessage: conflicts.isEmpty
              ? '冲突选择已保存，可继续同步'
              : '冲突选择已保存，仍有 ${conflicts.length} 项待确认',
        ),
      );
    } on CloudSyncConfirmationRequiredException catch (error) {
      state = AsyncData<CloudSyncUiState>(
        current.copyWith(busy: false, statusMessage: error.toString()),
      );
    } catch (_) {
      state = AsyncData<CloudSyncUiState>(
        current.copyWith(
          busy: false,
          statusMessage: '冲突处理失败，本地数据未被自动覆盖',
        ),
      );
    }
  }

  Future<void> _runSync(
    CloudSyncCoordinator coordinator,
    CloudSyncUiState current,
  ) async {
    try {
      final CloudSyncRunResult result = await coordinator.synchronize(
        accountId: _requiredAccountId,
      );
      final CloudSyncAccountState accountState =
          await _localStore!.readAccountState(_requiredAccountId);
      final List<CloudSyncConflict> conflicts =
          await _localStore!.readPendingConflicts(_requiredAccountId);
      state = AsyncData<CloudSyncUiState>(
        current.copyWith(
          enabled: accountState.enabled,
          busy: false,
          conflictCount: conflicts.length,
          conflicts: conflicts,
          statusMessage: switch (result.status) {
            CloudSyncRunStatus.disabled => '云同步未启用',
            CloudSyncRunStatus.synced => '允许的数据已同步',
            CloudSyncRunStatus.offline => '网络不可用，本地训练可继续',
            CloudSyncRunStatus.conflicts => '发现数据冲突，尚未自动覆盖',
          },
        ),
      );
    } catch (_) {
      state = AsyncData<CloudSyncUiState>(
        current.copyWith(
          busy: false,
          statusMessage: '同步暂时失败，本地训练不受影响',
        ),
      );
    }
  }

  CloudSyncUiState get _current =>
      state.value ?? const CloudSyncUiState.unavailable();

  String get _requiredAccountId {
    final String? value = _accountId;
    if (value == null) throw StateError('当前账号不能使用云同步');
    return value;
  }

  CloudSyncCoordinator _coordinator() {
    final CloudSyncLocalStore? localStore = _localStore;
    final CloudSyncRemoteGateway? remoteGateway = _remoteGateway;
    if (localStore == null || remoteGateway == null) {
      throw StateError('当前设备不能使用云同步');
    }
    return CloudSyncCoordinator(
      localStore: localStore,
      remoteGateway: remoteGateway,
    );
  }
}
