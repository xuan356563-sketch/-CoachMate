import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/trainflow_tokens.dart';

/// CoachMate 品牌渐变球体：旋转锥形渐变（深蓝 → 蜜桃 → 荧光绿）+ 高光 +
/// 唤醒时显示白脸表情 + 荧光绿光环。
///
/// 底部导航 v2 的中央 hero 与运动搭子欢迎页共用。
class CoachMateOrb extends StatelessWidget {
  const CoachMateOrb({
    super.key,
    required this.size,
    this.active = false,
    this.phase = 0.3,
    this.paintKey,
  });

  final double size;

  /// 是否处于「已唤醒」状态（显示白脸表情）。
  final bool active;

  /// 光斑旋转相位 0..1。
  final double phase;

  /// 传给内部 [CustomPaint] 的 key（便于测试与定位）。
  final Key? paintKey;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: active ? '运动搭子球体（已唤醒）' : '运动搭子球体',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          key: paintKey,
          painter: CoachMateOrbPainter(active: active, phase: phase),
        ),
      ),
    );
  }
}

class CoachMateOrbPainter extends CustomPainter {
  const CoachMateOrbPainter({required this.active, required this.phase});

  final bool active;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.width / 2;
    final Rect circleRect = Rect.fromCircle(center: center, radius: radius);

    final Paint sweep = Paint()
      ..shader = SweepGradient(
        transform: GradientRotation(phase * 2 * math.pi),
        colors: const <Color>[
          Color(0xFF191331),
          Color(0xFFF083C6),
          Color(0xFF6C3DF4),
          Color(0xFFFFD54A),
          Color(0xFF191331),
        ],
      ).createShader(circleRect);
    canvas.drawCircle(center, radius, sweep);

    final Paint highlight = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: center - Offset(radius * 0.35, radius * 0.35),
          radius: radius * 1.1,
        ),
      );
    canvas.drawCircle(center, radius, highlight);

    if (active) {
      final Paint eye = Paint()..color = Colors.white;
      canvas.drawCircle(
        center + Offset(-radius * 0.28, -radius * 0.12),
        radius * 0.09,
        eye,
      );
      canvas.drawCircle(
        center + Offset(radius * 0.28, -radius * 0.12),
        radius * 0.09,
        eye,
      );
      final Paint smile = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.07
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCenter(
          center: center + Offset(0, radius * 0.12),
          width: radius * 0.62,
          height: radius * 0.5,
        ),
        0.15 * math.pi,
        0.7 * math.pi,
        false,
        smile,
      );
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = TrainFlowTokens.accentGlow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CoachMateOrbPainter oldDelegate) {
    return oldDelegate.active != active || oldDelegate.phase != phase;
  }
}
