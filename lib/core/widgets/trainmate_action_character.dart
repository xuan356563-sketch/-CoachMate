import 'package:flutter/material.dart';

/// 智练 TrainMate 固定动作资产。
enum TrainMateAction {
  pointingGuide('01-pointing-guide.png', '指向引导'),
  running('02-running.png', '跑步'),
  sideLungeStretch('03-side-lunge-stretch.png', '侧弓步拉伸'),
  seatedMeditation('04-seated-meditation.png', '盘腿冥想'),
  jumpingJack('05-jumping-jack.png', '开合跳'),
  highKnees('06-high-knees.png', '高抬腿'),
  sprint('07-sprint.png', '冲刺'),
  jumpRope('08-jump-rope.png', '跳绳'),
  burpee('09-burpee.png', '波比跳'),
  squat('10-squat.png', '深蹲'),
  forwardLunge('11-forward-lunge.png', '前弓步'),
  pushUp('12-push-up.png', '俯卧撑'),
  plank('13-plank.png', '平板支撑'),
  mountainClimber('14-mountain-climber.png', '登山跑'),
  sitUpCrunch('15-sit-up-crunch.png', '仰卧卷腹'),
  dumbbellCurl('16-dumbbell-curl.png', '哑铃弯举'),
  dumbbellOverheadPress('17-dumbbell-overhead-press.png', '哑铃肩上推举'),
  standingSideStretch('18-standing-side-stretch.png', '站姿体侧拉伸'),
  seatedForwardFold('19-seated-forward-fold.png', '坐姿前屈'),
  treePoseBalance('20-tree-pose-balance.png', '单腿树式平衡');

  final String fileName;
  final String label;

  const TrainMateAction(this.fileName, this.label);
}

/// 人物配色版本。
enum TrainMateCharacterVariant { navy, peachLight }

abstract final class TrainMateActionAssets {
  static const String _root =
      'assets/branding/flow-v2-color-detail/action-characters';
  static const String _legacyRoot = 'assets/branding/action-characters';

  static String path(
    TrainMateAction action,
    TrainMateCharacterVariant variant,
  ) {
    final String directory = switch (variant) {
      TrainMateCharacterVariant.navy => 'navy',
      TrainMateCharacterVariant.peachLight => 'peach-light',
    };
    return '$_root/$directory/${action.fileName}';
  }

  /// Flow V2 素材无法加载时使用旧版 Flow，避免业务页面出现空白插画。
  static String legacyPath(
    TrainMateAction action,
    TrainMateCharacterVariant variant,
  ) {
    final String directory = switch (variant) {
      TrainMateCharacterVariant.navy => 'navy',
      TrainMateCharacterVariant.peachLight => 'peach-light',
    };
    return '$_legacyRoot/$directory/${action.fileName}';
  }

  static TrainMateCharacterVariant variantForBackground(Color background) {
    return background.computeLuminance() < 0.35
        ? TrainMateCharacterVariant.peachLight
        : TrainMateCharacterVariant.navy;
  }
}

/// 根据背景自动切换双配色的统一动作人物。
class TrainMateActionCharacter extends StatelessWidget {
  final TrainMateAction action;
  final double size;
  final Color backgroundColor;
  final String? semanticLabel;
  final TrainMateCharacterVariant? variant;

  const TrainMateActionCharacter({
    super.key,
    required this.action,
    required this.backgroundColor,
    this.size = 96,
    this.semanticLabel,
    this.variant,
  });

  TrainMateCharacterVariant get resolvedVariant =>
      variant ?? TrainMateActionAssets.variantForBackground(backgroundColor);

  String get assetPath => TrainMateActionAssets.path(action, resolvedVariant);

  @override
  Widget build(BuildContext context) {
    final TrainMateCharacterVariant selectedVariant = resolvedVariant;
    return RepaintBoundary(
      child: Semantics(
        image: true,
        label: semanticLabel ?? '智练 TrainMate ${action.label}动作人物',
        child: SizedBox.square(
          dimension: size,
          child: Image.asset(
            TrainMateActionAssets.path(action, selectedVariant),
            key: ValueKey<String>(
              'trainmate-action-${action.name}-${selectedVariant.name}',
            ),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
            errorBuilder: (
              BuildContext context,
              Object error,
              StackTrace? stackTrace,
            ) =>
                Image.asset(
              TrainMateActionAssets.legacyPath(action, selectedVariant),
              key: ValueKey<String>(
                'trainmate-action-fallback-${action.name}-${selectedVariant.name}',
              ),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}
