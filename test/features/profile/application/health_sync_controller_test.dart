import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/trainmate_structured_database_gateway.dart';
import 'package:trainflow_ai/data/models/health_snapshot.dart';
import 'package:trainflow_ai/data/repositories/health_snapshot_repository.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway_contract.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/feature_access.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/training_metrics_pipeline.dart';

class _FakeHealthGateway extends HealthDataGateway {
  _FakeHealthGateway({
    this.foregroundResult = const HealthForegroundSyncResult(),
    this.backgroundBatches = const <HealthSyncBatch>[],
    this.backgroundPages,
    this.events,
    this.clearError,
    this.foregroundCompleter,
  });

  final HealthForegroundSyncResult foregroundResult;
  final List<HealthSyncBatch> backgroundBatches;
  final List<List<HealthSyncBatch>>? backgroundPages;
  final List<String>? events;
  final Object? clearError;
  final Completer<HealthForegroundSyncResult>? foregroundCompleter;
  final List<String> acknowledged = <String>[];
  final List<String> clearedAthletes = <String>[];
  int drainCalls = 0;
  int authorizationRequests = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<HealthAuthorizationResult> requestAuthorization({
    required HealthPermissionStage stage,
    required String athleteId,
  }) async {
    authorizationRequests += 1;
    return HealthAuthorizationResult(
      stage: stage,
      state: HealthAuthorizationState.undetermined,
      requestCompleted: true,
    );
  }

  @override
  Future<HealthForegroundSyncResult> fetchForeground({
    required HealthPermissionStage stage,
    required String athleteId,
    required DateTime start,
    required DateTime end,
  }) =>
      foregroundCompleter?.future ??
      Future<HealthForegroundSyncResult>.value(foregroundResult);

  @override
  Future<void> pauseBackgroundSync({required String athleteId}) async {
    pauseCalls += 1;
  }

  @override
  Future<void> resumeBackgroundSync({required String athleteId}) async {
    resumeCalls += 1;
  }

  @override
  Future<List<HealthSyncBatch>> drainPendingBatches({int limit = 20}) async {
    drainCalls += 1;
    final List<List<HealthSyncBatch>>? pages = backgroundPages;
    if (pages != null) {
      final int pageIndex = drainCalls - 1;
      if (pageIndex >= pages.length) return const <HealthSyncBatch>[];
      return pages[pageIndex].take(limit).toList(growable: false);
    }
    return backgroundBatches.take(limit).toList();
  }

  @override
  Future<void> acknowledgeBatch(String batchId) async {
    acknowledged.add(batchId);
    events?.add('ack:$batchId');
  }

  @override
  Future<void> clearPendingBatches({required String athleteId}) async {
    events?.add('swift');
    if (clearError case final Object error) throw error;
    clearedAthletes.add(athleteId);
  }
}

class _FakeStructuredGateway implements TrainMateStructuredDatabaseGateway {
  _FakeStructuredGateway({
    this.events,
    this.applyError,
    this.clearError,
  });

  final List<String>? events;
  Object? applyError;
  Object? clearError;
  final List<HealthSyncBatch> appliedBatches = <HealthSyncBatch>[];
  final List<String> syncModes = <String>[];
  final List<String> clearedAthletes = <String>[];

  @override
  Future<HealthSyncApplyResult> applyHealthSyncBatch(
    HealthSyncBatch batch, {
    String syncMode = 'background',
  }) async {
    events?.add('structured_apply:$syncMode');
    if (applyError case final Object error) throw error;
    appliedBatches.add(batch);
    syncModes.add(syncMode);
    return HealthSyncApplyResult(
      batchId: batch.batchId,
      upsertCount: batch.upserts.length,
      deletedCount: batch.deletedExternalIds.length,
      invalidatedSourceIds: const <String>[],
    );
  }

  @override
  Future<void> clearAthleteStructuredData(String athleteId) async {
    events?.add('structured');
    if (clearError case final Object error) throw error;
    clearedAthletes.add(athleteId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试未实现的结构化网关调用。');
}

class _RecordingStorage extends InMemoryLocalStorageService {
  _RecordingStorage(this.events, {this.flushError});

  final List<String> events;
  final Object? flushError;

  @override
  void saveJson(String key, Map<String, dynamic> value) {
    if (key == HealthSnapshotRepository.storageKey) events.add('legacy');
    super.saveJson(key, value);
  }

  @override
  Future<void> flush() async {
    events.add('flush');
    if (flushError case final Object error) throw error;
  }
}

class _FailingMetricsPipeline extends TrainingMetricsPipeline {
  _FailingMetricsPipeline({
    required super.database,
    required super.healthDataGateway,
  }) : super(
          repository: InMemoryTrainingMetricsRepository(),
        );

  @override
  Future<HealthBatchMetricsResult> processCommittedHealthBatch(
    HealthSyncBatch batch,
    HealthSyncApplyResult applyResult,
  ) {
    throw StateError('HealthKit 明细暂时不可读');
  }
}

void main() {
  test('iOS 授权流程完成后仍保持读取权限不可判定', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final _FakeHealthGateway gateway = _FakeHealthGateway();
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
    ]);
    addTearDown(container.dispose);

    await container.read(healthSyncControllerProvider.future);
    await container
        .read(healthSyncControllerProvider.notifier)
        .connectAndSync(stage: HealthPermissionStage.analysis);

    final HealthSyncState state =
        container.read(healthSyncControllerProvider).requireValue;
    expect(
      state.authorizationFor(HealthPermissionStage.analysis),
      HealthAuthorizationState.undetermined,
    );
    expect(state.connected, isFalse);
    expect(state.statusMessage, contains('无法判定'));
  });

  test('analysis 前台同步成功后只递增每日活动摘要刷新信号', () async {
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      healthDataGatewayProvider.overrideWithValue(_FakeHealthGateway()),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
    ]);
    addTearDown(container.dispose);
    await container.read(healthSyncControllerProvider.future);
    expect(container.read(healthDailyActivityRefreshSignalProvider), 0);

    await container
        .read(healthSyncControllerProvider.notifier)
        .sync(stage: HealthPermissionStage.analysis);

    expect(container.read(healthDailyActivityRefreshSignalProvider), 1);
  });

  test('workout 前台同步不触发每日活动摘要刷新信号', () async {
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      healthDataGatewayProvider.overrideWithValue(_FakeHealthGateway()),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
    ]);
    addTearDown(container.dispose);
    await container.read(healthSyncControllerProvider.future);

    await container
        .read(healthSyncControllerProvider.notifier)
        .sync(stage: HealthPermissionStage.workout);

    expect(container.read(healthDailyActivityRefreshSignalProvider), 0);
  });

  test('有真实快照时才标记已读取本机健康数据', () async {
    final DateTime now = DateTime.utc(2026, 7, 15, 12);
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      foregroundResult: HealthForegroundSyncResult(
        snapshots: <HealthSnapshot>[
          HealthSnapshot(
            id: 'health-2026-07-15',
            date: DateTime(2026, 7, 15),
            sleepHours: 7.5,
            restingHeartRate: 56,
            hrvMs: 58,
            weightKg: null,
            bodyFatPercentage: null,
            syncedAt: now,
          ),
        ],
      ),
    );
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider
          .overrideWithValue(InMemoryLocalStorageService()),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
    ]);
    addTearDown(container.dispose);

    await container.read(healthSyncControllerProvider.future);
    await container
        .read(healthSyncControllerProvider.notifier)
        .connectAndSync(stage: HealthPermissionStage.analysis);

    final HealthSyncState state =
        container.read(healthSyncControllerProvider).requireValue;
    expect(state.connected, isTrue);
    expect(state.latest?.sleepHours, 7.5);
    expect(state.statusMessage, contains('已读取'));
  });

  test('后台批次只有在本地处理成功后才确认', () async {
    final HealthSyncBatch batch = HealthSyncBatch(
      batchId: 'batch-1',
      athleteId: 'athlete-a',
      objectType: 'workout',
      queryVersion: 1,
      upserts: const <Map<String, Object?>>[],
      deletedExternalIds: const <String>[],
      nextAnchor: 'anchor-1',
      createdAt: DateTime.utc(2026, 7, 15),
      requiresAcknowledgement: true,
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      backgroundBatches: <HealthSyncBatch>[batch],
    );
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider
          .overrideWithValue(InMemoryLocalStorageService()),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
    ]);
    addTearDown(container.dispose);
    await container.read(healthSyncControllerProvider.future);

    await expectLater(
      container.read(healthSyncControllerProvider.notifier).drainPendingBatches(
            processor: (_) async => throw StateError('写入失败'),
          ),
      throwsStateError,
    );
    expect(gateway.acknowledged, isEmpty);

    await container
        .read(healthSyncControllerProvider.notifier)
        .drainPendingBatches(
          processor: (_) async {},
        );
    expect(gateway.acknowledged, <String>['batch-1']);
  });

  test('前台批次处理成功后从待落库列表移除且不调用锚点确认', () async {
    final HealthSyncBatch foregroundBatch = HealthSyncBatch(
      batchId: 'foreground-1',
      athleteId: 'athlete-a',
      objectType: 'foreground.workout',
      queryVersion: 1,
      upserts: const <Map<String, Object?>>[
        <String, Object?>{'uuid': 'workout-1', 'kind': 'workout'},
      ],
      deletedExternalIds: const <String>[],
      nextAnchor: null,
      createdAt: DateTime.utc(2026, 7, 15),
      requiresAcknowledgement: false,
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      foregroundResult: HealthForegroundSyncResult(
        batches: <HealthSyncBatch>[foregroundBatch],
      ),
    );
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
    ]);
    addTearDown(container.dispose);
    await container.read(healthSyncControllerProvider.future);
    await container
        .read(healthSyncControllerProvider.notifier)
        .connectAndSync(stage: HealthPermissionStage.workout);

    final List<String> processed = <String>[];
    await container
        .read(healthSyncControllerProvider.notifier)
        .drainPendingBatches(
      processor: (HealthSyncBatch batch) async {
        processed.add(batch.batchId);
      },
    );

    expect(processed, <String>['foreground-1']);
    expect(gateway.acknowledged, isEmpty);
    expect(
      container.read(healthSyncControllerProvider).requireValue.pendingBatches,
      isEmpty,
    );
  });

  test('前台结构化事务失败时不保存快照同步时间', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final HealthSyncBatch batch = _batch(
      batchId: 'foreground-failed',
      athleteId: 'athlete-a',
      requiresAcknowledgement: false,
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      foregroundResult: HealthForegroundSyncResult(
        batches: <HealthSyncBatch>[batch],
      ),
    );
    final _FakeStructuredGateway structured = _FakeStructuredGateway(
      applyError: StateError('结构化事务失败'),
    );
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(healthSyncControllerProvider.future);

    await container
        .read(healthSyncControllerProvider.notifier)
        .sync(stage: HealthPermissionStage.workout);

    final HealthSnapshotRepository repository =
        HealthSnapshotRepository(storage);
    expect(
      repository.getLastSync(
        athleteId: 'athlete-a',
        stage: HealthPermissionStage.workout,
      ),
      isNull,
    );
    expect(gateway.acknowledged, isEmpty);
    expect(structured.syncModes, isEmpty);
    expect(
      container.read(healthSyncControllerProvider).requireValue.statusMessage,
      contains('失败'),
    );
  });

  test('build 只读，显式启动后台处理且仅在结构化事务成功后确认', () async {
    final HealthSyncBatch batch = _batch(
      batchId: 'background-success',
      athleteId: 'athlete-a',
      requiresAcknowledgement: true,
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      backgroundBatches: <HealthSyncBatch>[batch],
    );
    final _FakeStructuredGateway structured = _FakeStructuredGateway();
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
    ]);
    addTearDown(container.dispose);

    await container.read(healthSyncControllerProvider.future);

    expect(structured.appliedBatches, isEmpty);
    expect(gateway.acknowledged, isEmpty);
    expect(gateway.drainCalls, 0);
    await container
        .read(healthSyncControllerProvider.notifier)
        .initializeBackgroundDrain();

    expect(structured.appliedBatches, <HealthSyncBatch>[batch]);
    expect(structured.syncModes, <String>['background']);
    expect(gateway.acknowledged, <String>['background-success']);
    expect(gateway.drainCalls, 2);
    expect(container.read(healthDailyActivityRefreshSignalProvider), 1);
  });

  test('确认一页后会在同次启动继续排空后续 anchored 分页', () async {
    final HealthSyncBatch first = _batch(
      batchId: 'background-page-1',
      athleteId: 'athlete-a',
      requiresAcknowledgement: true,
    );
    final HealthSyncBatch second = _batch(
      batchId: 'background-page-2',
      athleteId: 'athlete-a',
      requiresAcknowledgement: true,
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      backgroundPages: <List<HealthSyncBatch>>[
        <HealthSyncBatch>[first],
        <HealthSyncBatch>[second],
        const <HealthSyncBatch>[],
      ],
    );
    final _FakeStructuredGateway structured = _FakeStructuredGateway();
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
    ]);
    addTearDown(container.dispose);

    await container.read(healthSyncControllerProvider.future);

    expect(structured.appliedBatches, isEmpty);
    expect(gateway.acknowledged, isEmpty);
    expect(gateway.drainCalls, 0);
    await container
        .read(healthSyncControllerProvider.notifier)
        .initializeBackgroundDrain();

    expect(structured.appliedBatches, <HealthSyncBatch>[first, second]);
    expect(
      gateway.acknowledged,
      <String>['background-page-1', 'background-page-2'],
    );
    expect(gateway.drainCalls, 3);
  });

  test('同页路线早于训练到达时先提交训练事实再处理路线', () async {
    final HealthSyncBatch route = _batch(
      batchId: 'background-route',
      athleteId: 'athlete-a',
      requiresAcknowledgement: true,
      objectType: 'HKSeriesTypeWorkoutRoute',
      kind: 'workoutRoute',
      createdAt: DateTime.utc(2026, 7, 15),
    );
    final HealthSyncBatch workout = _batch(
      batchId: 'background-workout',
      athleteId: 'athlete-a',
      requiresAcknowledgement: true,
      createdAt: DateTime.utc(2026, 7, 15, 0, 1),
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      backgroundPages: <List<HealthSyncBatch>>[
        <HealthSyncBatch>[route, workout],
        const <HealthSyncBatch>[],
      ],
    );
    final _FakeStructuredGateway structured = _FakeStructuredGateway();
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
    ]);
    addTearDown(container.dispose);

    await container.read(healthSyncControllerProvider.future);

    expect(structured.appliedBatches, isEmpty);
    expect(gateway.acknowledged, isEmpty);
    expect(gateway.drainCalls, 0);
    await container
        .read(healthSyncControllerProvider.notifier)
        .initializeBackgroundDrain();

    expect(structured.appliedBatches, <HealthSyncBatch>[workout, route]);
    expect(
      gateway.acknowledged,
      <String>['background-workout', 'background-route'],
    );
  });

  test('成长指标失败不阻塞原始健康事实落库和确认', () async {
    final HealthSyncBatch batch = _batch(
      batchId: 'background-details-failed',
      athleteId: 'athlete-a',
      requiresAcknowledgement: true,
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      backgroundBatches: <HealthSyncBatch>[batch],
    );
    final _FakeStructuredGateway structured = _FakeStructuredGateway();
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
      healthSyncMetricsPipelineProvider.overrideWithValue(
        _FailingMetricsPipeline(
          database: structured,
          healthDataGateway: gateway,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    await container.read(healthSyncControllerProvider.future);

    expect(structured.appliedBatches, isEmpty);
    expect(gateway.acknowledged, isEmpty);
    await container
        .read(healthSyncControllerProvider.notifier)
        .initializeBackgroundDrain();
    expect(structured.appliedBatches, <HealthSyncBatch>[batch]);
    expect(gateway.acknowledged, <String>['background-details-failed']);
  });

  test('后台删除后成长重算失败仍撤销旧摘要并确认原始批次', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final HealthSnapshotRepository repository =
        HealthSnapshotRepository(storage);
    repository.save(
      athleteId: 'athlete-a',
      stage: HealthPermissionStage.analysis,
      snapshots: <HealthSnapshot>[
        HealthSnapshot(
          id: 'stale-snapshot',
          date: DateTime(2026, 6, 1),
          sleepHours: null,
          restingHeartRate: 58,
          hrvMs: null,
          weightKg: null,
          bodyFatPercentage: null,
          syncedAt: DateTime.utc(2026, 6, 1),
          sourceIds: const <String>['deleted-observation'],
          sourceLineageVersion: 2,
        ),
      ],
      syncedAt: DateTime.utc(2026, 6, 1),
    );
    final HealthSyncBatch batch = HealthSyncBatch(
      batchId: 'background-observation-delete',
      athleteId: 'athlete-a',
      objectType: 'HKQuantityTypeIdentifierRestingHeartRate',
      queryVersion: 1,
      upserts: const <Map<String, Object?>>[],
      deletedExternalIds: const <String>['deleted-observation'],
      nextAnchor: 'delete-anchor',
      createdAt: DateTime.utc(2026, 7, 15),
      requiresAcknowledgement: true,
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      backgroundBatches: <HealthSyncBatch>[batch],
    );
    final _FakeStructuredGateway structured = _FakeStructuredGateway();
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
      healthSyncMetricsPipelineProvider.overrideWithValue(
        _FailingMetricsPipeline(
          database: structured,
          healthDataGateway: gateway,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    final HealthSyncState initial =
        await container.read(healthSyncControllerProvider.future);

    expect(initial.snapshots, hasLength(1));
    expect(structured.appliedBatches, isEmpty);
    await container
        .read(healthSyncControllerProvider.notifier)
        .initializeBackgroundDrain();
    expect(container.read(healthSyncControllerProvider).requireValue.snapshots,
        isEmpty);
    expect(repository.listSnapshots(athleteId: 'athlete-a'), isEmpty);
    expect(structured.appliedBatches, <HealthSyncBatch>[batch]);
    expect(gateway.acknowledged, <String>['background-observation-delete']);
  });

  test('显式后台事务失败时保留批次和 Swift 锚点并暴露中文错误', () async {
    final HealthSyncBatch batch = _batch(
      batchId: 'background-failed',
      athleteId: 'athlete-a',
      requiresAcknowledgement: true,
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      backgroundBatches: <HealthSyncBatch>[batch],
    );
    final _FakeStructuredGateway structured = _FakeStructuredGateway(
      applyError: StateError('SQLite 写入失败'),
    );
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
    ]);
    addTearDown(container.dispose);

    final HealthSyncState initial =
        await container.read(healthSyncControllerProvider.future);

    expect(initial.statusMessage, isNot(contains('后台健康数据写入失败')));
    expect(gateway.drainCalls, 0);
    await expectLater(
      container
          .read(healthSyncControllerProvider.notifier)
          .initializeBackgroundDrain(),
      throwsStateError,
    );
    final HealthSyncState state =
        container.read(healthSyncControllerProvider).requireValue;
    expect(gateway.acknowledged, isEmpty);
    expect(gateway.backgroundBatches, <HealthSyncBatch>[batch]);
    expect(state.statusMessage, contains('后台健康数据写入失败'));
  });

  test('后台队列中的其他运动员批次不落库也不确认', () async {
    final HealthSyncBatch batch = _batch(
      batchId: 'other-athlete',
      athleteId: 'athlete-b',
      requiresAcknowledgement: true,
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      backgroundBatches: <HealthSyncBatch>[batch],
    );
    final _FakeStructuredGateway structured = _FakeStructuredGateway();
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
    ]);
    addTearDown(container.dispose);

    await container.read(healthSyncControllerProvider.future);

    expect(gateway.drainCalls, 0);
    await container
        .read(healthSyncControllerProvider.notifier)
        .initializeBackgroundDrain();

    expect(structured.appliedBatches, isEmpty);
    expect(gateway.acknowledged, isEmpty);
    expect(gateway.backgroundBatches, <HealthSyncBatch>[batch]);
  });

  test('持久化停用时 build 只读历史且不恢复、排空或请求授权', () async {
    final PluginRuntime runtime = await _runtime();
    await runtime.disable('feature.activity_import');
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    HealthSnapshotRepository(storage).save(
      athleteId: 'athlete-a',
      stage: HealthPermissionStage.analysis,
      snapshots: <HealthSnapshot>[
        HealthSnapshot(
          id: 'history',
          date: DateTime(2026, 7, 14),
          sleepHours: 7,
          restingHeartRate: 58,
          hrvMs: 55,
          weightKg: null,
          bodyFatPercentage: null,
          syncedAt: DateTime.utc(2026, 7, 14),
        ),
      ],
      syncedAt: DateTime.utc(2026, 7, 14),
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      backgroundBatches: <HealthSyncBatch>[
        _batch(
          batchId: 'disabled-pending',
          athleteId: 'athlete-a',
          requiresAcknowledgement: true,
        ),
      ],
    );
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        _FakeStructuredGateway(),
      ),
    ]);
    addTearDown(container.dispose);

    final HealthSyncState disabled =
        await container.read(healthSyncControllerProvider.future);
    expect(disabled.snapshots.single.id, 'history');
    expect(disabled.statusMessage, contains('已停用'));
    expect(gateway.resumeCalls, 0);
    expect(gateway.drainCalls, 0);
    expect(gateway.authorizationRequests, 0);
    await expectLater(
      container.read(healthSyncControllerProvider.notifier).sync(),
      throwsStateError,
    );
    await container
        .read(healthSyncControllerProvider.notifier)
        .clearAthleteData();
    expect(gateway.clearedAthletes, <String>['athlete-a']);
    expect(
      HealthSnapshotRepository(storage).listSnapshots(athleteId: 'athlete-a'),
      isEmpty,
    );

    await runtime.enable('feature.activity_import');
    await container.pump();
    await container.read(healthSyncControllerProvider.future);
    expect(gateway.resumeCalls, 1);
    expect(gateway.drainCalls, 0);
    expect(gateway.authorizationRequests, 0);
  });

  test('前台返回前停用活动导入时迟到结果不落库也不确认', () async {
    final PluginRuntime runtime = await _runtime();
    final Completer<HealthForegroundSyncResult> incoming =
        Completer<HealthForegroundSyncResult>();
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      foregroundCompleter: incoming,
    );
    final _FakeStructuredGateway structured = _FakeStructuredGateway();
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(healthSyncControllerProvider.future);

    final Future<void> pending = container
        .read(healthSyncControllerProvider.notifier)
        .sync(stage: HealthPermissionStage.workout);
    await Future<void>.delayed(Duration.zero);
    await runtime.disable('feature.activity_import');
    expect(gateway.pauseCalls, 1);
    incoming.complete(HealthForegroundSyncResult(
      batches: <HealthSyncBatch>[
        _batch(
          batchId: 'late-foreground',
          athleteId: 'athlete-a',
          requiresAcknowledgement: true,
        ),
      ],
    ));

    await expectLater(pending, throwsStateError);
    expect(structured.appliedBatches, isEmpty);
    expect(gateway.acknowledged, isEmpty);
  });

  test('成长功能停用不阻塞原始健康批次落库和确认', () async {
    final PluginRuntime runtime = await _runtime();
    await runtime.disable('feature.growth');
    final HealthSyncBatch batch = _batch(
      batchId: 'growth-disabled',
      athleteId: 'athlete-a',
      requiresAcknowledgement: true,
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      backgroundBatches: <HealthSyncBatch>[batch],
    );
    final _FakeStructuredGateway structured = _FakeStructuredGateway();
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(healthSyncControllerProvider.future);

    await container
        .read(healthSyncControllerProvider.notifier)
        .initializeBackgroundDrain();

    expect(structured.appliedBatches, <HealthSyncBatch>[batch]);
    expect(gateway.acknowledged, <String>['growth-disabled']);
  });

  for (final bool foreground in [true, false]) {
    for (final String transition in ['停用', '停用重开', '切换账户', '关闭成长', '保持启用']) {
      test('${foreground ? '前台' : '后台'} ACK 等待时$transition保留提交确认事实并限制旧派生', () async {
        final runtime = await _runtime();
        final batch = _batch(
          batchId: 'ack-lifecycle',
          athleteId: 'athlete-a',
          requiresAcknowledgement: true,
        );
        final gateway = _GatedAckGateway(
          foregroundResult: HealthForegroundSyncResult(batches: [batch]),
          backgroundBatches: [batch],
        );
        final structured = _FakeStructuredGateway();
        bool sourceLocksVerified = false;
        final pipeline = _RecordingMetricsPipeline(
          database: structured,
          healthDataGateway: gateway,
          onProcess: () async {
            await expectLater(runtime.disable('feature.activity_import'), throwsStateError);
            await expectLater(runtime.disable('feature.growth'), throwsStateError);
            await expectLater(runtime.changeAccountScope(), throwsStateError);
            sourceLocksVerified = true;
          },
        );
        runtime.service('feature.growth')!.bind('metricsPipeline', pipeline);
        final container = ProviderContainer(overrides: [
          pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
          localStorageServiceProvider.overrideWithValue(InMemoryLocalStorageService()),
          healthDataGatewayProvider.overrideWithValue(gateway),
          healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
          healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(structured),
          healthSyncMetricsPipelineProvider.overrideWithValue(pipeline),
        ]);
        addTearDown(container.dispose);
        await container.read(healthSyncControllerProvider.future);
        final controller = container.read(healthSyncControllerProvider.notifier);
        final pending = foreground
            ? controller.sync(stage: HealthPermissionStage.workout)
            : controller.initializeBackgroundDrain();
        final outcome = pending.then<Object?>((_) => null,
            onError: (Object error) => error);
        await gateway.entered.future;
        expect(structured.appliedBatches, [batch]);
        expect(gateway.acknowledged, isEmpty);
        switch (transition) {
          case '停用':
            await runtime.disable('feature.activity_import');
          case '停用重开':
            await runtime.disable('feature.activity_import');
            await runtime.enable('feature.activity_import');
          case '切换账户':
            await runtime.changeAccountScope();
          case '关闭成长':
            await runtime.disable('feature.growth');
        }
        gateway.released.complete();
        final error = await outcome;
        expect(pipeline.calls, transition == '保持启用' ? 1 : 0);
        expect(sourceLocksVerified, transition == '保持启用',
            reason: '成长异步派生提交必须同时锁定原导入来源和账户域。');
        expect(structured.appliedBatches, [batch], reason: '已提交事实不能回滚或重复写入。');
        expect(gateway.acknowledged, [batch.batchId], reason: '已返回的原生确认不能被抹除。');
        if (transition == '关闭成长' || transition == '保持启用') {
          expect(error, isNull);
        } else {
          expect(error, isA<FeatureOperationInvalidation>());
        }
      });
    }
  }

  test('清理严格按 Swift、结构化事务、旧文档、flush 顺序执行', () async {
    final List<String> events = <String>[];
    final _RecordingStorage storage = _RecordingStorage(events);
    final _FakeHealthGateway gateway = _FakeHealthGateway(events: events);
    final _FakeStructuredGateway structured =
        _FakeStructuredGateway(events: events);
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(healthSyncControllerProvider.future);

    await container
        .read(healthSyncControllerProvider.notifier)
        .clearAthleteData();

    expect(events, <String>['swift', 'structured', 'legacy', 'flush']);
    expect(structured.clearedAthletes, <String>['athlete-a']);
    expect(
      container.read(healthSyncControllerProvider).requireValue.statusMessage,
      contains('已清除'),
    );
  });

  test('结构化清理失败时停止后续清理、显示失败并向调用方抛出', () async {
    final List<String> events = <String>[];
    final _RecordingStorage storage = _RecordingStorage(events);
    final _FakeHealthGateway gateway = _FakeHealthGateway(events: events);
    final _FakeStructuredGateway structured = _FakeStructuredGateway(
      events: events,
      clearError: StateError('结构化清理失败'),
    );
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(healthSyncControllerProvider.future);

    await expectLater(
      container.read(healthSyncControllerProvider.notifier).clearAthleteData(),
      throwsStateError,
    );

    expect(events, <String>['swift', 'structured']);
    expect(
      container.read(healthSyncControllerProvider).requireValue.statusMessage,
      contains('失败'),
    );
  });

  test('Swift 队列清理失败时不触碰结构化数据和旧文档', () async {
    final List<String> events = <String>[];
    final _RecordingStorage storage = _RecordingStorage(events);
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      events: events,
      clearError: StateError('Swift 队列清理失败'),
    );
    final _FakeStructuredGateway structured =
        _FakeStructuredGateway(events: events);
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(healthSyncControllerProvider.future);

    await expectLater(
      container.read(healthSyncControllerProvider.notifier).clearAthleteData(),
      throwsStateError,
    );

    expect(events, <String>['swift']);
    expect(structured.clearedAthletes, isEmpty);
  });

  test('flush 失败时不能显示清理成功且异常返回调用方', () async {
    final List<String> events = <String>[];
    final _RecordingStorage storage = _RecordingStorage(
      events,
      flushError: StateError('旧文档持久化失败'),
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(events: events);
    final _FakeStructuredGateway structured =
        _FakeStructuredGateway(events: events);
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
        structured,
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(healthSyncControllerProvider.future);

    await expectLater(
      container.read(healthSyncControllerProvider.notifier).clearAthleteData(),
      throwsStateError,
    );

    expect(events, <String>['swift', 'structured', 'legacy', 'flush']);
    expect(
      container.read(healthSyncControllerProvider).requireValue.statusMessage,
      contains('失败'),
    );
  });

  test('未注入结构化网关时保持 Web 和旧测试兼容且不排空原生队列', () async {
    final HealthSyncBatch batch = _batch(
      batchId: 'preserved-without-structured-gateway',
      athleteId: 'athlete-a',
      requiresAcknowledgement: true,
    );
    final _FakeHealthGateway gateway = _FakeHealthGateway(
      backgroundBatches: <HealthSyncBatch>[batch],
    );
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      healthDataGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
    ]);
    addTearDown(container.dispose);

    await container.read(healthSyncControllerProvider.future);

    expect(container.read(healthSyncStructuredDatabaseGatewayProvider), isNull);
    expect(gateway.drainCalls, 0);
    expect(gateway.acknowledged, isEmpty);
  });
}

Future<PluginRuntime> _runtime() async {
  final PluginRuntime runtime =
      PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
  await runtime.initialize();
  return runtime;
}

HealthSyncBatch _batch({
  required String batchId,
  required String athleteId,
  required bool requiresAcknowledgement,
  String objectType = 'HKWorkoutTypeIdentifier',
  String kind = 'workout',
  DateTime? createdAt,
}) =>
    HealthSyncBatch(
      batchId: batchId,
      athleteId: athleteId,
      objectType: objectType,
      queryVersion: 1,
      upserts: <Map<String, Object?>>[
        <String, Object?>{
          'uuid': 'workout-$batchId',
          'kind': kind,
        },
      ],
      deletedExternalIds: const <String>[],
      nextAnchor: 'anchor-$batchId',
      createdAt: createdAt ?? DateTime.utc(2026, 7, 15),
      requiresAcknowledgement: requiresAcknowledgement,
    );

class _GatedAckGateway extends _FakeHealthGateway {
  _GatedAckGateway({required super.foregroundResult, required super.backgroundBatches});
  final entered = Completer<void>();
  final released = Completer<void>();

  @override
  Future<void> acknowledgeBatch(String batchId) async {
    entered.complete();
    await released.future;
    await super.acknowledgeBatch(batchId);
  }
}

class _RecordingMetricsPipeline extends _FailingMetricsPipeline {
  _RecordingMetricsPipeline({required super.database, required super.healthDataGateway, this.onProcess});
  final Future<void> Function()? onProcess;
  int calls = 0;

  @override
  Future<HealthBatchMetricsResult> processCommittedHealthBatch(
    HealthSyncBatch batch,
    HealthSyncApplyResult applyResult,
  ) async {
    calls += 1;
    await onProcess?.call();
    return super.processCommittedHealthBatch(batch, applyResult);
  }
}
