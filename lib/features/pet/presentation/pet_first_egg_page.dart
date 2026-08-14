import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/trainmate_visual_mode.dart';
import '../../../core/theme/trainflow_tokens.dart';
import '../../../core/widgets/trainmate_branding.dart';
import '../../../core/widgets/trainmate_showcase_widgets.dart';
import '../../../core/widgets/trainflow_widgets.dart';
import '../../../data/models/pet.dart';
import '../application/pet_controller.dart';
import 'illustrated_pet_renderer.dart';

class PetFirstEggPage extends ConsumerWidget {
  const PetFirstEggPage({super.key, this.asMainTab = false});

  final bool asMainTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget content = TrainFlowPage(
      title: '选择第一颗伙伴蛋',
      subtitle: 'M1 先完成衡衡狸的完整养成闭环',
      eyebrow: '训练伙伴',
      includeDisclaimer: false,
      children: <Widget>[
        TrainFlowCard(
          tone: TrainFlowCardTone.peach,
          child: Column(
            children: <Widget>[
              const IllustratedPetRenderer(
                species: PetSpecies.balanceRaccoon,
                stage: PetStage.patternEgg,
                mood: PetMood.calm,
                semanticLabel: '衡衡狸伙伴蛋，等待选择',
                size: 196,
              ),
              const SizedBox(height: 12),
              Text(
                '衡衡狸',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              const Text('擅长把训练、活动与恢复保持在平衡节奏中。'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => ref
                      .read(petControllerProvider.notifier)
                      .chooseFirstEgg(PetSpecies.balanceRaccoon),
                  child: const Text('选择衡衡狸'),
                ),
              ),
            ],
          ),
        ),
        const TrainFlowCard(
          child: Text('其余五种伙伴将在下一里程碑开放，届时可首蛋自选并建立完整图鉴。'),
        ),
      ],
    );
    if (!asMainTab) return content;
    return TrainMateImmersiveHubPage(
      includeDisclaimer: false,
      mode: TrainMateVisualMode.darkTraining,
      hero: TrainMateSceneHero(
        sceneAsset:
            'assets/images/immersive_scenes/trainmate_companion_room.png',
        greeting: '你好，训练者',
        dateLabel: '运动搭子',
        character: const TrainMateBrandmark(size: 128),
        taskTitle: '选择第一颗伙伴蛋',
        taskSubtitle: '选择后，衡衡狸会在已有训练与活动事实里陪你。',
        taskIcon: Icons.egg_alt_outlined,
      ),
      children: <Widget>[
        TrainFlowCard(
          tone: TrainFlowCardTone.peach,
          child: Column(
            children: <Widget>[
              const IllustratedPetRenderer(
                species: PetSpecies.balanceRaccoon,
                stage: PetStage.patternEgg,
                mood: PetMood.calm,
                semanticLabel: '衡衡狸伙伴蛋，等待选择',
                size: 168,
              ),
              const SizedBox(height: 10),
              Text(
                '衡衡狸',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: TrainFlowTokens.darkTrainingOnSurface,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              const Text('擅长把训练、活动与恢复保持在平衡节奏中。'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => ref
                      .read(petControllerProvider.notifier)
                      .chooseFirstEgg(PetSpecies.balanceRaccoon),
                  child: const Text('选择衡衡狸'),
                ),
              ),
            ],
          ),
        ),
        const TrainFlowCard(
          child: Text('其余五种伙伴将在下一里程碑开放，届时可首蛋自选并建立完整图鉴。'),
        ),
      ],
    );
  }
}
