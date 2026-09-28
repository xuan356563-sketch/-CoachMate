import '../data/models/body_metric.dart';

/// 仅供身体摘要和图表读取，不参与训练处方或准备度计算。
enum BodyMetricDisplayField {
  weight('weightKg', '体重', 'kg'),
  heartRate('restingHeartRate', '静息心率', 'bpm'),
  hrv('hrvMs', 'HRV', 'ms'),
  sleep('sleepHours', '睡眠', 'h'),
  fatigue('fatigueLevel', '疲劳', '/10');

  const BodyMetricDisplayField(this.key, this.label, this.unit);
  final String key;
  final String label;
  final String unit;

  double value(BodyMetric metric) => switch (this) {
        weight => metric.weightKg,
        heartRate => metric.restingHeartRate.toDouble(),
        hrv => metric.hrvMs.toDouble(),
        sleep => metric.sleepHours,
        fatigue => metric.fatigueLevel.toDouble(),
      };

  String format(double? value) =>
      value == null ? '无有效记录' : '${value.toStringAsFixed(1)} $unit';
}

class BodyMetricDisplaySeries {
  final BodyMetricDisplayField field;

  /// 按本地自然日升序排列；空日保持 null，绘图不得跨空日连线。
  final List<BodyMetric?> samples;

  BodyMetricDisplaySeries(this.field, List<BodyMetric?> samples)
      : samples = List.unmodifiable(samples);

  List<double?> get values => [
        for (final metric in samples)
          metric == null ? null : field.value(metric)
      ];
  List<BodyMetric> get observations => samples.whereType<BodyMetric>().toList();
  int get count => observations.length;
  BodyMetric? get latest => observations.lastOrNull;
  double? get average {
    final actual = observations;
    if (actual.isEmpty) return null;
    // 分项先除以数量，避免多个有限大值求和溢出。
    return actual.fold<double>(
        0, (sum, item) => sum + field.value(item) / actual.length);
  }

  String get meanLabel => field.format(average);
  String get latestLabel =>
      field.format(latest == null ? null : field.value(latest!));
  String get evidenceLabel {
    final sources = observations.map((m) => m.source.label).toSet().join('、');
    final date = latest == null
        ? '无有效日期'
        : bodyMetricDisplayDate(latest!.measuredAt.toLocal());
    return '$count/${samples.length} 日；最近有效记录：$date；来源：${sources.isEmpty ? "无" : sources}';
  }
}

class BodyMetricDisplayReport {
  final List<DateTime> days;
  final Map<BodyMetricDisplayField, BodyMetricDisplaySeries> series;

  BodyMetricDisplayReport(List<DateTime> days,
      Map<BodyMetricDisplayField, BodyMetricDisplaySeries> series)
      : days = List.unmodifiable(days),
        series = Map.unmodifiable(series);

  BodyMetricDisplaySeries operator [](BodyMetricDisplayField field) =>
      series[field]!;
  int get coveredDays => [
        for (var i = 0; i < days.length; i++)
          if (series.values.any((s) => s.samples[i] != null)) i
      ].length;
  String get periodLabel =>
      '${bodyMetricDisplayDate(days.first)} 至 ${bodyMetricDisplayDate(days.last)}';
}

class BodyMetricDisplayService {
  BodyMetricDisplayReport build(
      {required List<BodyMetric> metrics, int windowDays = 7, DateTime? now}) {
    if (windowDays < 1) throw ArgumentError('展示窗口天数必须大于零。');
    final current = (now ?? DateTime.now()).toLocal();
    // 使用日历构造而非 24 小时相减，跨夏令时仍是一格一个自然日。
    final days = List.generate(
        windowDays,
        (i) => DateTime(
            current.year, current.month, current.day - windowDays + 1 + i));
    final candidates = metrics
        .where((m) =>
            m.sourceVerified &&
            !m.measuredAt.isBefore(days.first) &&
            !m.measuredAt.isAfter(current))
        .toList()
      ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    final series = <BodyMetricDisplayField, BodyMetricDisplaySeries>{};
    for (final field in BodyMetricDisplayField.values) {
      final byDay = <String, BodyMetric>{};
      for (final metric in candidates) {
        if (metric.hasValue(field.key)) {
          byDay.putIfAbsent(
              bodyMetricDisplayDate(metric.measuredAt.toLocal()), () => metric);
        }
      }
      series[field] = BodyMetricDisplaySeries(
          field, [for (final day in days) byDay[bodyMetricDisplayDate(day)]]);
    }
    return BodyMetricDisplayReport(days, series);
  }
}

String bodyMetricDisplayDate(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
