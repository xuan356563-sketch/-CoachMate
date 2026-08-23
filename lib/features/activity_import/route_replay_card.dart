import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/imported_workout.dart';

class RouteReplayCard extends StatefulWidget {
  const RouteReplayCard({
    required this.workout,
    required this.onDeleteRoute,
    super.key,
  });

  final ImportedWorkout workout;
  final VoidCallback onDeleteRoute;

  @override
  State<RouteReplayCard> createState() => _RouteReplayCardState();
}

class _RouteReplayCardState extends State<RouteReplayCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_outlined, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '离线路线回放',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const ToneBadge(label: '本地 · 去地理化'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '仅保存路线形状，不保存原始经纬度，也不请求地图服务。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1.8,
            child: CustomPaint(
              painter: _RouteShapePainter(
                points: widget.workout.routeShape,
                progress: _controller.value,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: _controller.isAnimating ? '暂停回放' : '播放回放',
                onPressed: () {
                  if (_controller.isAnimating) {
                    _controller.stop();
                  } else {
                    if (_controller.isCompleted) _controller.value = 0;
                    _controller.forward();
                  }
                  setState(() {});
                },
                icon: Icon(
                  _controller.isAnimating
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _controller.value,
                  onChanged: (double value) {
                    _controller.stop();
                    _controller.value = value;
                  },
                ),
              ),
              TextButton.icon(
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除路线'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除本地路线数据？'),
        content: const Text('只删除去地理化路线形状，训练摘要和成长证据会继续保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onDeleteRoute();
  }
}

class _RouteShapePainter extends CustomPainter {
  const _RouteShapePainter({required this.points, required this.progress});

  final List<RouteShapePoint> points;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect background = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(18),
    );
    canvas.drawRRect(
      background,
      Paint()..color = AppColors.background,
    );
    if (points.length < 2) return;

    final Rect drawingRect = Rect.fromLTWH(
      18,
      18,
      size.width - 36,
      size.height - 36,
    );
    Offset offsetFor(RouteShapePoint point) => Offset(
          drawingRect.left + point.x * drawingRect.width,
          drawingRect.top + point.y * drawingRect.height,
        );

    final Paint basePaint = Paint()
      ..color = TrainFlowTokens.darkTrainingMuted.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint activePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _drawRoute(canvas, points, offsetFor, basePaint, 1);
    _drawRoute(canvas, points, offsetFor, activePaint, progress);

    canvas.drawCircle(
      offsetFor(points.first),
      6,
      Paint()..color = AppColors.success,
    );
    canvas.drawCircle(
      offsetFor(points.last),
      6,
      Paint()..color = AppColors.primary,
    );
    final RouteShapePoint current = points.lastWhere(
      (RouteShapePoint point) => point.progress <= progress,
      orElse: () => points.first,
    );
    canvas.drawCircle(
      offsetFor(current),
      5,
      Paint()..color = Colors.white,
    );
  }

  void _drawRoute(
    Canvas canvas,
    List<RouteShapePoint> route,
    Offset Function(RouteShapePoint point) offsetFor,
    Paint paint,
    double visibleProgress,
  ) {
    Path? path;
    int? activeSegment;
    for (final RouteShapePoint point in route) {
      if (point.progress > visibleProgress) break;
      if (activeSegment != point.segmentIndex) {
        if (path != null) canvas.drawPath(path, paint);
        path = Path()..moveTo(offsetFor(point).dx, offsetFor(point).dy);
        activeSegment = point.segmentIndex;
      } else {
        path!.lineTo(offsetFor(point).dx, offsetFor(point).dy);
      }
    }
    if (path != null) canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RouteShapePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.progress != progress;
  }
}
