import '../models/cloud_sync.dart';

class MigrationCheckpoint {
  const MigrationCheckpoint({
    required this.migrationId,
    required this.version,
    required this.sourceDocumentCount,
    required this.migratedDocumentCount,
    required this.completedAt,
  });

  final String migrationId;
  final int version;
  final int sourceDocumentCount;
  final int migratedDocumentCount;
  final DateTime completedAt;
}

abstract interface class TrainFlowDatabaseTransaction {
  Future<MigrationCheckpoint?> readMigrationCheckpoint(String migrationId);

  Future<void> upsertLegacyDocument(
    String key,
    Map<String, dynamic> value,
    DateTime migratedAt,
  );

  Future<Map<String, dynamic>?> readLegacyDocument(String key);

  Future<void> markMigrationCompleted(MigrationCheckpoint checkpoint);

  Future<void> upsertAthleteProfileRow(Map<String, Object?> row);

  Future<void> markStorageCutover({
    required int schemaVersion,
    required DateTime completedAt,
  });
}

abstract interface class TrainFlowDatabaseGateway {
  Future<Map<String, Map<String, dynamic>>> readAllLegacyDocuments();

  Future<void> upsertLegacyDocument(
    String key,
    Map<String, dynamic> value,
  );

  Future<void> deleteLegacyDocument(String key);

  Future<void> clearLegacyDocuments({
    Set<String> preservedKeys = const <String>{},
  });

  /// 在单一事务中清理运动员业务数据并写入替换文档。
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  });

  Future<T> transaction<T>(
    Future<T> Function(TrainFlowDatabaseTransaction transaction) action,
  );

  Future<void> close();
}

abstract interface class TrainFlowCloudSyncWriteGateway {
  Future<void> upsertLegacyDocumentWithCloudMutations({
    required String key,
    required Map<String, dynamic> value,
    required String accountId,
    required List<CloudSyncMutation> mutations,
  });
}

/// 成长功能使用的结构化 SQLite 能力。
///
/// 将其与旧文档迁移接口分开，便于旧测试桩和 Web 降级存储保持兼容。
abstract interface class GrowthDatabaseGateway {
  Future<void> upsertGrowthEvidenceRow(Map<String, Object?> row);

  Future<List<Map<String, Object?>>> listGrowthEvidenceRows({
    required String athleteProfileId,
    required bool includeRevoked,
    required int limit,
    required int offset,
  });

  Future<void> revokeGrowthEvidenceRow({
    required String athleteProfileId,
    required String sourceTable,
    required String sourceId,
    required String revokedAt,
  });

  Future<Map<String, Object?>?> readGrowthLevelStateRow(
    String athleteProfileId,
  );

  Future<void> upsertGrowthLevelStateRow(Map<String, Object?> row);

  Future<void> upsertWeeklyGrowthReportRow(Map<String, Object?> row);

  Future<List<Map<String, Object?>>> listWeeklyGrowthReportRows({
    required String athleteProfileId,
    required int limit,
    required int offset,
  });
}
