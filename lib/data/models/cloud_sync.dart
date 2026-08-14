import 'dart:math';

enum CloudSyncEntityType {
  userProfile('user_profile'),
  trainingPreferences('training_preferences'),
  planVersions('plan_versions'),
  scheduledWorkouts('scheduled_workouts'),
  completionSummaries('completion_summaries'),
  appSettings('app_settings');

  const CloudSyncEntityType(this.wireName);

  final String wireName;

  static CloudSyncEntityType fromWireName(String value) {
    return CloudSyncEntityType.values.firstWhere(
      (CloudSyncEntityType type) => type.wireName == value,
      orElse: () => throw const FormatException('云同步实体类型无效'),
    );
  }
}

class CloudSyncMutation {
  CloudSyncMutation._({
    required this.mutationId,
    required this.entityType,
    required this.entityId,
    required this.baseVersion,
    required Map<String, Object?> payload,
  }) : payload = Map<String, Object?>.unmodifiable(payload);

  factory CloudSyncMutation.fromPayload({
    required String mutationId,
    required CloudSyncEntityType entityType,
    required String entityId,
    required int? baseVersion,
    required Map<String, Object?> payload,
  }) {
    _validatePayload(entityType, payload);
    return CloudSyncMutation._(
      mutationId: mutationId,
      entityType: entityType,
      entityId: entityId,
      baseVersion: baseVersion,
      payload: payload,
    );
  }

  factory CloudSyncMutation.trainingPreferences({
    required String mutationId,
    required String entityId,
    required int? baseVersion,
    required String goal,
    required List<String> sportTypes,
    required String experienceLevel,
    required List<int> weeklyAvailability,
    required List<String> equipment,
  }) {
    return CloudSyncMutation.fromPayload(
      mutationId: mutationId,
      entityType: CloudSyncEntityType.trainingPreferences,
      entityId: entityId,
      baseVersion: baseVersion,
      payload: <String, Object?>{
        'goal': goal,
        'sport_types': List<String>.of(sportTypes),
        'experience_level': experienceLevel,
        'weekly_availability': List<int>.of(weeklyAvailability),
        'equipment': List<String>.of(equipment),
      },
    );
  }

  factory CloudSyncMutation.userProfile({
    required String mutationId,
    required String entityId,
    required int? baseVersion,
    required Map<String, Object?> confirmedProfile,
  }) {
    return CloudSyncMutation.fromPayload(
      mutationId: mutationId,
      entityType: CloudSyncEntityType.userProfile,
      entityId: entityId,
      baseVersion: baseVersion,
      payload: confirmedProfile,
    );
  }

  factory CloudSyncMutation.planVersion({
    required String mutationId,
    required String entityId,
    required int? baseVersion,
    required String title,
    required DateTime startsOn,
    required DateTime? endsOn,
    required String state,
  }) {
    return CloudSyncMutation.fromPayload(
      mutationId: mutationId,
      entityType: CloudSyncEntityType.planVersions,
      entityId: entityId,
      baseVersion: baseVersion,
      payload: <String, Object?>{
        'title': title,
        'starts_on': _dateOnly(startsOn),
        'ends_on': endsOn == null ? null : _dateOnly(endsOn),
        'state': state,
      },
    );
  }

  factory CloudSyncMutation.scheduledWorkout({
    required String mutationId,
    required String entityId,
    required int? baseVersion,
    required String planVersionId,
    required DateTime scheduledDate,
    required String sportType,
    required String title,
    required int durationMinutes,
    required String state,
  }) {
    return CloudSyncMutation.fromPayload(
      mutationId: mutationId,
      entityType: CloudSyncEntityType.scheduledWorkouts,
      entityId: entityId,
      baseVersion: baseVersion,
      payload: <String, Object?>{
        'plan_version_id': planVersionId,
        'scheduled_date': _dateOnly(scheduledDate),
        'sport_type': sportType,
        'title': title,
        'duration_minutes': durationMinutes,
        'state': state,
      },
    );
  }

  factory CloudSyncMutation.completionSummary({
    required String mutationId,
    required String entityId,
    required String planVersionId,
    required String scheduledWorkoutId,
    required DateTime startedAt,
    required DateTime endedAt,
    required int durationSeconds,
    required int completionPercentage,
    required bool revoked,
  }) {
    return CloudSyncMutation.fromPayload(
      mutationId: mutationId,
      entityType: CloudSyncEntityType.completionSummaries,
      entityId: entityId,
      baseVersion: null,
      payload: <String, Object?>{
        'plan_version_id': planVersionId,
        'scheduled_workout_id': scheduledWorkoutId,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt.toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
        'completion_percentage': completionPercentage,
        'revoked': revoked,
      },
    );
  }

  factory CloudSyncMutation.appSettings({
    required String mutationId,
    required String entityId,
    required int? baseVersion,
    required String locale,
    required int weekStartsOn,
    required bool notificationsEnabled,
  }) {
    return CloudSyncMutation.fromPayload(
      mutationId: mutationId,
      entityType: CloudSyncEntityType.appSettings,
      entityId: entityId,
      baseVersion: baseVersion,
      payload: <String, Object?>{
        'locale': locale,
        'week_starts_on': weekStartsOn,
        'notifications_enabled': notificationsEnabled,
      },
    );
  }

  final String mutationId;
  final CloudSyncEntityType entityType;
  final String entityId;
  final int? baseVersion;
  final Map<String, Object?> payload;

  Map<String, Object?> toRequestJson() {
    return <String, Object?>{
      'mutation_id': mutationId,
      'entity_type': entityType.wireName,
      'entity_id': entityId,
      'operation': 'upsert',
      'base_version': baseVersion,
      'payload': payload,
    };
  }

  static void _validatePayload(
    CloudSyncEntityType entityType,
    Map<String, Object?> payload,
  ) {
    final Set<String> allowed = _allowedPayloadFields[entityType]!;
    if (payload.keys.toSet().difference(allowed).isNotEmpty ||
        allowed.difference(payload.keys.toSet()).isNotEmpty) {
      throw const FormatException('同步数据包含未声明或缺失的字段');
    }
  }
}

const Map<CloudSyncEntityType, Set<String>> _allowedPayloadFields =
    <CloudSyncEntityType, Set<String>>{
  CloudSyncEntityType.userProfile: <String>{
    'schema_version',
    'nickname',
    'gender',
    'declared_age',
    'height_cm',
    'weight_kg',
    'worker_profile_type',
    'work_schedule_type',
    'training_goal',
    'main_sports',
    'training_experience_level',
    'training_environment',
    'weekly_training_days',
    'daily_available_minutes',
    'core_self_report',
    'aerobic_talk_test',
    'cardio_recovery',
    'injuries',
    'health_fields_included',
  },
  CloudSyncEntityType.trainingPreferences: <String>{
    'goal',
    'sport_types',
    'experience_level',
    'weekly_availability',
    'equipment',
  },
  CloudSyncEntityType.planVersions: <String>{
    'title',
    'starts_on',
    'ends_on',
    'state',
  },
  CloudSyncEntityType.scheduledWorkouts: <String>{
    'plan_version_id',
    'scheduled_date',
    'sport_type',
    'title',
    'duration_minutes',
    'state',
  },
  CloudSyncEntityType.completionSummaries: <String>{
    'plan_version_id',
    'scheduled_workout_id',
    'started_at',
    'ended_at',
    'duration_seconds',
    'completion_percentage',
    'revoked',
  },
  CloudSyncEntityType.appSettings: <String>{
    'locale',
    'week_starts_on',
    'notifications_enabled',
  },
};

class CloudSyncEntity {
  const CloudSyncEntity({
    required this.entityType,
    required this.entityId,
    required this.version,
    required this.payload,
  });

  final CloudSyncEntityType entityType;
  final String entityId;
  final int version;
  final Map<String, Object?> payload;
}

class CloudSyncSnapshot {
  const CloudSyncSnapshot({
    required this.cursor,
    required this.entities,
  });

  factory CloudSyncSnapshot.fromJson(Map<String, dynamic> json) {
    final List<CloudSyncEntity> entities = <CloudSyncEntity>[];
    final Object? rawEntities = json['entities'];
    if (rawEntities is! Map<String, dynamic>) {
      throw const FormatException('云同步快照格式无效');
    }
    for (final MapEntry<String, dynamic> entry in rawEntities.entries) {
      final CloudSyncEntityType type =
          CloudSyncEntityType.fromWireName(entry.key);
      final Object? rows = entry.value;
      if (rows is! List<dynamic>) {
        throw const FormatException('云同步快照实体格式无效');
      }
      for (final Object? rawRow in rows) {
        if (rawRow is! Map<String, dynamic>) {
          throw const FormatException('云同步快照条目格式无效');
        }
        final Object? payload = rawRow['payload'];
        if (payload is! Map<String, dynamic>) {
          throw const FormatException('云同步快照载荷格式无效');
        }
        _validatePayload(type, payload.cast<String, Object?>());
        entities.add(
          CloudSyncEntity(
            entityType: type,
            entityId: rawRow['entity_id'] as String,
            version: rawRow['version'] as int,
            payload: payload.cast<String, Object?>(),
          ),
        );
      }
    }
    return CloudSyncSnapshot(
      cursor: json['cursor'] as int,
      entities: List<CloudSyncEntity>.unmodifiable(entities),
    );
  }

  final int cursor;
  final List<CloudSyncEntity> entities;
}

enum CloudSyncMutationStatus { applied, conflict }

enum CloudSyncConflictResolution { keepLocal, useCloud }

class CloudSyncConflict {
  const CloudSyncConflict({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.cloudVersion,
  });

  final String id;
  final CloudSyncEntityType entityType;
  final String entityId;
  final int cloudVersion;
}

class CloudSyncMutationResult {
  const CloudSyncMutationResult({
    required this.mutationId,
    required this.entityType,
    required this.entityId,
    required this.status,
    required this.version,
    this.cursor,
    this.cloudPayload,
  });

  factory CloudSyncMutationResult.fromJson(Map<String, dynamic> json) {
    final String status = json['status'] as String;
    return CloudSyncMutationResult(
      mutationId: json['mutation_id'] as String,
      entityType:
          CloudSyncEntityType.fromWireName(json['entity_type'] as String),
      entityId: json['entity_id'] as String,
      status: status == 'applied'
          ? CloudSyncMutationStatus.applied
          : CloudSyncMutationStatus.conflict,
      version: json['version'] as int,
      cursor: json['cursor'] as int?,
      cloudPayload: (json['cloud_payload'] as Map<String, dynamic>?)
          ?.cast<String, Object?>(),
    );
  }

  final String mutationId;
  final CloudSyncEntityType entityType;
  final String entityId;
  final CloudSyncMutationStatus status;
  final int version;
  final int? cursor;
  final Map<String, Object?>? cloudPayload;
}

class CloudSyncChange extends CloudSyncEntity {
  const CloudSyncChange({
    required super.entityType,
    required super.entityId,
    required super.version,
    required super.payload,
    required this.cursor,
    required this.mutationId,
  });

  factory CloudSyncChange.fromJson(Map<String, dynamic> json) {
    final CloudSyncEntityType type =
        CloudSyncEntityType.fromWireName(json['entity_type'] as String);
    final Map<String, Object?> payload =
        (json['payload'] as Map<String, dynamic>).cast<String, Object?>();
    _validatePayload(type, payload);
    return CloudSyncChange(
      entityType: type,
      entityId: json['entity_id'] as String,
      version: json['version'] as int,
      payload: payload,
      cursor: json['cursor'] as int,
      mutationId: json['mutation_id'] as String,
    );
  }

  final int cursor;
  final String mutationId;
}

class CloudSyncChangePage {
  const CloudSyncChangePage({
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<CloudSyncChange> changes;
  final int nextCursor;
  final bool hasMore;
}

class CloudSyncAccountState {
  const CloudSyncAccountState({
    required this.enabled,
    required this.snapshotRequired,
    required this.cursor,
    required this.hasExistingLocalData,
  });

  final bool enabled;
  final bool snapshotRequired;
  final int cursor;
  final bool hasExistingLocalData;
}

class CloudSyncTransportException implements Exception {
  const CloudSyncTransportException();

  @override
  String toString() => '云同步暂时不可用，本地训练不受影响';
}

String generateCloudSyncMutationId() {
  final Random random = Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return _uuidFromBytes(bytes);
}

String stableCloudSyncEntityId(String namespace, String localId) {
  final String source = '$namespace:$localId';
  int firstHigh = 0xcbf29ce4;
  int firstLow = 0x84222325;
  int secondHigh = 0x84222325;
  int secondLow = 0xcbf29ce4;
  for (final int codeUnit in source.codeUnits) {
    (firstHigh, firstLow) = _multiplyFnv1a64(
      firstHigh,
      (firstLow ^ codeUnit).toUnsigned(32),
    );
    (secondHigh, secondLow) = _multiplyFnv1a64(
      secondHigh,
      (secondLow ^ (codeUnit + 31)).toUnsigned(32),
    );
  }
  final List<int> bytes = <int>[
    for (int shift = 24; shift >= 0; shift -= 8) (firstHigh >> shift) & 0xff,
    for (int shift = 24; shift >= 0; shift -= 8) (firstLow >> shift) & 0xff,
    for (int shift = 24; shift >= 0; shift -= 8) (secondHigh >> shift) & 0xff,
    for (int shift = 24; shift >= 0; shift -= 8) (secondLow >> shift) & 0xff,
  ];
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return _uuidFromBytes(bytes);
}

(int, int) _multiplyFnv1a64(int high, int low) {
  const int twoTo32 = 0x100000000;
  const int primeLow = 0x1b3;
  const int primeHigh = 0x100;
  final int lowProduct = low * primeLow;
  final int nextLow = lowProduct % twoTo32;
  final int carry = lowProduct ~/ twoTo32;
  final int nextHigh = (high * primeLow + low * primeHigh + carry) % twoTo32;
  return (nextHigh, nextLow);
}

void _validatePayload(
  CloudSyncEntityType entityType,
  Map<String, Object?> payload,
) {
  CloudSyncMutation._validatePayload(entityType, payload);
}

String _uuidFromBytes(List<int> bytes) {
  final String hex =
      bytes.map((int value) => value.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

String _dateOnly(DateTime value) {
  final DateTime local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
