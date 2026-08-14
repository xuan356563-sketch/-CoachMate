import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/body_rhythm.dart';
import 'application/body_rhythm_controller.dart';

class RhythmDetailPage extends ConsumerWidget {
  const RhythmDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<BodyRhythmState> rhythm =
        ref.watch(bodyRhythmControllerProvider);
    return TrainFlowPage(
      title: '身体节奏',
      layout: TrainFlowPageLayout.report,
      subtitle: '基于近 30 天长期趋势，每周一生成一次不可变快照。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.dashboard,
      ),
      children: [
        rhythm.when(
          data: (BodyRhythmState value) =>
              _RhythmHeroCard(snapshot: value.snapshot),
          loading: () => const TrainFlowCard(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object error, StackTrace stackTrace) => TrainFlowCard(
            child: Text('身体节奏暂时无法读取：$error'),
          ),
        ),
        if (rhythm case AsyncData<BodyRhythmState>(:final value)) ...[
          _RhythmSpeedCard(snapshot: value.snapshot),
          _FactorCard(snapshot: value.snapshot),
          TrainFlowCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.fact_check_outlined,
                color: AppColors.primary,
              ),
              title: const Text('15 天复盘'),
              subtitle: Text(
                value.reviewStatus.isUnlocked
                    ? '记录条件已满足，可以查看阶段变化。'
                    : value.reviewStatus.gaps.join('；'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.progressReview),
            ),
          ),
          const TrainFlowCard(
            key: ValueKey<String>('rhythm-medical-disclaimer'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppColors.textSecondary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '这不是医学年龄。状态年龄根据你的长期行为与健康趋势估算，'
                    '用于帮助你选择下一步训练行动，不预测寿命，也不能代替医学检查。',
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RhythmHeroCard extends StatelessWidget {
  const _RhythmHeroCard({required this.snapshot});

  final RhythmSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final String primaryText;
    final String secondaryText;
    if (!snapshot.hasBaseline) {
      primaryText = '${snapshot.sufficientFactorCount}/4';
      secondaryText = '状态基线积累中';
    } else if (snapshot.stateAge == null) {
      primaryText = '${snapshot.speed.toStringAsFixed(1)}×';
      secondaryText = '填写生日后显示状态年龄';
    } else {
      primaryText = snapshot.stateAge!.toStringAsFixed(1);
      secondaryText = '状态年龄';
    }
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Semantics(
        label: '$secondaryText，$primaryText。${snapshot.paceLabel}',
        child: Column(
          children: [
            SizedBox(
              width: 190,
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: ((snapshot.speed - 0.6) / 0.8).clamp(0, 1),
                      strokeWidth: 14,
                      color: AppColors.primary,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.12),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        primaryText,
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        secondaryText,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              snapshot.hasBaseline ? snapshot.paceLabel : '还需要更多长期数据',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '算法 ${snapshot.configVersion} · 每周更新一次',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RhythmSpeedCard extends StatelessWidget {
  const _RhythmSpeedCard({required this.snapshot});

  final RhythmSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final double position = ((snapshot.speed - 0.6) / 0.8).clamp(0, 1);
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '近期节奏速度',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    Text(
                      snapshot.paceLabel,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              Text(
                '${snapshot.speed.toStringAsFixed(1)}×',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Semantics(
            label: '节奏速度 ${snapshot.speed.toStringAsFixed(1)} 倍，'
                '范围从 0.6 倍放缓到 1.4 倍加快',
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return SizedBox(
                  height: 18,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.success,
                              AppColors.secondary,
                              AppColors.primary,
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: position * (constraints.maxWidth - 18),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.textPrimary,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0.6× 放缓'),
              Text('1.0× 稳定'),
              Text('1.4× 加快'),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '正常节奏 1.0× + 近 30 天四项变化 '
            '= ${snapshot.speed.toStringAsFixed(1)}×',
          ),
        ],
      ),
    );
  }
}

class _FactorCard extends StatelessWidget {
  const _FactorCard({required this.snapshot});

  final RhythmSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '四项怎么影响速度',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final RhythmFactor factor in RhythmFactor.values) ...[
            _FactorRow(result: snapshot.factors[factor]!),
            if (factor != RhythmFactor.values.last) const Divider(height: 20),
          ],
        ],
      ),
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.result});

  final RhythmFactorResult result;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (result.factor) {
      RhythmFactor.sleep => Icons.bedtime_outlined,
      RhythmFactor.activity => Icons.directions_walk,
      RhythmFactor.training => Icons.fitness_center,
      RhythmFactor.restingHeartRate => Icons.favorite_outline,
    };
    return Semantics(
      label: '${result.factor.label}，${result.summary}，${result.statusLabel}',
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.10),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.factor.label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  result.summary,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            result.statusLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: result.isSufficient
                  ? AppColors.primary
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
