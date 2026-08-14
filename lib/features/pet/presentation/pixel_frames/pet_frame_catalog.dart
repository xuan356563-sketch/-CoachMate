import '../../../../data/models/pet.dart';
import 'balance_raccoon_frames.dart';
import 'pixel_frame.dart';

/// M1 点阵目录，仅包含衡衡狸五阶段。
abstract final class PetFrameCatalog {
  static final Map<(PetSpecies, PetStage), PetFormFrames> _forms =
      <(PetSpecies, PetStage), PetFormFrames>{
    for (final PetFormFrames form in balanceRaccoonForms)
      (form.species, form.stage): form,
  };

  static List<PetFormFrames> get forms =>
      List<PetFormFrames>.unmodifiable(_forms.values);

  static PetFormFrames formFor(PetSpecies species, PetStage stage) {
    final PetFormFrames? form = _forms[(species, stage)];
    if (form == null) {
      throw StateError('当前里程碑尚未提供 ${species.id}/${stage.id} 的点阵形态');
    }
    return form;
  }
}
