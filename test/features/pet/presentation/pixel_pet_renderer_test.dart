import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/features/pet/presentation/pixel_pet_renderer.dart';

void main() {
  Future<void> pumpRenderer(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: const Scaffold(
            body: Center(
              child: PixelPetRenderer(
                species: PetSpecies.balanceRaccoon,
                stage: PetStage.sprout,
                mood: PetMood.happy,
                semanticLabel: '衡衡狸，萌芽体，心情开心，今日获得 38 能量，距离下一阶段 712',
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('默认每 500ms 在 A/B 两帧间切换', (tester) async {
    await pumpRenderer(tester);

    expect(find.byKey(const ValueKey<String>('pixel-pet-frame-0')), findsOne);
    await tester.pump(const Duration(milliseconds: 499));
    expect(find.byKey(const ValueKey<String>('pixel-pet-frame-0')), findsOne);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey<String>('pixel-pet-frame-1')), findsOne);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey<String>('pixel-pet-frame-0')), findsOne);
  });

  testWidgets('减少动态效果时固定 A 帧且保留完整语义', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await pumpRenderer(tester, disableAnimations: true);

      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey<String>('pixel-pet-frame-0')), findsOne);
      expect(find.byKey(const ValueKey<String>('pixel-pet-frame-1')),
          findsNothing);
      expect(
        find.bySemanticsLabel('衡衡狸，萌芽体，心情开心，今日获得 38 能量，距离下一阶段 712'),
        findsOne,
      );
    } finally {
      semantics.dispose();
    }
  });

  test('绘制层顺序固定且主体先于表情、装扮和特效', () {
    expect(
      PixelPetPainter.layerOrder,
      const <PixelRenderLayer>[
        PixelRenderLayer.offGrid,
        PixelRenderLayer.body,
        PixelRenderLayer.expression,
        PixelRenderLayer.accessory,
        PixelRenderLayer.effect,
      ],
    );
  });
}
