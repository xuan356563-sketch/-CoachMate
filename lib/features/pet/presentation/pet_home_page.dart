import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/trainmate_showcase_widgets.dart';
import '../../../core/widgets/trainflow_widgets.dart';
import '../../../data/models/pet.dart';
import '../application/pet_controller.dart';
import 'illustrated_pet_renderer.dart';
import 'pet_first_egg_page.dart';
import 'pet_labels.dart';
import 'widgets/pet_energy_breakdown_card.dart';
import 'widgets/pet_illustration_card.dart';

class PetHomePage extends ConsumerWidget {
  const PetHomePage({super.key, this.archiveMode = false});

  final bool archiveMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PetState> state = ref.watch(petControllerProvider);
    return state.when(
      loading: () => TrainFlowPage(
        title: archiveMode ? '成长档案' : '我的伙伴',
        leading: archiveMode
            ? const TrainMateBackButton(fallbackRoute: AppRoutes.companion)
            : null,
        includeDisclaimer: false,
        children: <Widget>[
          TrainMateStatePanel(
            title: '正在唤醒伙伴',
            message: '训练与活动数据正在本机读取。',
            icon: Icons.pets_outlined,
          ),
        ],
      ),
      error: (_, __) => _PetUnavailablePage(
        message: '伙伴状态读取失败，训练功能仍可正常使用。',
        archiveMode: archiveMode,
      ),
      data: (PetState value) => switch (value.status) {
        PetStateStatus.needsFirstEgg when archiveMode =>
          const _PetUnavailablePage(
            message: '先选择衡衡狸后，才能查看成长档案。',
            archiveMode: true,
          ),
        PetStateStatus.needsFirstEgg => const PetFirstEggPage(),
        PetStateStatus.storageUnavailable ||
        PetStateStatus.readOnly =>
          _PetUnavailablePage(
            message: value.statusMessage,
            archiveMode: archiveMode,
          ),
        PetStateStatus.ready => _ReadyPetHome(
            state: value,
            archiveMode: archiveMode,
          ),
      },
    );
  }
}

class _ReadyPetHome extends StatelessWidget {
  const _ReadyPetHome({required this.state, required this.archiveMode});

  final PetState state;
  final bool archiveMode;

  @override
  Widget build(BuildContext context) {
    final PetCompanion companion = state.activeCompanion!;
    final int todayEnergy = state.todayEnergy?.awardedTotal ?? 0;
    final int? nextStageDistance = _nextStageDistance(companion);
    final double progress = _stageProgress(companion);
    return TrainMateShowcasePage(
      showcase: TrainMateShowcaseEntrance(
        child: KeyedSubtree(
          key: const ValueKey<String>('pet-showcase-header'),
          child: TrainMateHubHeader(
            title: archiveMode ? '成长档案' : '我的伙伴',
            subtitle: archiveMode
                ? '查看衡衡狸的能量、活动和已记录的训练事实。'
                : '训练是主食，日常活动是零食，恢复日也会得到正向奖励。',
            eyebrow: '${archiveMode ? '搭子档案' : 'M1'} · ${companion.nickname}',
            semanticLabel: '训练伙伴概览',
            backgroundColor: AppColors.petPaper,
            accentColor: AppColors.secondary,
            artwork: IllustratedPetRenderer(
              species: companion.species,
              stage: companion.stage,
              mood: companion.mood,
              size: 150,
              semanticLabel: '${companion.nickname}的训练伙伴形象',
            ),
            action: archiveMode
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: TrainMateBackButton(
                      fallbackRoute: AppRoutes.companion,
                    ),
                  )
                : null,
            metrics: <Widget>[
              TrainMateHubMetric(
                label: '阶段',
                value: petStageLabel(companion.stage),
                icon: Icons.auto_awesome,
              ),
              TrainMateHubMetric(
                label: '今日能量',
                value: '$todayEnergy',
                icon: Icons.bolt,
                tone: TrainFlowCardTone.peach,
              ),
              TrainMateHubMetric(
                label: '伙伴星',
                value: '${companion.partnerStars}',
                icon: Icons.star_outline,
              ),
            ],
          ),
        ),
      ),
      includeDisclaimer: false,
      children: <Widget>[
        PetIllustrationCard(
          companion: companion,
          todayEnergy: todayEnergy,
          nextStageDistance: nextStageDistance,
        ),
        const SizedBox(height: 12),
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(petStageLabel(companion.stage)),
                  Text('今日能量 $todayEnergy'),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                nextStageDistance == null
                    ? '已达到冠军阶段 · 伙伴星 ${companion.partnerStars}'
                    : '距离下一阶段还需 $nextStageDistance 能量',
              ),
            ],
          ),
        ),
        PetEnergyBreakdownCard(energy: state.todayEnergy),
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('活动与补录', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(state.todayActivitySummary == null
                  ? '今日活动尚未同步，可连接 Apple 健康或手动补录。'
                  : '今日活动摘要已同步，缺失字段仍会保持“未授权”。'),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.petData),
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: const Text('管理活动数据'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PetUnavailablePage extends StatelessWidget {
  const _PetUnavailablePage({
    required this.message,
    this.archiveMode = false,
  });

  final String message;
  final bool archiveMode;

  @override
  Widget build(BuildContext context) {
    return TrainFlowPage(
      title: archiveMode ? '成长档案' : '我的伙伴',
      subtitle: '当前不会修改任何伙伴数据',
      leading: archiveMode
          ? const TrainMateBackButton(fallbackRoute: AppRoutes.companion)
          : null,
      includeDisclaimer: false,
      children: <Widget>[
        TrainMateStatePanel(
          title: '伙伴暂时不可用',
          message: message,
          icon: Icons.pets_outlined,
        ),
      ],
    );
  }
}

int? _nextStageDistance(PetCompanion companion) {
  final int? target = switch (companion.stage) {
    PetStage.patternEgg => 150,
    PetStage.sprout => 900,
    PetStage.junior => 2100,
    PetStage.advanced => 3600,
    PetStage.champion => null,
  };
  return target == null
      ? null
      : (target - companion.totalEnergy).clamp(0, target);
}

double _stageProgress(PetCompanion companion) {
  final (int start, int? end) = switch (companion.stage) {
    PetStage.patternEgg => (0, 150),
    PetStage.sprout => (150, 900),
    PetStage.junior => (900, 2100),
    PetStage.advanced => (2100, 3600),
    PetStage.champion => (3600, null),
  };
  if (end == null) return 1;
  return ((companion.totalEnergy - start) / (end - start)).clamp(0, 1);
}
