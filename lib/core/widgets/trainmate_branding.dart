import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'trainmate_action_character.dart';

abstract final class TrainMateBrandAssets {
  static const String brandmark =
      'assets/branding/exports/png/trainmate-flow-logo-final-256.png';
  static const String character =
      'assets/branding/flow-v2-color-detail/exports/png/trainmate-flow-character-1024.png';
  static const String lockup =
      'assets/branding/exports/png/trainmate-flow-logo-final-lockup-1600.png';

  static const String legacyBrandmark =
      'assets/branding/exports/png/trainmate-flow-logo-final-256.png';
  static const String legacyLockup =
      'assets/branding/exports/png/trainmate-flow-logo-final-lockup-1600.png';
}

class TrainMateBrandLockup extends StatelessWidget {
  final double height;

  const TrainMateBrandLockup({
    super.key,
    this.height = 112,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      TrainMateBrandAssets.lockup,
      key: const ValueKey<String>('trainmate-brand-lockup'),
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '智练 TrainMate',
      errorBuilder: (
        BuildContext context,
        Object error,
        StackTrace? stackTrace,
      ) =>
          Image.asset(
        TrainMateBrandAssets.legacyLockup,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}

class TrainMateBrandmark extends StatelessWidget {
  final double size;

  const TrainMateBrandmark({
    super.key,
    this.size = 72,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        TrainMateBrandAssets.brandmark,
        key: const ValueKey<String>('trainmate-brandmark'),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: '智练 TrainMate 定版品牌头像',
        errorBuilder: (
          BuildContext context,
          Object error,
          StackTrace? stackTrace,
        ) =>
            Image.asset(
          TrainMateBrandAssets.legacyBrandmark,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

class TrainMateCharacterAvatar extends StatelessWidget {
  final double size;
  final TrainMateAction action;
  final Color backgroundColor;
  final String? semanticLabel;
  final TrainMateCharacterVariant? variant;

  const TrainMateCharacterAvatar({
    super.key,
    this.size = 96,
    this.action = TrainMateAction.pointingGuide,
    this.backgroundColor = AppColors.primary,
    this.semanticLabel,
    this.variant,
  });

  @override
  Widget build(BuildContext context) {
    return TrainMateActionCharacter(
      action: action,
      size: size,
      backgroundColor: backgroundColor,
      semanticLabel: semanticLabel,
      variant: variant,
    );
  }
}
