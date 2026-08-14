import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/features/pet/presentation/pixel_frames/pet_frame_catalog.dart';
import 'package:trainflow_ai/features/pet/presentation/pixel_frames/pixel_frame.dart';

void main() {
  group('PixelFrame', () {
    test('拒绝非 24 行、超过 24 位和全空主体', () {
      expect(
        () => PixelFrame(List<int>.filled(23, 1)),
        throwsArgumentError,
      );
      expect(
        () => PixelFrame(<int>[
          1 << 24,
          ...List<int>.filled(23, 1),
        ]),
        throwsArgumentError,
      );
      expect(
        () => PixelFrame(List<int>.filled(24, 0)),
        throwsArgumentError,
      );
    });

    test('按坐标读取低 24 位像素', () {
      final PixelFrame frame = PixelFrame(<int>[
        5,
        ...List<int>.filled(23, 1),
      ]);

      expect(frame.isOn(0, 0), isTrue);
      expect(frame.isOn(1, 0), isFalse);
      expect(frame.isOn(2, 0), isTrue);
    });
  });

  test('衡衡狸五阶段恰好提供 10 个非空且可区分的主体帧', () {
    final List<PetFormFrames> forms = PetStage.values
        .map(
          (PetStage stage) => PetFrameCatalog.formFor(
            PetSpecies.balanceRaccoon,
            stage,
          ),
        )
        .toList(growable: false);

    expect(forms, hasLength(5));
    expect(forms.expand((PetFormFrames form) => form.frames), hasLength(10));
    for (final PetFormFrames form in forms) {
      expect(form.species, PetSpecies.balanceRaccoon);
      expect(form.frameA, isNot(form.frameB));
      expect(form.frameA.litPixelCount, greaterThan(0));
      expect(form.frameB.litPixelCount, greaterThan(0));
    }
  });
}
