import 'workout_day.dart';
import 'exercise_training_profile.dart';

enum WorkoutPlayerPhase {
  foamRolling,
  dynamicStretch,
  activation,
  main,
  deload,
  cooldown,
}

extension WorkoutPlayerPhaseLabel on WorkoutPlayerPhase {
  String get label {
    switch (this) {
      case WorkoutPlayerPhase.foamRolling:
        return '泡沫轴放松';
      case WorkoutPlayerPhase.dynamicStretch:
        return '动态拉伸';
      case WorkoutPlayerPhase.activation:
        return '激活动作';
      case WorkoutPlayerPhase.main:
        return '正式训练';
      case WorkoutPlayerPhase.deload:
        return '降级训练';
      case WorkoutPlayerPhase.cooldown:
        return '训练后放松与反馈';
    }
  }
}

class WorkoutPlayerStep {
  final String id;
  final WorkoutPlayerPhase phase;
  final String title;
  final List<String> cues;
  final int estimatedSeconds;
  final int restSeconds;
  final String voiceCue;
  final List<String> exerciseIds;

  const WorkoutPlayerStep({
    required this.id,
    required this.phase,
    required this.title,
    required this.cues,
    required this.estimatedSeconds,
    required this.restSeconds,
    required this.voiceCue,
    required this.exerciseIds,
  });

  String get durationLabel {
    if (estimatedSeconds < 60) {
      return '$estimatedSeconds 秒';
    }
    final int minutes = estimatedSeconds ~/ 60;
    final int seconds = estimatedSeconds % 60;
    if (seconds == 0) {
      return '$minutes 分钟';
    }
    return '$minutes 分 $seconds 秒';
  }
}

List<WorkoutPlayerStep> buildWorkoutPlayerSteps(
  WorkoutDay workout, {
  required bool deloaded,
  bool matchDeclaredDuration = false,
}) {
  final int totalSeconds =
      workout.estimatedMinutes <= 0 ? 10 * 60 : workout.estimatedMinutes * 60;
  // 确认课程保留原处方的 5 分钟冷身，扣除准备与冷身共 21 分钟。
  // 旧计划默认沿用原计时；新调整另行审核能否容纳至少 8 分钟主训练。
  final int mainSeconds = _atLeast(
      totalSeconds - (matchDeclaredDuration ? 21 : 18) * 60, 8 * 60);
  final List<String> mainCues = deloaded
      ? const [
          '把剩余正式训练改为低强度版，不再追求配速或重量',
          '轻松步行或无痛灵活性练习 8-12 分钟',
          '如果疼痛或头晕上升，直接结束并记录原因',
        ]
      : workout.mainSets;

  return [
    _step(
      id: 'foam',
      phase: WorkoutPlayerPhase.foamRolling,
      cues: workout.foamRollingSteps,
      estimatedSeconds: 5 * 60,
      restSeconds: 20,
      exerciseIds: _exerciseIdsForPhase(
        workout,
        WorkoutPlayerPhase.foamRolling,
      ),
    ),
    _step(
      id: 'stretch',
      phase: WorkoutPlayerPhase.dynamicStretch,
      cues: workout.dynamicStretchSteps,
      estimatedSeconds: 6 * 60,
      restSeconds: 20,
      exerciseIds: _exerciseIdsForPhase(
        workout,
        WorkoutPlayerPhase.dynamicStretch,
      ),
    ),
    _step(
      id: 'activation',
      phase: WorkoutPlayerPhase.activation,
      cues: workout.activationSteps,
      estimatedSeconds: 5 * 60,
      restSeconds: 30,
      exerciseIds: _exerciseIdsForPhase(
        workout,
        WorkoutPlayerPhase.activation,
      ),
    ),
    _step(
      id: deloaded ? 'deload' : 'main',
      phase: deloaded ? WorkoutPlayerPhase.deload : WorkoutPlayerPhase.main,
      cues: mainCues,
      estimatedSeconds: deloaded ? 10 * 60 : mainSeconds,
      restSeconds: 45,
      exerciseIds: deloaded
          ? _safeDeloadExerciseIds(workout)
          : _exerciseIdsForPhase(workout, WorkoutPlayerPhase.main),
      restSecondsOverride: deloaded ? 30 : _mainRestSeconds(workout),
      voiceCueOverride: deloaded ? null : _mainVoiceCue(workout),
    ),
    _step(
      id: 'cooldown',
      phase: WorkoutPlayerPhase.cooldown,
      cues: workout.cooldownSteps,
      estimatedSeconds: (matchDeclaredDuration ? 5 : 4) * 60,
      restSeconds: 0,
      exerciseIds: _exerciseIdsForPhase(
        workout,
        WorkoutPlayerPhase.cooldown,
      ),
    ),
  ];
}

WorkoutPlayerStep _step({
  required String id,
  required WorkoutPlayerPhase phase,
  required List<String> cues,
  required int estimatedSeconds,
  required int restSeconds,
  required List<String> exerciseIds,
  int? restSecondsOverride,
  String? voiceCueOverride,
}) {
  final String title = phase.label;
  return WorkoutPlayerStep(
    id: id,
    phase: phase,
    title: title,
    cues: cues.isEmpty ? const ['今日无需安排，直接进入下一步'] : cues,
    estimatedSeconds: estimatedSeconds,
    restSeconds: restSecondsOverride ?? restSeconds,
    voiceCue: voiceCueOverride ??
        '开始$title。结束后休息 ${restSecondsOverride ?? restSeconds} 秒，再进入下一步。',
    exerciseIds: exerciseIds,
  );
}

int _mainRestSeconds(WorkoutDay workout) {
  int restSeconds = 45;
  for (final WorkoutExerciseLink link in workout.workoutExercises) {
    if ((link.module == WorkoutExerciseModule.mainTraining ||
            link.module == WorkoutExerciseModule.accessory) &&
        link.restSeconds > restSeconds) {
      restSeconds = link.restSeconds;
    }
  }
  return restSeconds;
}

String? _mainVoiceCue(WorkoutDay workout) {
  final List<WorkoutExerciseLink> links = workout.workoutExercises
      .where((WorkoutExerciseLink link) =>
          link.module == WorkoutExerciseModule.mainTraining ||
          link.module == WorkoutExerciseModule.accessory)
      .toList()
    ..sort(
      (WorkoutExerciseLink first, WorkoutExerciseLink second) =>
          first.sequence.compareTo(second.sequence),
    );
  if (links.isEmpty) return null;
  final WorkoutExerciseLink first = links.first;
  final List<String> cues = <String>[
    '开始正式训练',
    if (first.tempo != null) '动作节奏 ${first.tempo}',
    first.executionIntent.label,
    if (first.breathingCue != null) first.breathingCue!,
    '组间休息 ${_mainRestSeconds(workout)} 秒',
  ];
  return '${cues.join('。')}。';
}

List<String> _safeDeloadExerciseIds(WorkoutDay workout) {
  final List<String> safeIds = <String>[];
  for (final WorkoutExerciseLink link in workout.workoutExercises) {
    final ExerciseTrainingProfile profile =
        trainingProfileForExercise(link.exerciseId);
    final bool highDemand =
        profile.dimensions.contains(TrainingDimension.neural) ||
            profile.dimensions.contains(TrainingDimension.eccentric);
    if (!highDemand &&
        link.exerciseId.isNotEmpty &&
        !safeIds.contains(link.exerciseId)) {
      safeIds.add(link.exerciseId);
    }
  }
  return List<String>.unmodifiable(safeIds);
}

List<String> _exerciseIdsForPhase(
  WorkoutDay workout,
  WorkoutPlayerPhase phase,
) {
  final List<WorkoutExerciseModule> modules = switch (phase) {
    WorkoutPlayerPhase.foamRolling => const [WorkoutExerciseModule.foamRolling],
    WorkoutPlayerPhase.dynamicStretch => const [
        WorkoutExerciseModule.dynamicStretch,
        WorkoutExerciseModule.warmup,
        WorkoutExerciseModule.hipDrive,
      ],
    WorkoutPlayerPhase.activation => const [
        WorkoutExerciseModule.activation,
        WorkoutExerciseModule.calf,
      ],
    WorkoutPlayerPhase.main => const [
        WorkoutExerciseModule.mainTraining,
        WorkoutExerciseModule.accessory,
      ],
    WorkoutPlayerPhase.deload => const [],
    WorkoutPlayerPhase.cooldown => const [WorkoutExerciseModule.cooldown],
  };
  final List<WorkoutExerciseLink> links = [...workout.workoutExercises]..sort(
      (WorkoutExerciseLink first, WorkoutExerciseLink second) =>
          first.sequence.compareTo(second.sequence),
    );
  final List<String> exerciseIds = [];
  for (final WorkoutExerciseLink link in links) {
    if (modules.contains(link.module) &&
        link.exerciseId.isNotEmpty &&
        !exerciseIds.contains(link.exerciseId)) {
      exerciseIds.add(link.exerciseId);
    }
  }
  return List<String>.unmodifiable(exerciseIds);
}

int _atLeast(int value, int minimum) {
  if (value < minimum) {
    return minimum;
  }
  return value;
}
