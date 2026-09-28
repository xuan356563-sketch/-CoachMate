import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/features/pet/presentation/illustrated_pet_renderer.dart';

void main() {
  Future<void> pumpRenderer(
    WidgetTester tester, {
    PetStage stage = PetStage.sprout,
    PetMood mood = PetMood.happy,
    bool disableAnimations = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Center(
              child: IllustratedPetRenderer(
                species: PetSpecies.balanceRaccoon,
                stage: stage,
                mood: mood,
                semanticLabel: '袋小满，${stage.id}，${mood.id}',
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('使用平滑 2D 插画画布而不是 24×24 点阵帧', (tester) async {
    await pumpRenderer(tester);

    expect(find.byType(IllustratedPetRenderer), findsOneWidget);
    expect(find.byType(IllustratedPetCanvas), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('illustrated-pet-body')), findsOne);
    expect(
        find.byKey(const ValueKey<String>('pixel-pet-frame-0')), findsNothing);
    expect(
        find.byKey(const ValueKey<String>('pixel-pet-frame-1')), findsNothing);
  });

  testWidgets('五个成长阶段都有可识别的插画配置', (tester) async {
    for (final PetStage stage in PetStage.values) {
      await pumpRenderer(tester, stage: stage);
      final IllustratedPetCanvas canvas = tester.widget<IllustratedPetCanvas>(
        find.byType(IllustratedPetCanvas),
      );
      expect(canvas.stage, stage);
      expect(canvas.visual.stageScale, greaterThan(0));
    }
  });

  testWidgets('五种心情映射到不同表情并保留完整语义', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      final Set<String> signatures = <String>{};
      for (final PetMood mood in PetMood.values) {
        await pumpRenderer(tester, mood: mood, disableAnimations: true);
        final IllustratedPetCanvas canvas = tester.widget<IllustratedPetCanvas>(
          find.byType(IllustratedPetCanvas),
        );
        signatures.add(canvas.visual.expressionSignature);
        expect(
          find.bySemanticsLabel('袋小满，sprout，${mood.id}'),
          findsOne,
        );
      }
      expect(signatures, hasLength(PetMood.values.length));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('关闭动态效果后角色直接保持最终静态姿态', (tester) async {
    await pumpRenderer(tester, disableAnimations: true);
    final Transform initial = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('illustrated-pet-motion')),
    );

    await tester.pump(const Duration(seconds: 2));
    final Transform settled = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('illustrated-pet-motion')),
    );

    expect(initial.transform, settled.transform);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
