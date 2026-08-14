import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/trainflow_tokens.dart';
import '../../core/widgets/trainmate_branding.dart';

enum NavigationItemRole {
  standard,
  today,
  plan,
  partner,
  ai,
  exercises,
  profile,
}

/// 选中圆盘内容由角色声明，避免依赖导航索引或文案判断。
enum NavigationSelectedVisual { face, flowBrandmark }

class NavigationItem {
  const NavigationItem({
    required this.path,
    required this.label,
    required this.displayLabel,
    required this.icon,
    this.role = NavigationItemRole.standard,
    this.selectedVisual = NavigationSelectedVisual.face,
  });

  final String path;
  final String label;
  final String displayLabel;
  final IconData icon;
  final NavigationItemRole role;
  final NavigationSelectedVisual selectedVisual;
}

/// 主导航使用等宽入口：玻璃胶囊、连续圆盘与上浮表情圆盘。
class TrainMateBottomNavigation extends StatefulWidget {
  const TrainMateBottomNavigation({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.animationDuration,
    required this.onDestinationSelected,
    this.surfaceColor = TrainFlowTokens.navigationSurface,
  })  : assert(items.length >= 2),
        assert(selectedIndex >= 0 && selectedIndex < items.length);

  final List<NavigationItem> items;
  final int selectedIndex;
  final Duration animationDuration;
  final ValueChanged<int> onDestinationSelected;
  final Color surfaceColor;

  @override
  State<TrainMateBottomNavigation> createState() =>
      _TrainMateBottomNavigationState();
}

class _TrainMateBottomNavigationState extends State<TrainMateBottomNavigation>
    with TickerProviderStateMixin {
  late final AnimationController _selectionController;
  late final AnimationController _pressController;
  late final Listenable _navigationRepaint;
  late List<double> _fromWeights;
  late List<double> _toWeights;
  late double _fromDiscPosition;
  late int _targetIndex;
  int? _pressedIndex;
  bool? _motionEnabled;

  List<double> get _currentWeights {
    if (_selectionController.value >= 1) {
      return List<double>.of(_toWeights);
    }
    final double timeline = const Interval(
      0.35,
      0.65,
      curve: Curves.easeInOut,
    ).transform(_selectionController.value.clamp(0, 1));
    return List<double>.generate(widget.items.length, (int index) {
      return ui.lerpDouble(_fromWeights[index], _toWeights[index], timeline)!;
    });
  }

  double get _currentDiscPosition {
    if (_selectionController.value >= 1) {
      return _targetIndex + 0.5;
    }
    final double timeline = TrainFlowMotion.easeOut.transform(
      _selectionController.value.clamp(0, 1),
    );
    return ui.lerpDouble(_fromDiscPosition, _targetIndex + 0.5, timeline)!;
  }

  @override
  void initState() {
    super.initState();
    _fromWeights = _oneHot(widget.selectedIndex);
    _toWeights = List<double>.of(_fromWeights);
    _fromDiscPosition = widget.selectedIndex + 0.5;
    _targetIndex = widget.selectedIndex;
    _selectionController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
      value: 1,
    );
    _pressController = AnimationController(
      vsync: this,
      duration: TrainFlowMotion.button,
    );
    _navigationRepaint = Listenable.merge(<Listenable>[
      _selectionController,
      _pressController,
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool enabled = TrainFlowMotion.isEnabled(context) &&
        widget.animationDuration != Duration.zero;
    if (_motionEnabled == enabled) return;
    _motionEnabled = enabled;
    _pressController.duration =
        enabled ? TrainFlowMotion.button : Duration.zero;
    if (!enabled) {
      _jumpToSelection();
    }
  }

  @override
  void didUpdateWidget(TrainMateBottomNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationDuration != widget.animationDuration) {
      _selectionController.duration = widget.animationDuration;
    }
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _moveToSelection();
      return;
    }
  }

  void _jumpToSelection() {
    _selectionController.stop();
    _fromWeights = _oneHot(widget.selectedIndex);
    _toWeights = List<double>.of(_fromWeights);
    _fromDiscPosition = widget.selectedIndex + 0.5;
    _targetIndex = widget.selectedIndex;
    _selectionController.value = 1;
  }

  void _moveToSelection() {
    if (!(_motionEnabled ?? false)) {
      _jumpToSelection();
      return;
    }

    final List<double> currentWeights = _currentWeights;
    final double currentDiscPosition = _currentDiscPosition;
    _fromWeights = List<double>.of(currentWeights);
    _toWeights = _oneHot(widget.selectedIndex);
    _fromDiscPosition = currentDiscPosition;
    _targetIndex = widget.selectedIndex;
    _selectionController
      ..value = 0
      ..forward();
  }

  List<double> _oneHot(int selectedIndex) {
    return List<double>.generate(
      widget.items.length,
      (int index) => index == selectedIndex ? 1 : 0,
    );
  }

  double _horizontalInset(double maxWidth) {
    final double maximumInset = math.max(
      0.0,
      (maxWidth -
              TrainFlowTokens.bottomNavigationMinimumItemWidth *
                  widget.items.length) /
          2,
    );
    return math.min(
      TrainFlowTokens.bottomNavigationHorizontalInset,
      math.max(
        TrainFlowTokens.bottomNavigationMinimumHorizontalInset,
        maximumInset,
      ),
    );
  }

  void _setPressed(int index, bool pressed) {
    if (pressed) {
      if (_pressedIndex != index) {
        setState(() => _pressedIndex = index);
      }
      _pressController.forward(from: 0);
      return;
    }
    if (_pressedIndex != index) return;
    _pressController.reverse().whenComplete(() {
      if (!mounted || _pressController.value != 0 || _pressedIndex != index) {
        return;
      }
      setState(() => _pressedIndex = null);
    });
  }

  @override
  void dispose() {
    _selectionController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey<String>('trainmate-bottom-navigation-surface'),
      color: widget.surfaceColor,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: TrainFlowTokens.pageMaxWidth),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double inset = _horizontalInset(constraints.maxWidth);
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  child: SizedBox(
                    key: const ValueKey<String>(
                      'trainmate-bottom-navigation',
                    ),
                    height: TrainFlowTokens.bottomNavigationVisualHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Positioned(
                          left: 0,
                          right: 0,
                          top: TrainFlowTokens.bottomNavigationPillTop,
                          height: TrainFlowTokens.bottomNavigationPillHeight,
                          child: RepaintBoundary(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(
                                  TrainFlowTokens.bottomNavigationPillRadius,
                                ),
                              ),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX:
                                      TrainFlowTokens.bottomNavigationBlurSigma,
                                  sigmaY:
                                      TrainFlowTokens.bottomNavigationBlurSigma,
                                ),
                                child: CustomPaint(
                                  key: const ValueKey<String>(
                                    'trainmate-bottom-navigation-pill',
                                  ),
                                  painter:
                                      const TrainMateNavigationStaticBarPainter(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: TrainFlowTokens.bottomNavigationPillTop,
                          height: TrainFlowTokens.bottomNavigationPillHeight,
                          child: ExcludeSemantics(
                            child: IgnorePointer(
                              child: AnimatedBuilder(
                                animation: _navigationRepaint,
                                builder: (BuildContext context, Widget? child) {
                                  final List<double> weights = _currentWeights;
                                  return Row(
                                    key: const ValueKey<String>(
                                      'trainmate-bottom-navigation-visuals',
                                    ),
                                    children: <Widget>[
                                      for (int index = 0;
                                          index < widget.items.length;
                                          index += 1)
                                        Expanded(
                                          child: _NavigationItemVisual(
                                            item: widget.items[index],
                                            selectionWeight: weights[index],
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: -TrainFlowTokens.bottomNavigationPaintOverflow,
                          right: -TrainFlowTokens.bottomNavigationPaintOverflow,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: AnimatedBuilder(
                                animation: _navigationRepaint,
                                builder: (BuildContext context, Widget? child) {
                                  return CustomPaint(
                                    key: const ValueKey<String>(
                                      'trainmate-bottom-navigation-dynamic-layer',
                                    ),
                                    painter: TrainMateNavigationBarPainter(
                                      items: widget.items,
                                      selectionWeights: _currentWeights,
                                      discPosition: _currentDiscPosition,
                                      targetIndex: _targetIndex,
                                      surfaceColor: widget.surfaceColor,
                                      pressedIndex: _pressedIndex,
                                      pressProgress: TrainFlowMotion.easeOut
                                          .transform(_pressController.value),
                                      horizontalOverflow: TrainFlowTokens
                                          .bottomNavigationPaintOverflow,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        // 品牌图形必须位于选中圆盘之上，避免被暖黑圆盘遮住。
                        Positioned(
                          left: -TrainFlowTokens.bottomNavigationPaintOverflow,
                          right: -TrainFlowTokens.bottomNavigationPaintOverflow,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _navigationRepaint,
                              builder: (BuildContext context, Widget? child) {
                                return _NavigationBrandmarkOverlay(
                                  key: const ValueKey<String>(
                                    'trainmate-bottom-navigation-brandmark-overlay',
                                  ),
                                  items: widget.items,
                                  selectionWeights: _currentWeights,
                                  discPosition: _currentDiscPosition,
                                  horizontalOverflow: TrainFlowTokens
                                      .bottomNavigationPaintOverflow,
                                );
                              },
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Row(
                            children: <Widget>[
                              for (int index = 0;
                                  index < widget.items.length;
                                  index += 1)
                                _NavigationButton(
                                  item: widget.items[index],
                                  index: index,
                                  selected: widget.selectedIndex == index,
                                  onPressed: () =>
                                      widget.onDestinationSelected(index),
                                  onPressedChanged: (bool pressed) =>
                                      _setPressed(index, pressed),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationItemVisual extends StatelessWidget {
  const _NavigationItemVisual({
    required this.item,
    required this.selectionWeight,
  });

  final NavigationItem item;
  final double selectionWeight;

  @override
  Widget build(BuildContext context) {
    final double selected = selectionWeight.clamp(0, 1);
    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[
          Positioned(
            top: TrainFlowTokens.bottomNavigationInlineIconTop,
            child: Opacity(
              opacity: 1 - selected,
              child: TrainMateNavigationFaceGlyph(
                role: item.role,
                size: TrainFlowTokens.bottomNavigationIconSize,
                faceColor: TrainFlowTokens.navigationInactive,
                markColor: TrainFlowTokens.navigationPillSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationBrandmarkOverlay extends StatelessWidget {
  const _NavigationBrandmarkOverlay({
    super.key,
    required this.items,
    required this.selectionWeights,
    required this.discPosition,
    required this.horizontalOverflow,
  });

  final List<NavigationItem> items;
  final List<double> selectionWeights;
  final double discPosition;
  final double horizontalOverflow;

  @override
  Widget build(BuildContext context) {
    final int brandmarkIndex = items.indexWhere(
      (NavigationItem item) =>
          item.selectedVisual == NavigationSelectedVisual.flowBrandmark,
    );
    if (brandmarkIndex < 0) return const SizedBox.shrink();
    final double opacity = selectionWeights[brandmarkIndex].clamp(0, 1);
    if (opacity <= 0.001) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double contentWidth =
            constraints.maxWidth - horizontalOverflow * 2;
        final double itemWidth = contentWidth / items.length;
        final double center = horizontalOverflow + itemWidth * discPosition;
        final double size = TrainFlowTokens.bottomNavigationSelectedInnerSize;
        return Stack(
          children: <Widget>[
            Positioned(
              left: center - size / 2,
              top: TrainFlowTokens.bottomNavigationPillTop +
                  TrainFlowTokens.bottomNavigationSelectedCenterFromPillTop -
                  size / 2,
              width: size,
              height: size,
              child: Opacity(
                opacity: opacity,
                child: const TrainMateBrandmark(size: 44),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 参考图风格的线性导航图标，避免依赖运行环境中的图标字体。
class TrainMateNavigationReferenceIcon extends StatelessWidget {
  const TrainMateNavigationReferenceIcon({
    super.key,
    required this.role,
    required this.size,
    required this.color,
  });

  final NavigationItemRole role;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _TrainMateNavigationReferenceIconPainter(
          role: role,
          color: color,
        ),
      ),
    );
  }
}

class _TrainMateNavigationReferenceIconPainter extends CustomPainter {
  const _TrainMateNavigationReferenceIconPainter({
    required this.role,
    required this.color,
  });

  final NavigationItemRole role;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    switch (role) {
      case NavigationItemRole.today:
        _paintHome(canvas, size);
      case NavigationItemRole.plan:
        _paintCalendar(canvas, size);
      case NavigationItemRole.partner:
        _paintPartner(canvas, size);
      case NavigationItemRole.ai:
        _paintSparkle(canvas, size);
      case NavigationItemRole.exercises:
        _paintBook(canvas, size);
      case NavigationItemRole.profile:
        _paintProfile(canvas, size);
      case NavigationItemRole.standard:
        _paintCard(canvas, size);
    }
  }

  Paint _stroke(Size size) {
    return Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
  }

  void _paintHome(Canvas canvas, Size size) {
    final Path roof = Path()
      ..moveTo(size.width * 0.14, size.height * 0.48)
      ..lineTo(size.width * 0.5, size.height * 0.16)
      ..lineTo(size.width * 0.86, size.height * 0.48);
    final Paint stroke = _stroke(size);
    canvas.drawPath(roof, stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.24,
          size.height * 0.44,
          size.width * 0.52,
          size.height * 0.4,
        ),
        Radius.circular(size.width * 0.05),
      ),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.84),
      Offset(size.width * 0.5, size.height * 0.62),
      stroke,
    );
  }

  void _paintCalendar(Canvas canvas, Size size) {
    final Paint stroke = _stroke(size);
    final RRect frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.16,
        size.height * 0.23,
        size.width * 0.68,
        size.height * 0.62,
      ),
      Radius.circular(size.width * 0.12),
    );
    canvas.drawRRect(frame, stroke);
    canvas.drawLine(
      Offset(size.width * 0.16, size.height * 0.45),
      Offset(size.width * 0.84, size.height * 0.45),
      stroke,
    );
    for (final double x in <double>[0.34, 0.66]) {
      canvas.drawLine(
        Offset(size.width * x, size.height * 0.15),
        Offset(size.width * x, size.height * 0.32),
        stroke,
      );
    }
  }

  void _paintPartner(Canvas canvas, Size size) {
    final Paint stroke = _stroke(size);
    canvas.drawCircle(
      Offset(size.width * 0.38, size.height * 0.38),
      size.width * 0.12,
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width * 0.66, size.height * 0.42),
      size.width * 0.1,
      stroke,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.45,
        size.width * 0.43,
        size.height * 0.36,
      ),
      math.pi,
      math.pi,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * 0.45,
        size.height * 0.5,
        size.width * 0.32,
        size.height * 0.28,
      ),
      math.pi,
      math.pi,
      false,
      stroke,
    );
  }

  void _paintSparkle(Canvas canvas, Size size) {
    final Paint stroke = _stroke(size);
    final Path star = Path()
      ..moveTo(size.width * 0.5, size.height * 0.12)
      ..lineTo(size.width * 0.59, size.height * 0.41)
      ..lineTo(size.width * 0.88, size.height * 0.5)
      ..lineTo(size.width * 0.59, size.height * 0.59)
      ..lineTo(size.width * 0.5, size.height * 0.88)
      ..lineTo(size.width * 0.41, size.height * 0.59)
      ..lineTo(size.width * 0.12, size.height * 0.5)
      ..lineTo(size.width * 0.41, size.height * 0.41)
      ..close();
    canvas.drawPath(star, stroke);
  }

  void _paintBook(Canvas canvas, Size size) {
    final Paint stroke = _stroke(size);
    final RRect left = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.14,
        size.height * 0.2,
        size.width * 0.36,
        size.height * 0.62,
      ),
      Radius.circular(size.width * 0.06),
    );
    final RRect right = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.5,
        size.height * 0.2,
        size.width * 0.36,
        size.height * 0.62,
      ),
      Radius.circular(size.width * 0.06),
    );
    canvas.drawRRect(left, stroke);
    canvas.drawRRect(right, stroke);
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.24),
      Offset(size.width * 0.5, size.height * 0.82),
      stroke,
    );
  }

  void _paintProfile(Canvas canvas, Size size) {
    final Paint stroke = _stroke(size);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      size.width * 0.38,
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.39),
      size.width * 0.13,
      stroke,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * 0.27,
        size.height * 0.48,
        size.width * 0.46,
        size.height * 0.32,
      ),
      math.pi,
      math.pi,
      false,
      stroke,
    );
  }

  void _paintCard(Canvas canvas, Size size) {
    final Paint stroke = _stroke(size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.13,
          size.height * 0.24,
          size.width * 0.74,
          size.height * 0.52,
        ),
        Radius.circular(size.width * 0.1),
      ),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.16, size.height * 0.48),
      Offset(size.width * 0.84, size.height * 0.48),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_TrainMateNavigationReferenceIconPainter oldDelegate) {
    return oldDelegate.role != role || oldDelegate.color != color;
  }
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.item,
    required this.index,
    required this.selected,
    required this.onPressed,
    required this.onPressedChanged,
  });

  final NavigationItem item;
  final int index;
  final bool selected;
  final VoidCallback onPressed;
  final ValueChanged<bool> onPressedChanged;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        key: ValueKey<String>('bottom-nav-item-$index'),
        label: item.label,
        button: true,
        selected: selected,
        sortKey: OrdinalSortKey(index.toDouble()),
        onTap: onPressed,
        excludeSemantics: true,
        child: Tooltip(
          message: item.label,
          excludeFromSemantics: true,
          child: Material(
            color: AppColors.transparent,
            child: InkResponse(
              onTap: () {
                onPressedChanged(false);
                onPressed();
              },
              onTapDown: (_) => onPressedChanged(true),
              onTapCancel: () => onPressedChanged(false),
              onTapUp: (_) => onPressedChanged(false),
              containedInkWell: true,
              highlightShape: BoxShape.circle,
              radius: 24,
              splashColor: AppColors.transparent,
              highlightColor: AppColors.transparent,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

/// 参考视频风格的圆角气泡表情，所有路径均为矢量，任意密度保持清晰。
class TrainMateNavigationFaceGlyph extends StatelessWidget {
  const TrainMateNavigationFaceGlyph({
    super.key,
    required this.role,
    required this.size,
    required this.faceColor,
    required this.markColor,
  });

  final NavigationItemRole role;
  final double size;
  final Color faceColor;
  final Color markColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _TrainMateNavigationFacePainter(
          role: role,
          faceColor: faceColor,
          markColor: markColor,
        ),
      ),
    );
  }
}

/// 兼容上一版公开 AI 图标接口。
class TrainMateAiGlyph extends StatelessWidget {
  const TrainMateAiGlyph({
    super.key,
    required this.size,
    required this.faceColor,
    required this.dotColor,
  });

  final double size;
  final Color faceColor;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return TrainMateNavigationFaceGlyph(
      role: NavigationItemRole.ai,
      size: size,
      faceColor: faceColor,
      markColor: dotColor,
    );
  }
}

class _TrainMateNavigationFacePainter extends CustomPainter {
  const _TrainMateNavigationFacePainter({
    required this.role,
    required this.faceColor,
    required this.markColor,
  });

  final NavigationItemRole role;
  final Color faceColor;
  final Color markColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint facePaint = Paint()..color = faceColor;
    final Rect faceRect = Rect.fromLTWH(
      size.width * 0.11,
      size.height * 0.17,
      size.width * 0.76,
      size.height * 0.6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        faceRect,
        Radius.circular(size.width * 0.21),
      ),
      facePaint,
    );
    final Path tail = Path()
      ..moveTo(size.width * 0.64, size.height * 0.7)
      ..quadraticBezierTo(
        size.width * 0.83,
        size.height * 0.9,
        size.width * 0.79,
        size.height * 0.62,
      )
      ..close();
    canvas.drawPath(tail, facePaint);

    switch (role) {
      case NavigationItemRole.today:
        _paintToday(canvas, size);
      case NavigationItemRole.plan:
        _paintPlan(canvas, size);
      case NavigationItemRole.partner:
        _paintPartner(canvas, size);
      case NavigationItemRole.ai:
      case NavigationItemRole.standard:
        _paintAi(canvas, size);
      case NavigationItemRole.exercises:
        _paintExercises(canvas, size);
      case NavigationItemRole.profile:
        _paintProfile(canvas, size);
    }
  }

  Paint _stroke(Size size) {
    return Paint()
      ..color = markColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.065
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
  }

  void _dot(Canvas canvas, Size size, double x, double y,
      [double radius = 0.045]) {
    canvas.drawCircle(
      Offset(size.width * x, size.height * y),
      size.width * radius,
      Paint()..color = markColor,
    );
  }

  void _paintToday(Canvas canvas, Size size) {
    _dot(canvas, size, 0.39, 0.44);
    _dot(canvas, size, 0.58, 0.44);
    final Path smile = Path()
      ..moveTo(size.width * 0.39, size.height * 0.56)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.68,
        size.width * 0.64,
        size.height * 0.51,
      );
    canvas.drawPath(smile, _stroke(size));
    final Paint starPaint = _stroke(size)..strokeWidth = size.width * 0.045;
    canvas.drawLine(
      Offset(size.width * 0.7, size.height * 0.3),
      Offset(size.width * 0.7, size.height * 0.4),
      starPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.65, size.height * 0.35),
      Offset(size.width * 0.75, size.height * 0.35),
      starPaint,
    );
  }

  void _paintPlan(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = markColor;
    final double side = size.width * 0.1;
    for (final double x in <double>[0.39, 0.59]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width * x, size.height * 0.44),
            width: side,
            height: side,
          ),
          Radius.circular(side * 0.25),
        ),
        paint,
      );
    }
    canvas.drawLine(
      Offset(size.width * 0.42, size.height * 0.6),
      Offset(size.width * 0.62, size.height * 0.6),
      _stroke(size),
    );
  }

  void _paintPartner(Canvas canvas, Size size) {
    _dot(canvas, size, 0.39, 0.45);
    final Path wink = Path()
      ..moveTo(size.width * 0.55, size.height * 0.46)
      ..quadraticBezierTo(
        size.width * 0.61,
        size.height * 0.41,
        size.width * 0.67,
        size.height * 0.46,
      );
    canvas.drawPath(wink, _stroke(size));
    final Path smile = Path()
      ..moveTo(size.width * 0.42, size.height * 0.57)
      ..quadraticBezierTo(
        size.width * 0.53,
        size.height * 0.68,
        size.width * 0.64,
        size.height * 0.57,
      );
    canvas.drawPath(smile, _stroke(size));
  }

  void _paintAi(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = markColor;
    final double width = size.width * 0.07;
    final List<double> heights = <double>[0.16, 0.24, 0.16];
    for (int index = 0; index < heights.length; index += 1) {
      final double height = size.height * heights[index];
      final Rect rect = Rect.fromCenter(
        center: Offset(size.width * (0.4 + index * 0.1), size.height * 0.49),
        width: width,
        height: height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(width / 2)),
        paint,
      );
    }
  }

  void _paintExercises(Canvas canvas, Size size) {
    final Paint paint = _stroke(size);
    canvas.drawLine(
      Offset(size.width * 0.35, size.height * 0.47),
      Offset(size.width * 0.43, size.height * 0.4),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.57, size.height * 0.4),
      Offset(size.width * 0.65, size.height * 0.47),
      paint,
    );
    final Path bolt = Path()
      ..moveTo(size.width * 0.43, size.height * 0.58)
      ..lineTo(size.width * 0.51, size.height * 0.54)
      ..lineTo(size.width * 0.49, size.height * 0.64)
      ..lineTo(size.width * 0.59, size.height * 0.58);
    canvas.drawPath(bolt, paint);
  }

  void _paintProfile(Canvas canvas, Size size) {
    _dot(canvas, size, 0.4, 0.44);
    _dot(canvas, size, 0.6, 0.44);
    final Path smile = Path()
      ..moveTo(size.width * 0.4, size.height * 0.56)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.7,
        size.width * 0.61,
        size.height * 0.56,
      );
    canvas.drawPath(smile, _stroke(size));
  }

  @override
  bool shouldRepaint(_TrainMateNavigationFacePainter oldDelegate) {
    return oldDelegate.role != role ||
        oldDelegate.faceColor != faceColor ||
        oldDelegate.markColor != markColor;
  }
}

/// 只绘制悬浮玻璃导航胶囊；模糊在静态层中完成，避免动画时重复采样。
class TrainMateNavigationStaticBarPainter extends CustomPainter {
  const TrainMateNavigationStaticBarPainter({
    this.pillColor = TrainFlowTokens.navigationPillSurface,
    this.shadowColor = TrainFlowTokens.navigationGlassShadow,
  });

  final Color pillColor;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect pill = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(TrainFlowTokens.bottomNavigationPillRadius),
    );
    if (shadowColor.a > 0) {
      final Path shadowPath = Path()..addRRect(pill);
      canvas.drawShadow(shadowPath, shadowColor, 4, false);
    }
    canvas.drawRRect(pill, Paint()..color = pillColor);
    canvas.drawRRect(
      pill,
      Paint()
        ..color = TrainFlowTokens.navigationGlassBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(TrainMateNavigationStaticBarPainter oldDelegate) {
    return oldDelegate.pillColor != pillColor ||
        oldDelegate.shadowColor != shadowColor;
  }
}

/// 绘制玻璃胶囊上连续移动的活动圆盘。
class TrainMateNavigationBarPainter extends CustomPainter {
  const TrainMateNavigationBarPainter({
    required this.items,
    required this.selectionWeights,
    required this.targetIndex,
    required this.surfaceColor,
    this.discPosition = 0.5,
    this.inactiveColor = TrainFlowTokens.navigationInactive,
    this.selectedFaceColor = TrainFlowTokens.navigationSelectedFace,
    this.selectedDiscColor = TrainFlowTokens.navigationInk,
    this.pressedIndex,
    this.pressProgress = 0,
    this.horizontalOverflow = 0,
  });

  final List<NavigationItem> items;
  final List<double> selectionWeights;
  final int targetIndex;
  final Color surfaceColor;
  final double discPosition;
  final Color inactiveColor;
  final Color selectedFaceColor;
  final Color selectedDiscColor;
  final int? pressedIndex;
  final double pressProgress;
  final double horizontalOverflow;

  @override
  void paint(Canvas canvas, Size size) {
    final double contentWidth = size.width - horizontalOverflow * 2;
    final double itemWidth = contentWidth / items.length;
    final Offset center = Offset(
      horizontalOverflow +
          itemWidth * discPosition.clamp(0.5, items.length - 0.5),
      TrainFlowTokens.bottomNavigationPillTop +
          TrainFlowTokens.bottomNavigationSelectedCenterFromPillTop,
    );
    _paintSelection(canvas, center);
  }

  void _paintSelection(Canvas canvas, Offset center) {
    final double scale = _pressScale(targetIndex);
    final double discRadius =
        TrainFlowTokens.bottomNavigationSelectedSize / 2 * scale;
    canvas.drawCircle(
      center,
      discRadius + TrainFlowTokens.bottomNavigationSelectedRingWidth,
      Paint()..color = TrainFlowTokens.navigationAccent.withValues(alpha: 0.42),
    );
    canvas.drawCircle(center, discRadius, Paint()..color = selectedDiscColor);
    for (int index = 0; index < items.length; index += 1) {
      final double opacity = selectionWeights[index].clamp(0, 1);
      if (opacity <= 0.001) continue;
      _paintFace(
        canvas,
        item: items[index],
        center: center,
        opacity: opacity,
        scale: scale,
      );
    }
  }

  double _pressScale(int index) {
    if (pressedIndex != index) return 1;
    return ui.lerpDouble(1, 0.94, pressProgress.clamp(0, 1))!;
  }

  void _paintFace(
    Canvas canvas, {
    required NavigationItem item,
    required Offset center,
    required double opacity,
    required double scale,
  }) {
    if (item.selectedVisual == NavigationSelectedVisual.flowBrandmark) {
      return;
    }
    final double size = TrainFlowTokens.bottomNavigationSelectedInnerSize;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale, scale);
    canvas.translate(-size / 2, -size / 2);
    _TrainMateNavigationFacePainter(
      role: item.role,
      faceColor: selectedFaceColor.withValues(alpha: opacity),
      markColor: selectedDiscColor.withValues(alpha: opacity),
    ).paint(canvas, Size.square(size));
    canvas.restore();
  }

  @override
  bool shouldRepaint(TrainMateNavigationBarPainter oldDelegate) {
    return !listEquals(oldDelegate.items, items) ||
        !listEquals(oldDelegate.selectionWeights, selectionWeights) ||
        oldDelegate.targetIndex != targetIndex ||
        oldDelegate.surfaceColor != surfaceColor ||
        oldDelegate.discPosition != discPosition ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.selectedFaceColor != selectedFaceColor ||
        oldDelegate.selectedDiscColor != selectedDiscColor ||
        oldDelegate.pressedIndex != pressedIndex ||
        oldDelegate.pressProgress != pressProgress ||
        oldDelegate.horizontalOverflow != horizontalOverflow;
  }
}
