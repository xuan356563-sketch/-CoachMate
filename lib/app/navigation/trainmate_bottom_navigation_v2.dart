import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/trainflow_tokens.dart';
import '../../core/widgets/coach_mate_orb.dart';
import 'trainmate_bottom_navigation.dart' show NavigationItem;

/// 底部导航 v2：悬浮白玻璃胶囊 + 中央 hero 球体（AI / 运动搭子入口）。
///
/// 参考图形态：5 等分 —— 4 角线性图标（无文字标签）+ 中央 64pt 渐变球体向上凸出；
/// 角落 Tab 选中用深色圆底 + 青柠图标，切换为颜色 / 缩放过渡（无滑动圆盘）。
class TrainMateBottomNavigationV2 extends StatefulWidget {
  const TrainMateBottomNavigationV2({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.animationDuration,
    required this.onDestinationSelected,
    this.surfaceColor = Colors.transparent,
  }) : assert(items.length == 5, '底部导航 v2 需要 5 个槽位（含中央球体）');

  final List<NavigationItem> items;
  final int selectedIndex;
  final Duration animationDuration;
  final ValueChanged<int> onDestinationSelected;
  final Color surfaceColor;

  /// 中央球体固定在第 3 格（index 2）。
  static const int orbIndex = 2;

  @override
  State<TrainMateBottomNavigationV2> createState() =>
      _TrainMateBottomNavigationV2State();
}

class _TrainMateBottomNavigationV2State
    extends State<TrainMateBottomNavigationV2>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idleController;
  bool _orbEntranceStarted = false;
  int _pressedIndex = -1;

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 光斑流动只播一次（进场动效），避免无限 repeat 阻塞测试 settle。
    if (_orbEntranceStarted) return;
    _orbEntranceStarted = true;
    if (TrainFlowMotion.isEnabled(context)) {
      _idleController.forward();
    } else {
      _idleController.value = 0.3;
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    super.dispose();
  }

  void _setPressed(int index, bool pressed) {
    if (pressed && _pressedIndex != index) {
      setState(() => _pressedIndex = index);
    } else if (!pressed && _pressedIndex == index) {
      setState(() => _pressedIndex = -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey<String>('trainmate-bottom-navigation-surface'),
      color: widget.surfaceColor,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 16),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: TrainFlowTokens.pageMaxWidth,
            ),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double viewWidth = constraints.maxWidth;
                final double capsuleWidth =
                    math.min(viewWidth - 32, TrainFlowTokens.pageMaxWidth - 32);
                final double capsuleLeft = (viewWidth - capsuleWidth) / 2;
                final double orbSize = 56;
                return SizedBox(
                  height: TrainFlowTokens.bottomNavigationVisualHeight,
                  child: Stack(
                    key: const ValueKey<String>(
                      'trainmate-bottom-navigation',
                    ),
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 96,
                        child: IgnorePointer(
                          child: _BottomGlow(
                            animation: widget.animationDuration == Duration.zero
                                ? 0.3
                                : _idleController.value,
                          ),
                        ),
                      ),
                      Positioned(
                        left: capsuleLeft,
                        bottom: 16,
                        width: capsuleWidth,
                        height: 76,
                        child: _buildCapsule(
                          capsuleWidth: capsuleWidth,
                        ),
                      ),
                      Positioned(
                        left: capsuleLeft + capsuleWidth / 2 - orbSize / 2,
                        top: 2,
                        width: orbSize,
                        height: orbSize,
                        child: _buildOrb(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCapsule({required double capsuleWidth}) {
    return Container(
      key: const ValueKey<String>('trainmate-bottom-navigation-v2-capsule'),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: TrainFlowTokens.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x26191331),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
          BoxShadow(color: Color(0x146C3DF4), blurRadius: 16),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Row(
            children: <Widget>[
              for (int index = 0; index < widget.items.length; index += 1)
                Expanded(
                  child: index == TrainMateBottomNavigationV2.orbIndex
                      ? _OrbLabelCell(item: widget.items[index], selected: widget.selectedIndex == index)
                      : _CornerTab(
                          item: widget.items[index],
                          index: index,
                          selected: widget.selectedIndex == index,
                          pressed: _pressedIndex == index,
                          motionEnabled:
                              TrainFlowMotion.isEnabled(context),
                          onPressed: () =>
                              widget.onDestinationSelected(index),
                          onPressedChanged: (bool pressed) =>
                              _setPressed(index, pressed),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrb() {
    final int orbIndex = TrainMateBottomNavigationV2.orbIndex;
    final NavigationItem item = widget.items[orbIndex];
    final bool active = widget.selectedIndex == orbIndex;
    return Semantics(
      key: ValueKey<String>('bottom-nav-item-$orbIndex'),
      label: item.label,
      button: true,
      selected: active,
      onTap: () => widget.onDestinationSelected(orbIndex),
      excludeSemantics: true,
      child: Tooltip(
        message: item.label,
        excludeFromSemantics: true,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: TrainFlowMotion.resolve(
            context,
            TrainFlowMotion.sceneEntrance,
          ),
          curve: TrainFlowMotion.easeOut,
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              onTap: () => widget.onDestinationSelected(orbIndex),
              radius: 32,
              containedInkWell: true,
              customBorder: const CircleBorder(),
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: CoachMateOrb(
                size: 56,
                active: active,
                phase: widget.animationDuration == Duration.zero
                    ? 0.3
                    : _idleController.value,
                paintKey: const ValueKey<String>('central-hero-orb'),
              ),
            ),
          ),
          builder: (BuildContext context, double value, Widget? child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(
                scale: 0.8 + 0.2 * value,
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 角落 Tab：28pt 线性图标，选中为深色圆底 + 青柠图标（含发光）。
class _CornerTab extends StatefulWidget {
  const _CornerTab({
    required this.item,
    required this.index,
    required this.selected,
    required this.pressed,
    required this.motionEnabled,
    required this.onPressed,
    required this.onPressedChanged,
  });

  final NavigationItem item;
  final int index;
  final bool selected;
  final bool pressed;
  final bool motionEnabled;
  final VoidCallback onPressed;
  final ValueChanged<bool> onPressedChanged;

  @override
  State<_CornerTab> createState() => _CornerTabState();
}

class _CornerTabState extends State<_CornerTab> {
  @override
  Widget build(BuildContext context) {
    final Duration duration = TrainFlowMotion.resolve(
      context,
      TrainFlowMotion.navigationStandardSelection,
    );
    final double scale = widget.pressed && widget.motionEnabled ? 0.92 : 1;
    final Color iconColor =
        widget.selected ? TrainFlowTokens.accent : TrainFlowTokens.navigationInactive;
    return Semantics(
      key: ValueKey<String>('bottom-nav-item-${widget.index}'),
      button: true,
      selected: widget.selected,
      label: widget.item.label,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.item.label,
        excludeFromSemantics: true,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              onTap: widget.onPressed,
              onTapDown: (_) => widget.onPressedChanged(true),
              onTapCancel: () => widget.onPressedChanged(false),
              onTapUp: (_) => widget.onPressedChanged(false),
              containedInkWell: true,
              highlightShape: BoxShape.circle,
              radius: 24,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: AnimatedScale(
                scale: scale,
                duration: duration,
                curve: TrainFlowMotion.easeOut,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AnimatedContainer(
                      duration: duration,
                      curve: TrainFlowMotion.easeOut,
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: widget.selected
                            ? TrainFlowTokens.brandDark
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: widget.selected
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: TrainFlowTokens.accentGlow,
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        widget.item.icon,
                        size: 28,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.4,
                      child: Text(
                        widget.item.displayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: iconColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 中央球体下方的标签格：给球体留位，标签与角落对齐。
class _OrbLabelCell extends StatelessWidget {
  const _OrbLabelCell({required this.item, required this.selected});

  final NavigationItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(width: 48, height: 48),
        const SizedBox(height: 3),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.4,
          child: Text(
            item.displayLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected
                      ? TrainFlowTokens.accent
                      : TrainFlowTokens.navigationLabelInactive,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

/// 胶囊下方的彩色光晕（暖黑 → 荧光绿 → 淡紫）。
class _BottomGlow extends StatelessWidget {
  const _BottomGlow({required this.animation});

  final double animation;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            TrainFlowTokens.accent.withValues(alpha: 0.18),
            const Color(0xFFB388EB).withValues(alpha: 0.10),
            Colors.transparent,
          ],
          stops: const <double>[0.0, 0.45, 1.0],
        ),
      ),
    );
  }
}
