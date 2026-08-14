import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/trainmate_structured_database_gateway.dart';
import 'package:trainflow_ai/data/models/health_snapshot.dart';
import 'package:trainflow_ai/data/repositories/health_snapshot_repository.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway_contract.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/training_metrics_pipeline.dart';

class _FakeHealthGateway extends HealthDataGateway {
  _FakeHealthGateway({
    this.foregroundResult = const HealthForegroundSyncResult(),
    this.backgroundBatches = const <HealthSyncBatch>[],
    this.backgroundPages,
    this.events,
    this.clearError,
  });

  final HealthForegroundSyncResult foregroundResult;
  final List<HealthSyncBatch> backgroundBatches;
  final List<List<HealthSyncBatch>>? backgroundPages;
  final List<String>? events;
  final Object? clearError;
  final List<String> acknowledged = <String>[];
  final List<String> clearedAthletes = <String>[];
  int drainCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<HealthAuthorizationResult> requestAuthorization({
    required HealthPermissionStage stage,
    required String athleteId,
  }) async =>
      HealthAuthorizationResult(
        stage: stage,
        state: HealthAuthorizationState.undetermined,
        requestCompleted: true,
      );

  @override
  Future<HealthForegroundSyncResult> fetchForeground({
    required HealthPermissionStage stage,
    required String athleteId,
    required DateTime start,
    required DateTime end,
  }) async =>
      foregroundResult;

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

  test('build 自动处理后台批次且仅在结构化事务成功后确认', () async {
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

    expect(structured.appliedBatches, <HealthSyncBatch>[workout, route]);
    expect(
      gateway.acknowledged,
      <String>['background-workout', 'background-route'],
    );
  });

  test('指标处理中的瞬时明细读取异常会保留 Swift 批次且不确认锚点', () async {
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

    final HealthSyncState state =
        await container.read(healthSyncControllerProvider.future);

    expect(structured.appliedBatches, <HealthSyncBatch>[batch]);
    expect(gateway.acknowledged, isEmpty);
    expect(gateway.backgroundBatches, <HealthSyncBatch>[batch]);
    expect(state.statusMessage, contains('后台健康数据写入失败'));
  });

  test('后台删除后即使指标重算失败，也先撤销旧健康摘要且保留批次重投', () async {
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

    final HealthSyncState state =
        await container.read(healthSyncControllerProvider.future);

    expect(state.snapshots, isEmpty);
    expect(repository.listSnapshots(athleteId: 'athlete-a'), isEmpty);
    expect(gateway.acknowledged, isEmpty);
    expect(state.statusMessage, contains('后台健康数据写入失败'));
  });

  test('build 后台事务失败时保留批次和 Swift 锚点并暴露中文错误', () async {
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

    final HealthSyncState state =
        await container.read(healthSyncControllerProvider.future);

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

    expect(structured.appliedBatches, isEmpty);
    expect(gateway.acknowledged, isEmpty);
    expect(gateway.backgroundBatches, <HealthSyncBatch>[batch]);
  });

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
