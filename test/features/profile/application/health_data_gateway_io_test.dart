import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

import 'package:trainflow_ai/features/profile/application/health_data_gateway_contract.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway_io.dart';

void main() {
  test('分析阶段和身体阶段只读取各自需要的插件类型', () {
    expect(
      healthPluginTypesForStage(HealthPermissionStage.analysis),
      <HealthDataType>[
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.HEART_RATE_VARIABILITY_SDNN,
      ],
    );
    expect(
      healthPluginTypesForStage(HealthPermissionStage.body),
      <HealthDataType>[
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
      ],
    );
    expect(
      healthPluginTypesForStage(HealthPermissionStage.workout),
      isEmpty,
    );
  });

  test('跨午夜睡眠归到醒来日且重叠来源不重复累计', () {
    final DateTime start = DateTime(2026, 7, 14, 23);
    final DateTime end = DateTime(2026, 7, 15, 7);
    final List<HealthDataPoint> points = <HealthDataPoint>[
      _point(
        uuid: 'sleep-watch',
        sourceId: 'watch',
        type: HealthDataType.SLEEP_ASLEEP,
        start: start,
        end: end,
        value: 480,
      ),
      _point(
        uuid: 'sleep-phone',
        sourceId: 'phone',
        type: HealthDataType.SLEEP_ASLEEP,
        start: start.add(const Duration(hours: 1)),
        end: end,
        value: 420,
      ),
    ];

    final snapshots = aggregateHealthSnapshots(
      points,
      syncedAt: DateTime.utc(2026, 7, 15, 12),
    );

    expect(snapshots, hasLength(1));
    expect(snapshots.single.id, 'apple-health-2026-07-15');
    expect(snapshots.single.date, DateTime(2026, 7, 15));
    expect(snapshots.single.sleepHours, 8);
    expect(
      snapshots.single.sourceIds,
      <String>['sleep-phone', 'sleep-watch'],
    );
  });

  test('插件侧单项读取失败时仍保留原生训练事实批次', () async {
    final HealthSyncBatch nativeBatch = HealthSyncBatch(
      batchId: 'foreground-1',
      athleteId: 'athlete-a',
      objectType: 'foreground.analysis',
      queryVersion: 1,
      upserts: const <Map<String, Object?>>[
        <String, Object?>{'uuid': 'workout-1', 'kind': 'workout'},
      ],
      deletedExternalIds: const <String>[],
      nextAnchor: null,
      createdAt: DateTime.utc(2026, 7, 15),
      requiresAcknowledgement: false,
    );
    final AppleHealthDataGateway gateway = AppleHealthDataGateway(
      plugin: _ThrowingHealthPluginClient(),
      nativeBridge: _FakeNativeHealthKitBridge(nativeBatch),
    );

    final HealthForegroundSyncResult result = await gateway.fetchForeground(
      stage: HealthPermissionStage.analysis,
      athleteId: 'athlete-a',
      start: DateTime.utc(2026, 7, 14),
      end: DateTime.utc(2026, 7, 15),
    );

    expect(result.snapshots, isEmpty);
    expect(result.batches, <HealthSyncBatch>[nativeBatch]);
  });

  test('每日活动摘要透传原生桥并按本地日期升序排列', () async {
    final List<HealthDailyActivitySummaryPayload> nativeSummaries =
        <HealthDailyActivitySummaryPayload>[
      _dailySummary(localDate: '2026-07-16', steps: 9000),
      _dailySummary(localDate: '2026-07-14', steps: 7000),
      _dailySummary(localDate: '2026-07-15', steps: 8000),
    ];
    final _FakeNativeHealthKitBridge nativeBridge =
        _FakeNativeHealthKitBridge(null, dailySummaries: nativeSummaries);
    final AppleHealthDataGateway gateway = AppleHealthDataGateway(
      plugin: _ThrowingHealthPluginClient(),
      nativeBridge: nativeBridge,
    );
    final DateTime start = DateTime.utc(2026, 7, 14);
    final DateTime end = DateTime.utc(2026, 7, 17);

    final List<HealthDailyActivitySummaryPayload> result =
        await gateway.fetchDailyActivitySummaries(start: start, end: end);

    expect(
      result.map((HealthDailyActivitySummaryPayload item) => item.localDate),
      <String>['2026-07-14', '2026-07-15', '2026-07-16'],
    );
    expect(nativeBridge.dailySummaryStart, start);
    expect(nativeBridge.dailySummaryEnd, end);
  });
}

class _ThrowingHealthPluginClient implements HealthPluginClient {
  @override
  Future<void> configure() async {}

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
  }) =>
      Future<List<HealthDataPoint>>.error(StateError('单项读取失败'));
}

class _FakeNativeHealthKitBridge implements NativeHealthKitBridge {
  _FakeNativeHealthKitBridge(
    this.foregroundBatch, {
    this.dailySummaries = const <HealthDailyActivitySummaryPayload>[],
  });

  final HealthSyncBatch? foregroundBatch;
  final List<HealthDailyActivitySummaryPayload> dailySummaries;
  DateTime? dailySummaryStart;
  DateTime? dailySummaryEnd;

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
  Future<HealthSyncBatch?> fetchForeground({
    required HealthPermissionStage stage,
    required String athleteId,
    required DateTime start,
    required DateTime end,
  }) async =>
      foregroundBatch;

  @override
  Future<List<HealthDailyActivitySummaryPayload>> fetchDailyActivitySummaries({
    required DateTime start,
    required DateTime end,
  }) async {
    dailySummaryStart = start;
    dailySummaryEnd = end;
    return dailySummaries;
  }

  @override
  Future<Map<String, Object?>?> fetchWorkoutDetails({
    required String workoutUuid,
  }) async =>
      null;

  @override
  Future<void> enableBackgroundSync({
    required HealthPermissionStage stage,
    required String athleteId,
  }) async {}

  @override
  Future<void> pauseBackgroundSync({required String athleteId}) async {}

  @override
  Future<void> resumeBackgroundSync({required String athleteId}) async {}

  @override
  Future<List<HealthSyncBatch>> drainPendingBatches({int limit = 20}) async =>
      const <HealthSyncBatch>[];

  @override
  Future<void> acknowledgeBatch(String batchId) async {}

  @override
  Future<void> clearPendingBatches({required String athleteId}) async {}

  @override
  Future<void> protectLocalFiles(List<String> paths) async {}
}

HealthDailyActivitySummaryPayload _dailySummary({
  required String localDate,
  required int steps,
}) =>
    HealthDailyActivitySummaryPayload.fromMap(<String, Object?>{
      'localDate': localDate,
      'timeZoneName': 'Asia/Shanghai',
      'timeZoneOffsetMinutes': 480,
      'steps': steps,
      'activeEnergyKcal': 300.0,
      'activeEnergyGoalKcal': 500.0,
      'exerciseMinutes': 30,
      'exerciseGoalMinutes': 30,
      'standHours': 10,
      'standGoalHours': 12,
      'availableFields': <String>[
        'steps',
        'activeEnergyKcal',
        'activeEnergyGoalKcal',
        'exerciseMinutes',
        'exerciseGoalMinutes',
        'standHours',
        'standGoalHours',
      ],
      'syncedAt': '2026-07-16T00:00:00.000Z',
    });

HealthDataPoint _point({
  required String uuid,
  required String sourceId,
  required HealthDataType type,
  required DateTime start,
  required DateTime end,
  required double value,
}) =>
    HealthDataPoint(
      uuid: uuid,
      value: NumericHealthValue(numericValue: value),
      type: type,
      unit: type == HealthDataType.SLEEP_ASLEEP
          ? HealthDataUnit.MINUTE
          : HealthDataUnit.UNKNOWN_UNIT,
      dateFrom: start,
      dateTo: end,
      sourcePlatform: HealthPlatformType.appleHealth,
      sourceDeviceId: 'device',
      sourceId: sourceId,
      sourceName: sourceId,
    );
