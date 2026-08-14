/// Coach v1 的本地持久化边界。
///
/// 接口没有 sync_outbox 写入能力；云端投影必须经过独立授权和网络客户端。
abstract interface class CoachDatabaseGateway {
  Future<void> upsertStateSnapshotRow(Map<String, Object?> row);

  Future<Map<String, Object?>?> readLatestStateSnapshotRow({
    required String athleteProfileId,
  });

  Future<void> writeMemory({
    required Map<String, Object?> memoryRow,
    required List<Map<String, Object?>> sourceRows,
    String? supersedesMemoryId,
  });

  Future<void> tombstoneMemory({
    required String memoryId,
    required String athleteProfileId,
    required DateTime deletedAt,
    required DateTime tombstoneExpiresAt,
  });

  Future<Map<String, Object?>?> readMemoryRow({
    required String memoryId,
    required String athleteProfileId,
  });

  Future<List<Map<String, Object?>>> listMemoryRows({
    required String athleteProfileId,
  });

  Future<List<Map<String, Object?>>> listMemorySourceRows(String memoryId);

  Future<void> upsertTurnTraceRow(Map<String, Object?> row);
}

abstract interface class CoachDatabaseGatewayProvider {
  CoachDatabaseGateway createCoachDatabaseGateway();
}
