import 'package:flutter/material.dart';

import '../../../core/widgets/trainflow_widgets.dart';
import '../../../data/models/training_load_curve.dart';
import '../../dashboard/training_mvp_controller.dart';

class TrainingLoadCard extends StatelessWidget {
  final TrainingMvpState state;

  const TrainingLoadCard({
    required this.state,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final double acute = state.acuteLoadScore;
    final double chronic = state.chronicLoadScore;
    final double acuteRatio = (acute / chronic).clamp(0.0, 1.4).toDouble();
    final double chronicRatio = (chronic / 520).clamp(0.0, 1.0).toDouble();
    final List<TrainingLoadCurvePoint> curvePoints =
        state.trainingLoadCurvePoints;
    final TrainingLoadCurvePoint? latestLoadPoint =
        curvePoints.isEmpty ? null : curvePoints.last;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '训练负荷工程估算',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: state.trainingStatusLabel),
            ],
          ),
          const SizedBox(height: 8),
          const Text('沿用档案起始值，优先读取训练日志；无日志时，使用有效身体字段或当日计划估算。'
              '身体字段缺失不计入，空日按旧公式以 0 输入，不代表测得负荷为零。'
              '这些数值不代表实际训练量或已测得的体能。'),
          const SizedBox(height: 12),
          _LoadBar(
            label: 'ATL 急性负荷估算',
            value: acuteRatio / 1.4,
            score: acute.round(),
            color: TrainFlowTokens.darkTrainingOnSurface,
          ),
          const SizedBox(height: 10),
          _LoadBar(
            label: 'CTL 慢性负荷估算',
            value: chronicRatio,
            score: chronic.round(),
            color: TrainFlowTokens.accent,
          ),
          if (curvePoints.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'CTL / ATL / TSB 训练负荷曲线',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '当前 TSB ${latestLoadPoint!.tsbScore.round()} · 日负荷 ${latestLoadPoint.dailyLoadScore.round()}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
                  ),
            ),
            const SizedBox(height: 8),
            _LoadCurveChart(points: curvePoints),
            const SizedBox(height: 8),
            const _LoadCurveLegend(),
          ],
          const SizedBox(height: 12),
          Text(
            state.trainingStatusReason,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _LoadBar extends StatelessWidget {
  final String label;
  final double value;
  final int score;
  final Color color;

  const _LoadBar({
    required this.label,
    required this.value,
    required this.score,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '$score',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: value,
          minHeight: 8,
          color: color,
          backgroundColor: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
      ],
    );
  }
}

class _LoadCurveChart extends StatelessWidget {
  final List<TrainingLoadCurvePoint> points;

  const _LoadCurveChart({required this.points});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: CustomPaint(
        painter: _LoadCurvePainter(points: points),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 100),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  points.first.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: TrainFlowTokens.darkTrainingMuted,
                      ),
                ),
                Text(
                  points.last.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: TrainFlowTokens.darkTrainingMuted,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadCurveLegend extends StatelessWidget {
  const _LoadCurveLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _LegendDot(label: 'CTL', color: TrainFlowTokens.accent),
        _LegendDot(label: 'ATL', color: TrainFlowTokens.darkTrainingOnSurface),
        _LegendDot(label: 'TSB', color: TrainFlowTokens.darkTrainingMuted),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendDot({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _LoadCurvePainter extends CustomPainter {
  final List<TrainingLoadCurvePoint> points;

  const _LoadCurvePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = TrainFlowTokens.darkTrainingRaised
      ..strokeWidth = 1;
    final double chartHeight = size.height - 22;
    for (final double ratio in <double>[0, 0.5, 1]) {
      final double y = chartHeight * ratio;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final List<double> allValues = [
      for (final TrainingLoadCurvePoint point in points) ...[
        point.ctlScore,
        point.atlScore,
        point.tsbScore,
      ],
    ];
    final double minValue =
        allValues.reduce((double a, double b) => a < b ? a : b);
    final double maxValue =
        allValues.reduce((double a, double b) => a > b ? a : b);

    _drawLine(
      canvas: canvas,
      size: Size(size.width, chartHeight),
      color: TrainFlowTokens.accent,
      values:
          points.map((TrainingLoadCurvePoint point) => point.ctlScore).toList(),
      minValue: minValue,
      maxValue: maxValue,
    );
    _drawLine(
      canvas: canvas,
      size: Size(size.width, chartHeight),
      color: TrainFlowTokens.darkTrainingOnSurface,
      values:
          points.map((TrainingLoadCurvePoint point) => point.atlScore).toList(),
      minValue: minValue,
      maxValue: maxValue,
    );
    _drawLine(
      canvas: canvas,
      size: Size(size.width, chartHeight),
      color: TrainFlowTokens.darkTrainingMuted,
      values:
          points.map((TrainingLoadCurvePoint point) => point.tsbScore).toList(),
      minValue: minValue,
      maxValue: maxValue,
    );
  }

  void _drawLine({
    required Canvas canvas,
    required Size size,
    required Color color,
    required List<double> values,
    required double minValue,
    required double maxValue,
  }) {
    if (values.isEmpty) {
      return;
    }
    final double range =
        (maxValue - minValue).abs() < 1 ? 1 : maxValue - minValue;
    final Path path = Path();
    for (int i = 0; i < values.length; i += 1) {
      final double x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final double normalized = (values[i] - minValue) / range;
      final double y = size.height - normalized * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = color);
    }
    final Paint linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _LoadCurvePainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
