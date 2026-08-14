import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/trainflow_tokens.dart';
import 'trainmate_action_character.dart';

enum FlowMascotMood { ready, recovery, race, onboarding, empty }

/// 旧版动作名称继续保留，避免现有业务状态选择函数失效。
enum FlowMascotAction {
  jog,
  thumbsUp,
  plan,
  thinkCalendar,
  pointSuggestion,
  nodCheck,
  stretch,
  sprint,
  meditate,
  celebrate,
  scan,
  recover,
  beckon,
  correct,
  search,
  startLine,
  listen,
}

/// 表情用于兼容既有业务调用、无障碍语义和 Flow V2 素材的状态选择。
enum FlowMascotExpression {
  wink,
  smile,
  focused,
  determined,
  calm,
  concerned,
  closed,
  happy,
  curious,
}

@immutable
class FlowMascotPalette {
  final Color body;
  final Color outline;
  final Color face;
  final Color headband;
  final Color facialFeature;
  final Color mouth;

  const FlowMascotPalette({
    required this.body,
    required this.outline,
    required this.face,
    required this.headband,
    required this.facialFeature,
    required this.mouth,
  });

  static const FlowMascotPalette brand = FlowMascotPalette(
    body: Color(0xFF19172C),
    outline: Color(0xFF0E0D1B),
    face: Color(0xFFFFFDFC),
    headband: Color(0xFFFF6B4A),
    facialFeature: Color(0xFF19172C),
    mouth: Color(0xFFFF6B4A),
  );

  @override
  bool operator ==(Object other) =>
      other is FlowMascotPalette &&
      other.body == body &&
      other.outline == outline &&
      other.face == face &&
      other.headband == headband &&
      other.facialFeature == facialFeature &&
      other.mouth == mouth;

  @override
  int get hashCode => Object.hash(
        body,
        outline,
        face,
        headband,
        facialFeature,
        mouth,
      );
}

@immutable
class FlowMascotSpec {
  final FlowMascotAction action;
  final FlowMascotExpression expression;
  final String semanticLabel;
  final int durationMilliseconds;
  final int motionCycles;

  const FlowMascotSpec({
    required this.action,
    required this.expression,
    required this.semanticLabel,
    this.durationMilliseconds = 520,
    this.motionCycles = 1,
  })  : assert(durationMilliseconds >= 220),
        assert(durationMilliseconds <= 650),
        assert(motionCycles >= 0 && motionCycles <= 2);

  Duration get duration => Duration(milliseconds: durationMilliseconds);

  static const FlowMascotSpec ready = FlowMascotSpec(
    action: FlowMascotAction.jog,
    expression: FlowMascotExpression.wink,
    semanticLabel: 'Flow 训练伙伴准备出发',
    motionCycles: 2,
  );

  @override
  bool operator ==(Object other) =>
      other is FlowMascotSpec &&
      other.action == action &&
      other.expression == expression &&
      other.semanticLabel == semanticLabel &&
      other.durationMilliseconds == durationMilliseconds &&
      other.motionCycles == motionCycles;

  @override
  int get hashCode => Object.hash(
        action,
        expression,
        semanticLabel,
        durationMilliseconds,
        motionCycles,
      );
}

TrainMateAction trainMateActionForFlowMascot(FlowMascotAction action) {
  return switch (action) {
    FlowMascotAction.jog => TrainMateAction.running,
    FlowMascotAction.thumbsUp => TrainMateAction.treePoseBalance,
    FlowMascotAction.plan ||
    FlowMascotAction.pointSuggestion ||
    FlowMascotAction.beckon ||
    FlowMascotAction.search =>
      TrainMateAction.pointingGuide,
    FlowMascotAction.thinkCalendar ||
    FlowMascotAction.listen ||
    FlowMascotAction.meditate =>
      TrainMateAction.seatedMeditation,
    FlowMascotAction.nodCheck => TrainMateAction.treePoseBalance,
    FlowMascotAction.stretch => TrainMateAction.sideLungeStretch,
    FlowMascotAction.sprint ||
    FlowMascotAction.startLine =>
      TrainMateAction.sprint,
    FlowMascotAction.celebrate => TrainMateAction.jumpingJack,
    FlowMascotAction.scan => TrainMateAction.highKnees,
    FlowMascotAction.recover => TrainMateAction.seatedForwardFold,
    FlowMascotAction.correct => TrainMateAction.squat,
  };
}

FlowMascotSpec _legacyMascotSpec(FlowMascotMood mood) {
  return switch (mood) {
    FlowMascotMood.ready => FlowMascotSpec.ready,
    FlowMascotMood.recovery => const FlowMascotSpec(
        action: FlowMascotAction.recover,
        expression: FlowMascotExpression.closed,
        semanticLabel: 'Flow 训练伙伴正在恢复',
        durationMilliseconds: 620,
      ),
    FlowMascotMood.race => const FlowMascotSpec(
        action: FlowMascotAction.sprint,
        expression: FlowMascotExpression.determined,
        semanticLabel: 'Flow 训练伙伴准备比赛',
        durationMilliseconds: 460,
        motionCycles: 2,
      ),
    FlowMascotMood.onboarding => const FlowMascotSpec(
        action: FlowMascotAction.beckon,
        expression: FlowMascotExpression.happy,
        semanticLabel: 'Flow 训练伙伴向你问好',
      ),
    FlowMascotMood.empty => const FlowMascotSpec(
        action: FlowMascotAction.search,
        expression: FlowMascotExpression.curious,
        semanticLabel: 'Flow 训练伙伴等待新的训练记录',
      ),
  };
}

class FlowMascot extends StatelessWidget {
  final double size;
  final FlowMascotSpec spec;
  final FlowMascotPalette palette;
  final FlowMascotMood? mood;
  final Animation<double>? motion;
  final Color backgroundColor;

  const FlowMascot({
    super.key,
    this.size = 88,
    this.spec = FlowMascotSpec.ready,
    this.palette = FlowMascotPalette.brand,
    this.mood,
    this.motion,
    this.backgroundColor = TrainFlowTokens.ink,
  });

  FlowMascotSpec get resolvedSpec =>
      mood == null ? spec : _legacyMascotSpec(mood!);

  @override
  Widget build(BuildContext context) {
    final FlowMascotSpec effectiveSpec = resolvedSpec;
    final Widget character = TrainMateActionCharacter(
      action: trainMateActionForFlowMascot(effectiveSpec.action),
      size: size,
      backgroundColor: backgroundColor,
      semanticLabel: effectiveSpec.semanticLabel,
    );
    final Animation<double>? activeMotion = motion;
    if (activeMotion == null || effectiveSpec.motionCycles == 0) {
      return character;
    }
    return AnimatedBuilder(
      animation: activeMotion,
      child: character,
      builder: (BuildContext context, Widget? child) {
        final double phase = activeMotion.value.clamp(0, 1).toDouble();
        final double pulse =
            math.sin(math.pi * effectiveSpec.motionCycles * phase).abs();
        return Transform.translate(
          offset: Offset(0, -2.5 * pulse),
          child: Transform.scale(
            scale: 1 + 0.012 * pulse,
            child: child,
          ),
        );
      },
    );
  }
}

class FloatingFlowMascot extends StatefulWidget {
  final double size;
  final FlowMascotSpec spec;
  final FlowMascotPalette palette;
  final FlowMascotMood? mood;
  final Color backgroundColor;

  const FloatingFlowMascot({
    super.key,
    this.size = 88,
    this.spec = FlowMascotSpec.ready,
    this.palette = FlowMascotPalette.brand,
    this.mood,
    this.backgroundColor = TrainFlowTokens.ink,
  });

  FlowMascotSpec get resolvedSpec =>
      mood == null ? spec : _legacyMascotSpec(mood!);

  @override
  State<FloatingFlowMascot> createState() => _FloatingFlowMascotState();
}

class _FloatingFlowMascotState extends State<FloatingFlowMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _dependenciesResolved = false;
  bool _motionEnabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.resolvedSpec.duration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool enabled = TrainFlowMotion.isEnabled(context);
    if (!_dependenciesResolved || enabled != _motionEnabled) {
      _dependenciesResolved = true;
      _motionEnabled = enabled;
      if (enabled) {
        _playCurrentMotion();
      } else {
        _controller.stop();
        _controller.value = 1;
      }
    }
  }

  @override
  void didUpdateWidget(covariant FloatingFlowMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resolvedSpec != widget.resolvedSpec) {
      _controller.duration = widget.resolvedSpec.duration;
      if (_motionEnabled) {
        _playCurrentMotion();
      } else {
        _controller.stop();
        _controller.value = 1;
      }
    }
  }

  void _playCurrentMotion() {
    _controller.stop();
    _controller.value = 0;
    if (widget.resolvedSpec.motionCycles > 0) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlowMascot(
      size: widget.size,
      spec: widget.resolvedSpec,
      palette: widget.palette,
      backgroundColor: widget.backgroundColor,
      motion: _motionEnabled ? _controller : null,
    );
  }
}
