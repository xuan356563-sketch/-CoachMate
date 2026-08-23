import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/exercise_media.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainmate_action_mappings.dart';
import '../../core/widgets/trainmate_showcase_widgets.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/exercise.dart';
import '../../data/models/exercise_training_profile.dart';
import '../../data/models/pain_log.dart';
import '../../data/models/training_log.dart';
import '../../data/models/workout_day.dart';
import '../../data/models/workout_player_step.dart';
import '../dashboard/training_mvp_controller.dart';
import '../pet/application/pet_controller.dart';
import '../pet/presentation/widgets/pet_training_receipt.dart';
import '../training_log/presentation/training_record_editor.dart';

class WorkoutPlayerPage extends ConsumerWidget {
  const WorkoutPlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final WorkoutPlayerStep step = state.activeWorkoutPlayerStep;
    final TrainMateAction characterAction = trainMateActionForWorkoutPhase(
      step.phase,
      state.activeWorkoutPlayerWorkout.trainingType,
    );

    return TrainMateImmersivePage(
      title: '跟练执行',
      subtitle: '逐步引导、真实倒计时、TTS 提示队列和练中一键降级。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.dashboard,
      ),
      artwork: TrainMateActionCharacter(
        action: characterAction,
        backgroundColor: AppColors.primary,
      ),
      children: [
        _PlayerStatusCard(
          state: state,
          step: step,
          characterAction: characterAction,
        ),
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
  return showTrainingRecordEditor(
    context: context,
    workout: workout,
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
  final List<_StrengthSetDraft> setDrafts;
  final bool requestsLandingQuality;
  LandingQuality? landingQuality;

  _ExerciseExecutionDraft({
    required this.exerciseId,
    required this.exerciseName,
    required this.plannedSetCount,
    required this.repetitionsPerSet,
    this.requestsLandingQuality = false,
  })  : completedSetController = TextEditingController(),
        weightController = TextEditingController(),
        setDrafts = List<_StrengthSetDraft>.generate(
          plannedSetCount.clamp(1, 8).toInt(),
          (int index) => _StrengthSetDraft(
            setIndex: index + 1,
            plannedRepetitions: repetitionsPerSet,
          ),
        );

  void dispose() {
    completedSetController.dispose();
    weightController.dispose();
    for (final _StrengthSetDraft set in setDrafts) {
      set.dispose();
    }
  }
}

class _StrengthSetDraft {
  final int setIndex;
  bool completed = false;
  final TextEditingController repetitionsController;
  final TextEditingController weightController;
  final TextEditingController rpeController;
  final TextEditingController durationController;

  _StrengthSetDraft({
    required this.setIndex,
    required int plannedRepetitions,
  })  : repetitionsController = TextEditingController(
          text: plannedRepetitions > 0 ? plannedRepetitions.toString() : '',
        ),
        weightController = TextEditingController(),
        rpeController = TextEditingController(),
        durationController = TextEditingController();

  void dispose() {
    repetitionsController.dispose();
    weightController.dispose();
    rpeController.dispose();
    durationController.dispose();
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
  SessionFeel? _selectedSessionFeel;
  bool _abortedByUser = false;
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
        requestsLandingQuality: false,
      );
    }
    return _ExerciseExecutionDraft(
      exerciseId: null,
      exerciseName: match.group(1)!.trim(),
      plannedSetCount: int.tryParse(match.group(2)!) ?? 0,
      repetitionsPerSet: int.tryParse(match.group(3)!) ?? 0,
      requestsLandingQuality: false,
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
        _buildStructuredExerciseDraft(link),
    ];
  }

  _ExerciseExecutionDraft _buildStructuredExerciseDraft(
    WorkoutExerciseLink link,
  ) {
    final Exercise? exercise =
        ref.read(trainingMvpProvider).findExercise(link.exerciseId);
    final List<LegTrainingElement> legElements =
        exercise?.trainingStructureProfile.legElements ??
            const <LegTrainingElement>[];
    return _ExerciseExecutionDraft(
      exerciseId: link.exerciseId,
      exerciseName: exercise?.name ?? link.exerciseId,
      plannedSetCount: link.plannedSetCount,
      repetitionsPerSet: link.repetitionsPerSet,
      requestsLandingQuality:
          legElements.contains(LegTrainingElement.eccentricLanding) ||
              legElements.contains(LegTrainingElement.power),
    );
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
      final int legacyCompletedSetCount =
          int.tryParse(draft.completedSetController.text.trim()) ?? 0;
      final double legacyWeightKg =
          double.tryParse(draft.weightController.text.trim()) ?? 0;
      if (legacyCompletedSetCount < 0 || legacyCompletedSetCount > 99) {
        setState(() {
          _errorMessage = '${draft.exerciseName}的完成组数需在 0 到 99 之间。';
        });
        return;
      }
      if (draft.plannedSetCount > 0 &&
          legacyCompletedSetCount > draft.plannedSetCount) {
        setState(() {
          _errorMessage = '${draft.exerciseName}的完成组数不能超过计划组数。';
        });
        return;
      }
      if (legacyWeightKg < 0 || legacyWeightKg > 500) {
        setState(() {
          _errorMessage = '${draft.exerciseName}的工作重量需在 0 到 500 kg 之间。';
        });
        return;
      }
      final List<StrengthSetExecutionRecord> actualSets =
          <StrengthSetExecutionRecord>[];
      for (final _StrengthSetDraft set in draft.setDrafts) {
        if (!set.completed) continue;
        final int repetitions =
            int.tryParse(set.repetitionsController.text.trim()) ?? 0;
        final double weightKg =
            double.tryParse(set.weightController.text.trim()) ?? 0;
        final double? rpe = set.rpeController.text.trim().isEmpty
            ? null
            : double.tryParse(set.rpeController.text.trim());
        final int? durationSeconds = set.durationController.text.trim().isEmpty
            ? null
            : int.tryParse(set.durationController.text.trim());
        if (repetitions < 0 || repetitions > 999) {
          setState(() {
            _errorMessage =
                '${draft.exerciseName}第 ${set.setIndex} 组次数需在 0 到 999 之间。';
          });
          return;
        }
        if (weightKg < 0 || weightKg > 500) {
          setState(() {
            _errorMessage =
                '${draft.exerciseName}第 ${set.setIndex} 组重量需在 0 到 500 kg 之间。';
          });
          return;
        }
        if (rpe != null && (rpe < 1 || rpe > 10)) {
          setState(() {
            _errorMessage =
                '${draft.exerciseName}第 ${set.setIndex} 组 RPE 需在 1 到 10 之间。';
          });
          return;
        }
        if (durationSeconds != null &&
            (durationSeconds < 1 || durationSeconds > 3600)) {
          setState(() {
            _errorMessage =
                '${draft.exerciseName}第 ${set.setIndex} 组用时需在 1 到 3600 秒之间。';
          });
          return;
        }
        actualSets.add(
          StrengthSetExecutionRecord(
            setIndex: actualSets.length + 1,
            repetitions: repetitions,
            weightKg: weightKg,
            rpe: rpe,
            durationSeconds: durationSeconds,
          ),
        );
      }
      final int completedSetCount =
          actualSets.isEmpty ? legacyCompletedSetCount : actualSets.length;
      final double weightKg = actualSets.isEmpty
          ? legacyWeightKg
          : actualSets
              .map((StrengthSetExecutionRecord set) => set.weightKg)
              .reduce((double first, double second) =>
                  first > second ? first : second);
      final Set<int> actualRepetitions = actualSets
          .map((StrengthSetExecutionRecord set) => set.repetitions)
          .toSet();
      exerciseRecords.add(
        ExerciseExecutionRecord(
          exerciseId: draft.exerciseId,
          exerciseName: draft.exerciseName,
          plannedSetCount: draft.plannedSetCount,
          completedSetCount: completedSetCount,
          repetitionsPerSet:
              actualRepetitions.length == 1 ? actualRepetitions.single : 0,
          weightKg: weightKg,
          sets: List<StrengthSetExecutionRecord>.unmodifiable(actualSets),
          landingQuality: draft.landingQuality,
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
          abortedByUser: _abortedByUser,
          sessionFeel: _selectedSessionFeel,
        );
    if (exerciseRecords.any(
      (ExerciseExecutionRecord record) =>
          record.landingQuality == LandingQuality.pain,
    )) {
      ref.read(trainingMvpProvider.notifier).savePainLog(
            bodyPart: '落地动作相关部位',
            painLevel: 4,
            timing: PainTiming.duringTraining,
            note: '训练后落地质量反馈，需在疼痛记录中补充具体部位。',
          );
    }
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
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                widget.workout.title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
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
                '训练感受（可跳过）',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                key: const ValueKey<String>('workout-review-session-feel'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final SessionFeel feel in SessionFeel.values)
                    ChoiceChip(
                      label: Text(feel.label),
                      selected: _selectedSessionFeel == feel,
                      onSelected: (bool selected) {
                        setState(() {
                          _selectedSessionFeel = selected ? feel : null;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '完成度',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
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
                          if (percentage == 100) {
                            _abortedByUser = false;
                          }
                        });
                      },
                    ),
                ],
              ),
              CheckboxListTile(
                key: const ValueKey<String>('workout-review-aborted-toggle'),
                contentPadding: EdgeInsets.zero,
                value: _abortedByUser,
                onChanged: _selectedCompletionPercentage >= 100
                    ? null
                    : (bool? value) {
                        setState(() {
                          _abortedByUser = value ?? false;
                        });
                      },
                title: const Text('我主动中止本次训练'),
                subtitle: const Text('仅如实记录安全决策；无安全依据时不会获得额外成长分。'),
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
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                for (int index = 0;
                    index < _exerciseDrafts.length;
                    index += 1) ...[
                  _ExerciseExecutionFields(
                    index: index,
                    draft: _exerciseDrafts[index],
                    onChanged: () => setState(() {}),
                    onAddSet: () {
                      setState(() {
                        final _ExerciseExecutionDraft draft =
                            _exerciseDrafts[index];
                        draft.setDrafts.add(
                          _StrengthSetDraft(
                            setIndex: draft.setDrafts.length + 1,
                            plannedRepetitions: draft.repetitionsPerSet,
                          ),
                        );
                      });
                    },
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
  final VoidCallback onChanged;
  final VoidCallback onAddSet;

  const _ExerciseExecutionFields({
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onAddSet,
  });

  @override
  Widget build(BuildContext context) {
    final String plannedLabel = draft.plannedSetCount > 0
        ? '计划 ${draft.plannedSetCount} 组${draft.repetitionsPerSet > 0 ? ' x ${draft.repetitionsPerSet} 次' : ''}'
        : '未从计划文本识别组数，可按实际填写。';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TrainFlowTokens.darkTrainingRaised,
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
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              plannedLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
                  ),
            ),
            if (draft.requestsLandingQuality) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<LandingQuality>(
                key: ValueKey<String>(
                  'workout-review-exercise-$index-landing-quality',
                ),
                initialValue: draft.landingQuality,
                decoration: const InputDecoration(
                  labelText: '落地质量（本地记录）',
                  helperText: '选择疼痛后将进入本地疼痛保护流程。',
                ),
                items: <DropdownMenuItem<LandingQuality>>[
                  for (final LandingQuality quality in LandingQuality.values)
                    DropdownMenuItem<LandingQuality>(
                      value: quality,
                      child: Text(quality.label),
                    ),
                ],
                onChanged: (LandingQuality? value) {
                  draft.landingQuality = value;
                  onChanged();
                },
              ),
            ],
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
                    decoration: const InputDecoration(
                      labelText: '动作级完成组数（兼容）',
                    ),
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
                    decoration: const InputDecoration(
                      labelText: '动作级重量 kg（兼容）',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '真实逐组记录',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '只有勾选完成的组会写入 strength_sets；每组可记录不同重量、次数、RPE 和用时。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
                  ),
            ),
            const SizedBox(height: 8),
            for (int setIndex = 0;
                setIndex < draft.setDrafts.length;
                setIndex += 1)
              _StrengthSetExecutionFields(
                exerciseIndex: index,
                setDraft: draft.setDrafts[setIndex],
                onChanged: onChanged,
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: draft.setDrafts.length >= 12 ? null : onAddSet,
                icon: const Icon(Icons.add),
                label: const Text('添加一组'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StrengthSetExecutionFields extends StatelessWidget {
  final int exerciseIndex;
  final _StrengthSetDraft setDraft;
  final VoidCallback onChanged;

  const _StrengthSetExecutionFields({
    required this.exerciseIndex,
    required this.setDraft,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final int setIndex = setDraft.setIndex - 1;
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            key: ValueKey<String>(
              'workout-review-exercise-$exerciseIndex-set-$setIndex-completed',
            ),
            contentPadding: EdgeInsets.zero,
            value: setDraft.completed,
            onChanged: (bool? value) {
              setDraft.completed = value ?? false;
              onChanged();
            },
            title: Text('第 ${setDraft.setIndex} 组'),
            subtitle: const Text('勾选后按真实完成情况填写'),
          ),
        ),
        if (setDraft.completed)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 100,
                child: TextFormField(
                  key: ValueKey<String>(
                    'workout-review-exercise-$exerciseIndex-set-$setIndex-reps',
                  ),
                  controller: setDraft.repetitionsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '次数'),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextFormField(
                  key: ValueKey<String>(
                    'workout-review-exercise-$exerciseIndex-set-$setIndex-weight',
                  ),
                  controller: setDraft.weightController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '重量 kg'),
                ),
              ),
              SizedBox(
                width: 90,
                child: TextFormField(
                  key: ValueKey<String>(
                    'workout-review-exercise-$exerciseIndex-set-$setIndex-rpe',
                  ),
                  controller: setDraft.rpeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'RPE'),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextFormField(
                  key: ValueKey<String>(
                    'workout-review-exercise-$exerciseIndex-set-$setIndex-duration',
                  ),
                  controller: setDraft.durationController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '用时 秒'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _PlayerStatusCard extends StatelessWidget {
  final TrainingMvpState state;
  final WorkoutPlayerStep step;
  final TrainMateAction characterAction;

  const _PlayerStatusCard({
    required this.state,
    required this.step,
    required this.characterAction,
  });

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      cornerCharacterAction: characterAction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.play_circle_fill, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.activeWorkoutPlayerWorkout.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
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
                  color: TrainFlowTokens.darkTrainingMuted,
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
              const Icon(Icons.fitness_center, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  step.title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
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
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: state.workoutPlayerCountdownProgress,
            minHeight: 8,
            color: TrainFlowTokens.accent,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 8),
          Text(
            '剩余 ${state.workoutPlayerRemainingLabel} · 预计 ${step.durationLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
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
                      color: TrainFlowTokens.accent, size: 18),
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
        color: TrainFlowTokens.darkTrainingRaised,
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
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ExerciseMedia(exercise: exercises.first, compact: true),
          if (exercises.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              '本步骤另有关联动作 ${exercises.length - 1} 个，详情页可逐个查看。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
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
        color: TrainFlowTokens.darkTrainingRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.animation_outlined,
            color: TrainFlowTokens.accent,
            size: 42,
          ),
          SizedBox(height: 8),
          Text('动作动图占位'),
          SizedBox(height: 4),
          Text('当前步骤未关联动作动图'),
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
              const Icon(Icons.record_voice_over, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'TTS 提示队列',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: state.workoutPlayerVoiceSummaryLabel),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.workoutPlayerVoiceStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
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
                  color: TrainFlowTokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.workoutPlayerScreenAwakeStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
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
      final PetState? petState = ref.watch(petControllerProvider).value;
      final bool hasValidTraining = review != null &&
          review.isSessionRecord &&
          !review.abortedByUser &&
          review.normalizedCompletionPercentage >= 50;
      return TrainFlowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本次跟练已完成',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
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
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                review.sessionReviewSummary,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
              if (review.interruptionReason != null) ...[
                const SizedBox(height: 4),
                Text(
                  '中断原因：${review.interruptionReason}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TrainFlowTokens.darkTrainingMuted,
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
            PetTrainingReceiptCard(
              settlement: petState?.pendingSettlement,
              hasValidTraining: hasValidTraining,
              onAcknowledged: () => ref
                  .read(petControllerProvider.notifier)
                  .acknowledgeSettlement(),
            ),
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
                ?.copyWith(fontWeight: FontWeight.w600),
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
                ?.copyWith(fontWeight: FontWeight.w600),
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
