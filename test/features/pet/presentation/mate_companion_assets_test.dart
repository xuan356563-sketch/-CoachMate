import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/features/pet/presentation/mate_companion_assets.dart';

void main() {
  test('五阶段与五心情严格映射到二十五张 MATE C-08 素材', () {
    final Set<String> paths = <String>{};

    for (final PetStage stage in PetStage.values) {
      for (final PetMood mood in PetMood.values) {
        final String path = MateCompanionAssets.path(stage, mood);
        expect(path, contains('assets/branding/mate-feast-bag-v2/'));
        expect(path, endsWith('${stage.id}-${mood.id}.png'));
        paths.add(path);
      }
    }

    expect(paths, hasLength(25));
  });

  test('MATE 伙伴素材失败时保留现有插画宠物回退标识', () {
    expect(MateCompanionAssets.fallbackToIllustratedPet, isTrue);
  });
}
