import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/exercise_media.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/exercise.dart';
import '../../data/models/training_log.dart';
import '../../data/models/workout_day.dart';
import '../../data/models/workout_player_step.dart';
import '../dashboard/training_mvp_controller.dart';

class WorkoutPlayerPage extends ConsumerWidget {
  const WorkoutPlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final WorkoutPlayerStep step = state.activeWorkoutPlayerStep;

    return TrainFlowPage(
      title: '跟练执行',
      subtitle: '逐步引导、真实倒计时、TTS 提示队列和练中一键降级。',
      action: IconButton(
        tooltip: '关闭跟练',
        onPressed: () => context.go(AppRoutes.dashboard),
        icon: const Icon(Icons.close),
      ),
      children: [
        _PlayerStatusCard(state: state, step: step),
        _CurrentStepCard(step: step, state: state),
        _PlayerAssistCard(state: state),
        _PlayerActionCard(state: state),
        _PlayerEventCard(events: state.workoutPlayerEvents),
      ],
    );
  }
}

Future<void> _showWorkoutReviewSheet({
  required BuildContext context,
  required WorkoutDay workout,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) {
      return _WorkoutReviewSheet(
        workout: workout,
      );
    },
  );
}

class _WorkoutReviewSheet extends ConsumerStatefulWidget {
  final WorkoutDay workout;

  const _WorkoutReviewSheet({
    required this.workout,
  });

  @override
  ConsumerState<_WorkoutReviewSheet> createState() =>
      _WorkoutReviewSheetState();
}

class _ExerciseExecutionDraft {
  final String? exerciseId;
  final String exerciseName;
  final int plannedSetCount;
  final int repetitionsPerSet;
  final TextEditingController completedSetController;
  final TextEditingController weightController;

  _ExerciseExecutionDraft({
    required this.exerciseId,
    required this.exerciseName,
    required this.plannedSetCount,
    required this.repetitionsPerSet,
  })  : completedSetController = TextEditingController(),
        weightController = TextEditingController();

  void dispose() {
    completedSetController.dispose();
    weightController.dispose();
  }
}

class _WorkoutReviewSheetState extends ConsumerState<_WorkoutReviewSheet> {
  late final TextEditingController _durationController;
  late final TextEditingController _heartRateController;
  late final TextEditingController _paceController;
  late final TextEditingController _plannedSetsController;
  late final TextEditingController _completedSetsController;
  late final TextEditingController _interruptionReasonController;
  late final TextEditingController _noteController;
  late final List<_ExerciseExecutionDraft> _exerciseDrafts;
  int _selectedRpe = 6;
  int _selectedCompletionPercentage = 100;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _durationController = TextEditingController(
      text: widget.workout.estimatedMinutes.toString(),
    );
    _heartRateController = TextEditingController();
    _paceController = TextEditingController();
    _plannedSetsController = TextEditingController();
    _completedSetsController = TextEditingController();
    _interruptionReasonController = TextEditingController();
    _noteController = TextEditingController();
    _exerciseDrafts = widget.workout.workoutExercises.isEmpty
        ? [
            for (final String description in widget.workout.mainSets)
              _buildExerciseDraft(description),
          ]
        : _buildStructuredExerciseDrafts();
  }

  @override
  void dispose() {
    _durationController.dispose();
    _heartRateController.dispose();
    _paceController.dispose();
    _plannedSetsController.dispose();
    _completedSetsController.dispose();
    _interruptionReasonController.dispose();
    _noteController.dispose();
    for (final _ExerciseExecutionDraft draft in _exerciseDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  _ExerciseExecutionDraft _buildExerciseDraft(String description) {
    final RegExpMatch? match = RegExp(
      r'^(.+?)\s+(\d+)\s*(?:组|轮)\s*(?:x|×)\s*(\d+)',
    ).firstMatch(description.trim());
    if (match == null) {
      return _ExerciseExecutionDraft(
        exerciseId: null,
        exerciseName: description,
        plannedSetCount: 0,
        repetitionsPerSet: 0,
      );
    }
    return _ExerciseExecutionDraft(
      exerciseId: null,
      exerciseName: match.group(1)!.trim(),
      plannedSetCount: int.tryParse(match.group(2)!) ?? 0,
      repetitionsPerSet: int.tryParse(match.group(3)!) ?? 0,
    );
  }

  List<_ExerciseExecutionDraft> _buildStructuredExerciseDrafts() {
    final List<WorkoutExerciseLink> links = [
      ...widget.workout.workoutExercises.where(
        (WorkoutExerciseLink link) =>
            link.module == WorkoutExerciseModule.mainTraining ||
            link.module == WorkoutExerciseModule.accessory,
      ),
    ]..sort(
        (WorkoutExerciseLink first, WorkoutExerciseLink second) =>
            first.sequence.compareTo(second.sequence),
      );
    return [
      for (final WorkoutExerciseLink link in links)
        _ExerciseExecutionDraft(
          exerciseId: link.exerciseId,
          exerciseName: ref
                  .read(trainingMvpProvider)
                  .findExercise(link.exerciseId)
                  ?.name ??
              link.exerciseId,
          plannedSetCount: link.plannedSetCount,
          repetitionsPerSet: link.repetitionsPerSet,
        ),
    ];
  }

  void _save() {
    final int? actualDuration = int.tryParse(_durationController.text.trim());
    final int averageHeartRate =
        int.tryParse(_heartRateController.text.trim()) ?? 0;
    final int averagePaceSeconds =
        int.tryParse(_paceController.text.trim()) ?? 0;
    final int plannedSets =
        int.tryParse(_plannedSetsController.text.trim()) ?? 0;
    final int completedSets =
        int.tryParse(_completedSetsController.text.trim()) ?? 0;
    final List<ExerciseExecutionRecord> exerciseRecords = [];
    if (actualDuration == null || actualDuration < 5 || actualDuration > 360) {
      setState(() {
        _errorMessage = '请输入 5 到 360 分钟之间的实际时长。';
      });
      return;
    }
    if (averageHeartRate < 0 || averageHeartRate > 260) {
      setState(() {
        _errorMessage = '平均心率需在 0 到 260 之间。';
      });
      return;
    }
    if (averagePaceSeconds < 0 || averagePaceSeconds > 3600) {
      setState(() {
        _errorMessage = '平均配速秒数需在 0 到 3600 之间。';
      });
      return;
    }
    if (plannedSets < 0 || plannedSets > 99) {
      setState(() {
        _errorMessage = '计划组数需在 0 到 99 之间。';
      });
      return;
    }
    if (completedSets < 0 || completedSets > plannedSets) {
      setState(() {
        _errorMessage = '完成组数不能超过计划组数。';
      });
      return;
    }
    for (final _ExerciseExecutionDraft draft in _exerciseDrafts) {
      final int completedSetCount =
          int.tryParse(draft.completedSetController.text.trim()) ?? 0;
      final double weightKg =
          double.tryParse(draft.weightController.text.trim()) ?? 0;
      if (completedSetCount < 0 || completedSetCount > 99) {
        setState(() {
          _errorMessage = '${draft.exerciseName}的完成组数需在 0 到 99 之间。';
        });
        return;
      }
      if (draft.plannedSetCount > 0 &&
          completedSetCount > draft.plannedSetCount) {
        setState(() {
          _errorMessage = '${draft.exerciseName}的完成组数不能超过计划组数。';
        });
        return;
      }
      if (weightKg < 0 || weightKg > 500) {
        setState(() {
          _errorMessage = '${draft.exerciseName}的工作重量需在 0 到 500 kg 之间。';
        });
        return;
      }
      exerciseRecords.add(
        ExerciseExecutionRecord(
          exerciseId: draft.exerciseId,
          exerciseName: draft.exerciseName,
          plannedSetCount: draft.plannedSetCount,
          completedSetCount: completedSetCount,
          repetitionsPerSet: draft.repetitionsPerSet,
          weightKg: weightKg,
        ),
      );
    }

    ref.read(trainingMvpProvider.notifier).saveWorkoutSessionReview(
          actualDurationMinutes: actualDuration,
          completionPercentage: _selectedCompletionPercentage,
          rpe: _selectedRpe,
          averageHeartRate: averageHeartRate,
          averagePaceSecondsPerKm: averagePaceSeconds,
          plannedSetCount: plannedSets,
          completedSetCount: completedSets,
          exerciseRecords: exerciseRecords,
          interruptionReason: _interruptionReasonController.text,
          userNote: _noteController.text,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '训练后复盘',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                widget.workout.title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>('workout-review-duration-field'),
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '实际时长（分钟）',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                key: const ValueKey<String>('workout-review-rpe-selector'),
                initialValue: _selectedRpe,
                decoration: const InputDecoration(labelText: '主观强度'),
                items: [
                  for (int value = 1; value <= 10; value += 1)
                    DropdownMenuItem<int>(
                      value: value,
                      child: Text('RPE $value'),
                    ),
                ],
                onChanged: (int? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedRpe = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              Text(
                '完成度',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final int percentage in const [100, 75, 50, 0])
                    ChoiceChip(
                      label: Text(_completionLabel(percentage)),
                      selected: _selectedCompletionPercentage == percentage,
                      onSelected: (_) {
                        setState(() {
                          _selectedCompletionPercentage = percentage;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>(
                  'workout-review-heart-rate-field',
                ),
                controller: _heartRateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '平均心率（可选）',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('workout-review-pace-field'),
                controller: _paceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '平均配速秒/公里（可选）',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>(
                  'workout-review-planned-sets-field',
                ),
                controller: _plannedSetsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '计划组数（可选）',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>(
                  'workout-review-completed-sets-field',
                ),
                controller: _completedSetsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '完成组数（可选）',
                ),
              ),
              const SizedBox(height: 12),
              if (_exerciseDrafts.isNotEmpty) ...[
                Text(
                  '实际动作记录',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                for (int index = 0;
                    index < _exerciseDrafts.length;
                    index += 1) ...[
                  _ExerciseExecutionFields(
                    index: index,
                    draft: _exerciseDrafts[index],
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              TextFormField(
                key: const ValueKey<String>(
                  'workout-review-interruption-reason-field',
                ),
                controller: _interruptionReasonController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '中断原因（可选）'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('workout-review-note-field'),
                controller: _noteController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '训练备注（可选）'),
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
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存训练反馈'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _completionLabel(int percentage) {
    return switch (percentage) {
      100 => '100% 完成',
      75 => '75% 完成',
      50 => '50% 完成',
      _ => '未完成',
    };
  }
}

class _ExerciseExecutionFields extends StatelessWidget {
  final int index;
  final _ExerciseExecutionDraft draft;

  const _ExerciseExecutionFields({
    required this.index,
    required this.draft,
  });

  @override
  Widget build(BuildContext context) {
    final String plannedLabel = draft.plannedSetCount > 0
        ? '计划 ${draft.plannedSetCount} 组${draft.repetitionsPerSet > 0 ? ' x ${draft.repetitionsPerSet} 次' : ''}'
        : '未从计划文本识别组数，可按实际填写。';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primaryLightest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              draft.exerciseName,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              plannedLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey<String>(
                      'workout-review-exercise-$index-completed-sets-field',
                    ),
                    controller: draft.completedSetController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '完成组数'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    key: ValueKey<String>(
                      'workout-review-exercise-$index-weight-field',
                    ),
                    controller: draft.weightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '工作重量 kg'),
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

class _PlayerStatusCard extends StatelessWidget {
  final TrainingMvpState state;
  final WorkoutPlayerStep step;

  const _PlayerStatusCard({
    required this.state,
    required this.step,
  });

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.play_circle_fill, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.activeWorkoutPlayerWorkout.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: state.workoutPlayerProgressLabel),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '当前步骤',
                  value: step.phase.label,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '倒计时',
                  value: state.workoutPlayerRemainingLabel,
                  color: state.workoutPlayerTimerRunning
                      ? AppColors.primary
                      : AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            state.workoutPlayerStatusMessage,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _CurrentStepCard extends StatelessWidget {
  final WorkoutPlayerStep step;
  final TrainingMvpState state;

  const _CurrentStepCard({
    required this.step,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final List<Exercise> linkedExercises = [];
    for (final String exerciseId in step.exerciseIds) {
      final Exercise? exercise = state.findExercise(exerciseId);
      if (exercise != null) {
        linkedExercises.add(exercise);
      }
    }

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fitness_center, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  step.title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (state.workoutPlayerDeloaded)
                const ToneBadge(label: '已降级', color: AppColors.warning),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '真实倒计时',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: state.workoutPlayerCountdownProgress,
            minHeight: 8,
            color: AppColors.primary,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 8),
          Text(
            '剩余 ${state.workoutPlayerRemainingLabel} · 预计 ${step.durationLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 14),
          _ActionMediaPreview(exercises: linkedExercises),
          const SizedBox(height: 14),
          for (final String cue in step.cues)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(cue)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          InfoRow(label: '组间休息倒计时', value: '${step.restSeconds} 秒'),
          InfoRow(label: '本步 TTS 文案', value: step.voiceCue),
        ],
      ),
    );
  }
}

class _ActionMediaPreview extends StatelessWidget {
  final List<Exercise> exercises;

  const _ActionMediaPreview({required this.exercises});

  @override
  Widget build(BuildContext context) {
    if (exercises.isEmpty) {
      return const _PlayerMediaFallback();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLightest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exercises.first.name,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ExerciseMedia(exercise: exercises.first, compact: true),
          if (exercises.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              '本步骤另有关联动作 ${exercises.length - 1} 个，详情页可逐个查看。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerMediaFallback extends StatelessWidget {
  const _PlayerMediaFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primaryLightest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.ondemand_video_outlined,
            color: AppColors.primary,
            size: 42,
          ),
          SizedBox(height: 8),
          Text('动作演示占位'),
          SizedBox(height: 4),
          Text('当前步骤未关联动作媒体'),
        ],
      ),
    );
  }
}

class _PlayerAssistCard extends ConsumerWidget {
  final TrainingMvpState state;

  const _PlayerAssistCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String latestCue = state.workoutPlayerVoiceQueue.isEmpty
        ? '暂无语音提示。开始计时或切换步骤后会生成。'
        : state.workoutPlayerVoiceQueue.first;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.record_voice_over, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'TTS 提示队列',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: state.workoutPlayerVoiceSummaryLabel),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.workoutPlayerVoiceStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text('最近提示：$latestCue'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '屏幕常亮意图',
                  value: state.workoutPlayerScreenAwakeSummaryLabel,
                  color: AppColors.warningDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '提示条数',
                  value: '${state.workoutPlayerVoiceQueue.length} 条',
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.workoutPlayerScreenAwakeStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(trainingMvpProvider.notifier)
                        .toggleWorkoutPlayerVoice();
                  },
                  icon: Icon(
                    state.workoutPlayerVoiceEnabled
                        ? Icons.volume_off
                        : Icons.volume_up,
                  ),
                  label: Text(
                    state.workoutPlayerVoiceEnabled ? '关闭语音' : '开启语音',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(trainingMvpProvider.notifier)
                        .toggleWorkoutPlayerScreenAwake();
                  },
                  icon: Icon(
                    state.workoutPlayerScreenAwakeRequested
                        ? Icons.phonelink_erase
                        : Icons.stay_current_portrait,
                  ),
                  label: Text(
                    state.workoutPlayerScreenAwakeRequested ? '取消常亮' : '请求常亮',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayerActionCard extends ConsumerWidget {
  final TrainingMvpState state;

  const _PlayerActionCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.workoutPlayerFinished) {
      final review = state.latestWorkoutSessionReview;
      return TrainFlowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本次跟练已完成',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text('执行记录已写入 workout_logs，可作为后续画像和训练调整信号。'),
            const SizedBox(height: 12),
            if (review != null) ...[
              Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '已保存训练反馈',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                review.sessionReviewSummary,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              if (review.interruptionReason != null) ...[
                const SizedBox(height: 4),
                Text(
                  '中断原因：${review.interruptionReason}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
              if (review.exerciseRecords.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final ExerciseExecutionRecord item
                    in review.exerciseRecords)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${item.exerciseName} · ${item.setSummary}'),
                  ),
              ],
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showWorkoutReviewSheet(
                  context: context,
                  workout: state.activeWorkoutPlayerWorkout,
                ),
                icon: const Icon(Icons.rate_review_outlined),
                label: Text(review == null ? '记录训练反馈' : '更新训练反馈'),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => context.go(AppRoutes.dashboard),
                icon: const Icon(Icons.check),
                label: const Text('回到今日训练'),
              ),
            ),
          ],
        ),
      );
    }

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '练中反馈',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    final TrainingMvpController controller =
                        ref.read(trainingMvpProvider.notifier);
                    if (state.workoutPlayerTimerRunning) {
                      controller.pauseWorkoutPlayerCountdown();
                    } else {
                      controller.startWorkoutPlayerCountdown();
                    }
                  },
                  icon: Icon(
                    state.workoutPlayerTimerRunning ? Icons.pause : Icons.timer,
                  ),
                  label: Text(
                    state.workoutPlayerTimerRunning ? '暂停计时' : '开始计时',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(trainingMvpProvider.notifier)
                        .resetWorkoutPlayerCountdown();
                  },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('重置计时'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    ref
                        .read(trainingMvpProvider.notifier)
                        .completeWorkoutPlayerStep();
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('完成'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(trainingMvpProvider.notifier)
                        .skipWorkoutPlayerStep();
                  },
                  icon: const Icon(Icons.skip_next),
                  label: const Text('跳过'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ref.read(trainingMvpProvider.notifier).deloadWorkoutPlayer();
              },
              icon: const Icon(Icons.trending_down),
              label: const Text('太累了'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerEventCard extends StatelessWidget {
  final List<String> events;

  const _PlayerEventCard({required this.events});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '执行记录',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (events.isEmpty)
            const Text('还没有步骤记录。')
          else
            for (final String event in events.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('· $event'),
              ),
        ],
      ),
    );
  }
}
