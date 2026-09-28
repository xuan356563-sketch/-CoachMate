import 'dart:io';

import 'package:flutter/services.dart';

import 'health_data_gateway_contract.dart';

NativeHealthKitBridge createNativeHealthKitBridge() =>
    const MethodChannelNativeHealthKitBridge();

class MethodChannelNativeHealthKitBridge implements NativeHealthKitBridge {
  const MethodChannelNativeHealthKitBridge();

  static const MethodChannel _channel =
      MethodChannel('trainflow.ai/healthkit_sync');

  @override
  bool get isSupported => Platform.isIOS;

  @override
  Future<HealthAuthorizationResult> requestAuthorization({
    required HealthPermissionStage stage,
    required String athleteId,
  }) async {
    if (!isSupported) {
      return HealthAuthorizationResult(
        stage: stage,
        state: HealthAuthorizationState.unavailable,
        requestCompleted: false,
        message: '当前平台不支持 Apple 健康。',
      );
    }
    final Object? raw = await _channel.invokeMethod<Object?>(
      'requestAuthorization',
      <String, Object?>{'stage': stage.name, 'athleteId': athleteId},
    );
    final Map<String, Object?> map = _stringMap(raw);
    final bool completed = map['requestCompleted'] as bool? ?? false;
    return HealthAuthorizationResult(
      stage: stage,
      state: completed
          ? HealthAuthorizationState.undetermined
          : HealthAuthorizationState.failed,
      requestCompleted: completed,
      message: map['message'] as String?,
    );
  }

  @override
  Future<HealthSyncBatch?> fetchForeground({
    required HealthPermissionStage stage,
    required String athleteId,
    required DateTime start,
    required DateTime end,
  }) async {
    if (!isSupported) return null;
    final Object? raw = await _channel.invokeMethod<Object?>(
      'fetchForeground',
      <String, Object?>{
        'stage': stage.name,
        'athleteId': athleteId,
        'startTime': start.millisecondsSinceEpoch,
        'endTime': end.millisecondsSinceEpoch,
      },
    );
    if (raw is! Map) return null;
    return HealthSyncBatch.fromMap(_stringMap(raw));
  }

  @override
  Future<List<HealthDailyActivitySummaryPayload>> fetchDailyActivitySummaries({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!isSupported) return const <HealthDailyActivitySummaryPayload>[];
    if (!start.isBefore(end)) {
      throw ArgumentError('每日活动摘要时间范围无效。');
    }
    final List<Object?>? raw = await _channel.invokeListMethod<Object?>(
      'fetchDailyActivitySummaries',
      <String, Object?>{
        'startTime': start.millisecondsSinceEpoch,
        'endTime': end.millisecondsSinceEpoch,
      },
    );
    final List<HealthDailyActivitySummaryPayload> summaries =
        (raw ?? const <Object?>[])
            .whereType<Map>()
            .map(
              (Map item) => HealthDailyActivitySummaryPayload.fromMap(
                _stringMap(item),
              ),
            )
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
  Future<Map<String, Object?>?> fetchWorkoutDetails({
    required String workoutUuid,
  }) async {
    if (!isSupported) return null;
    final Object? raw = await _channel.invokeMethod<Object?>(
      'fetchWorkoutDetails',
      <String, Object?>{'workoutUuid': workoutUuid},
    );
    return raw is Map ? _stringMap(raw) : null;
  }

  @override
  Future<void> enableBackgroundSync({
    required HealthPermissionStage stage,
    required String athleteId,
  }) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>(
      'enableBackgroundSync',
      <String, Object?>{'stage': stage.name, 'athleteId': athleteId},
    );
  }

  @override
  Future<void> pauseBackgroundSync({required String athleteId}) {
    return _channel.invokeMethod<void>(
      'pauseBackgroundSync',
      <String, Object?>{'athleteId': athleteId},
    );
  }

  @override
  Future<void> resumeBackgroundSync({required String athleteId}) {
    return _channel.invokeMethod<void>(
      'resumeBackgroundSync',
      <String, Object?>{'athleteId': athleteId},
    );
  }

  @override
  Future<List<HealthSyncBatch>> drainPendingBatches({int limit = 20}) async {
    if (!isSupported) return const <HealthSyncBatch>[];
    final List<Object?>? raw = await _channel.invokeListMethod<Object?>(
      'drainPendingBatches',
      <String, Object?>{'limit': limit},
    );
    return (raw ?? const <Object?>[])
        .whereType<Map>()
        .map((Map item) => HealthSyncBatch.fromMap(_stringMap(item)))
        .toList(growable: false);
  }

  @override
  Future<void> acknowledgeBatch(String batchId) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>(
      'ackPendingBatch',
      <String, Object?>{'batchId': batchId},
    );
  }

  @override
  Future<void> clearPendingBatches({required String athleteId}) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>(
      'clearPendingBatches',
      <String, Object?>{'athleteId': athleteId},
    );
  }

  @override
  Future<void> protectLocalFiles(List<String> paths) async {
    validateHealthLocalFilePaths(paths);
    if (!isSupported) return;
    await _channel.invokeMethod<void>(
      'protectLocalFiles',
      <String, Object?>{'paths': List<String>.unmodifiable(paths)},
    );
  }
}

Map<String, Object?> _stringMap(Object? raw) {
  if (raw is! Map) return <String, Object?>{};
  return raw.map<String, Object?>(
    (Object? key, Object? value) => MapEntry<String, Object?>(
      key.toString(),
      value,
    ),
  );
}
