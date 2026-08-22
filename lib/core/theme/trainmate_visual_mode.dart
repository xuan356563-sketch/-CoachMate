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

  /// 暖黑「Indore」主标签 / 详情页共用的暗色主题。
  ///
  /// 主标签的 [TrainMateImmersiveHubPage] 与详情页的 [TrainFlowPage] 都基于
  /// [Theme.of] 派生这层主题，保证青柠主操作、抬升输入框、暗色弹层和文字层级一致。
  static ThemeData darkHubTheme(BuildContext context) {
    final ThemeData baseTheme = Theme.of(context);
    final OutlineInputBorder inputBorder = OutlineInputBorder(
      borderRadius: const BorderRadius.all(
        Radius.circular(TrainFlowTokens.mainTabControlRadius),
      ),
      borderSide: const BorderSide(color: TrainFlowTokens.darkTrainingRaised),
    );
    final ColorScheme colorScheme = baseTheme.colorScheme.copyWith(
      brightness: Brightness.light,
      primary: TrainFlowTokens.accent,
      onPrimary: TrainFlowTokens.onAccent,
      surface: TrainFlowTokens.darkTrainingSurface,
      onSurface: TrainFlowTokens.darkTrainingOnSurface,
      surfaceContainer: TrainFlowTokens.darkTrainingCard,
      surfaceContainerHigh: TrainFlowTokens.darkTrainingRaised,
      surfaceContainerHighest: TrainFlowTokens.darkTrainingHighest,
    );
    return baseTheme.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: TrainFlowTokens.darkTrainingSurface,
      canvasColor: TrainFlowTokens.darkTrainingSurface,
      dividerColor: TrainFlowTokens.darkTrainingRaised,
      colorScheme: colorScheme,
      textTheme: baseTheme.textTheme.apply(
        bodyColor: TrainFlowTokens.darkTrainingOnSurface,
        displayColor: TrainFlowTokens.darkTrainingOnSurface,
      ),
      iconTheme: const IconThemeData(color: TrainFlowTokens.accent),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TrainFlowTokens.accent,
          foregroundColor: TrainFlowTokens.onAccent,
          minimumSize: const Size(48, 48),
          elevation: 6,
          shadowColor: TrainFlowTokens.accent.withValues(alpha: 0.45),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(TrainFlowTokens.pillRadius),
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: TrainFlowTokens.accent,
          side: const BorderSide(color: TrainFlowTokens.darkTrainingRaised),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(TrainFlowTokens.mainTabControlRadius),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: TrainFlowTokens.accent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(TrainFlowTokens.mainTabControlRadius),
            ),
          ),
        ),
      ),
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: TrainFlowTokens.darkTrainingRaised,
        labelStyle: const TextStyle(color: TrainFlowTokens.darkTrainingMuted),
        hintStyle: const TextStyle(color: TrainFlowTokens.darkTrainingMuted),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(
            color: TrainFlowTokens.accent,
            width: 1.5,
          ),
        ),
      ),
      datePickerTheme: baseTheme.datePickerTheme.copyWith(
        backgroundColor: TrainFlowTokens.darkTrainingCard,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: TrainFlowTokens.darkTrainingRaised,
        headerForegroundColor: TrainFlowTokens.darkTrainingOnSurface,
        dayForegroundColor: WidgetStateProperty.all(
          TrainFlowTokens.darkTrainingOnSurface,
        ),
        todayForegroundColor: WidgetStateProperty.all(TrainFlowTokens.accent),
        todayBorder: const BorderSide(color: TrainFlowTokens.accent),
      ),
      popupMenuTheme: baseTheme.popupMenuTheme.copyWith(
        color: TrainFlowTokens.darkTrainingCard,
        textStyle: const TextStyle(
          color: TrainFlowTokens.darkTrainingOnSurface,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(TrainFlowTokens.mainTabCardRadius),
          ),
        ),
      ),
      dialogTheme: baseTheme.dialogTheme.copyWith(
        backgroundColor: TrainFlowTokens.darkTrainingCard,
        titleTextStyle: baseTheme.textTheme.titleLarge?.copyWith(
          color: TrainFlowTokens.darkTrainingOnSurface,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: baseTheme.textTheme.bodyMedium?.copyWith(
          color: TrainFlowTokens.darkTrainingMuted,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(TrainFlowTokens.mainTabCardRadius),
          ),
        ),
      ),
      bottomSheetTheme: baseTheme.bottomSheetTheme.copyWith(
        backgroundColor: TrainFlowTokens.darkTrainingCard,
        modalBackgroundColor: TrainFlowTokens.darkTrainingCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TrainFlowTokens.mainTabCardRadius),
          ),
        ),
      ),
    );
  }

  @override
  bool updateShouldNotify(TrainMateVisualScope oldWidget) {
    return oldWidget.mode != mode;
  }
}
