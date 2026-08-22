import 'package:flutter/material.dart';

import '../theme/trainflow_tokens.dart';

class AppColors {
  // 品牌色（深紫 + 紫/粉功能色）
  static const Color primary = TrainFlowTokens.ink;
  static const Color primaryLight = TrainFlowTokens.peachLight;
  static const Color primaryDark = TrainFlowTokens.inkDeep;
  static const Color primaryLightest = Color(0xFFEEE8FF);
  static const Color secondary = TrainFlowTokens.peach;
  static const Color secondaryLight = Color(0xFFFDE7F6);
  static const Color secondaryDark = Color(0xFFC944A9);

  // 伙伴系统 LCD 专用颜色
  static const Color petInk = Color(0xFF191331);
  static const Color petInkDeep = Color(0xFF130E26);
  static const Color petPeach = Color(0xFFF083C6);
  static const Color petPeachLight = Color(0xFFFDE7F6);
  static const Color petPaper = Color(0xFFFFFFFF);
  static const Color petLcd = Color(0xFFA3B58C);
  static const Color petLcdDim = Color(0xFF98AA80);
  static const Color petLcdPixel = Color(0xFF1C2415);

  // 业务状态色仅用于完成、预警和风险反馈
  static const Color success = Color(0xFF2DBE7F);
  static const Color warning = Color(0xFFF4A62A);
  static const Color warningDark = Color(0xFFC98200);
  static const Color danger = Color(0xFFE84A5F);
  static const Color dangerDark = Color(0xFFC2383A);

  // 中性色
  static const Color white = TrainFlowTokens.paper;
  static const Color whiteDark = Color(0xFFFAF8F8);
  static const Color grayLightest = TrainFlowTokens.page;
  static const Color grayLighter = Color(0xFFECE9EE);
  static const Color grayLight = Color(0xFFDEDCE2);
  static const Color grayLightish = Color(0xFFCBC8D0);
  static const Color gray = Color(0xFFAAA6B0);
  static const Color grayDarkish = Color(0xFF8E8997);
  static const Color grayDark = TrainFlowTokens.textMuted;
  static const Color grayDarker = Color(0xFF4E4A59);
  static const Color grayDarkest = TrainFlowTokens.text;
  static const Color blackLight = Color(0xFF242136);
  static const Color black = TrainFlowTokens.inkDeep;

  // 兼容旧调用的扁平色块，不再制造品牌渐变
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primary],
  );
  static const LinearGradient primaryGradientReverse = LinearGradient(
    colors: [primary, primary],
  );
  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [secondary, secondary],
  );
  static const LinearGradient successGradient = LinearGradient(
    colors: [success, success],
  );
  static const LinearGradient warningGradient = LinearGradient(
    colors: [warning, warning],
  );
  static const LinearGradient dangerGradient = LinearGradient(
    colors: [danger, danger],
  );

  // 页面与文本
  static const Color background = TrainFlowTokens.page;
  static const Color cardBackground = TrainFlowTokens.paper;
  static const Color modalBackground = TrainFlowTokens.paper;
  static const Color textPrimary = TrainFlowTokens.text;
  static const Color textSecondary = TrainFlowTokens.textMuted;
  static const Color textTertiary = Color(0xFF98939F);
  static const Color textInverse = TrainFlowTokens.paper;
  static const Color linkPrimary = primary;
  static const Color linkSecondary = secondaryDark;

  // 描边与遮罩
  static const Color border = TrainFlowTokens.ink;
  static const Color borderDark = TrainFlowTokens.inkDeep;
  static const Color divider = Color(0xFFD8D5DC);
  static const Color maskLight = Color(0x6611101F);
  static const Color maskDark = Color(0xD911101F);

  static const Color info = Color(0xFF4D5878);
  static const LinearGradient infoGradient = LinearGradient(
    colors: [info, info],
  );
  static const Color disabled = Color(0xFFE3E0E5);
  static const Color disabledText = Color(0xFF9B97A1);
  static const Color transparent = Color(0x00000000);

  static Color? getColorByName(String name) {
    final Map<String, Color> colorMap = <String, Color>{
      'primary': primary,
      'primaryLight': primaryLight,
      'primaryDark': primaryDark,
      'secondary': secondary,
      'success': success,
      'warning': warning,
      'danger': danger,
      'white': white,
      'black': black,
      'gray': gray,
      'textPrimary': textPrimary,
      'textSecondary': textSecondary,
    };
    return colorMap[name];
  }

  static LinearGradient? getGradientByName(String name) {
    final Map<String, LinearGradient> gradientMap = <String, LinearGradient>{
      'primary': primaryGradient,
      'primaryReverse': primaryGradientReverse,
      'secondary': secondaryGradient,
      'success': successGradient,
      'warning': warningGradient,
      'danger': dangerGradient,
      'info': infoGradient,
    };
    return gradientMap[name];
  }
}
