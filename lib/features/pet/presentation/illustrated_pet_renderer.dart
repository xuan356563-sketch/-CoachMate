import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/pet.dart';

/// 与养成数据解耦的 2D 插画宠物。
///
/// 物种、阶段与心情仍来自既有模型；这里只负责把状态转换为平滑矢量形象。
class IllustratedPetRenderer extends StatelessWidget {
  const IllustratedPetRenderer({
    super.key,
    required this.species,
    required this.stage,
    required this.mood,
    required this.semanticLabel,
    this.size = 240,
  });

  final PetSpecies species;
  final PetStage stage;
  final PetMood mood;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bool animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final IllustratedPetVisual visual = IllustratedPetVisual.resolve(
      species: species,
      stage: stage,
      mood: mood,
    );
    return Semantics(
      label: semanticLabel,
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: TweenAnimationBuilder<Offset>(
            tween: Tween<Offset>(
              begin: animationsDisabled ? Offset.zero : const Offset(0, 4),
              end: Offset.zero,
            ),
            duration: animationsDisabled
                ? Duration.zero
                : const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, Offset offset, Widget? child) {
              return Transform.translate(
                key: const ValueKey<String>('illustrated-pet-motion'),
                offset: offset,
                child: child,
              );
            },
            child: IllustratedPetCanvas(
              species: species,
              stage: stage,
              mood: mood,
              visual: visual,
            ),
          ),
        ),
      ),
    );
  }
}

/// 暴露稳定状态，便于视觉契约测试检查阶段和表情映射。
class IllustratedPetCanvas extends StatelessWidget {
  const IllustratedPetCanvas({
    super.key,
    required this.species,
    required this.stage,
    required this.mood,
    required this.visual,
  });

  final PetSpecies species;
  final PetStage stage;
  final PetMood mood;
  final IllustratedPetVisual visual;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const ValueKey<String>('illustrated-pet-body'),
      painter: IllustratedPetPainter(visual: visual),
      isComplex: true,
      willChange: false,
    );
  }
}

@immutable
class IllustratedPetVisual {
  const IllustratedPetVisual({
    required this.species,
    required this.stage,
    required this.mood,
    required this.stageScale,
    required this.expressionSignature,
    required this.furColor,
    required this.accentColor,
  });

  factory IllustratedPetVisual.resolve({
    required PetSpecies species,
    required PetStage stage,
    required PetMood mood,
  }) {
    final Color furColor = switch (species) {
      PetSpecies.balanceRaccoon => const Color(0xFFFFA46C),
      PetSpecies.windFox => const Color(0xFFFF8C66),
      PetSpecies.jumpRabbit => const Color(0xFFFFC7D8),
      PetSpecies.steadyTurtle => const Color(0xFF75D8B3),
      PetSpecies.energyDragon => const Color(0xFFFFD15C),
      PetSpecies.strengthBear => const Color(0xFFC69B7B),
    };
    final Color accentColor = switch (species) {
      PetSpecies.balanceRaccoon => const Color(0xFF72D6B3),
      PetSpecies.windFox => const Color(0xFF7ED8F6),
      PetSpecies.jumpRabbit => const Color(0xFF9B91FF),
      PetSpecies.steadyTurtle => const Color(0xFFFFB27D),
      PetSpecies.energyDragon => const Color(0xFF72D6B3),
      PetSpecies.strengthBear => const Color(0xFFFFB27D),
    };
    return IllustratedPetVisual(
      species: species,
      stage: stage,
      mood: mood,
      stageScale: switch (stage) {
        PetStage.patternEgg => 0.82,
        PetStage.sprout => 0.86,
        PetStage.junior => 0.92,
        PetStage.advanced => 0.97,
        PetStage.champion => 1,
      },
      expressionSignature: switch (mood) {
        PetMood.excited => 'star-eyes-open-smile',
        PetMood.happy => 'arc-eyes-smile',
        PetMood.curious => 'wide-eye-raised-brow',
        PetMood.calm => 'closed-eyes-soft-smile',
        PetMood.waiting => 'droop-eyes-small-mouth',
      },
      furColor: furColor,
      accentColor: accentColor,
    );
  }

  final PetSpecies species;
  final PetStage stage;
  final PetMood mood;
  final double stageScale;
  final String expressionSignature;
  final Color furColor;
  final Color accentColor;
}

class IllustratedPetPainter extends CustomPainter {
  const IllustratedPetPainter({required this.visual});

  final IllustratedPetVisual visual;

  static const Color _ink = Color(0xFF211E3F);
  static const Color _inkSoft = Color(0xFF37305F);
  static const Color _ivory = Color(0xFFFFFBF2);
  static const Color _blush = Color(0xFFFF8E9F);
  static const Color _gold = Color(0xFFFFD15C);

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / 240;
    canvas.save();
    canvas.translate((size.width - 240 * scale) / 2, 0);
    canvas.scale(scale);

    canvas.save();
    canvas.translate(120, 122);
    canvas.scale(visual.stageScale);
    canvas.translate(-120, -122);

    _drawGround(canvas);
    if (visual.stage == PetStage.patternEgg) {
      _drawEgg(canvas);
    } else {
      _drawTail(canvas);
      _drawBody(canvas);
      _drawHead(canvas);
      _drawFaceMask(canvas);
      _drawExpression(canvas);
      _drawStageDetails(canvas);
      _drawBalanceBadge(canvas);
    }
    canvas.restore();
    canvas.restore();
  }

  Paint _fill(Color color) => Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill
    ..color = color;

  Paint _stroke([double width = 4]) => Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = width
    ..color = _ink;

  void _drawGround(Canvas canvas) {
    canvas.drawOval(
      const Rect.fromLTWH(45, 205, 150, 18),
      _fill(_ink.withValues(alpha: 0.12)),
    );
  }

  void _drawEgg(Canvas canvas) {
    final Path shell = Path()
      ..moveTo(120, 35)
      ..cubicTo(76, 46, 62, 102, 67, 153)
      ..cubicTo(71, 196, 92, 211, 120, 211)
      ..cubicTo(148, 211, 169, 196, 173, 153)
      ..cubicTo(178, 102, 164, 46, 120, 35)
      ..close();
    canvas.drawShadow(shell, _ink.withValues(alpha: 0.18), 8, false);
    canvas.drawPath(shell, _fill(_ivory));
    canvas.drawPath(shell, _stroke(5));

    final Path orangeWave = Path()
      ..moveTo(76, 131)
      ..cubicTo(94, 113, 108, 150, 127, 131)
      ..cubicTo(144, 114, 157, 139, 169, 126)
      ..lineTo(170, 158)
      ..cubicTo(151, 171, 139, 145, 123, 161)
      ..cubicTo(104, 179, 90, 142, 70, 162)
      ..close();
    canvas.drawPath(orangeWave, _fill(visual.furColor));

    canvas.drawOval(const Rect.fromLTWH(88, 77, 64, 52), _fill(_ivory));
    _drawExpression(canvas, faceCenterY: 99, compact: true);
    _drawBadgeWaves(canvas, const Offset(120, 178), 0.72);

    canvas.drawPath(
      Path()
        ..moveTo(94, 50)
        ..quadraticBezierTo(104, 28, 117, 49)
        ..quadraticBezierTo(131, 25, 144, 51),
      _stroke(5),
    );
  }

  void _drawTail(Canvas canvas) {
    final Path tail = Path()
      ..moveTo(168, 145)
      ..cubicTo(220, 126, 222, 178, 195, 195)
      ..cubicTo(180, 204, 165, 194, 171, 181)
      ..cubicTo(190, 185, 197, 166, 175, 164)
      ..close();
    canvas.drawPath(tail, _fill(visual.furColor));
    canvas.drawPath(tail, _stroke());
    for (final double x in <double>[184, 197]) {
      canvas.drawArc(
        Rect.fromCenter(center: Offset(x, 169), width: 24, height: 39),
        -1.25,
        1.45,
        false,
        _stroke(5)..color = _inkSoft,
      );
    }
  }

  void _drawBody(Canvas canvas) {
    final Path body = Path()
      ..moveTo(76, 129)
      ..cubicTo(48, 146, 48, 197, 79, 211)
      ..cubicTo(99, 220, 153, 219, 173, 208)
      ..cubicTo(200, 193, 190, 146, 164, 130)
      ..close();
    canvas.drawShadow(body, _ink.withValues(alpha: 0.18), 8, false);
    canvas.drawPath(body, _fill(visual.furColor));
    canvas.drawPath(body, _stroke());

    canvas.drawOval(const Rect.fromLTWH(86, 143, 69, 65), _fill(_ivory));
    canvas.drawArc(
      const Rect.fromLTWH(55, 152, 47, 57),
      -1.7,
      2.5,
      false,
      _stroke(12)..color = visual.furColor,
    );
    canvas.drawArc(
      const Rect.fromLTWH(139, 151, 47, 58),
      2.4,
      2.5,
      false,
      _stroke(12)..color = visual.furColor,
    );
  }

  void _drawHead(Canvas canvas) {
    final Path leftEar = Path()
      ..moveTo(73, 74)
      ..quadraticBezierTo(52, 37, 89, 50)
      ..lineTo(101, 76)
      ..close();
    final Path rightEar = Path()
      ..moveTo(139, 74)
      ..lineTo(153, 49)
      ..quadraticBezierTo(188, 38, 167, 82)
      ..close();
    for (final Path ear in <Path>[leftEar, rightEar]) {
      canvas.drawPath(ear, _fill(visual.furColor));
      canvas.drawPath(ear, _stroke());
    }
    canvas.drawPath(
      Path()
        ..moveTo(78, 66)
        ..quadraticBezierTo(67, 50, 86, 57),
      _stroke(5)..color = _blush.withValues(alpha: 0.62),
    );
    canvas.drawPath(
      Path()
        ..moveTo(151, 60)
        ..quadraticBezierTo(171, 49, 161, 70),
      _stroke(5)..color = _blush.withValues(alpha: 0.62),
    );

    final Path head = Path()
      ..moveTo(120, 48)
      ..cubicTo(75, 44, 58, 75, 62, 111)
      ..cubicTo(65, 141, 86, 155, 120, 155)
      ..cubicTo(156, 155, 178, 140, 179, 109)
      ..cubicTo(181, 75, 163, 48, 120, 48)
      ..close();
    canvas.drawPath(head, _fill(visual.furColor));
    canvas.drawPath(head, _stroke());

    canvas.drawPath(
      Path()
        ..moveTo(111, 50)
        ..quadraticBezierTo(119, 36, 125, 51)
        ..quadraticBezierTo(133, 36, 138, 53),
      _stroke(4)..color = visual.furColor,
    );
  }

  void _drawFaceMask(Canvas canvas) {
    final Path mask = Path()
      ..moveTo(74, 90)
      ..cubicTo(84, 67, 108, 73, 120, 91)
      ..cubicTo(132, 72, 157, 68, 168, 91)
      ..cubicTo(177, 112, 156, 140, 120, 141)
      ..cubicTo(84, 140, 64, 112, 74, 90)
      ..close();
    canvas.drawPath(mask, _fill(_ivory));

    canvas.drawOval(
      const Rect.fromLTWH(73, 111, 22, 12),
      _fill(_blush.withValues(alpha: 0.30)),
    );
    canvas.drawOval(
      const Rect.fromLTWH(146, 111, 22, 12),
      _fill(_blush.withValues(alpha: 0.30)),
    );
  }

  void _drawExpression(
    Canvas canvas, {
    double faceCenterY = 103,
    bool compact = false,
  }) {
    final double eyeY = faceCenterY - 8;
    final double leftX = compact ? 106 : 98;
    final double rightX = compact ? 134 : 142;
    final double eyeSize = compact ? 5 : 7;
    final Paint faceStroke = _stroke(compact ? 3.2 : 4)..color = _ink;

    switch (visual.mood) {
      case PetMood.excited:
        _drawSparkEye(canvas, Offset(leftX, eyeY), eyeSize);
        _drawSparkEye(canvas, Offset(rightX, eyeY), eyeSize);
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(120, faceCenterY + 11),
            width: compact ? 18 : 27,
            height: compact ? 15 : 20,
          ),
          0.05,
          3.02,
          false,
          faceStroke,
        );
      case PetMood.happy:
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(leftX, eyeY + 2), width: 17, height: 11),
          3.32,
          2.55,
          false,
          faceStroke,
        );
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(rightX, eyeY + 2), width: 17, height: 11),
          3.32,
          2.55,
          false,
          faceStroke,
        );
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(120, faceCenterY + 8), width: 24, height: 16),
          0.10,
          2.94,
          false,
          faceStroke,
        );
      case PetMood.curious:
        canvas.drawCircle(Offset(leftX, eyeY), eyeSize + 1, _fill(_ink));
        canvas.drawCircle(Offset(rightX, eyeY - 2), eyeSize + 3, _fill(_ink));
        canvas.drawCircle(
          Offset(rightX - 2, eyeY - 4),
          2.3,
          _fill(_ivory),
        );
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(120, faceCenterY + 10), width: 13, height: 9),
          0,
          3.14,
          false,
          faceStroke,
        );
        canvas.drawLine(
          Offset(rightX - 8, eyeY - 13),
          Offset(rightX + 6, eyeY - 16),
          faceStroke,
        );
      case PetMood.calm:
        canvas.drawArc(
          Rect.fromCenter(center: Offset(leftX, eyeY), width: 16, height: 9),
          0.15,
          2.84,
          false,
          faceStroke,
        );
        canvas.drawArc(
          Rect.fromCenter(center: Offset(rightX, eyeY), width: 16, height: 9),
          0.15,
          2.84,
          false,
          faceStroke,
        );
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(120, faceCenterY + 10), width: 16, height: 8),
          0.2,
          2.74,
          false,
          faceStroke,
        );
      case PetMood.waiting:
        canvas.drawOval(
          Rect.fromCenter(center: Offset(leftX, eyeY), width: 8, height: 12),
          _fill(_inkSoft),
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(rightX, eyeY), width: 8, height: 12),
          _fill(_inkSoft),
        );
        canvas.drawLine(
          const Offset(112, 119),
          const Offset(128, 119),
          faceStroke,
        );
    }

    canvas.drawPath(
      Path()
        ..moveTo(116, faceCenterY + 1)
        ..quadraticBezierTo(120, faceCenterY + 5, 124, faceCenterY + 1)
        ..quadraticBezierTo(120, faceCenterY - 1, 116, faceCenterY + 1)
        ..close(),
      _fill(_ink),
    );
  }

  void _drawSparkEye(Canvas canvas, Offset center, double radius) {
    final Path star = Path();
    for (int index = 0; index < 8; index += 1) {
      final double x = center.dx +
          (index.isEven ? radius : radius * 0.42) *
              (index == 0 || index == 4
                  ? 0
                  : index < 4
                      ? 1
                      : -1);
      final double y = center.dy +
          (index.isEven ? radius : radius * 0.42) *
              (index == 2 || index == 6
                  ? 0
                  : index < 2 || index > 6
                      ? -1
                      : 1);
      if (index == 0) {
        star.moveTo(center.dx, center.dy - radius);
      } else {
        star.lineTo(x, y);
      }
    }
    star.close();
    canvas.drawPath(star, _fill(_ink));
    canvas.drawCircle(center.translate(-1.5, -1.7), 1.8, _fill(_ivory));
  }

  void _drawStageDetails(Canvas canvas) {
    switch (visual.stage) {
      case PetStage.patternEgg:
        return;
      case PetStage.sprout:
        canvas.drawPath(
          Path()
            ..moveTo(119, 50)
            ..quadraticBezierTo(109, 31, 95, 42)
            ..quadraticBezierTo(107, 55, 119, 50)
            ..quadraticBezierTo(132, 29, 145, 43)
            ..quadraticBezierTo(132, 55, 119, 50),
          _fill(visual.accentColor),
        );
      case PetStage.junior:
        _drawScarf(canvas);
      case PetStage.advanced:
        _drawScarf(canvas);
        _drawHeadband(canvas, showTails: false);
      case PetStage.champion:
        _drawScarf(canvas);
        _drawHeadband(canvas, showTails: true);
        _drawChampionStar(canvas);
    }
  }

  void _drawScarf(Canvas canvas) {
    final Paint scarf = _fill(visual.accentColor);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(76, 134, 89, 17),
        const Radius.circular(9),
      ),
      scarf,
    );
    final Path tail = Path()
      ..moveTo(150, 145)
      ..lineTo(177, 164)
      ..lineTo(157, 174)
      ..lineTo(141, 149)
      ..close();
    canvas.drawPath(tail, scarf);
  }

  void _drawHeadband(Canvas canvas, {required bool showTails}) {
    final Paint headband = _stroke(9)..color = AppColors.secondary;
    canvas.drawArc(
      const Rect.fromLTWH(68, 50, 104, 72),
      3.56,
      2.25,
      false,
      headband,
    );
    if (showTails) {
      canvas.drawPath(
        Path()
          ..moveTo(166, 68)
          ..cubicTo(198, 56, 203, 72, 183, 84)
          ..cubicTo(205, 82, 206, 99, 176, 101),
        _stroke(7)..color = AppColors.secondary,
      );
    }
  }

  void _drawChampionStar(Canvas canvas) {
    final Path star = Path()
      ..moveTo(120, 153)
      ..lineTo(125, 164)
      ..lineTo(137, 165)
      ..lineTo(128, 174)
      ..lineTo(131, 187)
      ..lineTo(120, 180)
      ..lineTo(109, 187)
      ..lineTo(112, 174)
      ..lineTo(103, 165)
      ..lineTo(115, 164)
      ..close();
    canvas.drawPath(star, _fill(_gold));
    canvas.drawPath(star, _stroke(2.5));
  }

  void _drawBalanceBadge(Canvas canvas) {
    _drawBadgeWaves(canvas, const Offset(120, 181), 1);
  }

  void _drawBadgeWaves(Canvas canvas, Offset center, double scale) {
    canvas.drawCircle(center, 18 * scale, _fill(_ivory));
    canvas.drawCircle(
      center,
      18 * scale,
      _stroke(2.2 * scale)..color = _inkSoft,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: center.translate(0, -3 * scale),
        width: 25 * scale,
        height: 12 * scale,
      ),
      0.1,
      2.94,
      false,
      _stroke(3 * scale)..color = AppColors.secondary,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: center.translate(0, 5 * scale),
        width: 20 * scale,
        height: 10 * scale,
      ),
      3.25,
      2.94,
      false,
      _stroke(3 * scale)..color = visual.accentColor,
    );
  }

  @override
  bool shouldRepaint(covariant IllustratedPetPainter oldDelegate) {
    return oldDelegate.visual != visual;
  }
}
