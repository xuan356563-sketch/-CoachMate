import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/local/trainmate_structured_database_gateway.dart';
import '../../../data/models/exercise.dart';
import '../../../data/models/training_log.dart';
import '../../../data/models/workout_day.dart';
import '../../dashboard/training_mvp_controller.dart';
import '../../profile/application/health_sync_controller.dart';
import '../application/training_energy_suggestion_service.dart';
import '../application/training_record_save_request.dart';

Future<void> showTrainingRecordEditor({
  required BuildContext context,
  required WorkoutDay workout,
  TrainingRecordSource initialSource = TrainingRecordSource.planned,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => FractionallySizedBox(
      heightFactor: 0.96,
      child: TrainingRecordEditor(
        workout: workout,
        initialSource: initialSource,
      ),
    ),
  );
}

class TrainingRecordEditor extends ConsumerStatefulWidget {
  const TrainingRecordEditor({
    super.key,
    required this.workout,
    this.initialSource = TrainingRecordSource.planned,
  });

  final WorkoutDay workout;
  final TrainingRecordSource initialSource;

  @override
  ConsumerState<TrainingRecordEditor> createState() =>
      _TrainingRecordEditorState();
}

class _TrainingRecordEditorState extends ConsumerState<TrainingRecordEditor> {
  late TrainingRecordSource _source;
  late TrainingActivityType _activityType;
  late final TextEditingController _durationController;
  late final TextEditingController _energyController;
  late final TextEditingController _customActivityController;
  late final TextEditingController _heartRateController;
  late final TextEditingController _paceController;
  late final TextEditingController _plannedSetsController;
  late final TextEditingController _completedSetsController;
  late final TextEditingController _interruptionReasonController;
  late final TextEditingController _noteController;
  late List<_ExerciseRecordDraft> _exerciseDrafts;
  int _completionPercentage = 100;
  int _rpe = 6;
  String? _errorMessage;
  TrainingEnergySuggestion? _energySuggestion;
  TrainingEnergySource? _energySource;
  String? _deviceWorkoutId;
  bool _loadingEnergySuggestion = false;

  @override
  void initState() {
    super.initState();
    _source = widget.initialSource;
    _activityType = _activityForWorkout(widget.workout);
    _durationController = TextEditingController(
      text: widget.workout.estimatedMinutes.toString(),
    );
    _energyController = TextEditingController();
    _customActivityController = TextEditingController(
      text: _activityType == TrainingActivityType.custom
          ? widget.workout.title
          : '',
    );
    _heartRateController = TextEditingController();
    _paceController = TextEditingController();
    _plannedSetsController = TextEditingController();
    _completedSetsController = TextEditingController();
    _interruptionReasonController = TextEditingController();
    _noteController = TextEditingController();
    _exerciseDrafts = _buildWorkoutExerciseDrafts(widget.workout);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadEnergySuggestion());
  }

  @override
  void dispose() {
    _durationController.dispose();
    _energyController.dispose();
    _customActivityController.dispose();
    _heartRateController.dispose();
    _paceController.dispose();
    _plannedSetsController.dispose();
    _completedSetsController.dispose();
    _interruptionReasonController.dispose();
    _noteController.dispose();
    for (final _ExerciseRecordDraft draft in _exerciseDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  List<_ExerciseRecordDraft> _buildWorkoutExerciseDrafts(WorkoutDay workout) {
    final TrainingMvpState state = ref.read(trainingMvpProvider);
    final List<WorkoutExerciseLink> links = workout.workoutExercises
        .where(
          (WorkoutExerciseLink link) =>
              link.module == WorkoutExerciseModule.mainTraining ||
              link.module == WorkoutExerciseModule.accessory,
        )
        .toList(growable: false)
      ..sort(
        (WorkoutExerciseLink first, WorkoutExerciseLink second) =>
            first.sequence.compareTo(second.sequence),
      );
    if (links.isNotEmpty) {
      return <_ExerciseRecordDraft>[
        for (final WorkoutExerciseLink link in links)
          _ExerciseRecordDraft(
            exerciseId: link.exerciseId,
            exerciseName:
                state.findExercise(link.exerciseId)?.name ?? link.exerciseId,
            plannedSetCount: link.plannedSetCount,
            repetitionsPerSet: link.repetitionsPerSet,
          ),
      ];
    }
    return <_ExerciseRecordDraft>[
      for (final String description in workout.mainSets)
        _draftFromDescription(description),
    ];
  }

  _ExerciseRecordDraft _draftFromDescription(String description) {
    final RegExpMatch? match = RegExp(
      r'^(.+?)\s+(\d+)\s*(?:组|轮)\s*(?:x|×)\s*(\d+)',
    ).firstMatch(description.trim());
    return _ExerciseRecordDraft(
      exerciseId: null,
      exerciseName: match?.group(1)?.trim() ?? description.trim(),
      plannedSetCount: int.tryParse(match?.group(2) ?? '') ?? 1,
      repetitionsPerSet: int.tryParse(match?.group(3) ?? '') ?? 0,
    );
  }

  Future<void> _loadEnergySuggestion() async {
    final TrainMateStructuredDatabaseGateway? database =
        ref.read(healthSyncStructuredDatabaseGatewayProvider);
    final int? duration = int.tryParse(_durationController.text.trim());
    if (database == null || duration == null || duration <= 0) {
      if (mounted) {
        setState(() {
          _energySuggestion = null;
          _loadingEnergySuggestion = false;
        });
      }
      return;
    }
    setState(() => _loadingEnergySuggestion = true);
    final DateTime now = DateTime.now();
    final DateTime localStart = DateTime(now.year, now.month, now.day);
    try {
      final List<Map<String, Object?>> rows =
          await database.listWorkoutFactRows(
        athleteProfileId: ref.read(trainingMvpProvider).profile.id,
        startedAtOrAfter: localStart.toUtc().toIso8601String(),
        startedBefore:
            localStart.add(const Duration(days: 1)).toUtc().toIso8601String(),
      );
      final TrainingEnergySuggestion? suggestion =
          const TrainingEnergySuggestionService().select(
        rows: rows,
        activityType: _activityType,
        localDate: localStart,
        expectedStart: now,
        expectedDurationMinutes: duration,
      );
      if (!mounted) return;
      setState(() {
        _energySuggestion = suggestion;
        _loadingEnergySuggestion = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _energySuggestion = null;
        _loadingEnergySuggestion = false;
      });
    }
  }

  void _selectSource(TrainingRecordSource source) {
    if (_source == source) return;
    for (final _ExerciseRecordDraft draft in _exerciseDrafts) {
      draft.dispose();
    }
    setState(() {
      _source = source;
      if (source == TrainingRecordSource.planned) {
        _activityType = _activityForWorkout(widget.workout);
        _durationController.text = widget.workout.estimatedMinutes.toString();
        _exerciseDrafts = _buildWorkoutExerciseDrafts(widget.workout);
      } else {
        _activityType = TrainingActivityType.running;
        _exerciseDrafts = <_ExerciseRecordDraft>[];
      }
      _energySuggestion = null;
      _energyController.clear();
      _energySource = null;
      _deviceWorkoutId = null;
      _errorMessage = null;
    });
    _loadEnergySuggestion();
  }

  Future<void> _addExercise() async {
    final TrainingMvpState state = ref.read(trainingMvpProvider);
    final Exercise? selected = await showModalBottomSheet<Exercise>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (BuildContext context) => FractionallySizedBox(
        heightFactor: 0.72,
        child: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '从动作库添加',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: state.exercises.length,
                itemBuilder: (BuildContext context, int index) {
                  final Exercise exercise = state.exercises[index];
                  return ListTile(
                    title: Text(exercise.name),
                    subtitle: Text(exercise.category.label),
                    onTap: () => Navigator.of(context).pop(exercise),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _exerciseDrafts.add(
        _ExerciseRecordDraft(
          exerciseId: selected.id,
          exerciseName: selected.name,
          plannedSetCount: 1,
          repetitionsPerSet: 0,
        ),
      );
    });
  }

  void _save() {
    final int? duration = int.tryParse(_durationController.text.trim());
    final double? energy = _energyController.text.trim().isEmpty
        ? null
        : double.tryParse(_energyController.text.trim());
    final int heartRate = int.tryParse(_heartRateController.text.trim()) ?? 0;
    final int pace = int.tryParse(_paceController.text.trim()) ?? 0;
    final int aggregatePlannedSets =
        int.tryParse(_plannedSetsController.text.trim()) ?? 0;
    final int aggregateCompletedSets =
        int.tryParse(_completedSetsController.text.trim()) ?? 0;
    if (duration == null) {
      setState(() => _errorMessage = '请输入有效的实际时长。');
      return;
    }
    final List<ExerciseExecutionRecord> exerciseRecords =
        _exerciseDrafts.map((_ExerciseRecordDraft draft) {
      final List<StrengthSetExecutionRecord> sets = draft.setDrafts
          .where((_StrengthSetRecordDraft set) => set.completed)
          .map(
            (_StrengthSetRecordDraft set) => StrengthSetExecutionRecord(
              setIndex: set.setIndex,
              repetitions:
                  int.tryParse(set.repetitionsController.text.trim()) ?? 0,
              weightKg: double.tryParse(set.weightController.text.trim()) ?? 0,
              rpe: set.rpeController.text.trim().isEmpty
                  ? null
                  : double.tryParse(set.rpeController.text.trim()),
              durationSeconds: set.durationController.text.trim().isEmpty
                  ? null
                  : int.tryParse(set.durationController.text.trim()),
            ),
          )
          .toList(growable: false);
      final int legacyCompleted =
          int.tryParse(draft.completedSetController.text.trim()) ?? 0;
      final double legacyWeight =
          double.tryParse(draft.weightController.text.trim()) ?? 0;
      return ExerciseExecutionRecord(
        exerciseId: draft.exerciseId,
        exerciseName: draft.exerciseName,
        plannedSetCount: draft.plannedSetCount,
        completedSetCount: sets.isEmpty ? legacyCompleted : sets.length,
        repetitionsPerSet: draft.repetitionsPerSet,
        weightKg: sets.isEmpty
            ? legacyWeight
            : sets
                .map((StrengthSetExecutionRecord set) => set.weightKg)
                .fold<double>(0, (double a, double b) => a > b ? a : b),
        sets: sets,
      );
    }).toList(growable: false);
    final DateTime now = DateTime.now();
    final TrainingRecordSaveRequest request = TrainingRecordSaveRequest(
      source: _source,
      workoutDayId: _source == TrainingRecordSource.planned
          ? widget.workout.id
          : 'extra-${_activityType.jsonValue}',
      planItemId: _source == TrainingRecordSource.planned &&
              ref
                      .read(trainingMvpProvider)
                      .scheduledTodayWorkout
                      ?.workoutDayId ==
                  widget.workout.id
          ? ref.read(trainingMvpProvider).scheduledTodayWorkout?.id
          : null,
      date: now,
      activityType: _activityType,
      customActivityName: _customActivityController.text,
      actualDurationMinutes: duration,
      completionPercentage: _completionPercentage,
      rpe: _rpe,
      energyKcal: energy,
      energySource:
          energy == null ? null : _energySource ?? TrainingEnergySource.manual,
      deviceWorkoutId: energy == null ? null : _deviceWorkoutId,
      averageHeartRate: heartRate,
      averagePaceSecondsPerKm: pace,
      plannedSetCount: aggregatePlannedSets,
      completedSetCount: aggregateCompletedSets,
      exerciseRecords: exerciseRecords,
      interruptionReason: _interruptionReasonController.text,
      userNote:
          _noteController.text.trim().isEmpty && _completionPercentage == 100
              ? '按计划完成'
              : _noteController.text,
    );
    try {
      ref.read(trainingMvpProvider.notifier).saveTrainingRecord(request);
      Navigator.of(context).pop();
    } on FormatException catch (error) {
      setState(() => _errorMessage = error.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final bool showRunningFields = <TrainingActivityType>{
      TrainingActivityType.running,
      TrainingActivityType.fastWalking,
      TrainingActivityType.hiking,
    }.contains(_activityType);
    return Material(
      key: const ValueKey<String>('training-record-editor'),
      color: AppColors.background,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: <Widget>[
            Container(
              color: AppColors.cardBackground,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Text(
                          '${now.month}月${now.day}日训练',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const Text(
                          '训练后复盘',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: _save, child: const Text('保存')),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SourceSelector(
                      selected: _source,
                      onSelected: _selectSource,
                    ),
                    const SizedBox(height: 18),
                    const _EditorSectionTitle(
                      title: '运动项目',
                      trailing: '球类 / 有氧，可多选或自定义',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: TrainingActivityType.values
                          .map(
                            (TrainingActivityType item) => FilterChip(
                              label:
                                  Text('${_activityEmoji(item)} ${item.label}'),
                              selected: _activityType == item,
                              onSelected: (_) {
                                setState(() {
                                  _activityType = item;
                                  _energySuggestion = null;
                                  _energyController.clear();
                                  _energySource = null;
                                  _deviceWorkoutId = null;
                                });
                                _loadEnergySuggestion();
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
                    if (_activityType ==
                        TrainingActivityType.custom) ...<Widget>[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _customActivityController,
                        decoration: const InputDecoration(
                          labelText: '自定义运动名称',
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const _EditorSectionTitle(
                      title: '训练数据',
                      trailing: '设备建议必须确认后才保存',
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                        final double width = constraints.maxWidth >= 360
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: <Widget>[
                            SizedBox(
                              width: width,
                              child: _MetricEditorCard(
                                label: '训练时长',
                                unit: '分钟',
                                child: TextField(
                                  key: const ValueKey<String>(
                                    'workout-review-duration-field',
                                  ),
                                  controller: _durationController,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => _loadEnergySuggestion(),
                                  decoration:
                                      const InputDecoration(hintText: '65'),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _MetricEditorCard(
                                label: '消耗热量',
                                unit: '千卡',
                                child: TextField(
                                  key: const ValueKey<String>(
                                    'training-record-energy-field',
                                  ),
                                  controller: _energyController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  onChanged: (_) {
                                    _energySource = TrainingEnergySource.manual;
                                    _deviceWorkoutId = null;
                                  },
                                  decoration:
                                      const InputDecoration(hintText: '可选'),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    if (_loadingEnergySuggestion)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    else if (_energySuggestion != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                '设备训练建议：${_energySuggestion!.energyKcal.toStringAsFixed(0)} 千卡',
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _energyController.text = _energySuggestion!
                                      .energyKcal
                                      .toStringAsFixed(0);
                                  _energySource =
                                      TrainingEnergySource.healthKitConfirmed;
                                  _deviceWorkoutId =
                                      _energySuggestion!.workoutId;
                                });
                              },
                              child: const Text('采用'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text('完成度', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: <int>[25, 50, 75, 100]
                          .map(
                            (int value) => ChoiceChip(
                              label: Text('$value% 完成'),
                              selected: _completionPercentage == value,
                              onSelected: (_) =>
                                  setState(() => _completionPercentage = value),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key:
                          const ValueKey<String>('workout-review-rpe-selector'),
                      initialValue: _rpe,
                      decoration: const InputDecoration(labelText: '训练强度 RPE'),
                      items: <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
                          .map(
                            (int value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('RPE $value'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (int? value) {
                        if (value != null) setState(() => _rpe = value);
                      },
                    ),
                    if (showRunningFields) ...<Widget>[
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              key: const ValueKey<String>(
                                'workout-review-heart-rate-field',
                              ),
                              controller: _heartRateController,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: '平均心率'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              key: const ValueKey<String>(
                                'workout-review-pace-field',
                              ),
                              controller: _paceController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '平均配速（秒/km）',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            key: const ValueKey<String>(
                              'workout-review-planned-sets-field',
                            ),
                            controller: _plannedSetsController,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '计划总组数'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: const ValueKey<String>(
                              'workout-review-completed-sets-field',
                            ),
                            controller: _completedSetsController,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '完成总组数'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _EditorSectionTitle(
                      title: '动作记录',
                      trailing: '共 ${_exerciseDrafts.length} 个动作',
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '实际动作记录',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    for (int index = 0;
                        index < _exerciseDrafts.length;
                        index += 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ExerciseRecordCard(
                          index: index,
                          draft: _exerciseDrafts[index],
                          onRemove: () {
                            final _ExerciseRecordDraft removed =
                                _exerciseDrafts.removeAt(index);
                            removed.dispose();
                            setState(() {});
                          },
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _addExercise,
                      icon: const Icon(Icons.add),
                      label: const Text('从动作库添加'),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      key: const ValueKey<String>(
                        'workout-review-interruption-reason-field',
                      ),
                      controller: _interruptionReasonController,
                      decoration: const InputDecoration(labelText: '中断原因（可选）'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey<String>('workout-review-note-field'),
                      controller: _noteController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '训练备注（可选）'),
                    ),
                    if (_errorMessage != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check),
                        label: const Text('保存训练反馈'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceSelector extends StatelessWidget {
  const _SourceSelector({required this.selected, required this.onSelected});

  final TrainingRecordSource selected;
  final ValueChanged<TrainingRecordSource> onSelected;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TrainingRecordSource>(
      segments: const <ButtonSegment<TrainingRecordSource>>[
        ButtonSegment<TrainingRecordSource>(
          value: TrainingRecordSource.planned,
          label: Text('今日计划'),
          icon: Icon(Icons.event_available_outlined),
        ),
        ButtonSegment<TrainingRecordSource>(
          value: TrainingRecordSource.extra,
          label: Text('额外训练'),
          icon: Icon(Icons.add_circle_outline),
        ),
      ],
      selected: <TrainingRecordSource>{selected},
      onSelectionChanged: (Set<TrainingRecordSource> values) {
        onSelected(values.single);
      },
    );
  }
}

class _EditorSectionTitle extends StatelessWidget {
  const _EditorSectionTitle({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        Text(
          trailing,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _MetricEditorCard extends StatelessWidget {
  const _MetricEditorCard({
    required this.label,
    required this.unit,
    required this.child,
  });

  final String label;
  final String unit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(child: child),
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 6),
                child: Text(unit),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExerciseRecordCard extends StatefulWidget {
  const _ExerciseRecordCard({
    required this.index,
    required this.draft,
    required this.onRemove,
  });

  final int index;
  final _ExerciseRecordDraft draft;
  final VoidCallback onRemove;

  @override
  State<_ExerciseRecordCard> createState() => _ExerciseRecordCardState();
}

class _ExerciseRecordCardState extends State<_ExerciseRecordCard> {
  @override
  Widget build(BuildContext context) {
    final _ExerciseRecordDraft draft = widget.draft;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  draft.exerciseName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: '删除动作',
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            '计划 ${draft.plannedSetCount} 组 x ${draft.repetitionsPerSet} 次',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Text('组数'),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: ValueKey<String>('exercise-${widget.index}-sets-minus'),
                onPressed: draft.setDrafts.length <= 1
                    ? null
                    : () => setState(draft.removeSet),
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${draft.setDrafts.length}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton.filledTonal(
                key: ValueKey<String>('exercise-${widget.index}-sets-plus'),
                onPressed: draft.setDrafts.length >= 8
                    ? null
                    : () => setState(draft.addSet),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: ValueKey<String>(
                    'workout-review-exercise-${widget.index}-completed-sets-field',
                  ),
                  controller: draft.completedSetController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '完成组数'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: ValueKey<String>(
                    'workout-review-exercise-${widget.index}-weight-field',
                  ),
                  controller: draft.weightController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '统一重量 kg'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('逐组详情'),
              children: <Widget>[
                for (final _StrengthSetRecordDraft set in draft.setDrafts)
                  _StrengthSetEditor(set: set),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StrengthSetEditor extends StatefulWidget {
  const _StrengthSetEditor({required this.set});

  final _StrengthSetRecordDraft set;

  @override
  State<_StrengthSetEditor> createState() => _StrengthSetEditorState();
}

class _StrengthSetEditorState extends State<_StrengthSetEditor> {
  @override
  Widget build(BuildContext context) {
    final _StrengthSetRecordDraft set = widget.set;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: <Widget>[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('第 ${set.setIndex} 组已完成'),
            value: set.completed,
            onChanged: (bool? value) =>
                setState(() => set.completed = value == true),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: set.repetitionsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '次数'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: set.weightController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '重量 kg'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: set.rpeController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'RPE'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: set.durationController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '用时 秒'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExerciseRecordDraft {
  _ExerciseRecordDraft({
    required this.exerciseId,
    required this.exerciseName,
    required int plannedSetCount,
    required this.repetitionsPerSet,
  })  : plannedSetCount = plannedSetCount.clamp(0, 99).toInt(),
        completedSetController = TextEditingController(
          text: plannedSetCount > 0 ? plannedSetCount.toString() : '',
        ),
        weightController = TextEditingController(),
        setDrafts = List<_StrengthSetRecordDraft>.generate(
          plannedSetCount.clamp(1, 8).toInt(),
          (int index) => _StrengthSetRecordDraft(
            setIndex: index + 1,
            repetitions: repetitionsPerSet,
          ),
        );

  final String? exerciseId;
  final String exerciseName;
  final int plannedSetCount;
  final int repetitionsPerSet;
  final TextEditingController completedSetController;
  final TextEditingController weightController;
  final List<_StrengthSetRecordDraft> setDrafts;

  void addSet() {
    setDrafts.add(
      _StrengthSetRecordDraft(
        setIndex: setDrafts.length + 1,
        repetitions: repetitionsPerSet,
      ),
    );
  }

  void removeSet() {
    if (setDrafts.length <= 1) return;
    setDrafts.removeLast().dispose();
  }

  void dispose() {
    completedSetController.dispose();
    weightController.dispose();
    for (final _StrengthSetRecordDraft set in setDrafts) {
      set.dispose();
    }
  }
}

class _StrengthSetRecordDraft {
  _StrengthSetRecordDraft({required this.setIndex, required int repetitions})
      : repetitionsController = TextEditingController(
          text: repetitions > 0 ? repetitions.toString() : '',
        ),
        weightController = TextEditingController(),
        rpeController = TextEditingController(),
        durationController = TextEditingController();

  final int setIndex;
  bool completed = false;
  final TextEditingController repetitionsController;
  final TextEditingController weightController;
  final TextEditingController rpeController;
  final TextEditingController durationController;

  void dispose() {
    repetitionsController.dispose();
    weightController.dispose();
    rpeController.dispose();
    durationController.dispose();
  }
}

TrainingActivityType _activityForWorkout(WorkoutDay workout) {
  return switch (workout.trainingType) {
    TrainingType.easyRun ||
    TrainingType.tempoRun ||
    TrainingType.intervalRun ||
    TrainingType.longRun =>
      TrainingActivityType.running,
    TrainingType.strength => TrainingActivityType.strength,
    TrainingType.hyrox => TrainingActivityType.hiit,
    TrainingType.mobility ||
    TrainingType.rehab ||
    TrainingType.rest =>
      TrainingActivityType.stretching,
    TrainingType.crossTraining => TrainingActivityType.custom,
  };
}

String _activityEmoji(TrainingActivityType activityType) {
  return switch (activityType) {
    TrainingActivityType.strength => '🏋️',
    TrainingActivityType.running => '🏃',
    TrainingActivityType.fastWalking => '🚶',
    TrainingActivityType.hiking => '🥾',
    TrainingActivityType.cycling => '🚴',
    TrainingActivityType.swimming => '🏊',
    TrainingActivityType.rowing => '🚣',
    TrainingActivityType.elliptical => '⭕',
    TrainingActivityType.stairClimbing => '🪜',
    TrainingActivityType.hiit => '⚡',
    TrainingActivityType.jumpRope => '🪢',
    TrainingActivityType.boxing => '🥊',
    TrainingActivityType.basketball => '🏀',
    TrainingActivityType.badminton => '🏸',
    TrainingActivityType.football => '⚽',
    TrainingActivityType.tennis => '🎾',
    TrainingActivityType.tableTennis => '🏓',
    TrainingActivityType.climbing => '🧗',
    TrainingActivityType.skiing => '⛷️',
    TrainingActivityType.dance => '💃',
    TrainingActivityType.yoga => '🧘',
    TrainingActivityType.pilates => '🤸',
    TrainingActivityType.stretching => '🙆',
    TrainingActivityType.custom => '＋',
  };
}
