import 'package:flutter/material.dart';

enum TrainFlowHeaderVariant { organic, compact, none }

enum TrainFlowCardTone { paper, ink, peach, outline }

/// 业务页面的视觉密度与信息层级。
enum TrainFlowPageLayout { detail, form, report, legal }

abstract final class TrainFlowTokens {
  /// Indore 主标签体系的唯一交互强调色。
  static const Color accent = Color(0xFFE0FF64);
  static const Color onAccent = Color(0xFF181814);
  static const Color darkTrainingSurface = Color(0xFF181814);
  static const Color darkTrainingCard = Color(0xFF21211D);
  static const Color darkTrainingRaised = Color(0xFF2A2A28);
  static const Color darkTrainingHighest = Color(0xFF353634);
  static const Color darkTrainingOnSurface = Color(0xFFFFFFFF);
  static const Color darkTrainingMuted = Color(0xFF8E8E88);
  static const Color lightCompanionSurface = Color(0xFFF4F3F1);
  static const Color lightCompanionCard = Color(0xFFFFFFFF);
  static const Color lightCompanionOnSurface = Color(0xFF1A1A18);
  static const Color lightCompanionMuted = Color(0xFF6B6B66);

  static const Color ink = Color(0xFF19172C);
  static const Color inkDeep = Color(0xFF11101F);
  static const Color paper = Color(0xFFFFFDFC);
  static const Color peach = Color(0xFFFFB27D);
  static const Color peachLight = Color(0xFFFFE2B8);
  static const Color page = Color(0xFFF4F2F5);
  static const Color text = Color(0xFF181722);
  static const Color textMuted = Color(0xFF6F6C78);
  static const Color navigationSurface = Color(0xFFFFFFFF);
  static const Color navigationPillSurface = Color(0xB3FFFFFF);
  static const Color navigationInk = darkTrainingSurface;
  static const Color navigationAccent = accent;
  static const Color navigationInactive = Color(0xFF3E3A3E);
  static const Color navigationLabelInactive = Color(0xFFA19B9D);
  static const Color navigationSelectedFace = accent;
  static const Color navigationGlassBorder = Color(0x8CFFFFFF);
  static const Color navigationGlassShadow = Color(0x1F19172C);

  static const double pageMaxWidth = 430;
  static const List<double> spacing = <double>[8, 12, 16, 20, 24, 32];
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
  static const double mainTabCardRadius = 14;
  static const double mainTabControlRadius = 14;
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
  static const Duration route = Duration(milliseconds: 220);
  static const Duration entrance = Duration(milliseconds: 200);
  static const Duration cardStagger = Duration(milliseconds: 40);
  static const Duration value = Duration(milliseconds: 450);
  static const Duration button = Duration(milliseconds: 120);
  static const Duration selection = Duration(milliseconds: 320);
  static const Duration sceneEntrance = Duration(milliseconds: 260);
  static const Duration navigationStandardSelection =
      Duration(milliseconds: 180);
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);

  static bool isEnabled(BuildContext context) {
    return !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  }

  static Duration resolve(BuildContext context, Duration duration) {
    return isEnabled(context) ? duration : Duration.zero;
  }
}
