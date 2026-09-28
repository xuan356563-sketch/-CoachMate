import 'package:flutter/material.dart';

import '../constants/app_brand.dart';

/// 练搭 CoachMate 固定动作资产。
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

/// 主标签使用的扁平展示人物；默认仍保留 C-08 复古素材。
enum TrainMateCharacterStyle { c08, flatShowcase }

abstract final class TrainMateActionAssets {
  static const String _mateRoot =
      'assets/branding/mate-feast-bag-v2/action-characters';
  static const String _flatShowcaseRoot =
      'assets/branding/mate-flat-showcase-v1/action-characters';
  static const String _flowV2Root =
      'assets/branding/flow-v2-color-detail/action-characters';
  static const String _legacyRoot = 'assets/branding/action-characters';

  /// 本轮只为五个主标签准备的九种扁平姿态。
  /// 其他训练场景继续使用 C-08 复古人物，避免误把展示插画用于教学页。
  static const Set<TrainMateAction> flatShowcaseActions = <TrainMateAction>{
    TrainMateAction.pointingGuide,
    TrainMateAction.running,
    TrainMateAction.sideLungeStretch,
    TrainMateAction.seatedMeditation,
    TrainMateAction.jumpingJack,
    TrainMateAction.highKnees,
    TrainMateAction.squat,
    TrainMateAction.seatedForwardFold,
    TrainMateAction.treePoseBalance,
  };

  static bool hasFlatShowcaseAsset(TrainMateAction action) =>
      flatShowcaseActions.contains(action);

  /// 扁平人物在浅色承接面上适度提纯，避免纸袋和陶土身体发灰。
  static const List<double> flatShowcaseNavyColorMatrix = <double>[
    1.2245464,
    -0.176748,
    -0.0177984,
    0,
    -1.84,
    -0.0526536,
    1.100452,
    -0.0177984,
    0,
    -1.84,
    -0.0526536,
    -0.176748,
    1.2594016,
    0,
    -1.84,
    0,
    0,
    0,
    1,
    0,
  ];

  /// 扁平人物在蓝、紫和珊瑚色主视觉上额外提亮并增强品牌饱和度。
  static const List<double> flatShowcasePeachLightColorMatrix = <double>[
    1.330959,
    -0.255255,
    -0.025704,
    0,
    1.6,
    -0.076041,
    1.151745,
    -0.025704,
    0,
    1.6,
    -0.076041,
    -0.255255,
    1.381296,
    0,
    1.6,
    0,
    0,
    0,
    1,
    0,
  ];

  static List<double> flatShowcaseColorMatrix(
    TrainMateCharacterVariant variant,
  ) =>
      switch (variant) {
        TrainMateCharacterVariant.navy => flatShowcaseNavyColorMatrix,
        TrainMateCharacterVariant.peachLight =>
          flatShowcasePeachLightColorMatrix,
      };

  static String path(
    TrainMateAction action,
    TrainMateCharacterVariant variant,
  ) {
    final String directory = switch (variant) {
      TrainMateCharacterVariant.navy => 'navy',
      TrainMateCharacterVariant.peachLight => 'peach-light',
    };
    return '$_mateRoot/$directory/${action.fileName}';
  }

  /// 五个主标签限定使用的高饱和扁平展示素材。
  static String flatShowcasePath(
    TrainMateAction action,
    TrainMateCharacterVariant variant,
  ) {
    final String directory = switch (variant) {
      TrainMateCharacterVariant.navy => 'navy',
      TrainMateCharacterVariant.peachLight => 'peach-light',
    };
    return '$_flatShowcaseRoot/$directory/${action.fileName}';
  }

  /// MATE C-08 素材无法加载时回退到当前 Flow V2。
  static String flowV2Path(
    TrainMateAction action,
    TrainMateCharacterVariant variant,
  ) {
    final String directory = switch (variant) {
      TrainMateCharacterVariant.navy => 'navy',
      TrainMateCharacterVariant.peachLight => 'peach-light',
    };
    return '$_flowV2Root/$directory/${action.fileName}';
  }

  /// Flow V2 仍无法加载时使用旧版 Flow，避免业务页面出现空白插画。
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
  final TrainMateCharacterStyle style;

  const TrainMateActionCharacter({
    super.key,
    required this.action,
    required this.backgroundColor,
    this.size = 96,
    this.semanticLabel,
    this.variant,
    this.style = TrainMateCharacterStyle.c08,
  });

  TrainMateCharacterVariant get resolvedVariant =>
      variant ?? TrainMateActionAssets.variantForBackground(backgroundColor);

  String get assetPath => switch (style) {
        TrainMateCharacterStyle.c08 =>
          TrainMateActionAssets.path(action, resolvedVariant),
        TrainMateCharacterStyle.flatShowcase
            when TrainMateActionAssets.hasFlatShowcaseAsset(action) =>
          TrainMateActionAssets.flatShowcasePath(action, resolvedVariant),
        TrainMateCharacterStyle.flatShowcase =>
          TrainMateActionAssets.path(action, resolvedVariant),
      };

  @override
  Widget build(BuildContext context) {
    final TrainMateCharacterVariant selectedVariant = resolvedVariant;
    final Widget character = Image.asset(
      assetPath,
      key: ValueKey<String>(
        style == TrainMateCharacterStyle.c08
            ? 'trainmate-action-${action.name}-${selectedVariant.name}'
            : 'trainmate-flat-showcase-action-'
                '${action.name}-${selectedVariant.name}',
      ),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
      errorBuilder: (
        BuildContext context,
        Object error,
        StackTrace? stackTrace,
      ) =>
          style == TrainMateCharacterStyle.flatShowcase &&
                  TrainMateActionAssets.hasFlatShowcaseAsset(action)
              ? Image.asset(
                  TrainMateActionAssets.path(action, selectedVariant),
                  key: ValueKey<String>(
                    'trainmate-action-c08-fallback-${action.name}-${selectedVariant.name}',
                  ),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                  errorBuilder: (
                    BuildContext context,
                    Object error,
                    StackTrace? stackTrace,
                  ) =>
                      _flowV2Fallback(selectedVariant),
                )
              : _flowV2Fallback(selectedVariant),
    );
    return RepaintBoundary(
      child: Semantics(
        image: true,
        label: semanticLabel ?? '${AppBrand.displayName} ${action.label} 动作人物',
        child: SizedBox.square(
          dimension: size,
          child: style == TrainMateCharacterStyle.flatShowcase
              ? ColorFiltered(
                  colorFilter: ColorFilter.matrix(
                    TrainMateActionAssets.flatShowcaseColorMatrix(
                      selectedVariant,
                    ),
                  ),
                  child: character,
                )
              : character,
        ),
      ),
    );
  }

  Widget _flowV2Fallback(TrainMateCharacterVariant selectedVariant) {
    return Image.asset(
      TrainMateActionAssets.flowV2Path(action, selectedVariant),
      key: ValueKey<String>(
        'trainmate-action-flow-v2-fallback-${action.name}-${selectedVariant.name}',
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
          'trainmate-action-legacy-fallback-${action.name}-${selectedVariant.name}',
        ),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}
