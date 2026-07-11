import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/training_plan.dart';
import '../../data/models/workout_day.dart';
import '../dashboard/training_mvp_controller.dart';

class PlanListPage extends ConsumerWidget {
  const PlanListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);

    return TrainFlowPage(
      title: '训练计划',
      subtitle: '按周查看训练结构，并进入每天的具体安排。',
      children: [
        for (final TrainingPlan plan in state.plans)
          TrainFlowCard(
            onTap: () => context.go(AppRoutes.planDetail(plan.id)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    ToneBadge(label: '${plan.durationWeeks} 周'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  plan.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 12),
                InfoRow(label: '目标', value: plan.goal),
                InfoRow(label: '周结构', value: plan.weeklyStructure),
                const SizedBox(height: 8),
                _WorkoutPreview(days: plan.workoutDays.take(4).toList()),
              ],
            ),
          ),
      ],
    );
  }
}

class _WorkoutPreview extends StatelessWidget {
  final List<WorkoutDay> days;

  const _WorkoutPreview({required this.days});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final WorkoutDay day in days)
          ToneBadge(
            label:
                'D${day.dayIndex} ${day.trainingType.label}/${day.decisionType.label}',
            color: AppColors.secondary,
          ),
      ],
    );
  }
}
