import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/models/pet.dart';
import '../pet_labels.dart';
import '../pixel_pet_renderer.dart';

class PetLcdDevice extends StatelessWidget {
  const PetLcdDevice({
    super.key,
    required this.companion,
    required this.todayEnergy,
    required this.nextStageDistance,
  });

  final PetCompanion companion;
  final int todayEnergy;
  final int? nextStageDistance;

  @override
  Widget build(BuildContext context) {
    final String distance =
        nextStageDistance == null ? '已达到冠军阶段' : '距离下一阶段 $nextStageDistance';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.petInk,
        border: Border.all(color: AppColors.petInkDeep, width: 2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            PixelPetRenderer(
              species: companion.species,
              stage: companion.stage,
              mood: companion.mood,
              semanticLabel:
                  '${companion.nickname}，${petStageLabel(companion.stage)}，'
                  '心情${petMoodLabel(companion.mood)}，今日获得 $todayEnergy 能量，$distance',
              size: 220,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  companion.nickname,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.petPaper,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                Text(
                  petStageLabel(companion.stage),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.petPeach,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
