import '../../../data/models/pet.dart';

/// MATE C-08 伙伴形象与既有成长、心情模型之间的只读映射。
abstract final class MateCompanionAssets {
  static const String _root =
      'assets/branding/mate-feast-bag-v2/companion-states';

  /// 素材加载失败时继续显示既有插画宠物，避免伙伴页出现空白。
  static const bool fallbackToIllustratedPet = true;

  static String path(PetStage stage, PetMood mood) {
    return '$_root/${stage.id}-${mood.id}.png';
  }
}
