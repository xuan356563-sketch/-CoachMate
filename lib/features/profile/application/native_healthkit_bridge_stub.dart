import 'health_data_gateway_contract.dart';

NativeHealthKitBridge createNativeHealthKitBridge() =>
    const UnsupportedNativeHealthKitBridge();

class UnsupportedNativeHealthKitBridge implements NativeHealthKitBridge {
  const UnsupportedNativeHealthKitBridge();

  @override
  bool get isSupported => false;

  @override
  Future<HealthAuthorizationResult> requestAuthorization({
    required HealthPermissionStage stage,
    required String athleteId,
  }) async =>
      HealthAuthorizationResult(
        stage: stage,
        state: HealthAuthorizationState.unavailable,
        requestCompleted: false,
        message: '当前平台不支持 Apple 健康。',
      );

  @override
  Future<HealthSyncBatch?> fetchForeground({
    required HealthPermissionStage stage,
    required String athleteId,
    required DateTime start,
    required DateTime end,
  }) async =>
      null;

  @override
  Future<List<HealthDailyActivitySummaryPayload>> fetchDailyActivitySummaries({
    required DateTime start,
    required DateTime end,
  }) async =>
      const <HealthDailyActivitySummaryPayload>[];

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
  Future<List<HealthSyncBatch>> drainPendingBatches({int limit = 20}) async =>
      const <HealthSyncBatch>[];

  @override
  Future<void> acknowledgeBatch(String batchId) async {}

  @override
  Future<void> clearPendingBatches({required String athleteId}) async {}

  @override
  Future<void> protectLocalFiles(List<String> paths) async {
    validateHealthLocalFilePaths(paths);
  }
}
