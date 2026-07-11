import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/exercise.dart';
import '../dashboard/training_mvp_controller.dart';

class ExerciseListPage extends ConsumerWidget {
  const ExerciseListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);

    return TrainFlowPage(
      title: '动作库',
      subtitle: '沉淀跑步、力量、康复和 HYROX 训练动作。',
      children: [
        for (final Exercise exercise in state.exercises)
          TrainFlowCard(
            onTap: () => context.go(AppRoutes.exerciseDetail(exercise.id)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        exercise.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    ToneBadge(label: exercise.category.label),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  exercise.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: Text('建议：${exercise.setsAndReps}')),
                    if (exercise.mediaUrl != null)
                      ToneBadge(
                        label: exercise.mediaStatus.label,
                        color:
                            exercise.mediaStatus == ExerciseMediaStatus.precise
                                ? AppColors.primary
                                : AppColors.secondary,
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
