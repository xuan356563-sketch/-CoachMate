import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainmate_action_mappings.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/exercise.dart';
import '../../data/models/exercise_training_profile.dart';
import '../../data/models/plan_adjustment.dart';
import '../../data/models/workout_day.dart';
import '../dashboard/training_mvp_controller.dart';
import 'application/plan_adjustment_controller.dart';

class WorkoutDetailPage extends ConsumerWidget {
  final String planId;
  final String workoutDayId;

  const WorkoutDetailPage({
    super.key,
    required this.planId,
    required this.workoutDayId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final WorkoutDay? workout = state.findWorkoutDay(workoutDayId);

    if (workout == null) {
      return TrainFlowPage(
        title: '训练日不存在',
        leading: TrainMateBackButton(
          fallbackRoute: AppRoutes.planDetail(planId),
        ),
        artwork: const TrainMateActionCharacter(
          action: TrainMateAction.seatedMeditation,
          backgroundColor: AppColors.primary,
        ),
        children: const [
          TrainFlowCard(
            cornerCharacterAction: TrainMateAction.seatedMeditation,
            child: Text('没有找到对应训练日。'),
          ),
        ],
      );
    }
    final TrainMateAction characterAction =
        trainMateActionForTrainingType(workout.trainingType);
    final PlanAdjustment? latestAdjustment =
        state.latestPlanAdjustmentFor(workout.id);
    final bool hasActiveAdjustment = latestAdjustment?.isActive ?? false;

    return TrainFlowPage(
      title: workout.title,
      subtitle: '第 ${workout.weekIndex} 周 · 第 ${workout.dayIndex} 天',
      leading: TrainMateBackButton(
        fallbackRoute: AppRoutes.planDetail(planId),
      ),
      artwork: TrainMateActionCharacter(
        action: characterAction,
        backgroundColor: AppColors.primary,
      ),
      children: [
        TrainFlowCard(
          cornerCharacterAction: characterAction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ToneBadge(label: workout.trainingType.label),
                  const SizedBox(width: 8),
                  ToneBadge(
                    label: '决策 ${workout.decisionType.label}',
                    color: _decisionColor(workout.decisionType),
                  ),
                  const SizedBox(width: 8),
                  ToneBadge(
                    label: workout.intensity,
                    color: AppColors.secondary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              InfoRow(label: '预计时长', value: '${workout.estimatedMinutes} 分钟'),
              InfoRow(label: '教练提示', value: workout.coachNotes),
              if (!workout.dimensionFocus.isEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final TrainingDimension dimension
                        in workout.dimensionFocus.primary)
                      ToneBadge(
                        label: '主维度 · ${dimension.label}',
                        color: AppColors.primary,
                      ),
                    for (final TrainingDimension dimension
                        in workout.dimensionFocus.touch)
                      ToneBadge(label: '触达 · ${dimension.label}'),
                  ],
                ),
              ],
              if (hasActiveAdjustment) ...[
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primaryLightest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前调整：${workout.estimatedMinutes} 分钟 · ${workout.intensity}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latestAdjustment!.reason,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showPlanAdjustmentSheet(
                    context: context,
                    workout: workout,
                    hasActiveAdjustment: hasActiveAdjustment,
                  ),
                  icon: const Icon(Icons.tune_outlined),
                  label: const Text('手动调整本次计划'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                state.planAdjustmentStatusMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 12),
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.primaryLightest,
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.pets_outlined, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '训练是伙伴的主食；保存真实训练反馈且完成度达到 50% 后，才会结算伙伴能量。',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final bool started = ref
                        .read(trainingMvpProvider.notifier)
                        .startWorkoutPlayer(workoutDayId: workout.id);
                    if (started) {
                      context.push(AppRoutes.workoutPlayer);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ref
                                .read(trainingMvpProvider)
                                .workoutPlayerStatusMessage,
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始跟练'),
                ),
              ),
            ],
          ),
        ),
        _WorkoutBlock(title: '1. 泡沫轴放松', items: workout.foamRollingSteps),
        _WorkoutBlock(title: '2. 动态拉伸', items: workout.dynamicStretchSteps),
        _WorkoutBlock(title: '3. 激活动作', items: workout.activationSteps),
        _WorkoutBlock(title: '4. 正式训练', items: workout.mainSets),
        if (workout.workoutExercises.isNotEmpty)
          _WorkoutExerciseLinksCard(
            links: workout.workoutExercises,
            exercises: state.exercises,
          ),
        _WorkoutBlock(title: '辅助训练', items: workout.accessoryWork),
        _WorkoutBlock(title: '5. 训练后放松与反馈', items: workout.cooldownSteps),
      ],
    );
  }
}

Future<void> _showPlanAdjustmentSheet({
  required BuildContext context,
  required WorkoutDay workout,
  required bool hasActiveAdjustment,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) {
      return _PlanAdjustmentSheet(
        workout: workout,
        hasActiveAdjustment: hasActiveAdjustment,
      );
    },
  );
}

class _PlanAdjustmentSheet extends ConsumerStatefulWidget {
  final WorkoutDay workout;
  final bool hasActiveAdjustment;

  const _PlanAdjustmentSheet({
    required this.workout,
    required this.hasActiveAdjustment,
  });

  @override
  ConsumerState<_PlanAdjustmentSheet> createState() =>
      _PlanAdjustmentSheetState();
}

class _PlanAdjustmentSheetState extends ConsumerState<_PlanAdjustmentSheet> {
  late final TextEditingController _minutesController;
  late final TextEditingController _reasonController;
  late String _selectedIntensity;
  String? _errorMessage;

  List<String> get _intensityOptions {
    return <String>{
      widget.workout.intensity,
      'RPE 2-3',
      'RPE 4-5',
      'RPE 6',
      'RPE 7',
    }.toList();
  }

  @override
  void initState() {
    super.initState();
    _minutesController = TextEditingController(
      text: widget.workout.estimatedMinutes.toString(),
    );
    _reasonController = TextEditingController();
    _selectedIntensity = widget.workout.intensity;
  }

  @override
  void dispose() {
    _minutesController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _save() {
    final int? adjustedMinutes = int.tryParse(_minutesController.text.trim());
    final String reason = _reasonController.text.trim();
    if (adjustedMinutes == null ||
        adjustedMinutes < 5 ||
        adjustedMinutes > 180) {
      setState(() {
        _errorMessage = '请输入 5 到 180 分钟之间的预计时长。';
      });
      return;
    }
    if (reason.isEmpty) {
      setState(() {
        _errorMessage = '请填写调整原因，供后续训练画像参考。';
      });
      return;
    }
    ref.read(planAdjustmentControllerProvider.notifier).saveManualAdjustment(
          workout: widget.workout,
          adjustedMinutes: adjustedMinutes,
          adjustedIntensity: _selectedIntensity,
          reason: reason,
        );
    Navigator.of(context).pop();
  }

  void _restore() {
    ref
        .read(planAdjustmentControllerProvider.notifier)
        .restoreOriginalPlan(widget.workout);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '手动调整训练日',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '只调整本次执行时长与强度，原始动作、训练依据和安全约束保持不变。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey<String>('plan-adjustment-minutes-field'),
                controller: _minutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '预计时长（分钟）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedIntensity,
                decoration: const InputDecoration(
                  labelText: '执行强度',
                  border: OutlineInputBorder(),
                ),
                items: _intensityOptions
                    .map(
                      (String intensity) => DropdownMenuItem<String>(
                        value: intensity,
                        child: Text(intensity),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedIntensity = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey<String>('plan-adjustment-reason-field'),
                controller: _reasonController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '调整原因',
                  hintText: '例如：今天只有午休时间',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('保存调整'),
                ),
              ),
              if (widget.hasActiveAdjustment) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _restore,
                    child: const Text('恢复原计划'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Color _decisionColor(TrainingDecisionType decisionType) {
  switch (decisionType) {
    case TrainingDecisionType.normal:
      return AppColors.primary;
    case TrainingDecisionType.deload:
      return AppColors.warningDark;
    case TrainingDecisionType.recovery:
      return AppColors.success;
    case TrainingDecisionType.technique:
      return AppColors.secondary;
    case TrainingDecisionType.rest:
      return AppColors.textSecondary;
  }
}

class _WorkoutBlock extends StatelessWidget {
  final String title;
  final List<String> items;

  const _WorkoutBlock({
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
          if (items.isEmpty)
            Text(
              '本日无该模块安排。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            )
          else
            for (final String item in items) ...[
              Text('· $item'),
              if (item != items.last) const SizedBox(height: 6),
            ],
        ],
      ),
    );
  }
}

class _WorkoutExerciseLinksCard extends StatelessWidget {
  final List<WorkoutExerciseLink> links;
  final List<Exercise> exercises;

  const _WorkoutExerciseLinksCard({
    required this.links,
    required this.exercises,
  });

  @override
  Widget build(BuildContext context) {
    final List<WorkoutExerciseLink> sortedLinks = [...links]..sort(
        (WorkoutExerciseLink first, WorkoutExerciseLink second) =>
            first.sequence.compareTo(second.sequence),
      );
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '训练-动作关联',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final WorkoutExerciseLink link in sortedLinks) ...[
            _WorkoutExerciseLinkRow(
              link: link,
              exercise: _findExercise(link.exerciseId),
            ),
            if (link != sortedLinks.last) const Divider(height: 20),
          ],
        ],
      ),
    );
  }

  Exercise? _findExercise(String id) {
    for (final Exercise exercise in exercises) {
      if (exercise.id == id) {
        return exercise;
      }
    }
    return null;
  }
}

class _WorkoutExerciseLinkRow extends StatelessWidget {
  final WorkoutExerciseLink link;
  final Exercise? exercise;

  const _WorkoutExerciseLinkRow({
    required this.link,
    required this.exercise,
  });

  @override
  Widget build(BuildContext context) {
    final String exerciseName = exercise?.name ?? link.exerciseId;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: AppColors.primaryLightest,
          child: Text(
            '${link.sequence}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$exerciseName · ${link.prescriptionLabel}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  ToneBadge(label: link.module.label),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                exercise == null
                    ? '动作库暂未找到该关联。'
                    : '器械：${exercise!.equipment.join('、')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              if (exercise != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    if (link.tempo != null)
                      ToneBadge(label: '节奏 ${link.tempo}'),
                    ToneBadge(label: link.executionIntent.label),
                    for (final LegTrainingElement element
                        in exercise!.trainingStructureProfile.legElements)
                      ToneBadge(label: element.label),
                  ],
                ),
                if (link.breathingCue != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '呼吸：${link.breathingCue}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
