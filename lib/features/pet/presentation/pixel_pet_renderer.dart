import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/pet.dart';
import 'pixel_frames/pet_frame_catalog.dart';
import 'pixel_frames/pixel_frame.dart';

enum PixelRenderLayer { offGrid, body, expression, accessory, effect }

class PixelPetRenderer extends StatefulWidget {
  const PixelPetRenderer({
    super.key,
    required this.species,
    required this.stage,
    required this.mood,
    required this.semanticLabel,
    this.accessoryLayer,
    this.effectLayer,
    this.inverted = false,
    this.size = 240,
  });

  final PetSpecies species;
  final PetStage stage;
  final PetMood mood;
  final String semanticLabel;
  final PixelFrame? accessoryLayer;
  final PixelFrame? effectLayer;
  final bool inverted;
  final double size;

  @override
  State<PixelPetRenderer> createState() => _PixelPetRendererState();
}

class _PixelPetRendererState extends State<PixelPetRenderer> {
  Timer? _timer;
  int _frameIndex = 0;
  bool? _animationsDisabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool disabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_animationsDisabled == disabled) return;
    _animationsDisabled = disabled;
    _timer?.cancel();
    _timer = null;
    _frameIndex = 0;
    if (!disabled) {
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) return;
        setState(() => _frameIndex = 1 - _frameIndex);
      });
    }
  }

  @override
  void didUpdateWidget(covariant PixelPetRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.species != widget.species ||
        oldWidget.stage != widget.stage) {
      _frameIndex = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PetFormFrames form = PetFrameCatalog.formFor(
      widget.species,
      widget.stage,
    );
    final PixelFrame frame = _frameIndex == 0 ? form.frameA : form.frameB;
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          key: ValueKey<String>('pixel-pet-frame-$_frameIndex'),
          painter: PixelPetPainter(
            frame: frame,
            mood: widget.mood,
            accessoryLayer: widget.accessoryLayer,
            effectLayer: widget.effectLayer,
            inverted: widget.inverted,
          ),
        ),
      ),
    );
  }
}

class PixelPetPainter extends CustomPainter {
  const PixelPetPainter({
    required this.frame,
    required this.mood,
    required this.accessoryLayer,
    required this.effectLayer,
    required this.inverted,
  });

  static const List<PixelRenderLayer> layerOrder = <PixelRenderLayer>[
    PixelRenderLayer.offGrid,
    PixelRenderLayer.body,
    PixelRenderLayer.expression,
    PixelRenderLayer.accessory,
    PixelRenderLayer.effect,
  ];

  final PixelFrame frame;
  final PetMood mood;
  final PixelFrame? accessoryLayer;
  final PixelFrame? effectLayer;
  final bool inverted;

  @override
  void paint(Canvas canvas, Size size) {
    final double cell = size.shortestSide / 24;
    final Paint background = Paint()
      ..color = inverted ? AppColors.petLcdPixel : AppColors.petLcd;
    final Paint offPixel = Paint()
      ..color = inverted
          ? AppColors.petLcd.withValues(alpha: 0.18)
          : AppColors.petLcdDim.withValues(alpha: 0.30);
    final Paint onPixel = Paint()
      ..color = inverted ? AppColors.petLcd : AppColors.petLcdPixel;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell)),
      background,
    );
    for (int y = 0; y < 24; y += 1) {
      for (int x = 0; x < 24; x += 1) {
        _drawPixel(canvas, x, y, cell, offPixel);
      }
    }
    _drawFrame(canvas, frame, cell, onPixel);
    _drawExpression(canvas, cell, onPixel);
    if (accessoryLayer != null) {
      _drawFrame(canvas, accessoryLayer!, cell, onPixel);
    }
    if (effectLayer != null) {
      _drawFrame(canvas, effectLayer!, cell, onPixel);
    }
  }

  void _drawFrame(Canvas canvas, PixelFrame source, double cell, Paint paint) {
    for (int y = 0; y < 24; y += 1) {
      for (int x = 0; x < 24; x += 1) {
        if (source.isOn(x, y)) _drawPixel(canvas, x, y, cell, paint);
      }
    }
  }

  void _drawExpression(Canvas canvas, double cell, Paint paint) {
    final List<(int, int)> pixels = switch (mood) {
      PetMood.excited => <(int, int)>[(9, 8), (14, 8), (11, 11), (12, 11)],
      PetMood.happy => <(int, int)>[(9, 8), (14, 8), (10, 11), (13, 11)],
      PetMood.curious => <(int, int)>[(9, 8), (14, 7), (12, 11)],
      PetMood.calm => <(int, int)>[(9, 8), (14, 8), (11, 11)],
      PetMood.waiting => <(int, int)>[(9, 9), (14, 9), (11, 12), (12, 12)],
    };
    for (final (int x, int y) in pixels) {
      _drawPixel(canvas, x, y, cell, paint);
    }
  }

  void _drawPixel(Canvas canvas, int x, int y, double cell, Paint paint) {
    final double gap = cell * 0.14;
    canvas.drawRect(
      Rect.fromLTWH(
        x * cell + gap,
        y * cell + gap,
        cell - gap * 2,
        cell - gap * 2,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant PixelPetPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.mood != mood ||
        oldDelegate.accessoryLayer != accessoryLayer ||
        oldDelegate.effectLayer != effectLayer ||
        oldDelegate.inverted != inverted;
  }
}
