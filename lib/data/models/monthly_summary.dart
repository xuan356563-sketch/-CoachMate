import 'weekly_report.dart';

enum MonthlyChangeState {
  improved,
  stable,
  mixed,
  needsAttention,
  accumulating,
}

enum MonthlySummaryDimension {
  trainingExecution,
  enduranceSpecialty,
  strength,
  recovery,
}

extension MonthlyChangeStateLabel on MonthlyChangeState {
  String get label => switch (this) {
        MonthlyChangeState.improved => '进步',
        MonthlyChangeState.stable => '稳定',
        MonthlyChangeState.mixed => '有变化',
        MonthlyChangeState.needsAttention => '需要关注',
        MonthlyChangeState.accumulating => '数据积累中',
      };
}

extension MonthlySummaryDimensionLabel on MonthlySummaryDimension {
  String get label => switch (this) {
        MonthlySummaryDimension.trainingExecution => '训练执行',
        MonthlySummaryDimension.enduranceSpecialty => '耐力 / 专项',
        MonthlySummaryDimension.strength => '力量',
        MonthlySummaryDimension.recovery => '恢复',
      };
}

class MonthlyMetricChange {
  const MonthlyMetricChange({
    required this.code,
    required this.label,
    required this.unit,
    required this.state,
    required this.directionIsNeutral,
    required this.currentValue,
    required this.previousValue,
    required this.firstWindowValue,
    required this.lastWindowValue,
    required this.monthOverMonthDelta,
    required this.withinMonthDelta,
    required this.validDayCount,
    required this.reason,
  });

  final String code;
  final String label;
  final String unit;
  final MonthlyChangeState state;
  final bool directionIsNeutral;
  final double? currentValue;
  final double? previousValue;
  final double? firstWindowValue;
  final double? lastWindowValue;
  final double? monthOverMonthDelta;
  final double? withinMonthDelta;
  final int validDayCount;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'label': label,
        'unit': unit,
        'state': state.name,
        'directionIsNeutral': directionIsNeutral,
        'currentValue': currentValue,
        'previousValue': previousValue,
        'firstWindowValue': firstWindowValue,
        'lastWindowValue': lastWindowValue,
        'monthOverMonthDelta': monthOverMonthDelta,
        'withinMonthDelta': withinMonthDelta,
        'validDayCount': validDayCount,
        'reason': reason,
      };

  factory MonthlyMetricChange.fromJson(Map<String, Object?> json) {
    return MonthlyMetricChange(
      code: json['code'] as String? ?? '',
      label: json['label'] as String? ?? '',
      unit: json['unit'] as String? ?? '',
      state: _enumByName(
        MonthlyChangeState.values,
        json['state'] as String?,
        MonthlyChangeState.accumulating,
      ),
      directionIsNeutral: json['directionIsNeutral'] as bool? ?? false,
      currentValue: (json['currentValue'] as num?)?.toDouble(),
      previousValue: (json['previousValue'] as num?)?.toDouble(),
      firstWindowValue: (json['firstWindowValue'] as num?)?.toDouble(),
      lastWindowValue: (json['lastWindowValue'] as num?)?.toDouble(),
      monthOverMonthDelta: (json['monthOverMonthDelta'] as num?)?.toDouble(),
      withinMonthDelta: (json['withinMonthDelta'] as num?)?.toDouble(),
      validDayCount: (json['validDayCount'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String? ?? '',
    );
  }
}

class MonthlyDimensionSummary {
  MonthlyDimensionSummary({
    required this.dimension,
    required this.state,
    required List<MonthlyMetricChange> metrics,
  }) : metrics = List<MonthlyMetricChange>.unmodifiable(metrics);

  final MonthlySummaryDimension dimension;
  final MonthlyChangeState state;
  final List<MonthlyMetricChange> metrics;

  Map<String, Object?> toJson() => <String, Object?>{
        'dimension': dimension.name,
        'state': state.name,
        'metrics': metrics
            .map((MonthlyMetricChange item) => item.toJson())
            .toList(growable: false),
      };

  factory MonthlyDimensionSummary.fromJson(Map<String, Object?> json) {
    final Object? rawMetrics = json['metrics'];
    return MonthlyDimensionSummary(
      dimension: _enumByName(
        MonthlySummaryDimension.values,
        json['dimension'] as String?,
        MonthlySummaryDimension.trainingExecution,
      ),
      state: _enumByName(
        MonthlyChangeState.values,
        json['state'] as String?,
        MonthlyChangeState.accumulating,
      ),
      metrics: rawMetrics is List
          ? rawMetrics
              .whereType<Map>()
              .map(
                (Map item) => MonthlyMetricChange.fromJson(
                  Map<String, Object?>.from(item),
                ),
              )
              .toList(growable: false)
          : const <MonthlyMetricChange>[],
    );
  }
}

class MonthlySummary {
  MonthlySummary({
    required this.monthStart,
    required this.previousMonthStart,
    required this.inputFingerprint,
    required List<MonthlyDimensionSummary> dimensions,
    required List<MonthlyMetricChange> bodyChanges,
    List<TrainingDimensionExposure> trainingDimensionExposure =
        const <TrainingDimensionExposure>[],
  })  : dimensions = List<MonthlyDimensionSummary>.unmodifiable(dimensions),
        bodyChanges = List<MonthlyMetricChange>.unmodifiable(bodyChanges),
        trainingDimensionExposure =
            List<TrainingDimensionExposure>.unmodifiable(
          trainingDimensionExposure,
        );

  final DateTime monthStart;
  final DateTime previousMonthStart;
  final String inputFingerprint;
  final List<MonthlyDimensionSummary> dimensions;
  final List<MonthlyMetricChange> bodyChanges;
  final List<TrainingDimensionExposure> trainingDimensionExposure;

  Map<String, Object?> toJson() => <String, Object?>{
        'monthStart': monthStart.toIso8601String(),
        'previousMonthStart': previousMonthStart.toIso8601String(),
        'inputFingerprint': inputFingerprint,
        'dimensions': dimensions
            .map((MonthlyDimensionSummary item) => item.toJson())
            .toList(growable: false),
        'bodyChanges': bodyChanges
            .map((MonthlyMetricChange item) => item.toJson())
            .toList(growable: false),
        'trainingDimensionExposure': trainingDimensionExposure
            .map((TrainingDimensionExposure item) => item.toJson())
            .toList(growable: false),
      };

  factory MonthlySummary.fromJson(Map<String, Object?> json) {
    return MonthlySummary(
      monthStart: _localDate(json['monthStart']) ?? DateTime(1970),
      previousMonthStart:
          _localDate(json['previousMonthStart']) ?? DateTime(1970),
      inputFingerprint: json['inputFingerprint'] as String? ?? '',
      dimensions: _objectList(json['dimensions'])
          .map(MonthlyDimensionSummary.fromJson)
          .toList(growable: false),
      bodyChanges: _objectList(json['bodyChanges'])
          .map(MonthlyMetricChange.fromJson)
          .toList(growable: false),
      trainingDimensionExposure: _objectList(json['trainingDimensionExposure'])
          .map(
            (Map<String, Object?> item) => TrainingDimensionExposure.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
    );
  }
}

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final T value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

DateTime? _localDate(Object? raw) {
  final DateTime? value = raw is String ? DateTime.tryParse(raw) : null;
  return value == null ? null : DateTime(value.year, value.month, value.day);
}

List<Map<String, Object?>> _objectList(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return raw
      .whereType<Map>()
      .map((Map item) => Map<String, Object?>.from(item))
      .toList(growable: false);
}
