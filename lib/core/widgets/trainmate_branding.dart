import 'package:flutter/material.dart';

import '../constants/app_brand.dart';
import '../constants/app_colors.dart';
import 'trainmate_action_character.dart';

abstract final class TrainMateBrandAssets {
  static const String brandmark =
      'assets/branding/coachmate-official-logo-v1/exports/png/coachmate-device-panel-1024.png';
  static const String character =
      'assets/branding/coachmate-official-logo-v1/exports/png/coachmate-brand-character-1024.png';
  static const String lockup =
      'assets/branding/coachmate-official-logo-v1/exports/png/coachmate-official-lockup-2048x1152.png';

  static const String mateV2Brandmark =
      'assets/branding/mate-feast-bag-v2/exports/png/mate-feast-brandmark-1024.png';
  static const String mateV2Character =
      'assets/branding/mate-feast-bag-v2/exports/png/mate-feast-character-1024.png';
  static const String mateV2Lockup =
      'assets/branding/mate-feast-bag-v2/exports/png/mate-feast-compact-mark-1024.png';

  static const String flowV2Brandmark =
      'assets/branding/exports/png/trainmate-flow-logo-final-256.png';
  static const String flowV2Character =
      'assets/branding/flow-v2-color-detail/exports/png/trainmate-flow-character-1024.png';
  static const String flowV2Lockup =
      'assets/branding/exports/png/trainmate-flow-logo-final-lockup-1600.png';

  static const String legacyBrandmark =
      'assets/branding/exports/png/trainmate-flow-brandmark-256.png';
  static const String legacyCharacter =
      'assets/branding/exports/png/trainmate-flow-character-256.png';
  static const String legacyLockup =
      'assets/branding/exports/png/trainmate-flow-lockup-1600.png';
}

class TrainMateBrandLockup extends StatelessWidget {
  final double height;

  const TrainMateBrandLockup({
    super.key,
    this.height = 112,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${AppBrand.displayName}，${AppBrand.tagline}',
      child: SizedBox(
        key: const ValueKey<String>('trainmate-brand-lockup'),
        height: height,
        child: _BrandAssetImage(
          paths: const <String>[
            TrainMateBrandAssets.lockup,
            TrainMateBrandAssets.mateV2Lockup,
            TrainMateBrandAssets.flowV2Lockup,
            TrainMateBrandAssets.legacyLockup,
          ],
          imageKey: const ValueKey<String>('trainmate-brand-lockup-image'),
          fit: BoxFit.contain,
          semanticLabel: '${AppBrand.displayName}，${AppBrand.tagline}',
        ),
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
      child: const _BrandAssetImage(
        paths: <String>[
          TrainMateBrandAssets.brandmark,
          TrainMateBrandAssets.mateV2Brandmark,
          TrainMateBrandAssets.flowV2Brandmark,
          TrainMateBrandAssets.legacyBrandmark,
        ],
        imageKey: ValueKey<String>('trainmate-brandmark'),
        fit: BoxFit.contain,
        semanticLabel: '练搭 CoachMate 品牌头像',
      ),
    );
  }
}

class TrainMateBrandCharacter extends StatelessWidget {
  final double size;
  final String semanticLabel;

  const TrainMateBrandCharacter({
    super.key,
    this.size = 128,
    this.semanticLabel = '练搭 CoachMate 完整品牌人物',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: _BrandAssetImage(
        paths: const <String>[
          TrainMateBrandAssets.character,
          TrainMateBrandAssets.mateV2Character,
          TrainMateBrandAssets.flowV2Character,
          TrainMateBrandAssets.legacyCharacter,
        ],
        imageKey: const ValueKey<String>('trainmate-brand-character'),
        fit: BoxFit.contain,
        semanticLabel: semanticLabel,
      ),
    );
  }
}

class _BrandAssetImage extends StatelessWidget {
  final List<String> paths;
  final Key? imageKey;
  final BoxFit fit;
  final String semanticLabel;

  const _BrandAssetImage({
    required this.paths,
    required this.fit,
    required this.semanticLabel,
    this.imageKey,
  });

  @override
  Widget build(BuildContext context) {
    return _buildImage(0);
  }

  Widget _buildImage(int index) {
    return Image.asset(
      paths[index],
      key: index == 0 ? imageKey : null,
      fit: fit,
      filterQuality: FilterQuality.high,
      semanticLabel: index == 0 ? semanticLabel : null,
      excludeFromSemantics: index != 0,
      errorBuilder: index + 1 < paths.length
          ? (
              BuildContext context,
              Object error,
              StackTrace? stackTrace,
            ) =>
              _buildImage(index + 1)
          : null,
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
