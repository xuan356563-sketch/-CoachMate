import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/exercise_media.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/evidence_source.dart';
import '../../data/models/exercise.dart';
import '../../data/models/exercise_body_profile.dart';
import '../../data/models/user_profile.dart';
import '../dashboard/training_mvp_controller.dart';

class ExerciseDetailPage extends ConsumerWidget {
  final String exerciseId;

  const ExerciseDetailPage({super.key, required this.exerciseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final Exercise? exercise = state.findExercise(exerciseId);

    if (exercise == null) {
      return const TrainFlowPage(
        title: '动作不存在',
        children: [
          TrainFlowCard(child: Text('没有找到对应动作。')),
        ],
      );
    }

    final ExerciseBodyProfile bodyProfile = exercise.bodyEngineProfile;

    return TrainFlowPage(
      title: exercise.name,
      subtitle: exercise.category.label,
      children: [
        if (exercise.mediaUrl != null)
          TrainFlowCard(
            child: ExerciseMedia(exercise: exercise),
          ),
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(exercise.description),
              const SizedBox(height: 12),
              InfoRow(label: '目标肌群', value: exercise.targetMuscles.join('、')),
              InfoRow(
                label: '适用运动',
                value: exercise.sportTags
                    .map((MainSport sport) => sport.label)
                    .join('、'),
              ),
              InfoRow(label: '组数次数', value: exercise.setsAndReps),
              InfoRow(label: '器械', value: exercise.equipment.join('、')),
            ],
          ),
        ),
        if (bodyProfile.isStructured)
          TrainFlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Body Engine 结构化解释',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                InfoRow(label: '动作模式', value: bodyProfile.movementPattern),
                InfoRow(
                  label: '涉及关节',
                  value: bodyProfile.involvedJoints.join('、'),
                ),
                InfoRow(
                  label: '主要肌群',
                  value: bodyProfile.primaryMuscles.join('、'),
                ),
                InfoRow(
                  label: '稳定肌群',
                  value: bodyProfile.stabilizerMuscles.join('、'),
                ),
                InfoRow(
                  label: '风险区域',
                  value: bodyProfile.riskAreas.join('、'),
                ),
                InfoRow(
                  label: '常见代偿',
                  value: bodyProfile.commonCompensations.join('、'),
                ),
              ],
            ),
          ),
        if (exercise.breathingCue.isNotEmpty ||
            exercise.contraindications.isNotEmpty ||
            exercise.suitableFor.isNotEmpty)
          TrainFlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '身体与安全提示',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (exercise.breathingCue.isNotEmpty)
                  InfoRow(label: '呼吸方式', value: exercise.breathingCue),
                if (exercise.suitableFor.isNotEmpty)
                  InfoRow(
                    label: '适用场景',
                    value: exercise.suitableFor.join('、'),
                  ),
                if (exercise.contraindications.isNotEmpty)
                  InfoRow(
                    label: '先暂停',
                    value: exercise.contraindications.join('；'),
                  ),
              ],
            ),
          ),
        _ExerciseBlock(title: '动作步骤', items: exercise.steps),
        _ExerciseBlock(title: '常见错误', items: exercise.commonMistakes),
        if (exercise.relations.isNotEmpty)
          _ExerciseRelationsCard(
            relations: exercise.relations,
            exercises: state.exercises,
          ),
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '依据来源',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              for (final source in exercise.evidenceSources) ...[
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                if (source != exercise.evidenceSources.last)
                  const Divider(height: 20),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ExerciseRelationsCard extends StatelessWidget {
  final List<ExerciseRelation> relations;
  final List<Exercise> exercises;

  const _ExerciseRelationsCard({
    required this.relations,
    required this.exercises,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, Exercise> exercisesById = {
      for (final Exercise exercise in exercises) exercise.id: exercise,
    };
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '动作调整',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final ExerciseRelation relation in relations) ...[
            _ExerciseRelationRow(
              relation: relation,
              exercise: exercisesById[relation.targetExerciseId],
            ),
            if (relation != relations.last) const Divider(height: 18),
          ],
        ],
      ),
    );
  }
}

class _ExerciseRelationRow extends StatelessWidget {
  final ExerciseRelation relation;
  final Exercise? exercise;

  const _ExerciseRelationRow({
    required this.relation,
    required this.exercise,
  });

  @override
  Widget build(BuildContext context) {
    final String targetName = exercise?.name ?? relation.targetExerciseId;
    return InkWell(
      onTap: exercise == null
          ? null
          : () => context.go(AppRoutes.exerciseDetail(exercise!.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconFor(relation.type), color: AppColors.secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ToneBadge(label: relation.type.label),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          targetName,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    relation.reason,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            if (exercise != null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child:
                    Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(ExerciseRelationType type) {
    return switch (type) {
      ExerciseRelationType.replacement => Icons.swap_horiz,
      ExerciseRelationType.regression => Icons.trending_down,
      ExerciseRelationType.progression => Icons.trending_up,
    };
  }
}

class _ExerciseBlock extends StatelessWidget {
  final String title;
  final List<String> items;

  const _ExerciseBlock({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final String item in items) ...[
            Text('· $item'),
            if (item != items.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}
