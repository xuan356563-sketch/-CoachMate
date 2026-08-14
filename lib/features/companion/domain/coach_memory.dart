import 'coach_common.dart';

enum CoachMemoryCategory {
  preference,
  obstacle,
  effectiveStrategy,
  ritual,
  boundary,
  milestone;

  String get storageValue => switch (this) {
        CoachMemoryCategory.preference => 'preference',
        CoachMemoryCategory.obstacle => 'obstacle',
        CoachMemoryCategory.effectiveStrategy => 'effective_strategy',
        CoachMemoryCategory.ritual => 'ritual',
        CoachMemoryCategory.boundary => 'boundary',
        CoachMemoryCategory.milestone => 'milestone',
      };

  int get defaultRetentionDays => switch (this) {
        CoachMemoryCategory.preference || CoachMemoryCategory.ritual => 180,
        CoachMemoryCategory.obstacle ||
        CoachMemoryCategory.effectiveStrategy =>
          90,
        CoachMemoryCategory.milestone => 365,
        CoachMemoryCategory.boundary => 0,
      };
}

enum CoachMemorySensitivity { low, medium, high }

enum CoachMemoryStatus {
  candidate,
  readyForReview,
  active,
  superseded,
  deleted,
  expired;

  String get storageValue => switch (this) {
        CoachMemoryStatus.readyForReview => 'ready_for_review',
        _ => name,
      };
}

enum CoachMemoryValidityPolicy { expiresAt, untilRevoked }

enum CoachMemoryConfirmationBasis {
  none,
  explicitCommand,
  panelConfirmation;

  String get storageValue => switch (this) {
        CoachMemoryConfirmationBasis.explicitCommand => 'explicit_command',
        CoachMemoryConfirmationBasis.panelConfirmation => 'panel_confirmation',
        CoachMemoryConfirmationBasis.none => 'none',
      };
}

class CoachMemoryV1 {
  const CoachMemoryV1({
    required this.memoryId,
    required this.athleteProfileId,
    required this.category,
    required this.subject,
    required this.value,
    required this.displayText,
    required this.sources,
    required this.confidenceBps,
    required this.importanceBps,
    required this.sensitivity,
    required this.status,
    required this.version,
    required this.validityPolicy,
    required this.validFrom,
    required this.mayMention,
    required this.userConfirmed,
    required this.syncAllowed,
    required this.confirmationBasis,
    required this.createdAt,
    required this.updatedAt,
    this.validUntil,
    this.supersededBy,
    this.deletedAt,
    this.surfacedCount30d = 0,
  });

  final String memoryId;
  final String athleteProfileId;
  final CoachMemoryCategory category;
  final String subject;
  final Map<String, Object?> value;
  final String displayText;
  final List<CoachSourceRef> sources;
  final int confidenceBps;
  final int importanceBps;
  final CoachMemorySensitivity sensitivity;
  final CoachMemoryStatus status;
  final int version;
  final CoachMemoryValidityPolicy validityPolicy;
  final DateTime validFrom;
  final DateTime? validUntil;
  final bool mayMention;
  final bool userConfirmed;
  final bool syncAllowed;
  final CoachMemoryConfirmationBasis confirmationBasis;
  final String? supersededBy;
  final DateTime? deletedAt;
  final int surfacedCount30d;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CoachMemoryV1.fromJson(Map<String, Object?> json) {
    final List<Object?> sourceValues =
        (json['sources'] as List<Object?>?) ?? const <Object?>[];
    return CoachMemoryV1(
      memoryId: json['memory_id']! as String,
      athleteProfileId: json['athlete_profile_id']! as String,
      category: _memoryCategory(json['category']),
      subject: json['subject']! as String,
      value: Map<String, Object?>.from(json['value']! as Map),
      displayText: json['display_text']! as String,
      sources: sourceValues
          .map((Object? item) => CoachSourceRef.fromJson(
                Map<String, Object?>.from(item! as Map),
              ))
          .toList(growable: false),
      confidenceBps: json['confidence_bps']! as int,
      importanceBps: json['importance_bps']! as int,
      sensitivity: CoachMemorySensitivity.values.firstWhere(
        (CoachMemorySensitivity item) => item.name == json['sensitivity'],
      ),
      status: _memoryStatus(json['status']),
      version: json['version']! as int,
      validityPolicy: json['validity_policy'] == 'until_revoked'
          ? CoachMemoryValidityPolicy.untilRevoked
          : CoachMemoryValidityPolicy.expiresAt,
      validFrom: DateTime.parse(json['valid_from']! as String),
      validUntil: _optionalDate(json['valid_until']),
      mayMention: json['may_mention'] == true,
      userConfirmed: json['user_confirmed'] == true,
      syncAllowed: json['sync_allowed'] == true,
      confirmationBasis: _confirmationBasis(json['confirmation_basis']),
      supersededBy: json['superseded_by'] as String?,
      deletedAt: _optionalDate(json['deleted_at']),
      surfacedCount30d: (json['surfaced_count_30d'] as int?) ?? 0,
      createdAt: DateTime.parse(json['created_at']! as String),
      updatedAt: DateTime.parse(json['updated_at']! as String),
    );
  }

  List<String> validate({bool inferred = false}) {
    final List<String> issues = <String>[];
    if (memoryId.trim().isEmpty) issues.add('memory_id_required');
    if (athleteProfileId.trim().isEmpty) {
      issues.add('memory_athlete_required');
    }
    if (subject.trim().isEmpty) issues.add('memory_subject_required');
    if (displayText.length > 240) issues.add('memory_display_text_too_long');
    if (sources.isEmpty) issues.add('memory_source_required');
    for (final CoachSourceRef source in sources) {
      issues.addAll(source.validate());
    }
    if (inferred &&
        sources
                .map((CoachSourceRef item) => item.sourceLocalId)
                .toSet()
                .length <
            2) {
      issues.add('memory_distinct_evidence_required');
    }
    if (confidenceBps < 0 || confidenceBps > 10000) {
      issues.add('memory_confidence_invalid');
    }
    if (importanceBps < 0 || importanceBps > 10000) {
      issues.add('memory_importance_invalid');
    }
    if (version < 1) issues.add('memory_version_invalid');
    if (validityPolicy == CoachMemoryValidityPolicy.expiresAt &&
        validUntil == null) {
      issues.add('memory_valid_until_required');
    }
    if (validityPolicy == CoachMemoryValidityPolicy.untilRevoked &&
        category != CoachMemoryCategory.boundary) {
      issues.add('memory_until_revoked_boundary_only');
    }
    if (status == CoachMemoryStatus.active && !userConfirmed) {
      issues.add('memory_confirmation_required');
    }
    if (syncAllowed && (!userConfirmed || status != CoachMemoryStatus.active)) {
      issues.add('memory_sync_requires_confirmed_active');
    }
    return issues.toSet().toList(growable: false);
  }

  bool isUsable(DateTime now) {
    if (validate().isNotEmpty ||
        status != CoachMemoryStatus.active ||
        !userConfirmed ||
        deletedAt != null ||
        now.isBefore(validFrom)) {
      return false;
    }
    return validUntil == null || now.isBefore(validUntil!);
  }

  CoachMemoryV1 copyWith({
    String? memoryId,
    CoachMemoryStatus? status,
    int? version,
    DateTime? validUntil,
    bool? mayMention,
    bool? userConfirmed,
    bool? syncAllowed,
    CoachMemoryConfirmationBasis? confirmationBasis,
    String? supersededBy,
    DateTime? deletedAt,
    int? importanceBps,
    DateTime? updatedAt,
    DateTime? validFrom,
    DateTime? createdAt,
    Map<String, Object?>? value,
    String? displayText,
    List<CoachSourceRef>? sources,
  }) {
    return CoachMemoryV1(
      memoryId: memoryId ?? this.memoryId,
      athleteProfileId: athleteProfileId,
      category: category,
      subject: subject,
      value: value ?? this.value,
      displayText: displayText ?? this.displayText,
      sources: sources ?? this.sources,
      confidenceBps: confidenceBps,
      importanceBps: importanceBps ?? this.importanceBps,
      sensitivity: sensitivity,
      status: status ?? this.status,
      version: version ?? this.version,
      validityPolicy: validityPolicy,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
      mayMention: mayMention ?? this.mayMention,
      userConfirmed: userConfirmed ?? this.userConfirmed,
      syncAllowed: syncAllowed ?? this.syncAllowed,
      confirmationBasis: confirmationBasis ?? this.confirmationBasis,
      supersededBy: supersededBy ?? this.supersededBy,
      deletedAt: deletedAt ?? this.deletedAt,
      surfacedCount30d: surfacedCount30d,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'memory_id': memoryId,
        'athlete_profile_id': athleteProfileId,
        'category': category.storageValue,
        'subject': subject,
        'value': value,
        'display_text': displayText,
        'sources': sources.map((CoachSourceRef item) => item.toJson()).toList(),
        'confidence_bps': confidenceBps,
        'importance_bps': importanceBps,
        'sensitivity': sensitivity.name,
        'status': status.storageValue,
        'version': version,
        'validity_policy': validityPolicy == CoachMemoryValidityPolicy.expiresAt
            ? 'expires_at'
            : 'until_revoked',
        'valid_from': validFrom.toUtc().toIso8601String(),
        'valid_until': validUntil?.toUtc().toIso8601String(),
        'may_mention': mayMention,
        'user_confirmed': userConfirmed,
        'sync_allowed': syncAllowed,
        'confirmation_basis': confirmationBasis.storageValue,
        'superseded_by': supersededBy,
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'surfaced_count_30d': surfacedCount30d,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}

class CoachMemoryRetrieval {
  const CoachMemoryRetrieval({
    required this.decisionMemories,
    required this.surfaceableMemories,
  });

  final List<CoachMemoryV1> decisionMemories;
  final List<CoachMemoryV1> surfaceableMemories;
}

CoachMemoryCategory _memoryCategory(Object? raw) {
  return CoachMemoryCategory.values.firstWhere(
    (CoachMemoryCategory item) => item.storageValue == raw,
    orElse: () => throw const CoachContractException(
      'memory_category_invalid',
      '记忆类别不在允许列表中。',
    ),
  );
}

CoachMemoryStatus _memoryStatus(Object? raw) {
  return CoachMemoryStatus.values.firstWhere(
    (CoachMemoryStatus item) => item.storageValue == raw,
    orElse: () => throw const CoachContractException(
      'memory_status_invalid',
      '记忆状态无效。',
    ),
  );
}

CoachMemoryConfirmationBasis _confirmationBasis(Object? raw) {
  return CoachMemoryConfirmationBasis.values.firstWhere(
    (CoachMemoryConfirmationBasis item) => item.storageValue == raw,
    orElse: () => CoachMemoryConfirmationBasis.none,
  );
}

DateTime? _optionalDate(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.parse(value) : null;

/// 精选记忆检索器：无论调用方传入多少记录，权限边界都在这里收口。
class CoachMemoryRetriever {
  const CoachMemoryRetriever();

  CoachMemoryRetrieval retrieve({
    required List<CoachMemoryV1> memories,
    required DateTime now,
    Set<CoachMemoryCategory>? categories,
  }) {
    final List<CoachMemoryV1> selected = memories
        .where((CoachMemoryV1 item) => item.isUsable(now))
        .where((CoachMemoryV1 item) =>
            categories == null || categories.contains(item.category))
        .toList(growable: false)
      ..sort((CoachMemoryV1 left, CoachMemoryV1 right) {
        final int importance =
            right.importanceBps.compareTo(left.importanceBps);
        if (importance != 0) return importance;
        final int confidence =
            right.confidenceBps.compareTo(left.confidenceBps);
        if (confidence != 0) return confidence;
        return right.updatedAt.compareTo(left.updatedAt);
      });
    final List<CoachMemoryV1> decision =
        selected.take(6).toList(growable: false);
    final List<CoachMemoryV1> surfaced = decision
        .where((CoachMemoryV1 item) => item.mayMention)
        .take(2)
        .toList(growable: false);
    return CoachMemoryRetrieval(
      decisionMemories: decision,
      surfaceableMemories: surfaced,
    );
  }
}
