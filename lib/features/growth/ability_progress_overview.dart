import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/training_metrics.dart';

class AbilityProgressPoint {
  const AbilityProgressPoint({
    required this.periodStart,
    required this.value,
  });

  final DateTime periodStart;
  final double value;
}

class AbilityProgressSeries {
  const AbilityProgressSeries({
    required this.title,
    required this.summary,
    required this.points,
    required this.status,
  });

  final String title;
  final String summary;
  final List<AbilityProgressPoint> points;
  final MetricStatus status;
}

class AbilityProgressSnapshot {
  const AbilityProgressSnapshot({
    required this.load,
    required this.strength,
    required this.samePaceHeartRate,
  });

  final AbilityProgressSeries load;
  final AbilityProgressSeries strength;
  final AbilityProgressSeries samePaceHeartRate;

  List<AbilityProgressSeries> get series =>
      <AbilityProgressSeries>[load, strength, samePaceHeartRate];
}

class AbilityProgressSelector {
  const AbilityProgressSelector();

  AbilityProgressSnapshot build(List<MetricAggregate> metrics) {
    return AbilityProgressSnapshot(
      load: _select(
        metrics: metrics,
        title: '负荷进展（ACWR）',
        matches: (MetricAggregate item) =>
            item.metricCode == 'acwr' || item.metricCode.startsWith('acwr.'),
        compatibilityKey: (MetricAggregate item) =>
            '${item.metricCode}|${item.algorithmVersion}|${item.loadMethod?.code ?? 'none'}',
        readySummary: _loadSummary,
      ),
      strength: _select(
        metrics: metrics,
        title: '力量主项',
        matches: (MetricAggregate item) => item.metricCode == 'strength_e1rm',
        compatibilityKey: (MetricAggregate item) =>
            '${item.algorithmVersion}|${item.metadata['exerciseKey'] ?? ''}',
        titleForLatest: (MetricAggregate latest) {
          final String name =
              (latest.metadata['exerciseName'] as String? ?? '').trim();
          return name.isEmpty ? '力量主项' : '力量主项 · $name';
        },
        readySummary: _strengthSummary,
      ),
      samePaceHeartRate: _select(
        metrics: metrics,
        title: '同配速心率',
        matches: (MetricAggregate item) =>
            item.metricCode == 'same_pace_heart_rate',
        compatibilityKey: (MetricAggregate item) =>
            '${item.algorithmVersion}|${item.metadata['bandVersion'] ?? ''}',
        readySummary: _heartRateSummary,
      ),
    );
  }
}

AbilityProgressSeries _select({
  required List<MetricAggregate> metrics,
  required String title,
  required bool Function(MetricAggregate item) matches,
  required String Function(MetricAggregate item) compatibilityKey,
  required String Function(List<AbilityProgressPoint> points) readySummary,
  String Function(MetricAggregate latest)? titleForLatest,
}) {
  final List<MetricAggregate> candidates = metrics
      .where((MetricAggregate item) =>
          matches(item) && item.status != MetricStatus.invalidated)
      .toList()
    ..sort((MetricAggregate first, MetricAggregate second) {
      final int byDate = second.periodStart.compareTo(first.periodStart);
      return byDate != 0
          ? byDate
          : second.computedAt.compareTo(first.computedAt);
    });
  if (candidates.isEmpty) {
    return AbilityProgressSeries(
      title: title,
      summary: '数据积累中：尚无可比较记录。',
      points: const <AbilityProgressPoint>[],
      status: MetricStatus.accumulating,
    );
  }

  final MetricAggregate latest = candidates.first;
  final String anchorKey = compatibilityKey(latest);
  final List<AbilityProgressPoint> points = candidates
      .where((MetricAggregate item) =>
          item.status == MetricStatus.ready &&
          item.value != null &&
          compatibilityKey(item) == anchorKey)
      .map(
        (MetricAggregate item) => AbilityProgressPoint(
          periodStart: item.periodStart,
          value: item.value!,
        ),
      )
      .toList()
    ..sort((AbilityProgressPoint first, AbilityProgressPoint second) =>
        first.periodStart.compareTo(second.periodStart));

  final String summary =
      latest.status == MetricStatus.ready && points.isNotEmpty
          ? readySummary(points)
          : _statusSummary(latest);
  return AbilityProgressSeries(
    title: titleForLatest?.call(latest) ?? title,
    summary: summary,
    points: List<AbilityProgressPoint>.unmodifiable(points),
    status: latest.status,
  );
}

String _loadSummary(List<AbilityProgressPoint> points) {
  final double latest = points.last.value;
  return '当前 ${latest.toStringAsFixed(2)} · 负荷状态不等于能力提升';
}

String _strengthSummary(List<AbilityProgressPoint> points) {
  final double latest = points.last.value;
  if (points.length < 2) return '当前 ${latest.toStringAsFixed(1)} kg · 等待历史对比';
  final double delta = latest - points.first.value;
  final String direction = delta >= 0 ? '提升' : '下降';
  return '当前 ${latest.toStringAsFixed(1)} kg · $direction ${delta.abs().toStringAsFixed(1)} kg';
}

String _heartRateSummary(List<AbilityProgressPoint> points) {
  final double latest = points.last.value;
  if (points.length < 2) return '当前 ${latest.toStringAsFixed(0)} bpm · 等待历史对比';
  final double delta = latest - points.first.value;
  final String direction = delta <= 0 ? '下降' : '上升';
  return '当前 ${latest.toStringAsFixed(0)} bpm · $direction ${delta.abs().toStringAsFixed(1)} bpm';
}

String _statusSummary(MetricAggregate metric) => switch (metric.status) {
      MetricStatus.accumulating => _remainingDataLabel(metric.metadata),
      MetricStatus.unavailable => '当前来源不支持，不使用替代值。',
      MetricStatus.invalidated => '口径已失效，等待重算。',
      MetricStatus.failed => '计算失败，原始记录仍保留。',
      MetricStatus.ready => '数据积累中：尚无可比较记录。',
    };

String _remainingDataLabel(Map<String, Object?> metadata) {
  final Object? minutes = metadata['remainingMinutes'];
  if (minutes is num) return '数据积累中：还需 ${minutes.ceil()} 分钟。';
  final Object? seconds =
      metadata['remainingSeconds'] ?? metadata['remainingDurationSeconds'];
  if (seconds is num) {
    return '数据积累中：还需 ${(seconds / 60).ceil()} 分钟。';
  }
  final Object? samples = metadata['remainingSamples'];
  if (samples is num) return '数据积累中：还需 ${samples.ceil()} 次训练。';
  final Object? days = metadata['remainingDays'];
  if (days is num) return '数据积累中：还需 ${days.ceil()} 个有效日。';
  return '数据积累中：尚未达到解释门槛。';
}

class AbilityProgressOverview extends StatelessWidget {
  const AbilityProgressOverview({
    required this.metrics,
    this.compact = false,
    this.onTap,
    super.key,
  });

  final AsyncValue<List<MetricAggregate>> metrics;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AbilityProgressSnapshot snapshot = metrics.when(
      data: const AbilityProgressSelector().build,
      loading: () => const AbilityProgressSelector().build(
        const <MetricAggregate>[],
      ),
      error: (Object error, StackTrace stackTrace) =>
          const AbilityProgressSelector().build(const <MetricAggregate>[]),
    );
    return Semantics(
      label: '能力进步总览，包含负荷、力量主项和同配速心率三项趋势',
      button: onTap != null,
      child: TrainFlowCard(
        key: ValueKey<String>(
          compact
              ? 'ability-progress-overview-compact'
              : 'ability-progress-overview-full',
        ),
        tone: compact ? TrainFlowCardTone.peach : TrainFlowCardTone.paper,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.show_chart, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '能力进步总览',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (onTap != null)
                      const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary),
                  ],
                ),
                const SizedBox(height: 8),
                for (int index = 0;
                    index < snapshot.series.length;
                    index++) ...[
                  _AbilitySeriesRow(series: snapshot.series[index]),
                  if (index != snapshot.series.length - 1)
                    const Divider(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AbilitySeriesRow extends StatelessWidget {
  const _AbilitySeriesRow({required this.series});

  final AbilityProgressSeries series;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  series.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.15,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: '${series.title}趋势，共 ${series.points.length} 个兼容数据点',
            child: CustomPaint(
              size: const Size(82, 34),
              painter: _AbilitySparklinePainter(series.points),
            ),
          ),
        ],
      ),
    );
  }
}

class _AbilitySparklinePainter extends CustomPainter {
  const _AbilitySparklinePainter(this.points);

  final List<AbilityProgressPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint baseline = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 2),
      Offset(size.width, size.height - 2),
      baseline,
    );
    if (points.isEmpty) return;

    final double minValue =
        points.map((AbilityProgressPoint item) => item.value).reduce(math.min);
    final double maxValue =
        points.map((AbilityProgressPoint item) => item.value).reduce(math.max);
    final double span = math.max(maxValue - minValue, 0.0001);
    final Path path = Path();
    for (int index = 0; index < points.length; index += 1) {
      final double x = points.length == 1
          ? size.width / 2
          : index * size.width / (points.length - 1);
      final double normalized = (points[index].value - minValue) / span;
      final double y = size.height - 4 - normalized * (size.height - 9);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final Paint line = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);
    final AbilityProgressPoint last = points.last;
    final double lastX = points.length == 1 ? size.width / 2 : size.width;
    final double lastY =
        size.height - 4 - (last.value - minValue) / span * (size.height - 9);
    canvas.drawCircle(
      Offset(lastX, lastY),
      3,
      Paint()..color = AppColors.secondaryDark,
    );
  }

  @override
  bool shouldRepaint(covariant _AbilitySparklinePainter oldDelegate) {
    if (oldDelegate.points.length != points.length) return true;
    for (int index = 0; index < points.length; index += 1) {
      if (oldDelegate.points[index].value != points[index].value ||
          oldDelegate.points[index].periodStart != points[index].periodStart) {
        return true;
      }
    }
    return false;
  }
}
