import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/evidence_source.dart';
import '../dashboard/training_mvp_controller.dart';

class AiCoachPage extends ConsumerWidget {
  const AiCoachPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);

    return TrainFlowPage(
      title: 'AI 教练',
      subtitle: '第一版为 Mock 决策建议，后续接真实训练规则和模型。',
      children: [
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI 教练建议 Mock',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              for (final String advice in state.coachAdvices) ...[
                Text('· $advice'),
                if (advice != state.coachAdvices.last)
                  const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        const SectionTitle(title: '决策依据'),
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final EvidenceSource source
                  in state.todayWorkout.evidenceSources) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        source.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    ToneBadge(
                      label: source.sourceType.label,
                      color: AppColors.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  source.citationLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text('原文片段：${source.quote}'),
                const SizedBox(height: 4),
                Text(
                  '适用原因：${source.note}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                if (source != state.todayWorkout.evidenceSources.last)
                  const Divider(height: 22),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
