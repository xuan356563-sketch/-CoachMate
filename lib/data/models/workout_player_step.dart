import 'workout_day.dart';

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
}) {
  final int totalSeconds =
      workout.estimatedMinutes <= 0 ? 10 * 60 : workout.estimatedMinutes * 60;
  final int mainSeconds = _atLeast(totalSeconds - 18 * 60, 8 * 60);
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
          ? const []
          : _exerciseIdsForPhase(workout, WorkoutPlayerPhase.main),
    ),
    _step(
      id: 'cooldown',
      phase: WorkoutPlayerPhase.cooldown,
      cues: workout.cooldownSteps,
      estimatedSeconds: 4 * 60,
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
}) {
  final String title = phase.label;
  return WorkoutPlayerStep(
    id: id,
    phase: phase,
    title: title,
    cues: cues.isEmpty ? const ['今日无需安排，直接进入下一步'] : cues,
    estimatedSeconds: estimatedSeconds,
    restSeconds: restSeconds,
    voiceCue: '开始$title。结束后休息 $restSeconds 秒，再进入下一步。',
    exerciseIds: exerciseIds,
  );
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
