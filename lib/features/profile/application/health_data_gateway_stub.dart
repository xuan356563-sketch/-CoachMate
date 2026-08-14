import 'health_data_gateway_contract.dart';

HealthDataGateway createHealthDataGateway() =>
    const UnsupportedHealthDataGateway();

class UnsupportedHealthDataGateway extends HealthDataGateway {
  const UnsupportedHealthDataGateway();

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
        message: '当前平台不支持 Apple 健康同步。',
      );

  @override
  Future<HealthForegroundSyncResult> fetchForeground({
    required HealthPermissionStage stage,
    required String athleteId,
    required DateTime start,
    required DateTime end,
  }) async =>
      const HealthForegroundSyncResult();

  @override
  Future<List<HealthDailyActivitySummaryPayload>> fetchDailyActivitySummaries({
    required DateTime start,
    required DateTime end,
  }) async =>
      const <HealthDailyActivitySummaryPayload>[];

  @override
  Future<List<HealthSyncBatch>> drainPendingBatches({int limit = 20}) async =>
      const <HealthSyncBatch>[];

  @override
  Future<void> acknowledgeBatch(String batchId) async {}

  @override
  Future<void> clearPendingBatches({required String athleteId}) async {}
}
