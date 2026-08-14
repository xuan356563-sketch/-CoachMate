import 'dart:convert';

import '../local/trainflow_database_gateway.dart';
import '../local/trainmate_structured_database_gateway.dart';
import '../models/growth_evidence.dart';
import '../../services/local_storage_service.dart';

abstract interface class GrowthEvidenceRepository {
  Future<List<GrowthEvidenceEvent>> listEvents({
    required String athleteProfileId,
    bool includeRevoked = false,
    int limit = 30,
    int offset = 0,
  });

  Future<GrowthEvidenceEvent?> findBySource({
    required String athleteProfileId,
    required String sourceTable,
    required String sourceId,
  });

  Future<void> saveEvent(GrowthEvidenceEvent event);

  Future<void> revokeSource({
    required String athleteProfileId,
    required String sourceTable,
    required String sourceId,
    required DateTime revokedAt,
  });

  Future<GrowthLevelState> readLevelState(String athleteProfileId);

  Future<void> saveLevelState({
    required String athleteProfileId,
    required GrowthLevelState state,
    required DateTime updatedAt,
  });

  Future<List<WeeklyGrowthReport>> listWeeklyReports({
    required String athleteProfileId,
    int limit = 30,
    int offset = 0,
  });

  Future<void> saveWeeklyReport(WeeklyGrowthReport report);

  /// 删除指定运动员的成长证据、等级峰值和兼容周报。
  Future<void> clearAthleteData(String athleteProfileId);
}

/// Web 与 SQLite 初始化失败时的本地文档降级实现。
class PersistedGrowthEvidenceRepository implements GrowthEvidenceRepository {
  PersistedGrowthEvidenceRepository(this._storageService) {
    _hydrate();
  }

  static const String storageKey = 'trainflow.growth_evidence.v2';
  static const int _webEventLimit = 2000;

  final LocalStorageService _storageService;
  final List<GrowthEvidenceEvent> _events = <GrowthEvidenceEvent>[];
  final Map<String, GrowthLevelState> _levelStates =
      <String, GrowthLevelState>{};
  final List<WeeklyGrowthReport> _weeklyReports = <WeeklyGrowthReport>[];

  @override
  Future<List<GrowthEvidenceEvent>> listEvents({
    required String athleteProfileId,
    bool includeRevoked = false,
    int limit = 30,
    int offset = 0,
  }) async {
    final List<GrowthEvidenceEvent> result = _events
        .where(
          (GrowthEvidenceEvent event) =>
              event.athleteProfileId == athleteProfileId &&
              (includeRevoked || event.isActive),
        )
        .toList()
      ..sort(_eventSortDescending);
    final int start = offset.clamp(0, result.length).toInt();
    final int end = (start + limit.clamp(1, 100).toInt())
        .clamp(start, result.length)
        .toInt();
    return List<GrowthEvidenceEvent>.unmodifiable(result.sublist(start, end));
  }

  @override
  Future<GrowthEvidenceEvent?> findBySource({
    required String athleteProfileId,
    required String sourceTable,
    required String sourceId,
  }) async {
    for (final GrowthEvidenceEvent event in _events) {
      if (event.athleteProfileId == athleteProfileId &&
          event.sourceTable == sourceTable &&
          event.sourceId == sourceId) {
        return event;
      }
    }
    return null;
  }

  @override
  Future<void> saveEvent(GrowthEvidenceEvent event) async {
    final List<GrowthEvidenceEvent> next = List<GrowthEvidenceEvent>.from(
      _events,
    )..removeWhere((GrowthEvidenceEvent item) => item.eventId == event.eventId);
    next.add(event);
    _trimRevokedEventsOrThrow(next);
    _events
      ..clear()
      ..addAll(next);
    _persist();
  }

  @override
  Future<void> revokeSource({
    required String athleteProfileId,
    required String sourceTable,
    required String sourceId,
    required DateTime revokedAt,
  }) async {
    bool changed = false;
    for (int index = 0; index < _events.length; index += 1) {
      final GrowthEvidenceEvent event = _events[index];
      if (event.athleteProfileId == athleteProfileId &&
          event.sourceTable == sourceTable &&
          event.sourceId == sourceId &&
          event.isActive) {
        _events[index] = event.copyWith(
          revokedAt: revokedAt,
          updatedAt: revokedAt,
        );
        changed = true;
      }
    }
    if (changed) {
      _persist();
    }
  }

  @override
  Future<GrowthLevelState> readLevelState(String athleteProfileId) async {
    return _levelStates[athleteProfileId] ??
        const GrowthLevelState(peakXp: 0, peakLevel: 1);
  }

  @override
  Future<void> saveLevelState({
    required String athleteProfileId,
    required GrowthLevelState state,
    required DateTime updatedAt,
  }) async {
    _levelStates[athleteProfileId] = state;
    _persist();
  }

  @override
  Future<List<WeeklyGrowthReport>> listWeeklyReports({
    required String athleteProfileId,
    int limit = 30,
    int offset = 0,
  }) async {
    final List<WeeklyGrowthReport> result = _weeklyReports
        .where(
          (WeeklyGrowthReport report) =>
              report.athleteProfileId == athleteProfileId,
        )
        .toList()
      ..sort(
        (WeeklyGrowthReport first, WeeklyGrowthReport second) =>
            second.weekStartsOn.compareTo(first.weekStartsOn),
      );
    final int start = offset.clamp(0, result.length).toInt();
    final int end = (start + limit.clamp(1, 100).toInt())
        .clamp(start, result.length)
        .toInt();
    return List<WeeklyGrowthReport>.unmodifiable(result.sublist(start, end));
  }

  @override
  Future<void> saveWeeklyReport(WeeklyGrowthReport report) async {
    _weeklyReports.removeWhere(
      (WeeklyGrowthReport item) =>
          item.athleteProfileId == report.athleteProfileId &&
          item.weekKey == report.weekKey,
    );
    _weeklyReports.add(report);
    _persist();
  }

  @override
  Future<void> clearAthleteData(String athleteProfileId) async {
    _events.removeWhere(
      (GrowthEvidenceEvent event) => event.athleteProfileId == athleteProfileId,
    );
    _levelStates.remove(athleteProfileId);
    _weeklyReports.removeWhere(
      (WeeklyGrowthReport report) =>
          report.athleteProfileId == athleteProfileId,
    );
    _persist();
    await _storageService.flush();
  }

  void _hydrate() {
    final Map<String, dynamic>? stored = _storageService.readJson(storageKey);
    if (stored == null) return;
    final List<dynamic> events =
        stored['events'] as List<dynamic>? ?? const <dynamic>[];
    final Map<String, dynamic> levels =
        stored['levelStates'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
    final List<dynamic> reports =
        stored['weeklyReports'] as List<dynamic>? ?? const <dynamic>[];
    _events.addAll(
      events
          .whereType<Map<String, dynamic>>()
          .map(GrowthEvidenceEvent.fromJson),
    );
    for (final MapEntry<String, dynamic> entry in levels.entries) {
      if (entry.value is Map<String, dynamic>) {
        _levelStates[entry.key] = GrowthLevelState.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    _weeklyReports.addAll(
      reports
          .whereType<Map<String, dynamic>>()
          .map(WeeklyGrowthReport.fromJson),
    );
  }

  void _persist() {
    _storageService.saveJson(storageKey, <String, dynamic>{
      'schemaVersion': 2,
      'events':
          _events.map((GrowthEvidenceEvent item) => item.toJson()).toList(),
      'levelStates': <String, dynamic>{
        for (final MapEntry<String, GrowthLevelState> entry
            in _levelStates.entries)
          entry.key: entry.value.toJson(),
      },
      'weeklyReports': _weeklyReports
          .map((WeeklyGrowthReport item) => item.toJson())
          .toList(),
    });
  }

  void _trimRevokedEventsOrThrow(List<GrowthEvidenceEvent> events) {
    if (events.length <= _webEventLimit) return;
    final List<GrowthEvidenceEvent> revoked =
        events.where((GrowthEvidenceEvent event) => event.isRevoked).toList()
          ..sort(
            (GrowthEvidenceEvent first, GrowthEvidenceEvent second) =>
                first.occurredAt.compareTo(second.occurredAt),
          );
    for (final GrowthEvidenceEvent event in revoked) {
      if (events.length <= _webEventLimit) break;
      events.remove(event);
    }
    if (events.length > _webEventLimit) {
      throw StateError('成长证据已达到本地容量上限，请先导出或清理已撤销记录。');
    }
  }
}

/// iOS/macOS 的结构化 SQLite 实现。
class SqliteGrowthEvidenceRepository implements GrowthEvidenceRepository {
  const SqliteGrowthEvidenceRepository(this._database);

  final GrowthDatabaseGateway _database;

  @override
  Future<List<GrowthEvidenceEvent>> listEvents({
    required String athleteProfileId,
    bool includeRevoked = false,
    int limit = 30,
    int offset = 0,
  }) async {
    final List<Map<String, Object?>> rows =
        await _database.listGrowthEvidenceRows(
      athleteProfileId: athleteProfileId,
      includeRevoked: includeRevoked,
      limit: limit,
      offset: offset,
    );
    return List<GrowthEvidenceEvent>.unmodifiable(
      rows.map(_eventFromRow),
    );
  }

  @override
  Future<GrowthEvidenceEvent?> findBySource({
    required String athleteProfileId,
    required String sourceTable,
    required String sourceId,
  }) async {
    int offset = 0;
    while (true) {
      final List<GrowthEvidenceEvent> events = await listEvents(
        athleteProfileId: athleteProfileId,
        includeRevoked: true,
        limit: 100,
        offset: offset,
      );
      for (final GrowthEvidenceEvent event in events) {
        if (event.sourceTable == sourceTable && event.sourceId == sourceId) {
          return event;
        }
      }
      if (events.length < 100) return null;
      offset += events.length;
    }
  }

  @override
  Future<void> saveEvent(GrowthEvidenceEvent event) {
    return _database.upsertGrowthEvidenceRow(<String, Object?>{
      'id': event.eventId,
      'athlete_profile_id': event.athleteProfileId,
      'event_type': event.eventType.jsonValue,
      'title': event.title,
      'description': event.description,
      'occurred_at': event.occurredAt.toUtc().toIso8601String(),
      'occurred_on': growthDateKey(event.occurredOn),
      'time_zone_offset_minutes': event.timeZoneOffsetMinutes,
      'time_zone_name': event.timeZoneName,
      'source_table': event.sourceTable,
      'source_id': event.sourceId,
      'evidence_json': jsonEncode(event.toJson()),
      'created_at': event.createdAt.toUtc().toIso8601String(),
      'updated_at': event.updatedAt.toUtc().toIso8601String(),
      'revoked_at': event.revokedAt?.toUtc().toIso8601String(),
      'model_version': event.modelVersion,
    });
  }

  @override
  Future<void> revokeSource({
    required String athleteProfileId,
    required String sourceTable,
    required String sourceId,
    required DateTime revokedAt,
  }) {
    return _database.revokeGrowthEvidenceRow(
      athleteProfileId: athleteProfileId,
      sourceTable: sourceTable,
      sourceId: sourceId,
      revokedAt: revokedAt.toUtc().toIso8601String(),
    );
  }

  @override
  Future<GrowthLevelState> readLevelState(String athleteProfileId) async {
    final Map<String, Object?>? row =
        await _database.readGrowthLevelStateRow(athleteProfileId);
    if (row == null) {
      return const GrowthLevelState(peakXp: 0, peakLevel: 1);
    }
    return GrowthLevelState(
      peakXp: (row['peak_xp'] as num?)?.toInt() ?? 0,
      peakLevel: (row['peak_level'] as num?)?.toInt() ?? 1,
      modelVersion: (row['model_version'] as num?)?.toInt() ?? 1,
    );
  }

  @override
  Future<void> saveLevelState({
    required String athleteProfileId,
    required GrowthLevelState state,
    required DateTime updatedAt,
  }) {
    return _database.upsertGrowthLevelStateRow(<String, Object?>{
      'athlete_profile_id': athleteProfileId,
      'peak_xp': state.peakXp,
      'peak_level': state.peakLevel,
      'model_version': state.modelVersion,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<WeeklyGrowthReport>> listWeeklyReports({
    required String athleteProfileId,
    int limit = 30,
    int offset = 0,
  }) async {
    final List<Map<String, Object?>> rows =
        await _database.listWeeklyGrowthReportRows(
      athleteProfileId: athleteProfileId,
      limit: limit,
      offset: offset,
    );
    return List<WeeklyGrowthReport>.unmodifiable(
      rows.map(_weeklyReportFromRow),
    );
  }

  @override
  Future<void> saveWeeklyReport(WeeklyGrowthReport report) {
    return _database.upsertWeeklyGrowthReportRow(<String, Object?>{
      'id': report.id,
      'athlete_profile_id': report.athleteProfileId,
      'week_key': report.weekKey,
      'week_starts_on': growthDateKey(report.weekStartsOn),
      'week_ends_on': growthDateKey(report.weekEndsOn),
      'completion_rate': report.completionRate,
      'training_load': report.trainingLoad,
      'summary': report.recoverySummary,
      'payload_json': jsonEncode(report.toJson()),
      'created_at': report.generatedAt.toUtc().toIso8601String(),
      'updated_at': report.generatedAt.toUtc().toIso8601String(),
      'locked_at': report.lockedAt?.toUtc().toIso8601String(),
      'regenerated_at': report.regeneratedAt?.toUtc().toIso8601String(),
      'model_version': report.modelVersion,
    });
  }

  @override
  Future<void> clearAthleteData(String athleteProfileId) async {
    final GrowthDatabaseGateway database = _database;
    if (database is! TrainMateStructuredDatabaseGateway) {
      throw StateError('当前成长数据库不支持运动员结构化数据清理。');
    }
    await (database as TrainMateStructuredDatabaseGateway)
        .clearAthleteStructuredData(athleteProfileId);
  }

  GrowthEvidenceEvent _eventFromRow(Map<String, Object?> row) {
    final Object? decoded = jsonDecode(row['evidence_json'] as String? ?? '{}');
    final Map<String, dynamic> json = decoded is Map<String, dynamic>
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    json.addAll(<String, dynamic>{
      'eventId': row['id'],
      'athleteProfileId': row['athlete_profile_id'],
      'eventType': row['event_type'],
      'title': row['title'],
      'description': row['description'],
      'occurredAt': row['occurred_at'],
      'occurredOn': row['occurred_on'],
      'timeZoneOffsetMinutes': row['time_zone_offset_minutes'],
      'timeZoneName': row['time_zone_name'],
      'sourceTable': row['source_table'],
      'sourceId': row['source_id'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
      'revokedAt': row['revoked_at'],
      'modelVersion': row['model_version'],
    });
    return GrowthEvidenceEvent.fromJson(json);
  }

  WeeklyGrowthReport _weeklyReportFromRow(Map<String, Object?> row) {
    final Object? decoded = jsonDecode(row['payload_json'] as String? ?? '{}');
    final Map<String, dynamic> json = decoded is Map<String, dynamic>
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    json.addAll(<String, dynamic>{
      'id': row['id'],
      'athleteProfileId': row['athlete_profile_id'],
      'weekKey': row['week_key'],
      'weekStartsOn': row['week_starts_on'],
      'weekEndsOn': row['week_ends_on'],
      'lockedAt': row['locked_at'],
      'regeneratedAt': row['regenerated_at'],
      'modelVersion': row['model_version'],
    });
    return WeeklyGrowthReport.fromJson(json);
  }
}

int _eventSortDescending(
  GrowthEvidenceEvent first,
  GrowthEvidenceEvent second,
) {
  final int byTime = second.occurredAt.compareTo(first.occurredAt);
  return byTime != 0 ? byTime : second.eventId.compareTo(first.eventId);
}
