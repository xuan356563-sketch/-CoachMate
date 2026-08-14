import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'trainflow_tokens.dart';

class TDesignTheme {
  static const List<String> _fontFallback = <String>[
    'PingFang SC',
    'Noto Sans CJK SC',
    'Microsoft YaHei',
    'sans-serif',
  ];

  static ThemeData get lightTheme {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: AppColors.primary,
      secondary: AppColors.secondary,
      onSecondary: AppColors.primary,
      secondaryContainer: AppColors.primaryLight,
      onSecondaryContainer: AppColors.primary,
      tertiary: AppColors.success,
      onTertiary: AppColors.white,
      error: AppColors.danger,
      onError: AppColors.white,
      surface: AppColors.white,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.grayLighter,
      surfaceContainerHigh: AppColors.white,
      surfaceContainer: AppColors.white,
      surfaceContainerLow: AppColors.grayLightest,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.white,
      splashColor: AppColors.secondary.withValues(alpha: 0.18),
      highlightColor: AppColors.secondary.withValues(alpha: 0.08),
      shadowColor: AppColors.primary.withValues(alpha: 0.12),
      dividerColor: AppColors.divider,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.white),
        titleTextStyle: TextStyle(
          color: AppColors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          fontFamilyFallback: _fontFallback,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: AppColors.primary,
        indicatorColor: AppColors.secondary,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: 10,
            letterSpacing: 0,
            fontFamilyFallback: _fontFallback,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.primary,
        selectedItemColor: AppColors.secondary,
        unselectedItemColor: AppColors.white,
        selectedLabelStyle: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          fontFamilyFallback: _fontFallback,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 10,
          letterSpacing: 0,
          fontFamilyFallback: _fontFallback,
        ),
        type: BottomNavigationBarType.fixed,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: AppColors.secondary,
          foregroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.disabled,
          disabledForegroundColor: AppColors.disabledText,
          elevation: 0,
          side: const BorderSide(
            color: AppColors.primary,
            width: TrainFlowTokens.borderWidth,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TrainFlowTokens.controlRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            fontFamilyFallback: _fontFallback,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.primary,
          side: const BorderSide(
            color: AppColors.primary,
            width: TrainFlowTokens.borderWidth,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TrainFlowTokens.controlRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            fontFamilyFallback: _fontFallback,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TrainFlowTokens.controlRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            fontFamilyFallback: _fontFallback,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: const CircleBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: _inputBorder(AppColors.primary),
        enabledBorder: _inputBorder(AppColors.primary),
        focusedBorder: _inputBorder(AppColors.secondaryDark, width: 2),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, width: 2),
        hintStyle: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 14,
          letterSpacing: 0,
          fontFamilyFallback: _fontFallback,
        ),
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          letterSpacing: 0,
          fontFamilyFallback: _fontFallback,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBackground,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TrainFlowTokens.cardRadius),
          side: const BorderSide(
            color: AppColors.primary,
            width: TrainFlowTokens.borderWidth,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TrainFlowTokens.sectionRadius),
          side: const BorderSide(
            color: AppColors.primary,
            width: TrainFlowTokens.borderWidth,
          ),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          fontFamilyFallback: _fontFallback,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          letterSpacing: 0,
          fontFamilyFallback: _fontFallback,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.white,
        selectedColor: AppColors.primaryLight,
        disabledColor: AppColors.disabled,
        labelStyle: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          fontFamilyFallback: _fontFallback,
        ),
        side: const BorderSide(
          color: AppColors.primary,
          width: TrainFlowTokens.borderWidth,
        ),
        shape: const StadiumBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: AppColors.secondary,
          foregroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.disabled,
          disabledForegroundColor: AppColors.disabledText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TrainFlowTokens.controlRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            fontFamilyFallback: _fontFallback,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        modalBackgroundColor: AppColors.white,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TrainFlowTokens.sectionRadius),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.white;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? AppColors.white
                : AppColors.primary;
          }),
          side: WidgetStateProperty.all(
            const BorderSide(
              color: AppColors.primary,
              width: TrainFlowTokens.borderWidth,
            ),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              fontFamilyFallback: _fontFallback,
            ),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.secondary
              : AppColors.grayLightish;
        }),
        trackOutlineColor: WidgetStateProperty.all(AppColors.primary),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.white;
        }),
        checkColor: WidgetStateProperty.all(AppColors.secondary),
        side: const BorderSide(
          color: AppColors.primary,
          width: TrainFlowTokens.borderWidth,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textSecondary;
        }),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.secondary,
        inactiveTrackColor: AppColors.grayLightish,
        thumbColor: AppColors.primary,
        overlayColor: Color(0x22FFB27D),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.secondary,
        linearTrackColor: AppColors.grayLighter,
        circularTrackColor: AppColors.grayLighter,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.primary,
        textColor: AppColors.textPrimary,
        collapsedTextColor: AppColors.textPrimary,
        tilePadding: EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        space: 1,
        thickness: 1,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.secondary.withValues(alpha: 0.35),
        selectionHandleColor: AppColors.primary,
      ),
      textTheme: _textTheme,
      iconTheme: const IconThemeData(color: AppColors.primary, size: 24),
      primaryIconTheme: const IconThemeData(color: AppColors.white, size: 24),
    );
  }

  // App 固定使用品牌亮色主题，避免系统深色模式造成页面视觉漂移。
  static ThemeData get darkTheme => lightTheme;

  static OutlineInputBorder _inputBorder(Color color, {double width = 1.5}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(TrainFlowTokens.controlRadius),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 32,
      height: 1.15,
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    displayMedium: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 28,
      height: 1.18,
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    displaySmall: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 24,
      height: 1.2,
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    headlineLarge: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 22,
      height: 1.25,
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    headlineMedium: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 20,
      height: 1.25,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    headlineSmall: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 18,
      height: 1.3,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    titleLarge: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 18,
      height: 1.35,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    titleMedium: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 16,
      height: 1.35,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    titleSmall: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    bodyLarge: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 16,
      height: 1.5,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    bodyMedium: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 14,
      height: 1.5,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    bodySmall: TextStyle(
      color: AppColors.textSecondary,
      fontSize: 12,
      height: 1.45,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    labelLarge: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    labelMedium: TextStyle(
      color: AppColors.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
    labelSmall: TextStyle(
      color: AppColors.textSecondary,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      fontFamilyFallback: _fontFallback,
    ),
  );
}
