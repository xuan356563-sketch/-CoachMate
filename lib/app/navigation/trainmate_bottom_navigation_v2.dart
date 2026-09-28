import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/trainflow_tokens.dart';
import 'trainmate_bottom_navigation.dart' show NavigationItem;

/// 五槽位深紫导航：选中胶囊在固定入口之间连续移动。
///
/// 外部接口保持与旧 v2 一致，避免影响路由和测试调用；内部不再保留中央常驻球体。
class TrainMateBottomNavigationV2 extends StatefulWidget {
  const TrainMateBottomNavigationV2({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.animationDuration,
    required this.onDestinationSelected,
    this.surfaceColor = Colors.transparent,
  })  : assert(items.length >= 2, '底部导航至少保留今日和我的'),
        assert(selectedIndex >= 0 && selectedIndex < items.length, '导航选中项超出范围');

  final List<NavigationItem> items;
  final int selectedIndex;
  final Duration animationDuration;
  final ValueChanged<int> onDestinationSelected;
  final Color surfaceColor;

  @override
  State<TrainMateBottomNavigationV2> createState() =>
      _TrainMateBottomNavigationV2State();
}

class _TrainMateBottomNavigationV2State
    extends State<TrainMateBottomNavigationV2>
    with SingleTickerProviderStateMixin {
  late final AnimationController _selectionController;
  double _fromPosition = 0;
  double _toPosition = 0;
  int _pressedIndex = -1;

  @override
  void initState() {
    super.initState();
    final double initial = widget.selectedIndex.toDouble();
    _fromPosition = initial;
    _toPosition = initial;
    _selectionController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant TrainMateBottomNavigationV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedItems = widget.items.map((i) => i.path).join('|') !=
        oldWidget.items.map((i) => i.path).join('|');
    if (changedItems) {
      _pressedIndex = -1;
      _fromPosition = widget.selectedIndex.toDouble();
      _toPosition = _fromPosition;
      _selectionController.value = 1;
      return;
    }
    if (widget.selectedIndex == oldWidget.selectedIndex) return;

    final double current = _visualPosition;
    _fromPosition = current;
    _toPosition = widget.selectedIndex.toDouble();
    _selectionController.duration = widget.animationDuration;
    if (!_motionEnabled || widget.animationDuration == Duration.zero) {
      _selectionController.value = 1;
    } else {
      _selectionController.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_motionEnabled && _selectionController.value != 1) {
      _selectionController.value = 1;
    }
  }

  bool get _motionEnabled =>
      TrainFlowMotion.isEnabled(context) &&
      widget.animationDuration != Duration.zero;

  double get _visualPosition {
    final double curved = Curves.easeOutCubic.transform(
      _selectionController.value,
    );
    return ui.lerpDouble(_fromPosition, _toPosition, curved) ?? _toPosition;
  }

  @override
  void dispose() {
    _selectionController.dispose();
    super.dispose();
  }

  void _setPressed(int index, bool pressed) {
    if ((_pressedIndex == index && !pressed) ||
        (_pressedIndex != index && pressed)) {
      setState(() => _pressedIndex = pressed ? index : -1);
    }
  }

  void _select(int index) {
    widget.onDestinationSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey<String>('trainmate-bottom-navigation-surface'),
      color: widget.surfaceColor,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          height: TrainFlowTokens.bottomNavigationVisualHeight,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: TrainFlowTokens.pageMaxWidth,
              ),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double navigationWidth =
                      (constraints.maxWidth - 32).clamp(0, 398).toDouble();
                  final double navigationLeft =
                      (constraints.maxWidth - navigationWidth) / 2;
                  final double slotWidth =
                      navigationWidth / widget.items.length;
                  return SizedBox(
                    height: TrainFlowTokens.bottomNavigationVisualHeight,
                    child: Stack(
                      key:
                          const ValueKey<String>('trainmate-bottom-navigation'),
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Positioned(
                          left: navigationLeft,
                          bottom: 0,
                          width: navigationWidth,
                          height: TrainFlowTokens.bottomNavigationHeight,
                          child: RepaintBoundary(
                            child: DecoratedBox(
                              key: const ValueKey<String>(
                                'trainmate-bottom-navigation-v2-capsule',
                              ),
                              decoration: BoxDecoration(
                                color: TrainFlowTokens.showcaseActionSurface,
                                borderRadius: BorderRadius.circular(32),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(
                                    color: TrainFlowTokens.showcaseShadow,
                                    blurRadius: 12,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: <Widget>[
                                  for (int index = 0;
                                      index < widget.items.length;
                                      index += 1)
                                    Expanded(
                                      child: _NavigationSlot(
                                        item: widget.items[index],
                                        index: index,
                                        selected: widget.selectedIndex == index,
                                        pressed: _pressedIndex == index,
                                        motionEnabled: _motionEnabled,
                                        onPressed: () => _select(index),
                                        onPressedChanged: (bool pressed) =>
                                            _setPressed(index, pressed),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _selectionController,
                          builder: (BuildContext context, Widget? child) {
                            final int targetIndex = widget.selectedIndex;
                            final double left = navigationLeft +
                                _visualPosition * slotWidth +
                                (slotWidth -
                                        TrainFlowTokens
                                            .bottomNavigationSelectedPillWidth) /
                                    2;
                            return Positioned(
                              left: left,
                              bottom: 4,
                              width: TrainFlowTokens
                                  .bottomNavigationSelectedPillWidth,
                              height: TrainFlowTokens
                                  .bottomNavigationSelectedPillHeight,
                              child: IgnorePointer(
                                child: RepaintBoundary(
                                  child: _SelectedNavigationPill(
                                    item: widget.items[targetIndex],
                                    yellow: targetIndex == 1,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationSlot extends StatelessWidget {
  const _NavigationSlot({
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
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey<String>('bottom-nav-item-$index'),
      button: true,
      selected: selected,
      label: item.label,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: item.label,
        excludeFromSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: onPressed,
            onTapDown: (_) => onPressedChanged(true),
            onTapCancel: () => onPressedChanged(false),
            onTapUp: (_) => onPressedChanged(false),
            radius: 28,
            containedInkWell: true,
            highlightShape: BoxShape.circle,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Center(
              child: AnimatedScale(
                scale: pressed && motionEnabled ? 0.9 : 1,
                duration: TrainFlowMotion.resolve(
                  context,
                  const Duration(milliseconds: 120),
                ),
                curve: Curves.easeOut,
                child: Icon(
                  item.icon,
                  size: 24,
                  color: TrainFlowTokens.paper.withValues(
                    alpha: selected ? 0 : 0.86,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedNavigationPill extends StatelessWidget {
  const _SelectedNavigationPill({required this.item, required this.yellow});

  final NavigationItem item;
  final bool yellow;

  @override
  Widget build(BuildContext context) {
    const Color foreground = TrainFlowTokens.brandDark;
    return DecoratedBox(
      key: const ValueKey<String>('trainmate-bottom-navigation-selected-pill'),
      decoration: BoxDecoration(
        color: yellow ? TrainFlowTokens.yellow : TrainFlowTokens.paper,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x24191331),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(item.icon, size: 21, color: foreground),
            const SizedBox(height: 1),
            Text(
              item.displayLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
