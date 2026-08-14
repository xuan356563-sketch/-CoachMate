import 'dart:convert';

import '../data/models/body_metric.dart';
import '../data/models/exercise_training_profile.dart';
import '../data/models/health_snapshot.dart';
import '../data/models/monthly_summary.dart';
import '../data/models/training_metrics.dart';
import '../data/models/weekly_report.dart';

/// 基于设备内结构化记录生成上一完整自然月的确定性总结。
class MonthlySummaryBuilder {
  const MonthlySummaryBuilder();

  static const int minimumBodyDays = 3;

  MonthlySummary build({
    required String athleteProfileId,
    required DateTime monthStart,
    required List<MetricAggregate> metricHistory,
    required List<BodyMetric> bodyMetrics,
    required List<HealthSnapshot> healthSnapshots,
    required List<WeeklyReport> weeklyReports,
  }) {
    final DateTime target = DateTime(monthStart.year, monthStart.month);
    final DateTime previous = DateTime(target.year, target.month - 1);
    final Map<DateTime, Map<String, double>> daily = _mergeBodySources(
      bodyMetrics,
      healthSnapshots,
    );
    final List<MonthlyMetricChange> bodyChanges = <MonthlyMetricChange>[
      _bodyChange(daily, target, previous, _bodyDefinitions[0]),
      _bodyChange(daily, target, previous, _bodyDefinitions[1]),
      _bodyChange(daily, target, previous, _bodyDefinitions[2]),
      _bodyChange(daily, target, previous, _bodyDefinitions[3]),
      _bodyChange(daily, target, previous, _bodyDefinitions[4]),
      _bodyChange(daily, target, previous, _bodyDefinitions[5]),
    ];
    final MonthlyMetricChange completion = _completionChange(
      weeklyReports,
      target,
      previous,
    );
    final MonthlyMetricChange endurance = _aggregateChange(
      metricHistory,
      target,
      previous,
      code: 'same_pace_heart_rate',
      label: '同配速心率',
      unit: 'bpm',
      threshold: 2,
      lowerIsBetter: true,
    );
    final MonthlyMetricChange strength = _aggregateChange(
      metricHistory,
      target,
      previous,
      code: 'strength_e1rm',
      label: '主力动作 e1RM',
      unit: 'kg',
      threshold: 0.02,
      relativeThreshold: true,
    );
    final MonthlyMetricChange specialty = _aggregateChange(
      metricHistory,
      target,
      previous,
      code: 'badminton_consistency',
      label: '专项训练次数',
      unit: '次',
      threshold: 1,
      neutral: true,
    );
    final bool hasRisk = weeklyReports.any(
      (WeeklyReport report) =>
          _isInMonth(report.generatedAt, target) &&
          report.psychRiskLevel.name != 'normal',
    );
    final List<MonthlyMetricChange> recovery = bodyChanges
        .where(
          (MonthlyMetricChange item) =>
              item.code == 'restingHeartRate' ||
              item.code == 'hrv' ||
              item.code == 'sleep' ||
              item.code == 'fatigue',
        )
        .toList(growable: false);
    final List<MonthlyDimensionSummary> dimensions = <MonthlyDimensionSummary>[
      MonthlyDimensionSummary(
        dimension: MonthlySummaryDimension.trainingExecution,
        state: _dimensionState(<MonthlyMetricChange>[completion]),
        metrics: <MonthlyMetricChange>[completion],
      ),
      MonthlyDimensionSummary(
        dimension: MonthlySummaryDimension.enduranceSpecialty,
        state: _dimensionState(<MonthlyMetricChange>[endurance, specialty]),
        metrics: <MonthlyMetricChange>[endurance, specialty],
      ),
      MonthlyDimensionSummary(
        dimension: MonthlySummaryDimension.strength,
        state: _dimensionState(<MonthlyMetricChange>[strength]),
        metrics: <MonthlyMetricChange>[strength],
      ),
      MonthlyDimensionSummary(
        dimension: MonthlySummaryDimension.recovery,
        state: hasRisk
            ? MonthlyChangeState.needsAttention
            : _dimensionState(recovery),
        metrics: recovery,
      ),
    ];
    return MonthlySummary(
      monthStart: target,
      previousMonthStart: previous,
      inputFingerprint: _fingerprint(<String>[
        athleteProfileId,
        _dateKey(target),
        ...metricHistory.map(
          (MetricAggregate item) =>
              '${item.id}:${item.inputFingerprint}:${item.status.name}',
        ),
        ...bodyMetrics.map(
          (BodyMetric item) =>
              '${item.id}:${item.measuredAt.toIso8601String()}:${item.toJson()}',
        ),
        ...healthSnapshots.map(
          (HealthSnapshot item) =>
              '${item.id}:${item.syncedAt.toIso8601String()}:${item.toJson()}',
        ),
        ...weeklyReports.map(
          (WeeklyReport item) =>
              '${item.id}:${item.generatedAt.toIso8601String()}:${item.completedWorkouts}:${item.plannedWorkouts}:${item.psychRiskLevel.name}:${item.dimensionExposure.map((TrainingDimensionExposure exposure) => exposure.toJson()).toList()}',
        ),
      ]),
      dimensions: dimensions,
      bodyChanges: bodyChanges,
      trainingDimensionExposure: _monthlyDimensionExposure(
        weeklyReports,
        target,
      ),
    );
  }

  List<TrainingDimensionExposure> _monthlyDimensionExposure(
    List<WeeklyReport> reports,
    DateTime target,
  ) {
    final Map<String, int> planned = <String, int>{};
    final Map<String, int> completed = <String, int>{};
    for (final WeeklyReport report in reports.where(
      (WeeklyReport item) => _isInMonth(item.generatedAt, target),
    )) {
      for (final TrainingDimensionExposure exposure
          in report.dimensionExposure) {
        final String code = exposure.dimension.jsonValue;
        planned.update(code, (int value) => value + exposure.plannedSessions,
            ifAbsent: () => exposure.plannedSessions);
        completed.update(
          code,
          (int value) => value + exposure.completedSessions,
          ifAbsent: () => exposure.completedSessions,
        );
      }
    }
    return <TrainingDimensionExposure>[
      for (final TrainingDimension dimension in TrainingDimension.values)
        TrainingDimensionExposure(
          dimension: dimension,
          plannedSessions: planned[dimension.jsonValue] ?? 0,
          completedSessions: completed[dimension.jsonValue] ?? 0,
        ),
    ];
  }

  MonthlyMetricChange _completionChange(
    List<WeeklyReport> reports,
    DateTime target,
    DateTime previous,
  ) {
    final List<WeeklyReport> current = reports
        .where((WeeklyReport item) => _isInMonth(item.generatedAt, target))
        .toList()
      ..sort((WeeklyReport a, WeeklyReport b) =>
          a.generatedAt.compareTo(b.generatedAt));
    final List<WeeklyReport> before = reports
        .where((WeeklyReport item) => _isInMonth(item.generatedAt, previous))
        .toList();
    final double? currentValue = _weightedCompletion(current);
    final double? previousValue = _weightedCompletion(before);
    final double? first = current.isEmpty ? null : current.first.completionRate;
    final double? last = current.isEmpty ? null : current.last.completionRate;
    return _change(
      code: 'completionRate',
      label: '训练完成率',
      unit: '%',
      threshold: 0.05,
      lowerIsBetter: false,
      neutral: false,
      current: currentValue,
      previous: previousValue,
      first: first,
      last: last,
      samples: current.length,
      insufficientReason: '本月尚无可用周训练执行记录。',
    );
  }

  MonthlyMetricChange _aggregateChange(
    List<MetricAggregate> metrics,
    DateTime target,
    DateTime previous, {
    required String code,
    required String label,
    required String unit,
    required double threshold,
    bool lowerIsBetter = false,
    bool relativeThreshold = false,
    bool neutral = false,
  }) {
    final List<MetricAggregate> all = metrics
        .where(
          (MetricAggregate item) =>
              item.metricCode == code &&
              item.status == MetricStatus.ready &&
              item.invalidatedAt == null &&
              item.value != null,
        )
        .toList()
      ..sort((MetricAggregate a, MetricAggregate b) =>
          a.periodStart.compareTo(b.periodStart));
    final List<MetricAggregate> current = all
        .where((MetricAggregate item) => _isInMonth(item.periodStart, target))
        .toList();
    final List<MetricAggregate> before = all
        .where((MetricAggregate item) => _isInMonth(item.periodStart, previous))
        .toList();
    if (current.isEmpty) {
      return _accumulating(code, label, unit, '本月指标尚未达到解释门槛。');
    }
    final String key = _comparisonKey(current.last);
    final List<MetricAggregate> compatibleCurrent = current
        .where((MetricAggregate item) => _comparisonKey(item) == key)
        .toList();
    final List<MetricAggregate> compatibleBefore = before
        .where((MetricAggregate item) => _comparisonKey(item) == key)
        .toList();
    if (before.isNotEmpty && compatibleBefore.isEmpty) {
      return _accumulating(
        code,
        label,
        unit,
        '算法版本、负荷口径或主力动作发生变化，暂不跨口径比较。',
      );
    }
    final double currentValue = _averageAggregates(compatibleCurrent);
    final double? previousValue =
        compatibleBefore.isEmpty ? null : _averageAggregates(compatibleBefore);
    final double effectiveThreshold = relativeThreshold
        ? ((previousValue ?? currentValue).abs() * threshold)
        : threshold;
    return _change(
      code: code,
      label: label,
      unit: unit,
      threshold: effectiveThreshold,
      lowerIsBetter: lowerIsBetter,
      neutral: neutral,
      current: currentValue,
      previous: previousValue,
      first: compatibleCurrent.first.value,
      last: compatibleCurrent.last.value,
      samples: compatibleCurrent.length,
      insufficientReason: '指标仍在积累。',
    );
  }

  MonthlyMetricChange _bodyChange(
    Map<DateTime, Map<String, double>> daily,
    DateTime target,
    DateTime previous,
    _BodyDefinition definition,
  ) {
    final List<_DailyValue> current =
        _dailyValues(daily, target, definition.code);
    final List<_DailyValue> before =
        _dailyValues(daily, previous, definition.code);
    final double? first = _windowAverage(current, fromStart: true);
    final double? last = _windowAverage(current, fromStart: false);
    final double? previousLast = _windowAverage(before, fromStart: false);
    if (first == null || last == null) {
      return _accumulating(
        definition.code,
        definition.label,
        definition.unit,
        '首尾窗口各需至少 $minimumBodyDays 个有效日；当前有效日 ${current.length} 个。',
        samples: current.length,
        neutral: definition.neutral,
      );
    }
    final double effectiveThreshold = definition.relativeThreshold == null
        ? definition.threshold
        : (previousLast ?? last).abs() * definition.relativeThreshold!;
    return _change(
      code: definition.code,
      label: definition.label,
      unit: definition.unit,
      threshold: effectiveThreshold,
      lowerIsBetter: definition.lowerIsBetter,
      neutral: definition.neutral,
      current: last,
      previous: previousLast,
      first: first,
      last: last,
      samples: current.length,
      insufficientReason: '身体数据仍在积累。',
    );
  }

  MonthlyMetricChange _change({
    required String code,
    required String label,
    required String unit,
    required double threshold,
    required bool lowerIsBetter,
    required bool neutral,
    required double? current,
    required double? previous,
    required double? first,
    required double? last,
    required int samples,
    required String insufficientReason,
  }) {
    if (current == null || last == null) {
      return _accumulating(
        code,
        label,
        unit,
        insufficientReason,
        samples: samples,
        neutral: neutral,
      );
    }
    final double? monthDelta = previous == null ? null : current - previous;
    final double? withinDelta = first == null ? null : last - first;
    final List<int> signals = <int>[
      if (monthDelta != null) _signal(monthDelta, threshold, lowerIsBetter),
      if (withinDelta != null) _signal(withinDelta, threshold, lowerIsBetter),
    ];
    MonthlyChangeState state;
    if (neutral) {
      state = signals.any((int value) => value != 0)
          ? MonthlyChangeState.mixed
          : MonthlyChangeState.stable;
    } else if (signals.isEmpty) {
      state = MonthlyChangeState.accumulating;
    } else if (signals.contains(1) && signals.contains(-1)) {
      state = MonthlyChangeState.mixed;
    } else if (signals.contains(1)) {
      state = MonthlyChangeState.improved;
    } else {
      state = MonthlyChangeState.stable;
    }
    return MonthlyMetricChange(
      code: code,
      label: label,
      unit: unit,
      state: state,
      directionIsNeutral: neutral,
      currentValue: current,
      previousValue: previous,
      firstWindowValue: first,
      lastWindowValue: last,
      monthOverMonthDelta: monthDelta,
      withinMonthDelta: withinDelta,
      validDayCount: samples,
      reason: previous == null
          ? '上月同口径样本不足，仅展示本月月内变化。'
          : neutral
              ? '仅描述数值变化，不判断好坏。'
              : '变化仅按固定阈值解释，不替代训练或医疗判断。',
    );
  }

  MonthlyMetricChange _accumulating(
    String code,
    String label,
    String unit,
    String reason, {
    int samples = 0,
    bool neutral = false,
  }) {
    return MonthlyMetricChange(
      code: code,
      label: label,
      unit: unit,
      state: MonthlyChangeState.accumulating,
      directionIsNeutral: neutral,
      currentValue: null,
      previousValue: null,
      firstWindowValue: null,
      lastWindowValue: null,
      monthOverMonthDelta: null,
      withinMonthDelta: null,
      validDayCount: samples,
      reason: reason,
    );
  }
}

const List<_BodyDefinition> _bodyDefinitions = <_BodyDefinition>[
  _BodyDefinition('weight', '体重', 'kg', 0.5, neutral: true),
  _BodyDefinition('bodyFat', '体脂率', '%', 0.5, neutral: true),
  _BodyDefinition(
    'restingHeartRate',
    '静息心率',
    'bpm',
    3,
    lowerIsBetter: true,
  ),
  _BodyDefinition('hrv', 'HRV', 'ms', 3, relativeThreshold: 0.05),
  _BodyDefinition('sleep', '睡眠', '小时', 0.3),
  _BodyDefinition('fatigue', '疲劳', '分', 1, lowerIsBetter: true),
];

class _BodyDefinition {
  const _BodyDefinition(
    this.code,
    this.label,
    this.unit,
    this.threshold, {
    this.lowerIsBetter = false,
    this.neutral = false,
    this.relativeThreshold,
  });

  final String code;
  final String label;
  final String unit;
  final double threshold;
  final bool lowerIsBetter;
  final bool neutral;
  final double? relativeThreshold;
}

class _DailyValue {
  const _DailyValue(this.date, this.value);

  final DateTime date;
  final double value;
}

Map<DateTime, Map<String, double>> _mergeBodySources(
  List<BodyMetric> bodyMetrics,
  List<HealthSnapshot> healthSnapshots,
) {
  final Map<DateTime, Map<String, double>> result =
      <DateTime, Map<String, double>>{};
  for (final HealthSnapshot item in healthSnapshots) {
    final Map<String, double> values =
        result.putIfAbsent(_date(item.date), () => <String, double>{});
    _putValid(values, 'weight', item.weightKg);
    _putValid(values, 'bodyFat', item.bodyFatPercentage);
    _putValid(values, 'restingHeartRate', item.restingHeartRate?.toDouble());
    _putValid(values, 'hrv', item.hrvMs?.toDouble());
    _putValid(values, 'sleep', item.sleepHours);
  }
  for (final BodyMetric item in bodyMetrics) {
    final Map<String, double> values =
        result.putIfAbsent(_date(item.measuredAt), () => <String, double>{});
    _putValid(values, 'weight', item.weightKg, overwrite: true);
    _putValid(values, 'bodyFat', item.bodyFatPercentage, overwrite: true);
    _putValid(
      values,
      'restingHeartRate',
      item.restingHeartRate.toDouble(),
      overwrite: true,
    );
    _putValid(values, 'hrv', item.hrvMs.toDouble(), overwrite: true);
    _putValid(values, 'sleep', item.sleepHours, overwrite: true);
    _putValid(
      values,
      'fatigue',
      item.fatigueLevel.toDouble(),
      overwrite: true,
    );
  }
  return result;
}

void _putValid(
  Map<String, double> values,
  String key,
  double? value, {
  bool overwrite = false,
}) {
  if (value == null || !value.isFinite || value <= 0) return;
  if (overwrite || !values.containsKey(key)) values[key] = value;
}

List<_DailyValue> _dailyValues(
  Map<DateTime, Map<String, double>> daily,
  DateTime month,
  String code,
) {
  final List<_DailyValue> values = daily.entries
      .where((MapEntry<DateTime, Map<String, double>> entry) =>
          _isInMonth(entry.key, month) && entry.value[code] != null)
      .map(
        (MapEntry<DateTime, Map<String, double>> entry) =>
            _DailyValue(entry.key, entry.value[code]!),
      )
      .toList()
    ..sort((_DailyValue a, _DailyValue b) => a.date.compareTo(b.date));
  return values;
}

double? _windowAverage(List<_DailyValue> values, {required bool fromStart}) {
  if (values.isEmpty) return null;
  final DateTime boundary = fromStart
      ? values.first.date.add(const Duration(days: 6))
      : values.last.date.subtract(const Duration(days: 6));
  final List<double> window = values
      .where((_DailyValue item) => fromStart
          ? !item.date.isAfter(boundary)
          : !item.date.isBefore(boundary))
      .map((_DailyValue item) => item.value)
      .toList(growable: false);
  if (window.length < MonthlySummaryBuilder.minimumBodyDays) return null;
  return window.reduce((double a, double b) => a + b) / window.length;
}

double? _weightedCompletion(List<WeeklyReport> reports) {
  final int planned = reports.fold<int>(
    0,
    (int total, WeeklyReport item) => total + item.plannedWorkouts,
  );
  if (planned <= 0) return null;
  final int completed = reports.fold<int>(
    0,
    (int total, WeeklyReport item) => total + item.completedWorkouts,
  );
  return completed / planned;
}

double _averageAggregates(List<MetricAggregate> values) {
  return values
          .map((MetricAggregate item) => item.value!)
          .reduce((double a, double b) => a + b) /
      values.length;
}

String _comparisonKey(MetricAggregate item) {
  final Object? exercise =
      item.metadata['exerciseKey'] ?? item.metadata['primaryExerciseKey'];
  return '${item.algorithmVersion}|${item.loadMethod?.code ?? ''}|${exercise ?? ''}';
}

int _signal(double delta, double threshold, bool lowerIsBetter) {
  if (delta.abs() < threshold) return 0;
  final bool improved = lowerIsBetter ? delta < 0 : delta > 0;
  return improved ? 1 : -1;
}

MonthlyChangeState _dimensionState(List<MonthlyMetricChange> metrics) {
  if (metrics.every(
    (MonthlyMetricChange item) => item.state == MonthlyChangeState.accumulating,
  )) {
    return MonthlyChangeState.accumulating;
  }
  if (metrics.any(
    (MonthlyMetricChange item) =>
        item.state == MonthlyChangeState.needsAttention,
  )) {
    return MonthlyChangeState.needsAttention;
  }
  final bool improved = metrics.any(
    (MonthlyMetricChange item) => item.state == MonthlyChangeState.improved,
  );
  final bool mixed = metrics.any(
    (MonthlyMetricChange item) => item.state == MonthlyChangeState.mixed,
  );
  return improved && !mixed
      ? MonthlyChangeState.improved
      : mixed
          ? MonthlyChangeState.mixed
          : MonthlyChangeState.stable;
}

bool _isInMonth(DateTime value, DateTime month) =>
    value.year == month.year && value.month == month.month;

DateTime _date(DateTime value) => DateTime(value.year, value.month, value.day);

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';

String _fingerprint(List<String> parts) {
  final List<String> sorted = List<String>.from(parts)..sort();
  int hash = 5381;
  for (final int byte in utf8.encode(sorted.join('\u0000'))) {
    hash = (((hash << 5) + hash) ^ byte) & 0x7fffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
