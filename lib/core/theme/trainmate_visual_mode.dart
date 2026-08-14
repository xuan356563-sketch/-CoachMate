import 'package:flutter/material.dart';

import 'trainflow_tokens.dart';

/// 主标签按功能分层使用的页面主题，不影响详情、表单与播放器页面。
///
/// 当前五个主标签统一采用暖黑训练体系；浅色模式仅为非主标签复用场景保留。
enum TrainMateVisualMode { lightCompanion, darkTraining }

/// 让共享卡片和状态组件在主标签内读取统一的前景与层级颜色。
class TrainMateVisualScope extends InheritedWidget {
  const TrainMateVisualScope({
    super.key,
    required this.mode,
    required super.child,
  });

  final TrainMateVisualMode mode;

  static TrainMateVisualScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TrainMateVisualScope>();
  }

  static TrainMateVisualMode modeOf(BuildContext context) {
    return maybeOf(context)?.mode ?? TrainMateVisualMode.lightCompanion;
  }

  static bool isDark(BuildContext context) {
    return modeOf(context) == TrainMateVisualMode.darkTraining;
  }

  static Color surface(BuildContext context) {
    return isDark(context)
        ? TrainFlowTokens.darkTrainingSurface
        : TrainFlowTokens.lightCompanionSurface;
  }

  static Color card(BuildContext context) {
    return isDark(context)
        ? TrainFlowTokens.darkTrainingCard
        : TrainFlowTokens.lightCompanionCard;
  }

  static Color raised(BuildContext context) {
    return isDark(context)
        ? TrainFlowTokens.darkTrainingRaised
        : TrainFlowTokens.lightCompanionCard;
  }

  static Color foreground(BuildContext context) {
    return isDark(context)
        ? TrainFlowTokens.darkTrainingOnSurface
        : TrainFlowTokens.lightCompanionOnSurface;
  }

  static Color muted(BuildContext context) {
    return isDark(context)
        ? TrainFlowTokens.darkTrainingMuted
        : TrainFlowTokens.lightCompanionMuted;
  }

  @override
  bool updateShouldNotify(TrainMateVisualScope oldWidget) {
    return oldWidget.mode != mode;
  }
}
