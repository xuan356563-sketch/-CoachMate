import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/evidence_source.dart';
import '../../data/models/meal_guide.dart';
import '../dashboard/training_mvp_controller.dart';

class MealGuidePage extends ConsumerWidget {
  const MealGuidePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final MealGuide activeGuide = state.activeMealGuide;

    return TrainFlowPage(
      title: '照吃指令卡',
      subtitle: '不记录热量，只给今天最容易执行的一条饮食指令。',
      children: [
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '吃饭场景',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MealScenario>(
                initialValue: state.mealScenario,
                decoration: const InputDecoration(labelText: '今天怎么吃'),
                items: [
                  for (final MealScenario scenario in MealScenario.values)
                    DropdownMenuItem<MealScenario>(
                      value: scenario,
                      child: Text(scenario.label),
                    ),
                ],
                onChanged: (MealScenario? value) {
                  if (value != null) {
                    ref
                        .read(trainingMvpProvider.notifier)
                        .setMealScenario(value);
                  }
                },
              ),
            ],
          ),
        ),
        _MealGuideCard(guide: activeGuide),
        const SectionTitle(title: '三种场景模板'),
        for (final MealGuide guide in state.mealGuides)
          _MealGuideSummaryCard(guide: guide),
      ],
    );
  }
}

class _MealGuideCard extends StatelessWidget {
  final MealGuide guide;

  const _MealGuideCard({required this.guide});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  guide.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: guide.dayLabel, color: AppColors.secondary),
            ],
          ),
          const SizedBox(height: 12),
          InfoRow(label: '今天照吃', value: guide.instruction),
          InfoRow(label: '公式', value: guide.formula),
          InfoRow(label: '只加一件事', value: guide.addOneThing),
          InfoRow(label: '避开', value: guide.avoidItems.join('、')),
          const SizedBox(height: 8),
          Text(
            guide.reason,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 14),
          _EvidenceBlock(sources: guide.evidenceSources),
        ],
      ),
    );
  }
}

class _MealGuideSummaryCard extends StatelessWidget {
  final MealGuide guide;

  const _MealGuideSummaryCard({required this.guide});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Row(
        children: [
          ToneBadge(label: guide.scenario.label),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              guide.instruction,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceBlock extends StatelessWidget {
  final List<EvidenceSource> sources;

  const _EvidenceBlock({required this.sources});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '依据来源',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final EvidenceSource source in sources) ...[
          Text(
            source.citationLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text('原文片段：${source.quote}'),
          const SizedBox(height: 4),
          Text(
            '适用原因：${source.note}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          if (source != sources.last) const Divider(height: 18),
        ],
      ],
    );
  }
}
