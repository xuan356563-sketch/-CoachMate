/// 运动搭子仅使用的本地数据库边界。
///
/// 该接口刻意不提供 sync_outbox 或既有训练、健康、计划、宠物表的写入能力。
abstract interface class CompanionDatabaseGateway {
  Future<Map<String, Object?>?> readRelationshipRow(String athleteProfileId);

  Future<void> upsertRelationshipRow(Map<String, Object?> row);

  Future<List<Map<String, Object?>>> listMessageRows({
    required String athleteProfileId,
    String? localDate,
    DateTime? createdSince,
    int? limit,
  });

  Future<void> upsertMessageRow(Map<String, Object?> row);

  Future<int> purgeExpiredConversationMessageRows({
    required String athleteProfileId,
    required DateTime createdBefore,
  });

  Future<void> markMessageOpened({
    required String messageId,
    required DateTime openedAt,
  });

  Future<void> recordMessageAction({
    required String messageId,
    required String actionId,
    required DateTime actedAt,
  });

  Future<List<Map<String, Object?>>> listEventRows({
    required String athleteProfileId,
    String? kind,
  });

  Future<void> upsertEventRow(Map<String, Object?> row);
}

/// 主数据库可选提供的陪伴领域能力。
abstract interface class CompanionDatabaseGatewayProvider {
  CompanionDatabaseGateway createCompanionDatabaseGateway();
}
