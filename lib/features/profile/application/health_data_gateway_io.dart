import 'package:health/health.dart';

import '../../../data/models/health_snapshot.dart';
import 'health_data_gateway_contract.dart';
import 'native_healthkit_bridge.dart';

HealthDataGateway createHealthDataGateway() => AppleHealthDataGateway();

abstract interface class HealthPluginClient {
  Future<void> configure();

  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
  });
}

class PackageHealthPluginClient implements HealthPluginClient {
  final Health _health;

  PackageHealthPluginClient([Health? health]) : _health = health ?? Health();

  @override
  Future<void> configure() => _health.configure();

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
  }) =>
      _health.getHealthDataFromTypes(
        types: types,
        startTime: startTime,
        endTime: endTime,
      );
}

class AppleHealthDataGateway extends HealthDataGateway {
  final HealthPluginClient _plugin;
  final NativeHealthKitBridge _nativeBridge;

  AppleHealthDataGateway({
    HealthPluginClient? plugin,
    NativeHealthKitBridge? nativeBridge,
  })  : _plugin = plugin ?? PackageHealthPluginClient(),
        _nativeBridge = nativeBridge ?? createNativeHealthKitBridge();

  @override
  bool get isSupported => _nativeBridge.isSupported;

  @override
  Future<HealthAuthorizationResult> requestAuthorization({
    required HealthPermissionStage stage,
    required String athleteId,
  }) {
    if (!isSupported) {
      return Future<HealthAuthorizationResult>.value(
        HealthAuthorizationResult(
          stage: stage,
          state: HealthAuthorizationState.unavailable,
          requestCompleted: false,
          message: '当前平台不支持 Apple 健康。',
        ),
      );
    }
    return _nativeBridge.requestAuthorization(
      stage: stage,
      athleteId: athleteId,
    );
  }

  @override
  Future<HealthForegroundSyncResult> fetchForeground({
    required HealthPermissionStage stage,
    required String athleteId,
    required DateTime start,
    required DateTime end,
  }) async {
    if (!isSupported) return const HealthForegroundSyncResult();
    final List<HealthDataType> pluginTypes = healthPluginTypesForStage(stage);
    List<HealthSnapshot> snapshots = const <HealthSnapshot>[];
    Object? firstFailure;
    StackTrace? firstFailureStack;
    if (pluginTypes.isNotEmpty) {
      try {
        await _plugin.configure();
        final List<HealthDataPoint> points =
            await _plugin.getHealthDataFromTypes(
          types: pluginTypes,
          startTime: start,
          endTime: end,
        );
        snapshots = aggregateHealthSnapshots(
          points,
          syncedAt: DateTime.now(),
        );
      } catch (error, stackTrace) {
        firstFailure = error;
        firstFailureStack = stackTrace;
      }
    }
    HealthSyncBatch? batch;
    try {
      batch = await _nativeBridge.fetchForeground(
        stage: stage,
        athleteId: athleteId,
        start: start,
        end: end,
      );
    } catch (error, stackTrace) {
      firstFailure ??= error;
      firstFailureStack ??= stackTrace;
    }
    if (snapshots.isEmpty && batch == null && firstFailure != null) {
      Error.throwWithStackTrace(firstFailure, firstFailureStack!);
    }
    return HealthForegroundSyncResult(
      snapshots: snapshots,
      batches:
          batch == null ? const <HealthSyncBatch>[] : <HealthSyncBatch>[batch],
    );
  }

  @override
  Future<List<HealthDailyActivitySummaryPayload>> fetchDailyActivitySummaries({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!isSupported) return const <HealthDailyActivitySummaryPayload>[];
    final List<HealthDailyActivitySummaryPayload> summaries =
        (await _nativeBridge.fetchDailyActivitySummaries(
      start: start,
      end: end,
    ))
            .toList(growable: false)
          ..sort(
            (
              HealthDailyActivitySummaryPayload left,
              HealthDailyActivitySummaryPayload right,
            ) =>
                left.localDate.compareTo(right.localDate),
          );
    return List<HealthDailyActivitySummaryPayload>.unmodifiable(summaries);
  }

  @override
  Future<Map<String, Object?>?> fetchWorkoutDetails(String workoutUuid) =>
      _nativeBridge.fetchWorkoutDetails(workoutUuid: workoutUuid);

  @override
  Future<void> enableBackgroundSync({
    required HealthPermissionStage stage,
    required String athleteId,
  }) =>
      _nativeBridge.enableBackgroundSync(
        stage: stage,
        athleteId: athleteId,
      );

  @override
  Future<void> pauseBackgroundSync({required String athleteId}) =>
      _nativeBridge.pauseBackgroundSync(athleteId: athleteId);

  @override
  Future<void> resumeBackgroundSync({required String athleteId}) =>
      _nativeBridge.resumeBackgroundSync(athleteId: athleteId);

  @override
  Future<List<HealthSyncBatch>> drainPendingBatches({int limit = 20}) =>
      _nativeBridge.drainPendingBatches(limit: limit);

  @override
  Future<void> acknowledgeBatch(String batchId) =>
      _nativeBridge.acknowledgeBatch(batchId);

  @override
  Future<void> clearPendingBatches({required String athleteId}) =>
      _nativeBridge.clearPendingBatches(athleteId: athleteId);

  @override
  Future<void> protectLocalFiles(List<String> paths) =>
      _nativeBridge.protectLocalFiles(paths);
}

List<HealthDataType> healthPluginTypesForStage(HealthPermissionStage stage) {
  switch (stage) {
    case HealthPermissionStage.workout:
      return const <HealthDataType>[];
    case HealthPermissionStage.analysis:
      return const <HealthDataType>[
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.HEART_RATE_VARIABILITY_SDNN,
      ];
    case HealthPermissionStage.body:
      return const <HealthDataType>[
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
      ];
  }
}

List<HealthSnapshot> aggregateHealthSnapshots(
  List<HealthDataPoint> points, {
  required DateTime syncedAt,
}) {
  final Set<String> seen = <String>{};
  final Map<String, List<HealthDataPoint>> grouped =
      <String, List<HealthDataPoint>>{};
  for (final HealthDataPoint point in points) {
    final String identity = point.uuid.isNotEmpty
        ? '${point.type.name}|${point.uuid}'
        : '${point.type.name}|${point.sourceId}|'
            '${point.dateFrom.toUtc().toIso8601String()}|'
            '${point.dateTo.toUtc().toIso8601String()}|${point.value}';
    if (!seen.add(identity)) continue;
    final DateTime day = point.type == HealthDataType.SLEEP_ASLEEP
        ? point.dateTo.toLocal()
        : point.dateFrom.toLocal();
    final String key = _dateKey(day);
    grouped.putIfAbsent(key, () => <HealthDataPoint>[]).add(point);
  }

  final List<HealthSnapshot> snapshots = grouped.entries.map((entry) {
    final List<HealthDataPoint> sorted = entry.value.toList()
      ..sort((HealthDataPoint left, HealthDataPoint right) =>
          left.dateFrom.compareTo(right.dateFrom));
    final List<(DateTime, DateTime)> sleepIntervals = <(DateTime, DateTime)>[];
    // 这个兼容摘要的删除传播使用 HealthKit 样本 UUID，不是来源
    // 应用 ID。HKDeletedObject 只能提供样本 UUID。
    final Set<String> sourceIds = <String>{};
    double? restingHeartRate;
    double? hrv;
    double? weight;
    double? bodyFat;
    for (final HealthDataPoint point in sorted) {
      if (point.uuid.isNotEmpty) sourceIds.add(point.uuid);
      final HealthValue value = point.value;
      if (value is! NumericHealthValue) continue;
      final double number = value.numericValue.toDouble();
      switch (point.type) {
        case HealthDataType.SLEEP_ASLEEP:
          if (point.dateTo.isAfter(point.dateFrom)) {
            sleepIntervals.add((point.dateFrom, point.dateTo));
          }
          break;
        case HealthDataType.RESTING_HEART_RATE:
          restingHeartRate = number;
          break;
        case HealthDataType.HEART_RATE_VARIABILITY_SDNN:
          hrv = number;
          break;
        case HealthDataType.WEIGHT:
          weight = number;
          break;
        case HealthDataType.BODY_FAT_PERCENTAGE:
          bodyFat = number <= 1 ? number * 100 : number;
          break;
        default:
          break;
      }
    }
    final DateTime date = DateTime.parse(entry.key);
    final double sleepMinutes = _unionMinutes(sleepIntervals);
    return HealthSnapshot(
      id: 'apple-health-${entry.key}',
      date: date,
      sleepHours: sleepMinutes > 0 ? sleepMinutes / 60 : null,
      restingHeartRate: restingHeartRate?.round(),
      hrvMs: hrv?.round(),
      weightKg: weight,
      bodyFatPercentage: bodyFat,
      syncedAt: syncedAt,
      sourceIds: sourceIds.toList()..sort(),
      sourceLineageVersion: 2,
    );
  }).toList()
    ..sort((HealthSnapshot left, HealthSnapshot right) =>
        right.date.compareTo(left.date));
  return snapshots;
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

double _unionMinutes(List<(DateTime, DateTime)> intervals) {
  if (intervals.isEmpty) return 0;
  intervals.sort(((DateTime, DateTime) left, (DateTime, DateTime) right) =>
      left.$1.compareTo(right.$1));
  DateTime start = intervals.first.$1;
  DateTime end = intervals.first.$2;
  Duration total = Duration.zero;
  for (final (DateTime nextStart, DateTime nextEnd) in intervals.skip(1)) {
    if (!nextStart.isAfter(end)) {
      if (nextEnd.isAfter(end)) end = nextEnd;
      continue;
    }
    total += end.difference(start);
    start = nextStart;
    end = nextEnd;
  }
  total += end.difference(start);
  return total.inMilliseconds / Duration.millisecondsPerMinute;
}
