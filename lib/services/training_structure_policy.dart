import '../data/models/exercise.dart';
import '../data/models/exercise_training_profile.dart';
import '../data/models/user_profile.dart';
import '../data/models/workout_day.dart';
import '../data/seed/seed_exercises.dart';

/// 只在本地执行的训练结构策略，不读取健康原文，也不触发云端调用。
class TrainingStructurePolicy {
  const TrainingStructurePolicy();

  WorkoutDay apply({
    required WorkoutDay workout,
    required String phaseCode,
    required UserProfile profile,
  }) {
    final DimensionFocus focus = focusFor(
      phaseCode: phaseCode,
      decisionType: workout.decisionType,
      trainingType: workout.trainingType,
    );
    final Map<String, Exercise> exercisesById = <String, Exercise>{
      for (final Exercise exercise in seedExercises) exercise.id: exercise,
    };
    List<WorkoutExerciseLink> decorated = workout.workoutExercises
        .map(
          (WorkoutExerciseLink link) => _decorateLink(
            link,
            exercise: exercisesById[link.exerciseId],
            profile: profile,
          ),
        )
        .toList(growable: false);
    if (_isLegStructureSession(workout, decorated)) {
      decorated = _buildLegStructure(
        workout: workout,
        links: decorated,
        phaseCode: phaseCode,
        profile: profile,
      );
    }

    return workout.copyWith(
      dimensionFocus: focus,
      structurePolicyVersion: trainingStructurePolicyVersion,
      workoutExercises: decorated,
    );
  }

  bool _isLegStructureSession(
    WorkoutDay workout,
    List<WorkoutExerciseLink> links,
  ) {
    if (workout.decisionType == TrainingDecisionType.recovery ||
        workout.decisionType == TrainingDecisionType.rest) {
      return false;
    }
    if (workout.trainingType == TrainingType.hyrox) return true;
    if (workout.trainingType != TrainingType.strength) return false;
    if (links.isEmpty) return true;
    return links.any(
      (WorkoutExerciseLink link) =>
          trainingProfileForExercise(link.exerciseId).legElements.isNotEmpty,
    );
  }

  List<WorkoutExerciseLink> _buildLegStructure({
    required WorkoutDay workout,
    required List<WorkoutExerciseLink> links,
    required String phaseCode,
    required UserProfile profile,
  }) {
    final List<WorkoutExerciseLink> ordered = links.toList()
      ..sort(
        (WorkoutExerciseLink first, WorkoutExerciseLink second) =>
            first.sequence.compareTo(second.sequence),
      );
    final List<WorkoutExerciseLink> preparation = ordered
        .where((WorkoutExerciseLink link) =>
            _isPreparation(link.module) && !_isCalfStrength(link))
        .toList();
    final List<WorkoutExerciseLink> main = ordered
        .where((WorkoutExerciseLink link) =>
            link.module == WorkoutExerciseModule.mainTraining &&
            !_isCalfStrength(link))
        .toList();
    final List<WorkoutExerciseLink> structuralLead = <WorkoutExerciseLink>[];
    final List<WorkoutExerciseLink> accessory = ordered
        .where((WorkoutExerciseLink link) =>
            link.module == WorkoutExerciseModule.accessory &&
            !_isCalfStrength(link))
        .toList();
    final List<WorkoutExerciseLink> calfFinish =
        ordered.where(_isCalfStrength).toList();
    final List<WorkoutExerciseLink> cooldown = ordered
        .where((WorkoutExerciseLink link) =>
            link.module == WorkoutExerciseModule.cooldown)
        .toList();
    final Set<String> exerciseIds =
        ordered.map((WorkoutExerciseLink link) => link.exerciseId).toSet();

    void addIfMissing(
        List<WorkoutExerciseLink> target, WorkoutExerciseLink link) {
      if (exerciseIds.add(link.exerciseId)) target.add(link);
    }

    addIfMissing(
      preparation,
      _link(
        workout: workout,
        suffix: 'short-foot',
        exerciseId: 'exercise-short-foot',
        module: WorkoutExerciseModule.activation,
        sets: 2,
        repetitions: 6,
        intensity: '每次保持 5 秒，脚趾放松',
        restSeconds: 20,
      ),
    );

    final bool specific = phaseCode == 'specific';
    if (specific) {
      final bool beginner =
          profile.trainingExperienceLevel == TrainingExperienceLevel.beginner;
      addIfMissing(
        structuralLead,
        _link(
          workout: workout,
          suffix: beginner ? 'fast-squat' : 'box-jump',
          exerciseId:
              beginner ? 'exercise-bodyweight-squat' : 'exercise-box-jump',
          module: WorkoutExerciseModule.mainTraining,
          sets: beginner ? 3 : 4,
          repetitions: beginner ? 6 : 3,
          intensity: beginner ? '快速站起但双脚不离地' : '落地安静，稳定后再开始下一次',
          restSeconds: beginner ? 60 : 90,
          intent: beginner
              ? ExecutionIntent.fastConcentric
              : ExecutionIntent.explosive,
        ),
      );
    } else if (phaseCode != 'deload' && phaseCode != 'taper') {
      final int landingSets = phaseCode == 'baseline' ? 3 : 1;
      addIfMissing(
        structuralLead,
        _link(
          workout: workout,
          suffix: 'drop-landing',
          exerciseId: 'exercise-drop-landing',
          module: WorkoutExerciseModule.mainTraining,
          sets: landingSets,
          repetitions: 4,
          intensity: '低台阶，落地稳定保持 2 秒',
          restSeconds: 60,
        ),
      );
    }

    if (phaseCode == 'build') {
      addIfMissing(
        main,
        _link(
          workout: workout,
          suffix: 'nordic',
          exerciseId: 'exercise-nordic-curl-eccentric',
          module: WorkoutExerciseModule.mainTraining,
          sets: 2,
          repetitions: 4,
          intensity: '只做可控下放，不追求幅度',
          restSeconds: 90,
          tempo: '5-0-1-0',
        ),
      );
    }

    addIfMissing(
      accessory,
      _link(
        workout: workout,
        suffix: 'single-leg-rdl',
        exerciseId: 'exercise-single-leg-rdl',
        module: WorkoutExerciseModule.accessory,
        sets: 3,
        repetitions: 8,
        intensity: '每侧控制完成，骨盆保持稳定',
        restSeconds: 60,
        tempo: '3-0-1-0',
      ),
    );
    addIfMissing(
      calfFinish,
      _link(
        workout: workout,
        suffix: 'single-leg-calf',
        exerciseId: 'exercise-single-leg-calf-raise',
        module: WorkoutExerciseModule.accessory,
        sets: 2,
        repetitions: 12,
        intensity: '顶点停顿 1 秒，缓慢下降',
        restSeconds: 45,
        tempo: '2-1-3-0',
      ),
    );

    final List<WorkoutExerciseLink> result = <WorkoutExerciseLink>[
      ...preparation,
      ...structuralLead,
      ...main,
      ...accessory,
      ...calfFinish,
      ...cooldown,
    ];
    return List<WorkoutExerciseLink>.unmodifiable(<WorkoutExerciseLink>[
      for (int index = 0; index < result.length; index += 1)
        result[index].copyWith(sequence: index + 1),
    ]);
  }

  bool _isPreparation(WorkoutExerciseModule module) => switch (module) {
        WorkoutExerciseModule.foamRolling ||
        WorkoutExerciseModule.dynamicStretch ||
        WorkoutExerciseModule.activation ||
        WorkoutExerciseModule.warmup ||
        WorkoutExerciseModule.hipDrive ||
        WorkoutExerciseModule.calf =>
          true,
        WorkoutExerciseModule.mainTraining ||
        WorkoutExerciseModule.accessory ||
        WorkoutExerciseModule.cooldown =>
          false,
      };

  bool _isCalfStrength(WorkoutExerciseLink link) {
    final ExerciseTrainingProfile profile =
        trainingProfileForExercise(link.exerciseId);
    return link.module == WorkoutExerciseModule.calf ||
        (profile.legElements.contains(LegTrainingElement.footAnkle) &&
            profile.dimensions.contains(TrainingDimension.strength) &&
            link.module != WorkoutExerciseModule.activation);
  }

  WorkoutExerciseLink _link({
    required WorkoutDay workout,
    required String suffix,
    required String exerciseId,
    required WorkoutExerciseModule module,
    required int sets,
    required int repetitions,
    required String intensity,
    required int restSeconds,
    String? tempo,
    ExecutionIntent intent = ExecutionIntent.controlled,
  }) {
    final Exercise? exercise = seedExercises.cast<Exercise?>().firstWhere(
          (Exercise? item) => item?.id == exerciseId,
          orElse: () => null,
        );
    return WorkoutExerciseLink(
      id: '${workout.id}-structure-$suffix',
      exerciseId: exerciseId,
      sequence: 99,
      module: module,
      plannedSetCount: sets,
      repetitionsPerSet: repetitions,
      plannedWeightOrIntensity: intensity,
      restSeconds: restSeconds,
      tempo: tempo,
      executionIntent: intent,
      breathingCue: exercise?.breathingCue,
    );
  }

  DimensionFocus focusFor({
    required String phaseCode,
    required TrainingDecisionType decisionType,
    required TrainingType trainingType,
  }) {
    if (trainingType == TrainingType.rest) {
      return const DimensionFocus();
    }
    if (decisionType == TrainingDecisionType.recovery ||
        trainingType == TrainingType.mobility ||
        trainingType == TrainingType.rehab ||
        phaseCode == 'post_race_recovery') {
      return const DimensionFocus(
        primary: <TrainingDimension>[
          TrainingDimension.stability,
          TrainingDimension.breathing,
        ],
      );
    }

    final List<TrainingDimension> primary = switch (phaseCode) {
      'baseline' => const <TrainingDimension>[
          TrainingDimension.stability,
          TrainingDimension.breathing,
        ],
      'build' => const <TrainingDimension>[
          TrainingDimension.strength,
          TrainingDimension.eccentric,
        ],
      'specific' => const <TrainingDimension>[
          TrainingDimension.strength,
          TrainingDimension.neural,
        ],
      'deload' || 'taper' || 'race_week' => const <TrainingDimension>[
          TrainingDimension.stability,
          TrainingDimension.breathing,
        ],
      'post_race_recovery' => const <TrainingDimension>[
          TrainingDimension.stability,
          TrainingDimension.breathing,
        ],
      _ => const <TrainingDimension>[
          TrainingDimension.stability,
          TrainingDimension.breathing,
        ],
    };
    final List<TrainingDimension> touch = TrainingDimension.values
        .where((TrainingDimension item) => !primary.contains(item))
        .toList(growable: false);
    return DimensionFocus(primary: primary, touch: touch);
  }

  WorkoutExerciseLink _decorateLink(
    WorkoutExerciseLink link, {
    required Exercise? exercise,
    required UserProfile profile,
  }) {
    if (exercise == null) return link;
    final ExerciseTrainingProfile training = exercise.trainingStructureProfile;
    String exerciseId = link.exerciseId;
    ExecutionIntent intent = training.defaultIntent;
    if (training.airborne &&
        profile.trainingExperienceLevel == TrainingExperienceLevel.beginner) {
      exerciseId = 'exercise-drop-landing';
      intent = ExecutionIntent.controlled;
    }
    final bool eccentric =
        training.dimensions.contains(TrainingDimension.eccentric);
    final bool explosive = intent == ExecutionIntent.explosive;
    return link.copyWith(
      exerciseId: exerciseId,
      tempo: link.tempo ?? (eccentric ? '3-0-1-0' : null),
      executionIntent: intent,
      breathingCue: link.breathingCue ?? exercise.breathingCue,
      restSeconds: explosive && link.restSeconds < 90 ? 90 : link.restSeconds,
    );
  }
}
