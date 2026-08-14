import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/trainmate_structured_database_gateway.dart';
import '../../../data/models/health_snapshot.dart';
import '../../../data/repositories/health_snapshot_repository.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/local_report_generation_coordinator.dart';
import '../../../services/training_metrics_pipeline.dart';
import '../../growth/application/growth_evidence_controller.dart';
import '../../growth/application/training_metrics_provider.dart';
import 'health_data_gateway.dart';
import 'user_profile_controller.dart';

final healthDataGatewayProvider = Provider<HealthDataGateway>(
  (Ref ref) => createHealthDataGateway(),
);
final healthSnapshotRepositoryProvider = Provider<HealthSnapshotRepository>(
  (Ref ref) => HealthSnapshotRepository(ref.watch(localStorageServiceProvider)),
);
final healthSyncStructuredDatabaseGatewayProvider =
    Provider<TrainMateStructuredDatabaseGateway?>((Ref ref) => null);

/// 测试和 Web 默认不启用；生产启动层仅在结构化数据库可用时注入。
final healthSyncMetricsPipelineProvider = Provider<TrainingMetricsPipeline?>(
  (Ref ref) => null,
);
final healthDailyActivityRefreshSignalProvider =
    NotifierProvider<HealthDailyActivityRefreshSignal, int>(
  HealthDailyActivityRefreshSignal.new,
);
final healthSyncAthleteIdProvider = Provider<String>(
  (Ref ref) => ref.watch(
    userProfileControllerProvider.select(
      (UserProfileState state) => state.profile.id,
    ),
  ),
);
final healthSyncControllerProvider =
    AsyncNotifierProvider<HealthSyncController, HealthSyncState>(
  HealthSyncController.new,
  retry: (int _, Object __) => null,
);

/// 只表示“每日活动摘要可以重新查询”，不携带宠物能量或授权推断。
class HealthDailyActivityRefreshSignal extends Notifier<int> {
  @override
  int build() => 0;

  void requestRefresh() => state += 1;
}

class HealthSyncState {
  final bool supported;
  final bool syncing;
  final List<HealthSnapshot> snapshots;
  final Map<HealthPermissionStage, HealthAuthorizationState>
      authorizationByStage;
  final Map<HealthPermissionStage, DateTime> lastSyncByStage;
  final List<HealthSyncBatch> pendingBatches;
  final String statusMessage;

  const HealthSyncState({
    required this.supported,
    required this.syncing,
    required this.snapshots,
    required this.authorizationByStage,
    required this.lastSyncByStage,
    required this.pendingBatches,
    required this.statusMessage,
  });

  bool get connected =>
      snapshots.isNotEmpty ||
      pendingBatches.any((HealthSyncBatch batch) => batch.upserts.isNotEmpty);

  HealthSnapshot? get latest => snapshots.isEmpty ? null : snapshots.first;

  DateTime? get lastSync {
    if (lastSyncByStage.isEmpty) return null;
    return lastSyncByStage.values.reduce(
      (DateTime left, DateTime right) => left.isAfter(right) ? left : right,
    );
  }

  HealthAuthorizationState authorizationFor(HealthPermissionStage stage) =>
      authorizationByStage[stage] ?? HealthAuthorizationState.notRequested;

  HealthSyncState copyWith({
    bool? syncing,
    List<HealthSnapshot>? snapshots,
    Map<HealthPermissionStage, HealthAuthorizationState>? authorizationByStage,
    Map<HealthPermissionStage, DateTime>? lastSyncByStage,
    List<HealthSyncBatch>? pendingBatches,
    String? statusMessage,
  }) =>
      HealthSyncState(
        supported: supported,
        syncing: syncing ?? this.syncing,
        snapshots: snapshots ?? this.snapshots,
        authorizationByStage: authorizationByStage ?? this.authorizationByStage,
        lastSyncByStage: lastSyncByStage ?? this.lastSyncByStage,
        pendingBatches: pendingBatches ?? this.pendingBatches,
        statusMessage: statusMessage ?? this.statusMessage,
      );
}

class HealthSyncController extends AsyncNotifier<HealthSyncState> {
  late HealthDataGateway _gateway;
  late HealthSnapshotRepository _repository;
  late LocalStorageService _localStorage;
  late TrainMateStructuredDatabaseGateway? _structuredGateway;
  late TrainingMetricsPipeline? _metricsPipeline;
  late String _athleteId;
  Future<int>? _backgroundDrainFuture;

  static const String _backgroundFailureMessage = '后台健康数据写入失败，批次和同步锚点已保留，请重试。';

  @override
  Future<HealthSyncState> build() async {
    _gateway = ref.read(healthDataGatewayProvider);
    _repository = ref.read(healthSnapshotRepositoryProvider);
    _localStorage = ref.read(localStorageServiceProvider);
    _structuredGateway = ref.watch(
      healthSyncStructuredDatabaseGatewayProvider,
    );
    _metricsPipeline = ref.watch(healthSyncMetricsPipelineProvider);
    _athleteId = ref.watch(healthSyncAthleteIdProvider);
    final List<HealthSnapshot> snapshots =
        _repository.listSnapshots(athleteId: _athleteId);
    final Map<HealthPermissionStage, HealthAuthorizationState> authorization =
        <HealthPermissionStage, HealthAuthorizationState>{
      for (final HealthPermissionStage stage in HealthPermissionStage.values)
        stage: _repository.getAuthorizationState(
          athleteId: _athleteId,
          stage: stage,
        ),
    };
    final Map<HealthPermissionStage, DateTime> lastSync =
        <HealthPermissionStage, DateTime>{};
    for (final HealthPermissionStage stage in HealthPermissionStage.values) {
      final DateTime? value = _repository.getLastSync(
        athleteId: _athleteId,
        stage: stage,
      );
      if (value != null) lastSync[stage] = value;
    }
    HealthSyncState initial = HealthSyncState(
      supported: _gateway.isSupported,
      syncing: false,
      snapshots: snapshots,
      authorizationByStage: authorization,
      lastSyncByStage: lastSync,
      pendingBatches: const <HealthSyncBatch>[],
      statusMessage: !_gateway.isSupported
          ? '当前平台不支持 Apple 健康同步。'
          : snapshots.isEmpty
              ? '尚未请求 Apple 健康读取权限。'
              : '已读取本机 Apple 健康数据。',
    );
    if (_gateway.isSupported && _structuredGateway != null) {
      try {
        final int processed = await _guardedBackgroundDrain(limit: 20);
        if (processed > 0) {
          initial = initial.copyWith(
            snapshots: _repository.listSnapshots(athleteId: _athleteId),
            statusMessage: '已安全写入 $processed 个后台健康数据批次。',
          );
        }
      } catch (_) {
        initial = initial.copyWith(
          snapshots: _repository.listSnapshots(athleteId: _athleteId),
          statusMessage: _backgroundFailureMessage,
        );
      }
    }
    return initial;
  }

  Future<void> connectAndSync({
    HealthPermissionStage stage = HealthPermissionStage.analysis,
  }) async {
    final HealthSyncState? current = state.value;
    if (current == null || !current.supported || current.syncing) return;
    state = AsyncData(current.copyWith(
      syncing: true,
      statusMessage: '正在请求 Apple 健康读取权限…',
    ));
    try {
      final HealthAuthorizationResult result = await _gateway.requestPermission(
        stage: stage,
        athleteId: _athleteId,
      );
      _repository.saveAuthorization(
        athleteId: _athleteId,
        stage: stage,
        state: result.state,
      );
      final Map<HealthPermissionStage, HealthAuthorizationState> authorization =
          <HealthPermissionStage, HealthAuthorizationState>{
        ...current.authorizationByStage,
        stage: result.state,
      };
      if (!result.requestCompleted) {
        state = AsyncData(current.copyWith(
          syncing: false,
          authorizationByStage: authorization,
          statusMessage: result.message ?? 'Apple 健康权限请求未完成，请稍后重试。',
        ));
        return;
      }
      state = AsyncData(current.copyWith(
        syncing: true,
        authorizationByStage: authorization,
      ));
      await _sync(stage);
      try {
        await _gateway.enableBackgroundSync(
          stage: stage,
          athleteId: _athleteId,
        );
      } catch (_) {
        final HealthSyncState? synced = state.value;
        if (synced != null) {
          state = AsyncData(synced.copyWith(
            statusMessage: '${synced.statusMessage} 后台更新暂未启用。',
          ));
        }
      }
    } catch (_) {
      final HealthSyncState fallback = state.value ?? current;
      state = AsyncData(fallback.copyWith(
        syncing: false,
        statusMessage: '健康数据同步失败，请解锁设备后重试。',
      ));
    }
  }

  Future<void> sync({
    HealthPermissionStage stage = HealthPermissionStage.analysis,
  }) async {
    final HealthSyncState? current = state.value;
    if (current == null || !current.supported || current.syncing) return;
    state = AsyncData(current.copyWith(
      syncing: true,
      statusMessage: '正在同步健康数据…',
    ));
    try {
      await _sync(stage);
    } catch (_) {
      state = AsyncData(current.copyWith(
        syncing: false,
        statusMessage: '健康数据同步失败，请稍后重试。',
      ));
    }
  }

  Future<void> _sync(HealthPermissionStage stage) async {
    final HealthSyncState current = state.value!;
    final DateTime end = DateTime.now();
    final DateTime start = current.lastSyncByStage[stage] == null
        ? end.subtract(const Duration(days: 30))
        : current.lastSyncByStage[stage]!.subtract(const Duration(days: 1));
    final HealthForegroundSyncResult incoming = await _gateway.syncForeground(
      stage: stage,
      athleteId: _athleteId,
      start: start,
      end: end,
    );
    final TrainMateStructuredDatabaseGateway? structured = _structuredGateway;
    final List<HealthSyncBatch> unprocessedBatches = <HealthSyncBatch>[];
    if (structured == null) {
      unprocessedBatches.addAll(incoming.batches);
    } else {
      for (final HealthSyncBatch batch in incoming.batches) {
        if (batch.athleteId != _athleteId) {
          throw StateError('前台健康数据批次与当前运动员不一致，已停止写入。');
        }
        final HealthSyncApplyResult applyResult =
            await structured.applyHealthSyncBatch(
          batch,
          syncMode: 'foreground',
        );
        await _processCommittedMetrics(batch, applyResult);
        if (batch.requiresAcknowledgement) {
          await _gateway.acknowledgeBatch(batch.batchId);
        }
      }
    }
    final Set<String> deletedLegacySourceIds = _legacyDeletedSourceIds(
      incoming.batches,
    );
    final Map<String, HealthSnapshot> merged = <String, HealthSnapshot>{
      for (final HealthSnapshot item in current.snapshots)
        if (!_snapshotMustBeRemoved(item, deletedLegacySourceIds))
          item.id: item,
      for (final HealthSnapshot item in incoming.snapshots) item.id: item,
    };
    final List<HealthSnapshot> snapshots = merged.values.toList()
      ..sort((HealthSnapshot left, HealthSnapshot right) =>
          right.date.compareTo(left.date));
    final List<HealthSyncBatch> pending = <HealthSyncBatch>[
      ...current.pendingBatches,
      ...unprocessedBatches,
    ];
    final Map<HealthPermissionStage, DateTime> lastSync =
        <HealthPermissionStage, DateTime>{...current.lastSyncByStage};
    final bool hasStructuredFacts = structured != null &&
        incoming.batches.any(
          (HealthSyncBatch batch) =>
              batch.upserts.isNotEmpty || batch.deletedExternalIds.isNotEmpty,
        );
    final bool hasPersistedReadableData =
        incoming.snapshots.isNotEmpty || hasStructuredFacts;
    if (hasPersistedReadableData) {
      _repository.save(
        athleteId: _athleteId,
        stage: stage,
        snapshots: snapshots,
        syncedAt: end,
      );
      await _localStorage.flush();
      lastSync[stage] = end;
    }
    state = AsyncData(current.copyWith(
      syncing: false,
      snapshots: snapshots,
      pendingBatches: pending,
      lastSyncByStage: lastSync,
      statusMessage: hasPersistedReadableData
          ? '已读取并安全保存本机 Apple 健康数据。'
          : unprocessedBatches.isNotEmpty
              ? '已读取健康数据，等待结构化存储可用后写入。'
              : '授权流程已完成，但系统无法判定逐项读取权限；当前未读取到数据。',
    ));
    if (stage == HealthPermissionStage.analysis) {
      ref
          .read(healthDailyActivityRefreshSignalProvider.notifier)
          .requestRefresh();
    }
  }

  Future<void> drainPendingBatches({
    required HealthSyncBatchProcessor processor,
    int limit = 20,
  }) async {
    final List<HealthSyncBatch> foregroundBatches = List<HealthSyncBatch>.from(
      state.value?.pendingBatches ?? const <HealthSyncBatch>[],
    );
    for (final HealthSyncBatch batch in foregroundBatches) {
      if (batch.athleteId != _athleteId) continue;
      await processor(batch);
      final HealthSyncState? latest = state.value;
      if (latest != null) {
        state = AsyncData(latest.copyWith(
          pendingBatches: latest.pendingBatches
              .where((HealthSyncBatch item) => item.batchId != batch.batchId)
              .toList(growable: false),
        ));
      }
    }

    if (_structuredGateway != null) {
      await drainPendingBackgroundBatches(limit: limit);
      return;
    }
    final List<HealthSyncBatch> batches =
        await _gateway.drainPendingBackgroundBatches(limit: limit);
    for (final HealthSyncBatch batch in batches) {
      if (batch.athleteId != _athleteId) continue;
      await processor(batch);
      if (batch.requiresAcknowledgement) {
        await _gateway.acknowledgeBatch(batch.batchId);
      }
    }
  }

  Future<void> drainPendingBackgroundBatches({int limit = 20}) async {
    if (_structuredGateway == null || !_gateway.isSupported) return;
    try {
      final int processed = await _guardedBackgroundDrain(limit: limit);
      final HealthSyncState? current = state.value;
      if (current != null && processed > 0) {
        state = AsyncData(current.copyWith(
          statusMessage: '已安全写入 $processed 个后台健康数据批次。',
        ));
      }
    } catch (error, stackTrace) {
      final HealthSyncState? current = state.value;
      if (current != null) {
        state = AsyncData(current.copyWith(
          syncing: false,
          statusMessage: _backgroundFailureMessage,
        ));
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<int> _guardedBackgroundDrain({required int limit}) {
    final Future<int>? active = _backgroundDrainFuture;
    if (active != null) return active;
    late final Future<int> operation;
    operation = _drainBackgroundOnce(limit: limit).whenComplete(() {
      if (identical(_backgroundDrainFuture, operation)) {
        _backgroundDrainFuture = null;
      }
    });
    _backgroundDrainFuture = operation;
    return operation;
  }

  Future<int> _drainBackgroundOnce({required int limit}) async {
    final TrainMateStructuredDatabaseGateway? structured = _structuredGateway;
    if (structured == null) return 0;
    final String athleteId = _athleteId;
    int processed = 0;
    final Set<String> processedBatchIds = <String>{};
    // 原生层在确认一个 anchored 批次后会等待下一页查询完成再返回，因此这里
    // 可以持续排空大于 500 条的分页，而不必等到下一次应用启动。
    for (int round = 0; round < 256; round += 1) {
      final List<HealthSyncBatch> batches =
          await _gateway.drainPendingBackgroundBatches(limit: limit);
      final List<HealthSyncBatch> pendingForAthlete = batches
          .where(
            (HealthSyncBatch batch) =>
                batch.athleteId == athleteId &&
                !processedBatchIds.contains(batch.batchId),
          )
          .toList(growable: false)
        ..sort(_compareBackgroundBatchPriority);
      if (pendingForAthlete.isEmpty) {
        if (processed > 0) {
          ref
              .read(healthDailyActivityRefreshSignalProvider.notifier)
              .requestRefresh();
        }
        return processed;
      }
      for (final HealthSyncBatch batch in pendingForAthlete) {
        final HealthSyncApplyResult applyResult =
            await structured.applyHealthSyncBatch(
          batch,
          syncMode: 'background',
        );
        await _removeDeletedLegacySnapshots(batch);
        await _processCommittedMetrics(batch, applyResult);
        if (batch.requiresAcknowledgement) {
          await _gateway.acknowledgeBatch(batch.batchId);
        }
        processedBatchIds.add(batch.batchId);
        processed += 1;
      }
    }
    throw StateError('后台健康数据分页过多，已保留剩余批次，请再次同步。');
  }

  static int _compareBackgroundBatchPriority(
    HealthSyncBatch first,
    HealthSyncBatch second,
  ) {
    final int byRoute = _isRouteBatch(first).compareTo(_isRouteBatch(second));
    if (byRoute != 0) return byRoute;
    final int byCreatedAt = first.createdAt.compareTo(second.createdAt);
    return byCreatedAt != 0
        ? byCreatedAt
        : first.batchId.compareTo(second.batchId);
  }

  static int _isRouteBatch(HealthSyncBatch batch) {
    if (batch.objectType.toLowerCase().contains('workoutroute')) return 1;
    return batch.upserts.any(
      (Map<String, Object?> row) =>
          (row['kind'] as String? ?? '').toLowerCase() == 'workoutroute',
    )
        ? 1
        : 0;
  }

  Future<void> _processCommittedMetrics(
    HealthSyncBatch batch,
    HealthSyncApplyResult applyResult,
  ) async {
    final TrainingMetricsPipeline? pipeline = _metricsPipeline;
    if (pipeline == null) return;
    final HealthBatchMetricsResult metricsResult =
        await pipeline.processCommittedHealthBatch(batch, applyResult);
    final LocalReportGenerationCoordinator reportCoordinator =
        LocalReportGenerationCoordinator(
      repository: ref.read(trainingMetricsRepositoryProvider),
      metricsPipeline: pipeline,
      monthlySummaryLoader: ref.read(monthlySummaryLoaderProvider),
    );
    for (final MetricPeriodWindow window in metricsResult.affectedPeriods) {
      await reportCoordinator.ensureClosedPeriod(
        athleteProfileId: batch.athleteId,
        period: window.period,
        periodStart: window.periodStart,
      );
    }
    if (applyResult.invalidatedSourceIds.isNotEmpty) {
      await ref
          .read(growthEvidenceControllerProvider.notifier)
          .refreshPersistedAthleteState(athleteProfileId: batch.athleteId);
    }
    ref.invalidate(trainingMetricAggregatesProvider);
    ref.invalidate(trainingReportRevisionsProvider);
    ref.invalidate(growthMetricsControllerProvider);
  }

  Future<void> _removeDeletedLegacySnapshots(HealthSyncBatch batch) async {
    final Set<String> deletedSourceIds =
        _legacyDeletedSourceIds(<HealthSyncBatch>[
      batch,
    ]);
    if (deletedSourceIds.isEmpty) return;
    final List<HealthSnapshot> snapshots = _repository.removeDeletedSources(
      athleteId: _athleteId,
      deletedSourceIds: deletedSourceIds,
    );
    await _localStorage.flush();
    final HealthSyncState? current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(snapshots: snapshots));
    }
  }

  Future<void> clearAthleteData() async {
    final HealthSyncState? current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(
        syncing: true,
        statusMessage: '正在清除当前运动员的本地健康数据…',
      ));
    }
    try {
      await _gateway.clearAthleteData(athleteId: _athleteId);
      await _structuredGateway?.clearAthleteStructuredData(_athleteId);
      _repository.clearAthlete(_athleteId);
      await _localStorage.flush();
      final HealthSyncState? latest = state.value ?? current;
      if (latest == null) return;
      state = AsyncData(HealthSyncState(
        supported: latest.supported,
        syncing: false,
        snapshots: const <HealthSnapshot>[],
        authorizationByStage: <HealthPermissionStage, HealthAuthorizationState>{
          for (final HealthPermissionStage stage
              in HealthPermissionStage.values)
            stage: HealthAuthorizationState.notRequested,
        },
        lastSyncByStage: const <HealthPermissionStage, DateTime>{},
        pendingBatches: const <HealthSyncBatch>[],
        statusMessage: '已清除当前运动员的本地健康数据。',
      ));
    } catch (error, stackTrace) {
      final HealthSyncState? latest = state.value ?? current;
      if (latest != null) {
        state = AsyncData(latest.copyWith(
          syncing: false,
          statusMessage: '清除本地健康数据失败，未完成的步骤可安全重试。',
        ));
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

Set<String> _legacyDeletedSourceIds(Iterable<HealthSyncBatch> batches) {
  final Set<String> result = <String>{};
  for (final HealthSyncBatch batch in batches) {
    final String type = batch.objectType.toLowerCase();
    if (type.contains('workout') || type.contains('route')) continue;
    result.addAll(
      batch.deletedExternalIds.where((String value) => value.trim().isNotEmpty),
    );
  }
  return result;
}

bool _snapshotMustBeRemoved(
  HealthSnapshot snapshot,
  Set<String> deletedSourceIds,
) {
  if (deletedSourceIds.isEmpty) return false;
  if (snapshot.sourceIds.isEmpty) return true;
  return snapshot.sourceIds.any(deletedSourceIds.contains);
}

class HealthSyncOperationException implements Exception {
  const HealthSyncOperationException(this.message, {required this.cause});

  final String message;
  final Object cause;

  @override
  String toString() => message;
}
