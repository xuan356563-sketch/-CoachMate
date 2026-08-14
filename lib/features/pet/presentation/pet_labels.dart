import '../../../data/models/pet.dart';

String petStageLabel(PetStage stage) => switch (stage) {
      PetStage.patternEgg => '纹样蛋',
      PetStage.sprout => '萌芽体',
      PetStage.junior => '幼练体',
      PetStage.advanced => '进阶体',
      PetStage.champion => '冠军体',
    };

String petMoodLabel(PetMood mood) => switch (mood) {
      PetMood.excited => '兴奋',
      PetMood.happy => '开心',
      PetMood.curious => '好奇',
      PetMood.calm => '平静',
      PetMood.waiting => '等待',
    };
