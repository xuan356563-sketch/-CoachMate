abstract interface class RhythmDatabaseGateway {
  Future<Map<String, Object?>?> readRhythmSnapshot({
    required String athleteProfileId,
    required String weekStart,
  });

  Future<Map<String, Object?>> insertRhythmSnapshotIfAbsent(
    Map<String, Object?> row,
  );

  Future<List<Map<String, Object?>>> listMealRecords({
    required String athleteProfileId,
    required String localDateOnOrAfter,
    required String localDateOnOrBefore,
  });

  Future<void> saveMealRecord(Map<String, Object?> row);

  Future<void> revokeMealRecord({
    required String athleteProfileId,
    required String recordId,
    required String revokedAt,
  });
}
