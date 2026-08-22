import 'package:flutter/material.dart';

enum TrainFlowHeaderVariant { organic, compact, none }

enum TrainFlowCardTone { paper, ink, peach, outline }

/// 业务页面的视觉密度与信息层级。
enum TrainFlowPageLayout { detail, form, report, legal }

abstract final class TrainFlowTokens {
  /// 品牌主色：深紫（主要操作 / 进度 / 选中态）。
  static const Color accent = Color(0xFF6C3DF4);
  static const Color accentDark = Color(0xFF191331);
  static const Color accentLight = Color(0xFFEEE8FF);
  static const Color accentGlow = Color(0x596C3DF4);
  static const Color onAccent = Color(0xFFFFFFFF);

  // 品牌与功能色（计划 5.1 / 5.2：深紫主色 + 多色功能强调）。
  static const Color brandDark = Color(0xFF191331);
  static const Color purple = Color(0xFF6C3DF4);
  static const Color purpleSoft = Color(0xFFEEE8FF);
  static const Color yellow = Color(0xFFFFD54A);
  static const Color pink = Color(0xFFF083C6);
  static const Color coral = Color(0xFFFF665B);
  static const Color blue = Color(0xFF438CF5);
  static const Color mint = Color(0xFF67E6B1);

  // 语义状态色（计划 5.1：成功 / 提醒 / 错误 / 信息）。
  static const Color success = Color(0xFF2DBE7F);
  static const Color warning = Color(0xFFF4A62A);
  static const Color error = Color(0xFFE84A5F);
  static const Color info = Color(0xFF438CF5);

  // 浅色暖灰底 + 白色卡片的语义分层（原「darkTraining*」命名保留，语义已切换为浅色品牌层）。
  static const Color darkTrainingSurface = Color(0xFFF6F6F4);
  static const Color darkTrainingCard = Color(0xFFFFFFFF);
  static const Color darkTrainingRaised = Color(0xFFECEDEF);
  static const Color darkTrainingHighest = Color(0xFFEEE8FF);
  static const Color darkTrainingOnSurface = Color(0xFF171522);
  static const Color darkTrainingMuted = Color(0xFF686574);
  static const Color darkTrainingTextTertiary = Color(0xFF9693A1);
  // 浅色背景渐变（场景头）。
  static const Color darkTrainingGradientTop = Color(0xFFFFFFFF);
  static const Color darkTrainingGradientBottom = Color(0xFFF6F6F4);
  static const Color lightCompanionSurface = Color(0xFFF6F6F4);
  static const Color lightCompanionCard = Color(0xFFFFFFFF);
  static const Color lightCompanionOnSurface = Color(0xFF171522);
  static const Color lightCompanionMuted = Color(0xFF686574);

  static const Color ink = Color(0xFF191331);
  static const Color inkDeep = Color(0xFF130E26);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color peach = Color(0xFFF083C6);
  static const Color peachLight = Color(0xFFFDE7F6);
  static const Color page = Color(0xFFF6F6F4);
  static const Color text = Color(0xFF171522);
  static const Color textMuted = Color(0xFF686574);
  static const Color border = Color(0xFFE7E5EB);
  static const Color navigationSurface = Color(0xFFFFFFFF);
  static const Color navigationPillSurface = Color(0xFFFFFFFF);
  static const Color navigationInk = brandDark;
  static const Color navigationAccent = accent;
  static const Color navigationInactive = Color(0xFF9693A1);
  static const Color navigationLabelInactive = Color(0xFF9693A1);
  static const Color navigationSelectedFace = accent;
  static const Color navigationGlassBorder = Color(0xFFE7E5EB);
  static const Color navigationGlassShadow = Color(0x1F191331);

  static const double pageMaxWidth = 430;
  static const List<double> spacing = <double>[4, 8, 12, 16, 20, 24, 32, 40];
  static const double heroRadius = 40;
  static const double sectionRadius = 32;
  static const double cardRadius = 24;
  static const double controlRadius = 16;
  static const double pillRadius = 999;
  static const double borderWidth = 1.5;
  static const double pageGutter = 16;
  static const double mainTabPageGutter = 20;
  static const double mainTabCardGap = 12;
  static const double mainTabCardPadding = 16;
  static const double mainTabCardRadius = 16;
  static const double mainTabControlRadius = 16;
  static const double bottomNavigationHorizontalInset = 40;
  static const double bottomNavigationMinimumHorizontalInset = 16;
  static const double bottomNavigationMinimumItemWidth = 48;
  static const double bottomNavigationPillHeight = 72;
  static const double bottomNavigationPillRadius = 36;
  static const double bottomNavigationVisualHeight = 96;
  static const double bottomNavigationPillTop = 24;
  static const double bottomNavigationSelectedSize = 56;
  static const double bottomNavigationSelectedInnerSize = 44;
  static const double bottomNavigationSelectedCenterFromPillTop = 14;
  static const double bottomNavigationSelectedLift =
      bottomNavigationSelectedCenterFromPillTop;
  static const double bottomNavigationNotchSize = 60;
  static const double bottomNavigationPaintOverflow = 8;
  static const double bottomNavigationNotchClearance = 2;
  static const double bottomNavigationSelectedRingWidth =
      bottomNavigationNotchClearance;
  static const double bottomNavigationAiSize = bottomNavigationSelectedSize;
  static const double bottomNavigationAiInnerSize =
      bottomNavigationSelectedInnerSize;
  static const double bottomNavigationAiLift = bottomNavigationSelectedLift;
  static const double bottomNavigationAiRingWidth =
      bottomNavigationSelectedRingWidth;
  static const double bottomNavigationStandardSelectionSize = 32;
  static const double bottomNavigationIconSize = 28;
  static const double bottomNavigationInlineIconTop = 14;
  static const double bottomNavigationLabelTop = 51;
  static const double bottomNavigationLabelFontSize = 10;
  static const double bottomNavigationCenterButtonSize = 72;
  static const double bottomNavigationCenterOverlap = 28;
  static const double bottomNavigationCenterGap = 80;
  static const double bottomNavigationBlurSigma = 16;
  static const double immersiveHeroMaxHeight = 372;
  static const double immersiveHeroMinHeight = 304;
  static const double immersiveHeroContentRatio = 0.436;
  static const double immersiveHeroTaskCardHeight = 122;
  static const double compactHubHeroMaxHeight = 304;
  static const double compactHubHeroMinHeight = 248;
  static const double compactHubHeroContentRatio = 0.35;
  static const double immersiveBottomContentPadding = 124;
}

abstract final class TrainFlowMotion {
  // CycleGo 方案包动效数值：页面转场 300ms、数字滚动 800ms、进度环 1200ms、
  // Tab 胶囊 200ms、图标 150ms、按钮按压 100ms。
  static const Duration route = Duration(milliseconds: 300);
  static const Duration entrance = Duration(milliseconds: 300);
  static const Duration cardStagger = Duration(milliseconds: 40);
  static const Duration value = Duration(milliseconds: 800);
  static const Duration progressRing = Duration(milliseconds: 1200);
  static const Duration button = Duration(milliseconds: 100);
  static const Duration selection = Duration(milliseconds: 200);
  static const Duration sceneEntrance = Duration(milliseconds: 300);
  static const Duration navigationStandardSelection =
      Duration(milliseconds: 150);
  static const Curve easeOut = Cubic(0.4, 0, 0.2, 1);

  static bool isEnabled(BuildContext context) {
    return !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  }

  static Duration resolve(BuildContext context, Duration duration) {
    return isEnabled(context) ? duration : Duration.zero;
  }
}
