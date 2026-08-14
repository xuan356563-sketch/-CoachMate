import 'monthly_summary.dart';

/// 指标是否已经具备足够、可信且仍然有效的数据。
enum MetricStatus {
  ready,
  accumulating,
  unavailable,
  invalidated,
  failed,
}

enum LoadMethod {
  banisterTrimp,
  sessionRpe,
  durationEstimate,
}

extension LoadMethodCode on LoadMethod {
  String get code => switch (this) {
        LoadMethod.banisterTrimp => 'banister_trimp',
        LoadMethod.sessionRpe => 'session_rpe',
        LoadMethod.durationEstimate => 'duration_estimate',
      };
}

enum WorkoutDiscipline {
  roadRun,
  trailRun,
  strength,
  badminton,
  hyrox,
  other,
}

enum BiologicalSex {
  male,
  female,
  other,
  unknown,
}

enum MetricPeriod {
  day,
  week,
  month,
  quarter,
  year,
}

enum CompletionTargetKind {
  duration,
  distance,
  load,
  sets,
}

enum WorkoutCompletionStatus {
  pending,
  completed,
  partial,
  missed,
  needsReview,
  cancelled,
  notPlanned,
}

class PlannedWorkoutTarget {
  const PlannedWorkoutTarget({
    required this.planItemId,
    required this.scheduledAt,
    required this.discipline,
    required this.targets,
    required this.primaryTargetKind,
    this.cancelled = false,
    this.rescheduledTo,
  });

  final String planItemId;
  final DateTime scheduledAt;
  final WorkoutDiscipline discipline;
  final Map<CompletionTargetKind, double> targets;
  final CompletionTargetKind? primaryTargetKind;
  final bool cancelled;
  final DateTime? rescheduledTo;
}

class CompletedWorkoutFact {
  const CompletedWorkoutFact({
    required this.workoutId,
    required this.planItemId,
    required this.occurredAt,
    required this.discipline,
    required this.actualValues,
  });

  final String workoutId;
  final String? planItemId;
  final DateTime occurredAt;
  final WorkoutDiscipline discipline;
  final Map<CompletionTargetKind, double> actualValues;
}

class ScheduledWorkoutResult {
  const ScheduledWorkoutResult({
    required this.planItemId,
    required this.workoutId,
    required this.status,
    required this.completionRatio,
    required this.evaluatedAt,
    required this.algorithmVersion,
    required this.reason,
    this.manualStatus,
    this.manualReason,
  });

  final String? planItemId;
  final String? workoutId;
  final WorkoutCompletionStatus status;
  final double? completionRatio;
  final DateTime evaluatedAt;
  final String algorithmVersion;
  final String reason;
  final WorkoutCompletionStatus? manualStatus;
  final String? manualReason;

  WorkoutCompletionStatus get effectiveStatus => manualStatus ?? status;
}

class WeeklyConsistencyResult {
  const WeeklyConsistencyResult({
    required this.status,
    required this.value,
    required this.completedCount,
    required this.denominator,
    required this.reason,
  });

  final MetricStatus status;
  final double? value;
  final int completedCount;
  final int denominator;
  final String reason;
}

class TrainingLoadInput {
  const TrainingLoadInput({
    required this.workoutId,
    required this.occurredOn,
    required this.discipline,
    required this.durationMinutes,
    required this.rpe,
    required this.averageHeartRate,
    required this.restingHeartRate,
    required this.maxHeartRate,
    required this.heartRateCoverage,
    required this.biologicalSex,
  });

  final String workoutId;
  final DateTime occurredOn;
  final WorkoutDiscipline discipline;
  final double durationMinutes;
  final double? rpe;
  final double? averageHeartRate;
  final double? restingHeartRate;
  final double? maxHeartRate;
  final double heartRateCoverage;
  final BiologicalSex biologicalSex;
}

class TrainingLoadValue {
  const TrainingLoadValue({
    required this.workoutId,
    required this.occurredOn,
    required this.method,
    required this.value,
    this.durationMinutes = 0,
    required this.estimated,
    required this.coverage,
    required this.reason,
  });

  final String workoutId;
  final DateTime occurredOn;
  final LoadMethod method;
  final double value;

  /// 该负荷值所覆盖的实际训练时长，用于按时间计算数据覆盖率。
  ///
  /// 旧数据缺少该字段时保守视为 0 分钟，不以负荷值反推训练时长。
  final double durationMinutes;
  final bool estimated;
  final double coverage;
  final String reason;
}

class AcwrResult {
  const AcwrResult({
    required this.status,
    required this.method,
    required this.ratio,
    required this.acuteTotal,
    required this.chronicTotal,
    required this.coverage,
    required this.reason,
  });

  final MetricStatus status;
  final LoadMethod? method;
  final double? ratio;
  final double acuteTotal;
  final double chronicTotal;
  final double coverage;
  final String reason;

  String get loadStateLabel {
    final double? current = ratio;
    if (status != MetricStatus.ready || current == null) {
      return '负荷状态：数据积累中';
    }
    if (current < 0.8) return '负荷状态：恢复';
    if (current <= 1.3) return '负荷状态：适中';
    return '负荷状态：偏高';
  }
}

class MetricAggregate {
  const MetricAggregate({
    required this.id,
    required this.athleteProfileId,
    required this.metricCode,
    required this.period,
    required this.periodStart,
    required this.value,
    required this.unit,
    required this.sampleCount,
    required this.sampleDurationSeconds,
    required this.coverage,
    required this.status,
    required this.algorithmVersion,
    required this.inputFingerprint,
    required this.computedAt,
    this.loadMethod,
    this.baselineValue,
    this.invalidatedAt,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String athleteProfileId;
  final String metricCode;
  final MetricPeriod period;
  final DateTime periodStart;
  final double? value;
  final String unit;
  final int sampleCount;
  final int sampleDurationSeconds;
  final double coverage;
  final MetricStatus status;
  final String algorithmVersion;
  final String inputFingerprint;
  final DateTime computedAt;
  final LoadMethod? loadMethod;
  final double? baselineValue;
  final DateTime? invalidatedAt;
  final Map<String, Object?> metadata;

  MetricAggregate copyWith({
    double? value,
    MetricStatus? status,
    DateTime? invalidatedAt,
  }) {
    return MetricAggregate(
      id: id,
      athleteProfileId: athleteProfileId,
      metricCode: metricCode,
      period: period,
      periodStart: periodStart,
      value: value ?? this.value,
      unit: unit,
      sampleCount: sampleCount,
      sampleDurationSeconds: sampleDurationSeconds,
      coverage: coverage,
      status: status ?? this.status,
      algorithmVersion: algorithmVersion,
      inputFingerprint: inputFingerprint,
      computedAt: computedAt,
      loadMethod: loadMethod,
      baselineValue: baselineValue,
      invalidatedAt: invalidatedAt ?? this.invalidatedAt,
      metadata: metadata,
    );
  }
}

class MetricLineage {
  const MetricLineage({
    required this.metricId,
    required this.sourceType,
    required this.sourceId,
    required this.relationship,
    required this.createdAt,
    this.invalidatedAt,
  });

  final String metricId;
  final String sourceType;
  final String sourceId;
  final String relationship;
  final DateTime createdAt;
  final DateTime? invalidatedAt;
}

/// 报告生成时使用的指标不可变快照，避免当前指标投影更新后改写历史报告依据。
class ReportMetricSnapshot {
  ReportMetricSnapshot({
    required this.metricId,
    required this.metricCode,
    required this.value,
    required this.unit,
    required this.sampleCount,
    required this.sampleDurationSeconds,
    required this.coverage,
    required this.status,
    required this.algorithmVersion,
    required this.inputFingerprint,
    required this.computedAt,
    this.loadMethod,
    this.baselineValue,
    this.invalidatedAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : metadata = _freezeReportSnapshotMetadata(metadata);

  factory ReportMetricSnapshot.fromAggregate(MetricAggregate aggregate) {
    return ReportMetricSnapshot(
      metricId: aggregate.id,
      metricCode: aggregate.metricCode,
      value: aggregate.value,
      unit: aggregate.unit,
      sampleCount: aggregate.sampleCount,
      sampleDurationSeconds: aggregate.sampleDurationSeconds,
      coverage: aggregate.coverage,
      status: aggregate.status,
      algorithmVersion: aggregate.algorithmVersion,
      inputFingerprint: aggregate.inputFingerprint,
      computedAt: aggregate.computedAt,
      loadMethod: aggregate.loadMethod,
      baselineValue: aggregate.baselineValue,
      invalidatedAt: aggregate.invalidatedAt,
      metadata: Map<String, Object?>.unmodifiable(aggregate.metadata),
    );
  }

  final String metricId;
  final String metricCode;
  final double? value;
  final String unit;
  final int sampleCount;
  final int sampleDurationSeconds;
  final double coverage;
  final MetricStatus status;
  final String algorithmVersion;
  final String inputFingerprint;
  final DateTime computedAt;
  final LoadMethod? loadMethod;
  final double? baselineValue;
  final DateTime? invalidatedAt;
  final Map<String, Object?> metadata;
}

Map<String, Object?> _freezeReportSnapshotMetadata(
  Map<String, Object?> metadata,
) {
  return Map<String, Object?>.unmodifiable(
    metadata.map(
      (String key, Object? value) =>
          MapEntry<String, Object?>(key, _freezeReportSnapshotValue(value)),
    ),
  );
}

Object? _freezeReportSnapshotValue(Object? value) {
  if (value is Map) {
    return Map<Object?, Object?>.unmodifiable(
      value.map(
        (Object? key, Object? nestedValue) => MapEntry<Object?, Object?>(
          key,
          _freezeReportSnapshotValue(nestedValue),
        ),
      ),
    );
  }
  if (value is Iterable) {
    return List<Object?>.unmodifiable(
      value.map<Object?>(_freezeReportSnapshotValue),
    );
  }
  return value;
}

class ReportRevision {
  const ReportRevision({
    required this.id,
    required this.athleteProfileId,
    required this.period,
    required this.periodStart,
    required this.revision,
    required this.generatedAt,
    required this.metricIds,
    required this.narrative,
    required this.algorithmVersion,
    this.previousRevisionId,
    this.metricSnapshots = const <ReportMetricSnapshot>[],
    this.monthlySummarySnapshot,
  });

  final String id;
  final String athleteProfileId;
  final MetricPeriod period;
  final DateTime periodStart;
  final int revision;
  final DateTime generatedAt;
  final List<String> metricIds;
  final String narrative;
  final String algorithmVersion;
  final String? previousRevisionId;
  final List<ReportMetricSnapshot> metricSnapshots;
  final MonthlySummary? monthlySummarySnapshot;
}

enum AdjustmentProposalStatus {
  proposed,
  confirmed,
  rejected,
  undone,
}

/// 周总量建议中每个训练日的不可变差异快照。
class AdjustmentProposalWorkoutChange {
  const AdjustmentProposalWorkoutChange({
    required this.workoutDayId,
    required this.workoutTitle,
    required this.originalMinutes,
    required this.adjustedMinutes,
    required this.originalIntensity,
    required this.adjustedIntensity,
  });

  final String workoutDayId;
  final String workoutTitle;
  final int originalMinutes;
  final int adjustedMinutes;
  final String originalIntensity;
  final String adjustedIntensity;

  Map<String, Object?> toJson() => <String, Object?>{
        'workoutDayId': workoutDayId,
        'workoutTitle': workoutTitle,
        'originalMinutes': originalMinutes,
        'adjustedMinutes': adjustedMinutes,
        'originalIntensity': originalIntensity,
        'adjustedIntensity': adjustedIntensity,
      };

  factory AdjustmentProposalWorkoutChange.fromJson(
    Map<String, Object?> json,
  ) {
    return AdjustmentProposalWorkoutChange(
      workoutDayId: json['workoutDayId'] as String? ?? '',
      workoutTitle: json['workoutTitle'] as String? ?? '',
      originalMinutes: (json['originalMinutes'] as num?)?.toInt() ?? 0,
      adjustedMinutes: (json['adjustedMinutes'] as num?)?.toInt() ?? 0,
      originalIntensity: json['originalIntensity'] as String? ?? '',
      adjustedIntensity: json['adjustedIntensity'] as String? ?? '',
    );
  }
}

class AdjustmentProposal {
  const AdjustmentProposal({
    required this.id,
    required this.athleteProfileId,
    required this.planId,
    required this.workoutDayId,
    required this.workoutTitle,
    required this.triggerMetricCode,
    required this.triggerAlgorithmVersion,
    required this.explanation,
    required this.originalMinutes,
    required this.adjustedMinutes,
    required this.originalIntensity,
    required this.adjustedIntensity,
    required this.status,
    required this.createdAt,
    this.workoutChanges = const <AdjustmentProposalWorkoutChange>[],
    this.confirmedAt,
    this.rejectedAt,
    this.undoneAt,
  });

  final String id;
  final String athleteProfileId;
  final String planId;
  final String? workoutDayId;
  final String workoutTitle;
  final String triggerMetricCode;
  final String triggerAlgorithmVersion;
  final String explanation;
  final int originalMinutes;
  final int adjustedMinutes;
  final String originalIntensity;
  final String adjustedIntensity;
  final AdjustmentProposalStatus status;
  final DateTime createdAt;
  final List<AdjustmentProposalWorkoutChange> workoutChanges;
  final DateTime? confirmedAt;
  final DateTime? rejectedAt;
  final DateTime? undoneAt;

  AdjustmentProposal copyWith({
    AdjustmentProposalStatus? status,
    DateTime? confirmedAt,
    DateTime? rejectedAt,
    DateTime? undoneAt,
  }) {
    return AdjustmentProposal(
      id: id,
      athleteProfileId: athleteProfileId,
      planId: planId,
      workoutDayId: workoutDayId,
      workoutTitle: workoutTitle,
      triggerMetricCode: triggerMetricCode,
      triggerAlgorithmVersion: triggerAlgorithmVersion,
      explanation: explanation,
      originalMinutes: originalMinutes,
      adjustedMinutes: adjustedMinutes,
      originalIntensity: originalIntensity,
      adjustedIntensity: adjustedIntensity,
      status: status ?? this.status,
      createdAt: createdAt,
      workoutChanges: workoutChanges,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      undoneAt: undoneAt ?? this.undoneAt,
    );
  }
}

class HeartRateSample {
  const HeartRateSample({required this.timestamp, required this.bpm});

  final DateTime timestamp;
  final double bpm;
}

class HeartRateGridPoint {
  const HeartRateGridPoint({
    required this.timestamp,
    required this.bpm,
    required this.interpolated,
    required this.segmentIndex,
  });

  final DateTime timestamp;
  final double? bpm;
  final bool interpolated;
  final int segmentIndex;
}

class HeartRateProcessingResult {
  const HeartRateProcessingResult({
    required this.points,
    required this.rawSampleCount,
    required this.rejectedSampleCount,
    required this.rawCoverage,
  });

  final List<HeartRateGridPoint> points;
  final int rawSampleCount;
  final int rejectedSampleCount;
  final double rawCoverage;
}

class GpsSample {
  const GpsSample({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.horizontalAccuracyMeters,
    this.altitudeMeters,
    this.verticalAccuracyMeters,
  });

  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double horizontalAccuracyMeters;
  final double? altitudeMeters;
  final double? verticalAccuracyMeters;
}

class GapResult {
  const GapResult({
    required this.equivalentSpeedMetersPerSecond,
    required this.clampedGrade,
  });

  static const String modelName = 'TrainMate GAP v1';
  static const bool experimental = true;

  final double equivalentSpeedMetersPerSecond;
  final double clampedGrade;
}

class VamResult {
  const VamResult({
    required this.status,
    required this.metersPerHour,
    required this.label,
  });

  final MetricStatus status;
  final double? metersPerHour;
  final String label;
}

class PaceObservation {
  const PaceObservation({
    required this.sourceWorkoutId,
    required this.occurredAt,
    required this.paceSecondsPerKm,
    required this.durationSeconds,
    required this.isAerobic,
  });

  final String sourceWorkoutId;
  final DateTime occurredAt;
  final double paceSecondsPerKm;
  final int durationSeconds;
  final bool isAerobic;
}

class PaceReferenceBand {
  const PaceReferenceBand({
    required this.status,
    required this.centerSecondsPerKm,
    required this.lowerSecondsPerKm,
    required this.upperSecondsPerKm,
    required this.frozenAt,
    required this.expiresAt,
    required this.version,
    required this.sampleCount,
    required this.remainingSamples,
  });

  final MetricStatus status;
  final double? centerSecondsPerKm;
  final double? lowerSecondsPerKm;
  final double? upperSecondsPerKm;
  final DateTime frozenAt;
  final DateTime expiresAt;
  final String version;
  final int sampleCount;
  final int remainingSamples;

  bool contains(double paceSecondsPerKm) {
    final double? lower = lowerSecondsPerKm;
    final double? upper = upperSecondsPerKm;
    return status == MetricStatus.ready &&
        lower != null &&
        upper != null &&
        paceSecondsPerKm >= lower &&
        paceSecondsPerKm <= upper;
  }
}

class SteadyPaceSegment {
  const SteadyPaceSegment({
    required this.sourceWorkoutId,
    required this.occurredAt,
    required this.paceSecondsPerKm,
    required this.averageHeartRate,
    required this.heartRateCoverage,
    required this.durationSeconds,
    required this.grade,
    required this.paceCoefficientOfVariation,
    required this.warmupExcluded,
    required this.isAerobic,
  });

  final String sourceWorkoutId;
  final DateTime occurredAt;
  final double paceSecondsPerKm;
  final double averageHeartRate;
  final double heartRateCoverage;
  final int durationSeconds;
  final double grade;
  final double paceCoefficientOfVariation;
  final bool warmupExcluded;
  final bool isAerobic;
}

class L2MetricResult {
  const L2MetricResult({
    required this.status,
    required this.value,
    required this.unit,
    required this.validDurationSeconds,
    required this.remainingDurationSeconds,
    required this.reason,
  });

  final MetricStatus status;
  final double? value;
  final String unit;
  final int validDurationSeconds;
  final int remainingDurationSeconds;
  final String reason;
}

/// 单次训练内前后半段跑步效率因子的可比结果。
class AerobicDecouplingWorkoutResult {
  const AerobicDecouplingWorkoutResult({
    required this.sourceWorkoutId,
    required this.firstHalfEfficiencyFactor,
    required this.secondHalfEfficiencyFactor,
    required this.decouplingPercent,
    required this.validDurationSeconds,
    required this.heartRateCoverage,
  });

  final String sourceWorkoutId;
  final double firstHalfEfficiencyFactor;
  final double secondHalfEfficiencyFactor;
  final double decouplingPercent;
  final int validDurationSeconds;
  final double heartRateCoverage;
}

/// 周期内有氧解耦结果；每个值必须先在单次训练内完成前后半段比较。
class AerobicDecouplingResult {
  const AerobicDecouplingResult({
    required this.status,
    required this.value,
    required this.validDurationSeconds,
    required this.comparableDurationSeconds,
    required this.remainingDurationSeconds,
    required this.validSegmentCount,
    required this.heartRateCoverage,
    required this.reason,
    required this.workouts,
  });

  final MetricStatus status;
  final double? value;
  final int validDurationSeconds;
  final int comparableDurationSeconds;
  final int remainingDurationSeconds;
  final int validSegmentCount;
  final double heartRateCoverage;
  final String reason;
  final List<AerobicDecouplingWorkoutResult> workouts;
}

class BodyObservation {
  const BodyObservation({required this.measuredAt, required this.value});

  final DateTime measuredAt;
  final double value;
}

class SevenDayBodyAverageResult {
  const SevenDayBodyAverageResult({
    required this.status,
    required this.average,
    required this.dailyMedians,
    required this.validDayCount,
    required this.remainingDays,
  });

  final MetricStatus status;
  final double? average;
  final Map<DateTime, double> dailyMedians;
  final int validDayCount;
  final int remainingDays;
}

class DeviceBestSegment {
  const DeviceBestSegment({
    required this.sourceId,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.isOfficialRaceResult,
  });

  final String sourceId;
  final double distanceMeters;
  final int durationSeconds;
  final bool isOfficialRaceResult;

  String get displayName => isOfficialRaceResult ? '正式比赛 PB' : '设备记录最佳分段';
}
