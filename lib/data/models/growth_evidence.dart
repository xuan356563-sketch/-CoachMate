import 'dart:math' as math;

/// 成长事件的来源类型。事件只表达可追溯事实，不把模型估算伪装成生理检测结果。
enum GrowthEventType {
  training('training'),
  health('health');

  const GrowthEventType(this.jsonValue);

  final String jsonValue;

  String get label => switch (this) {
        GrowthEventType.training => '训练证据',
        GrowthEventType.health => '健康记录',
      };

  static GrowthEventType fromJson(String? value) {
    return GrowthEventType.values.firstWhere(
      (GrowthEventType item) => item.jsonValue == value,
      orElse: () => GrowthEventType.training,
    );
  }
}

/// XP 分量类型。排序即每日上限的稳定分配顺序。
enum GrowthXpComponentType {
  completion('completion'),
  dataQuality('dataQuality'),
  dailyHealth('dailyHealth'),
  safetyDecision('safetyDecision');

  const GrowthXpComponentType(this.jsonValue);

  final String jsonValue;

  String get label => switch (this) {
        GrowthXpComponentType.completion => '训练完成',
        GrowthXpComponentType.dataQuality => '数据完整',
        GrowthXpComponentType.dailyHealth => '健康记录',
        GrowthXpComponentType.safetyDecision => '安全决策',
      };

  static GrowthXpComponentType fromJson(String? value) {
    return GrowthXpComponentType.values.firstWhere(
      (GrowthXpComponentType item) => item.jsonValue == value,
      orElse: () => GrowthXpComponentType.completion,
    );
  }
}

enum GrowthConfidence {
  high('high', '高'),
  medium('medium', '中'),
  low('low', '低');

  const GrowthConfidence(this.jsonValue, this.label);

  final String jsonValue;
  final String label;

  static GrowthConfidence fromJson(String? value) {
    return GrowthConfidence.values.firstWhere(
      (GrowthConfidence item) => item.jsonValue == value,
      orElse: () => GrowthConfidence.low,
    );
  }
}

enum GrowthImpactDimension {
  aerobic('aerobic', '有氧刺激'),
  strength('strength', '力量刺激'),
  movementQuality('movement_quality', '动作质量'),
  recovery('recovery', '恢复支持'),
  raceReadiness('race_readiness', '比赛准备');

  const GrowthImpactDimension(this.jsonValue, this.label);

  final String jsonValue;
  final String label;

  static GrowthImpactDimension fromJson(String? value) {
    return GrowthImpactDimension.values.firstWhere(
      (GrowthImpactDimension item) => item.jsonValue == value,
      orElse: () => GrowthImpactDimension.aerobic,
    );
  }
}

class GrowthXpComponent {
  const GrowthXpComponent({
    required this.type,
    required this.amount,
    required this.reason,
  });

  final GrowthXpComponentType type;
  final int amount;
  final String reason;

  factory GrowthXpComponent.fromJson(Map<String, dynamic> json) {
    return GrowthXpComponent(
      type: GrowthXpComponentType.fromJson(json['type'] as String?),
      amount: ((json['amount'] as num?)?.round() ?? 0).clamp(0, 50).toInt(),
      reason: json['reason'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.jsonValue,
        'amount': amount,
        'reason': reason,
      };
}

class GrowthImpact {
  const GrowthImpact({
    required this.dimension,
    required this.points,
    required this.estimated,
    required this.reason,
  });

  final GrowthImpactDimension dimension;
  final double points;
  final bool estimated;
  final String reason;

  String get pointsLabel =>
      '+${points.toStringAsFixed(points % 1 == 0 ? 0 : 1)} 分';

  factory GrowthImpact.fromJson(Map<String, dynamic> json) {
    return GrowthImpact(
      dimension: GrowthImpactDimension.fromJson(json['dimension'] as String?),
      points: ((json['points'] as num?)?.toDouble() ?? 0).clamp(0, 20),
      estimated: json['estimated'] != false,
      reason: json['reason'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'dimension': dimension.jsonValue,
        'points': points,
        'estimated': estimated,
        'reason': reason,
      };
}

/// 在事件生成时固化的本地日期上下文，避免后续设备时区切换改变历史归属。
class GrowthOccurrence {
  const GrowthOccurrence({
    required this.occurredOn,
    required this.timeZoneOffsetMinutes,
    required this.timeZoneName,
  });

  final DateTime occurredOn;
  final int timeZoneOffsetMinutes;
  final String timeZoneName;
}

class GrowthEvidenceEvent {
  const GrowthEvidenceEvent({
    required this.eventId,
    required this.athleteProfileId,
    required this.eventType,
    required this.title,
    required this.description,
    required this.occurredAt,
    required this.occurredOn,
    required this.timeZoneOffsetMinutes,
    required this.timeZoneName,
    required this.sourceTable,
    required this.sourceId,
    required this.xpComponents,
    required this.impacts,
    required this.confidence,
    required this.missingData,
    required this.inputSnapshot,
    required this.modelVersion,
    required this.createdAt,
    required this.updatedAt,
    this.revokedAt,
  });

  final String eventId;
  final String athleteProfileId;
  final GrowthEventType eventType;
  final String title;
  final String description;
  final DateTime occurredAt;
  final DateTime occurredOn;
  final int timeZoneOffsetMinutes;
  final String timeZoneName;
  final String sourceTable;
  final String sourceId;
  final List<GrowthXpComponent> xpComponents;
  final List<GrowthImpact> impacts;
  final GrowthConfidence confidence;
  final List<String> missingData;
  final Map<String, dynamic> inputSnapshot;
  final int modelVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;
  bool get isActive => !isRevoked;

  int get rawXp => xpComponents.fold<int>(
        0,
        (int total, GrowthXpComponent component) => total + component.amount,
      );

  String get occurredOnKey => growthDateKey(occurredOn);

  GrowthEvidenceEvent copyWith({
    String? title,
    String? description,
    List<GrowthXpComponent>? xpComponents,
    List<GrowthImpact>? impacts,
    GrowthConfidence? confidence,
    List<String>? missingData,
    Map<String, dynamic>? inputSnapshot,
    DateTime? updatedAt,
    Object? revokedAt = _growthUnchanged,
  }) {
    return GrowthEvidenceEvent(
      eventId: eventId,
      athleteProfileId: athleteProfileId,
      eventType: eventType,
      title: title ?? this.title,
      description: description ?? this.description,
      occurredAt: occurredAt,
      occurredOn: occurredOn,
      timeZoneOffsetMinutes: timeZoneOffsetMinutes,
      timeZoneName: timeZoneName,
      sourceTable: sourceTable,
      sourceId: sourceId,
      xpComponents: xpComponents ?? this.xpComponents,
      impacts: impacts ?? this.impacts,
      confidence: confidence ?? this.confidence,
      missingData: missingData ?? this.missingData,
      inputSnapshot: inputSnapshot ?? this.inputSnapshot,
      modelVersion: modelVersion,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      revokedAt: identical(revokedAt, _growthUnchanged)
          ? this.revokedAt
          : revokedAt as DateTime?,
    );
  }

  factory GrowthEvidenceEvent.fromJson(Map<String, dynamic> json) {
    final List<dynamic> components =
        json['xpComponents'] as List<dynamic>? ?? const <dynamic>[];
    final List<dynamic> impacts =
        json['impacts'] as List<dynamic>? ?? const <dynamic>[];
    return GrowthEvidenceEvent(
      eventId: json['eventId'] as String? ?? '',
      athleteProfileId: json['athleteProfileId'] as String? ?? '',
      eventType: GrowthEventType.fromJson(json['eventType'] as String?),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      occurredAt: _parseDate(json['occurredAt']),
      occurredOn:
          _dateOnly(_parseDate(json['occurredOn'] ?? json['occurredAt'])),
      timeZoneOffsetMinutes:
          (json['timeZoneOffsetMinutes'] as num?)?.toInt() ?? 0,
      timeZoneName: json['timeZoneName'] as String? ?? '',
      sourceTable: json['sourceTable'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      xpComponents: List<GrowthXpComponent>.unmodifiable(
        components
            .whereType<Map<String, dynamic>>()
            .map(GrowthXpComponent.fromJson),
      ),
      impacts: List<GrowthImpact>.unmodifiable(
        impacts.whereType<Map<String, dynamic>>().map(GrowthImpact.fromJson),
      ),
      confidence: GrowthConfidence.fromJson(json['confidence'] as String?),
      missingData: List<String>.unmodifiable(
        (json['missingData'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>(),
      ),
      inputSnapshot: Map<String, dynamic>.from(
        json['inputSnapshot'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
      modelVersion: (json['modelVersion'] as num?)?.toInt() ?? 1,
      createdAt: _parseDate(json['createdAt'] ?? json['occurredAt']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['createdAt']),
      revokedAt: _tryParseDate(json['revokedAt']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'eventId': eventId,
        'athleteProfileId': athleteProfileId,
        'eventType': eventType.jsonValue,
        'title': title,
        'description': description,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'occurredOn': growthDateKey(occurredOn),
        'timeZoneOffsetMinutes': timeZoneOffsetMinutes,
        'timeZoneName': timeZoneName,
        'sourceTable': sourceTable,
        'sourceId': sourceId,
        'xpComponents': xpComponents
            .map((GrowthXpComponent component) => component.toJson())
            .toList(),
        'impacts':
            impacts.map((GrowthImpact impact) => impact.toJson()).toList(),
        'confidence': confidence.jsonValue,
        'missingData': missingData,
        'inputSnapshot': inputSnapshot,
        'modelVersion': modelVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'revokedAt': revokedAt?.toUtc().toIso8601String(),
      };
}

class DailyXpSettlement {
  const DailyXpSettlement({
    required this.occurredOn,
    required this.rawTotal,
    required this.awardedTotal,
    required this.awardsByEventId,
  });

  final DateTime occurredOn;
  final int rawTotal;
  final int awardedTotal;
  final Map<String, int> awardsByEventId;

  int awardFor(String eventId) => awardsByEventId[eventId] ?? 0;
}

class GrowthLevelState {
  const GrowthLevelState({
    required this.peakXp,
    required this.peakLevel,
    this.modelVersion = 1,
  });

  final int peakXp;
  final int peakLevel;
  final int modelVersion;

  factory GrowthLevelState.fromJson(Map<String, dynamic> json) {
    return GrowthLevelState(
      peakXp: (json['peakXp'] as num?)?.toInt() ?? 0,
      peakLevel: math.max(1, (json['peakLevel'] as num?)?.toInt() ?? 1),
      modelVersion: (json['modelVersion'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'peakXp': peakXp,
        'peakLevel': peakLevel,
        'modelVersion': modelVersion,
      };
}

class GrowthLevelProgress {
  const GrowthLevelProgress({
    required this.currentXp,
    required this.peakXp,
    required this.level,
    required this.nextLevelXp,
  });

  final int currentXp;
  final int peakXp;
  final int level;
  final int nextLevelXp;

  double get progress {
    if (nextLevelXp <= 0) return 0;
    return (currentXp / nextLevelXp).clamp(0, 1).toDouble();
  }

  String get label => 'Lv.$level';
}

class GrowthTask {
  const GrowthTask({
    required this.id,
    required this.title,
    required this.completed,
    required this.kind,
  });

  final String id;
  final String title;
  final bool completed;
  final String kind;
}

class GrowthMetricDelta {
  const GrowthMetricDelta({
    required this.label,
    required this.before,
    required this.after,
    required this.unit,
    required this.sourceLabel,
  });

  final String label;
  final double before;
  final double after;
  final String unit;
  final String sourceLabel;

  double get delta => after - before;
  String get labelValue =>
      '${before.toStringAsFixed(1)} → ${after.toStringAsFixed(1)}$unit';
}

class TrainingGrowthReceipt {
  const TrainingGrowthReceipt({
    required this.event,
    required this.awardedXp,
    required this.longTermMeaning,
    required this.message,
  });

  final GrowthEvidenceEvent event;
  final int awardedXp;
  final String longTermMeaning;
  final String message;
}

class GrowthDashboard {
  const GrowthDashboard({
    required this.growthDay,
    required this.level,
    required this.tasks,
    required this.impacts,
    required this.completedTaskCount,
    required this.totalTaskCount,
    required this.raceCountdownLabel,
    required this.growthStartEventId,
  });

  final int? growthDay;
  final GrowthLevelProgress level;
  final List<GrowthTask> tasks;
  final List<GrowthImpact> impacts;
  final int completedTaskCount;
  final int totalTaskCount;
  final String raceCountdownLabel;
  final String? growthStartEventId;

  double get completionRate => totalTaskCount == 0
      ? 0
      : (completedTaskCount / totalTaskCount).clamp(0, 1).toDouble();
}

class WeeklyGrowthReport {
  const WeeklyGrowthReport({
    required this.id,
    required this.athleteProfileId,
    required this.weekKey,
    required this.weekStartsOn,
    required this.weekEndsOn,
    required this.generatedAt,
    required this.lockedAt,
    required this.regeneratedAt,
    required this.consecutiveTrainingDays,
    required this.runningDistanceKm,
    required this.strengthSessionCount,
    required this.completionRate,
    required this.trainingLoad,
    required this.growthIndex,
    required this.availableIndexDimensions,
    required this.recoverySummary,
    required this.evidenceEventIds,
    required this.modelVersion,
  });

  final String id;
  final String athleteProfileId;
  final String weekKey;
  final DateTime weekStartsOn;
  final DateTime weekEndsOn;
  final DateTime generatedAt;
  final DateTime? lockedAt;
  final DateTime? regeneratedAt;
  final int consecutiveTrainingDays;
  final double runningDistanceKm;
  final int strengthSessionCount;
  final double completionRate;
  final double trainingLoad;
  final double? growthIndex;
  final int availableIndexDimensions;
  final String recoverySummary;
  final List<String> evidenceEventIds;
  final int modelVersion;

  bool get isLocked => lockedAt != null;
  String get completionRateLabel => '${(completionRate * 100).round()}%';
  double? get trainingExecutionIndex => growthIndex;
  String get trainingExecutionIndexLabel => trainingExecutionIndex == null
      ? '数据不足'
      : trainingExecutionIndex!.round().toString();

  @Deprecated('请使用 trainingExecutionIndexLabel。')
  String get growthIndexLabel => trainingExecutionIndexLabel;

  WeeklyGrowthReport copyWith({
    DateTime? generatedAt,
    Object? lockedAt = _growthUnchanged,
    Object? regeneratedAt = _growthUnchanged,
    int? consecutiveTrainingDays,
    double? runningDistanceKm,
    int? strengthSessionCount,
    double? completionRate,
    double? trainingLoad,
    Object? growthIndex = _growthUnchanged,
    int? availableIndexDimensions,
    String? recoverySummary,
    List<String>? evidenceEventIds,
    int? modelVersion,
  }) {
    return WeeklyGrowthReport(
      id: id,
      athleteProfileId: athleteProfileId,
      weekKey: weekKey,
      weekStartsOn: weekStartsOn,
      weekEndsOn: weekEndsOn,
      generatedAt: generatedAt ?? this.generatedAt,
      lockedAt: identical(lockedAt, _growthUnchanged)
          ? this.lockedAt
          : lockedAt as DateTime?,
      regeneratedAt: identical(regeneratedAt, _growthUnchanged)
          ? this.regeneratedAt
          : regeneratedAt as DateTime?,
      consecutiveTrainingDays:
          consecutiveTrainingDays ?? this.consecutiveTrainingDays,
      runningDistanceKm: runningDistanceKm ?? this.runningDistanceKm,
      strengthSessionCount: strengthSessionCount ?? this.strengthSessionCount,
      completionRate: completionRate ?? this.completionRate,
      trainingLoad: trainingLoad ?? this.trainingLoad,
      growthIndex: identical(growthIndex, _growthUnchanged)
          ? this.growthIndex
          : growthIndex as double?,
      availableIndexDimensions:
          availableIndexDimensions ?? this.availableIndexDimensions,
      recoverySummary: recoverySummary ?? this.recoverySummary,
      evidenceEventIds: evidenceEventIds ?? this.evidenceEventIds,
      modelVersion: modelVersion ?? this.modelVersion,
    );
  }

  factory WeeklyGrowthReport.fromJson(Map<String, dynamic> json) {
    return WeeklyGrowthReport(
      id: json['id'] as String? ?? '',
      athleteProfileId: json['athleteProfileId'] as String? ?? '',
      weekKey: json['weekKey'] as String? ?? '',
      weekStartsOn: _parseDate(json['weekStartsOn']),
      weekEndsOn: _parseDate(json['weekEndsOn']),
      generatedAt: _parseDate(json['generatedAt']),
      lockedAt: _tryParseDate(json['lockedAt']),
      regeneratedAt: _tryParseDate(json['regeneratedAt']),
      consecutiveTrainingDays:
          (json['consecutiveTrainingDays'] as num?)?.toInt() ?? 0,
      runningDistanceKm: (json['runningDistanceKm'] as num?)?.toDouble() ?? 0,
      strengthSessionCount:
          (json['strengthSessionCount'] as num?)?.toInt() ?? 0,
      completionRate: (json['completionRate'] as num?)?.toDouble() ?? 0,
      trainingLoad: (json['trainingLoad'] as num?)?.toDouble() ?? 0,
      growthIndex: (json['trainingExecutionIndex'] as num?)?.toDouble() ??
          (json['growthIndex'] as num?)?.toDouble(),
      availableIndexDimensions:
          (json['availableIndexDimensions'] as num?)?.toInt() ?? 0,
      recoverySummary: json['recoverySummary'] as String? ?? '数据不足',
      evidenceEventIds: List<String>.unmodifiable(
        (json['evidenceEventIds'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>(),
      ),
      modelVersion: (json['modelVersion'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'athleteProfileId': athleteProfileId,
        'weekKey': weekKey,
        'weekStartsOn': growthDateKey(weekStartsOn),
        'weekEndsOn': growthDateKey(weekEndsOn),
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'lockedAt': lockedAt?.toUtc().toIso8601String(),
        'regeneratedAt': regeneratedAt?.toUtc().toIso8601String(),
        'consecutiveTrainingDays': consecutiveTrainingDays,
        'runningDistanceKm': runningDistanceKm,
        'strengthSessionCount': strengthSessionCount,
        'completionRate': completionRate,
        'trainingLoad': trainingLoad,
        'trainingExecutionIndex': trainingExecutionIndex,
        // 迁移期继续写入旧键，确保旧版本应用仍能读取同一执行指标。
        'growthIndex': trainingExecutionIndex,
        'availableIndexDimensions': availableIndexDimensions,
        'recoverySummary': recoverySummary,
        'evidenceEventIds': evidenceEventIds,
        'modelVersion': modelVersion,
      };
}

const Object _growthUnchanged = Object();

String growthDateKey(DateTime value) {
  final DateTime date = _dateOnly(value);
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

DateTime growthDateFromKey(String value) {
  final DateTime? parsed = DateTime.tryParse(value);
  return parsed == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : _dateOnly(parsed);
}

DateTime growthWeekStart(DateTime value) {
  final DateTime date = _dateOnly(value);
  return DateTime(date.year, date.month, date.day - (date.weekday - 1));
}

DateTime growthAddCalendarDays(DateTime value, int days) {
  final DateTime date = _dateOnly(value);
  return DateTime(date.year, date.month, date.day + days);
}

bool growthIsSameDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _parseDate(Object? value) {
  return _tryParseDate(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _tryParseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
