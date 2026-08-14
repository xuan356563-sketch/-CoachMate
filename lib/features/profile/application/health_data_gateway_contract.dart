import 'dart:convert';

import '../../../data/models/health_snapshot.dart';

enum HealthPermissionStage { workout, analysis, body }

enum HealthAuthorizationState {
  notRequested,
  undetermined,
  unavailable,
  failed,
}

class HealthAuthorizationResult {
  final HealthPermissionStage stage;
  final HealthAuthorizationState state;
  final bool requestCompleted;
  final String? message;

  const HealthAuthorizationResult({
    required this.stage,
    required this.state,
    required this.requestCompleted,
    this.message,
  });

  bool get canClaimReadAuthorization => false;
}

class HealthSyncBatch {
  final String batchId;
  final String athleteId;
  final String objectType;
  final int queryVersion;
  final List<Map<String, Object?>> upserts;
  final List<String> deletedExternalIds;
  final String? nextAnchor;
  final DateTime createdAt;
  final bool requiresAcknowledgement;
  final DateTime? coverageStart;
  final DateTime? coverageEnd;

  const HealthSyncBatch({
    required this.batchId,
    required this.athleteId,
    required this.objectType,
    required this.queryVersion,
    required this.upserts,
    required this.deletedExternalIds,
    required this.nextAnchor,
    required this.createdAt,
    required this.requiresAcknowledgement,
    this.coverageStart,
    this.coverageEnd,
  });

  factory HealthSyncBatch.fromMap(Map<String, Object?> map) {
    final List<Object?> rawUpserts =
        (map['upserts'] as List<Object?>?) ?? const <Object?>[];
    final List<Object?> rawDeleted =
        (map['deletedExternalIds'] as List<Object?>?) ?? const <Object?>[];
    return HealthSyncBatch(
      batchId: map['batchId'] as String? ?? '',
      athleteId: map['athleteId'] as String? ?? '',
      objectType: map['objectType'] as String? ?? 'unknown',
      queryVersion: (map['queryVersion'] as num?)?.toInt() ?? 1,
      upserts: rawUpserts
          .whereType<Map>()
          .map((Map item) => Map<String, Object?>.from(item))
          .toList(growable: false),
      deletedExternalIds:
          rawDeleted.whereType<String>().toList(growable: false),
      nextAnchor: map['nextAnchor'] as String?,
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      requiresAcknowledgement: map['requiresAcknowledgement'] as bool? ?? true,
      coverageStart:
          DateTime.tryParse(map['coverageStart'] as String? ?? '')?.toUtc(),
      coverageEnd:
          DateTime.tryParse(map['coverageEnd'] as String? ?? '')?.toUtc(),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'batchId': batchId,
        'athleteId': athleteId,
        'objectType': objectType,
        'queryVersion': queryVersion,
        'upserts': upserts,
        'deletedExternalIds': deletedExternalIds,
        'nextAnchor': nextAnchor,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'requiresAcknowledgement': requiresAcknowledgement,
        if (coverageStart != null)
          'coverageStart': coverageStart!.toUtc().toIso8601String(),
        if (coverageEnd != null)
          'coverageEnd': coverageEnd!.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is HealthSyncBatch &&
      jsonEncode(other.toMap()) == jsonEncode(toMap());

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;
}

class HealthForegroundSyncResult {
  final List<HealthSnapshot> snapshots;
  final List<HealthSyncBatch> batches;

  const HealthForegroundSyncResult({
    this.snapshots = const <HealthSnapshot>[],
    this.batches = const <HealthSyncBatch>[],
  });

  bool get hasReadableData =>
      snapshots.isNotEmpty ||
      batches.any((HealthSyncBatch batch) =>
          batch.upserts.isNotEmpty || batch.deletedExternalIds.isNotEmpty);
}

/// HealthKit 按本地自然日聚合的活动摘要传输对象。
///
/// `availableFields` 单独记录原生端实际可读取的字段，避免把未授权或
/// 暂无数据误写成零。Apple 活动圆环不提供步数目标，因此该对象不包含
/// `stepGoal`。
class HealthDailyActivitySummaryPayload {
  HealthDailyActivitySummaryPayload({
    required this.localDate,
    required this.timeZoneName,
    required this.timeZoneOffsetMinutes,
    this.steps,
    this.activeEnergyKcal,
    this.activeEnergyGoalKcal,
    this.exerciseMinutes,
    this.exerciseGoalMinutes,
    this.standHours,
    this.standGoalHours,
    required Set<String> availableFields,
    required DateTime syncedAt,
  })  : availableFields = Set<String>.unmodifiable(availableFields),
        syncedAt = syncedAt.toUtc();

  factory HealthDailyActivitySummaryPayload.fromMap(
    Map<String, Object?> map,
  ) {
    final String localDate = map['localDate'] as String? ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(localDate)) {
      throw const FormatException('每日活动摘要的本地日期无效。');
    }
    final DateTime? syncedAt = _payloadDateTime(map['syncedAt']);
    if (syncedAt == null) {
      throw const FormatException('每日活动摘要的同步时间无效。');
    }
    final Object? rawAvailableFields = map['availableFields'];
    final Set<String> availableFields = rawAvailableFields is List
        ? rawAvailableFields.whereType<String>().toSet()
        : const <String>{};
    return HealthDailyActivitySummaryPayload(
      localDate: localDate,
      timeZoneName: map['timeZoneName'] as String? ?? '',
      timeZoneOffsetMinutes:
          (map['timeZoneOffsetMinutes'] as num?)?.toInt() ?? 0,
      steps: (map['steps'] as num?)?.toInt(),
      activeEnergyKcal: (map['activeEnergyKcal'] as num?)?.toDouble(),
      activeEnergyGoalKcal: (map['activeEnergyGoalKcal'] as num?)?.toDouble(),
      exerciseMinutes: (map['exerciseMinutes'] as num?)?.toInt(),
      exerciseGoalMinutes: (map['exerciseGoalMinutes'] as num?)?.toInt(),
      standHours: (map['standHours'] as num?)?.toInt(),
      standGoalHours: (map['standGoalHours'] as num?)?.toInt(),
      availableFields: availableFields,
      syncedAt: syncedAt,
    );
  }

  final String localDate;
  final String timeZoneName;
  final int timeZoneOffsetMinutes;
  final int? steps;
  final double? activeEnergyKcal;
  final double? activeEnergyGoalKcal;
  final int? exerciseMinutes;
  final int? exerciseGoalMinutes;
  final int? standHours;
  final int? standGoalHours;
  final Set<String> availableFields;
  final DateTime syncedAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'localDate': localDate,
        'timeZoneName': timeZoneName,
        'timeZoneOffsetMinutes': timeZoneOffsetMinutes,
        'steps': steps,
        'activeEnergyKcal': activeEnergyKcal,
        'activeEnergyGoalKcal': activeEnergyGoalKcal,
        'exerciseMinutes': exerciseMinutes,
        'exerciseGoalMinutes': exerciseGoalMinutes,
        'standHours': standHours,
        'standGoalHours': standGoalHours,
        'availableFields': availableFields.toList()..sort(),
        'syncedAt': syncedAt.toIso8601String(),
      };
}

abstract class NativeHealthKitBridge {
  bool get isSupported;

  Future<HealthAuthorizationResult> requestAuthorization({
    required HealthPermissionStage stage,
    required String athleteId,
  });

  Future<HealthSyncBatch?> fetchForeground({
    required HealthPermissionStage stage,
    required String athleteId,
    required DateTime start,
    required DateTime end,
  });

  Future<List<HealthDailyActivitySummaryPayload>> fetchDailyActivitySummaries({
    required DateTime start,
    required DateTime end,
  }) async =>
      const <HealthDailyActivitySummaryPayload>[];

  Future<Map<String, Object?>?> fetchWorkoutDetails({
    required String workoutUuid,
  });

  Future<void> enableBackgroundSync({
    required HealthPermissionStage stage,
    required String athleteId,
  });

  Future<List<HealthSyncBatch>> drainPendingBatches({int limit = 20});

  Future<void> acknowledgeBatch(String batchId);

  Future<void> clearPendingBatches({required String athleteId});

  Future<void> protectLocalFiles(List<String> paths);
}

abstract class HealthDataGateway {
  const HealthDataGateway();

  bool get isSupported;

  Future<HealthAuthorizationResult> requestAuthorization({
    required HealthPermissionStage stage,
    required String athleteId,
  });

  Future<HealthAuthorizationResult> requestPermission({
    required HealthPermissionStage stage,
    required String athleteId,
  }) =>
      requestAuthorization(stage: stage, athleteId: athleteId);

  Future<HealthForegroundSyncResult> fetchForeground({
    required HealthPermissionStage stage,
    required String athleteId,
    required DateTime start,
    required DateTime end,
  });

  Future<HealthForegroundSyncResult> syncForeground({
    required HealthPermissionStage stage,
    required String athleteId,
    required DateTime start,
    required DateTime end,
  }) =>
      fetchForeground(
        stage: stage,
        athleteId: athleteId,
        start: start,
        end: end,
      );

  Future<List<HealthDailyActivitySummaryPayload>> fetchDailyActivitySummaries({
    required DateTime start,
    required DateTime end,
  }) async =>
      const <HealthDailyActivitySummaryPayload>[];

  Future<Map<String, Object?>?> fetchWorkoutDetails(String workoutUuid) async =>
      null;

  Future<void> enableBackgroundSync({
    required HealthPermissionStage stage,
    required String athleteId,
  }) async {}

  Future<List<HealthSyncBatch>> drainPendingBatches({int limit = 20});

  Future<List<HealthSyncBatch>> drainPendingBackgroundBatches({
    int limit = 20,
  }) =>
      drainPendingBatches(limit: limit);

  Future<void> acknowledgeBatch(String batchId);

  Future<void> clearPendingBatches({required String athleteId});

  Future<void> clearAthleteData({required String athleteId}) =>
      clearPendingBatches(athleteId: athleteId);

  Future<void> protectLocalFiles(List<String> paths) async {
    validateHealthLocalFilePaths(paths);
  }
}

typedef HealthSyncBatchProcessor = Future<void> Function(HealthSyncBatch batch);

void validateHealthLocalFilePaths(List<String> paths) {
  if (paths.isEmpty ||
      paths.length > 16 ||
      paths.any(
        (String path) => !path.startsWith('/') || path.contains('\u0000'),
      )) {
    throw ArgumentError('本地健康数据文件路径无效。');
  }
}

DateTime? _payloadDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  if (value is String) return DateTime.tryParse(value);
  return null;
}
