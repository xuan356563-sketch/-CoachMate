import '../data/models/race.dart';
import '../core/config/training_structure_config.dart';
import '../data/models/plan_generation_preferences.dart';
import '../data/models/training_plan.dart';
import '../data/models/user_profile.dart';
import '../data/models/workout_day.dart';
import '../data/seed/seed_training_plans.dart';
import '../data/seed/seed_exercises.dart';
import 'abc_strength_cycle_compiler.dart';
import 'exercise_substitution_service.dart';
import 'training_structure_policy.dart';

enum TrainingCyclePhase {
  baseline,
  build,
  specific,
  deload,
  taper,
  raceWeek,
  postRaceRecovery,
}

extension TrainingCyclePhaseText on TrainingCyclePhase {
  String get jsonValue => switch (this) {
        TrainingCyclePhase.baseline => 'baseline',
        TrainingCyclePhase.build => 'build',
        TrainingCyclePhase.specific => 'specific',
        TrainingCyclePhase.deload => 'deload',
        TrainingCyclePhase.taper => 'taper',
        TrainingCyclePhase.raceWeek => 'race_week',
        TrainingCyclePhase.postRaceRecovery => 'post_race_recovery',
      };

  String get label => switch (this) {
        TrainingCyclePhase.baseline => '基线周',
        TrainingCyclePhase.build => '提升周',
        TrainingCyclePhase.specific => '专项周',
        TrainingCyclePhase.deload => '减量周',
        TrainingCyclePhase.taper => '赛前减量',
        TrainingCyclePhase.raceWeek => '比赛周',
        TrainingCyclePhase.postRaceRecovery => '赛后恢复',
      };

  String get focus => switch (this) {
        TrainingCyclePhase.baseline => '建立可稳定完成、可恢复的训练基线。',
        TrainingCyclePhase.build => '只增加一个训练变量，逐步提高耐受。',
        TrainingCyclePhase.specific => '让关键课更贴近主目标和比赛需求。',
        TrainingCyclePhase.deload => '降低总量并巩固动作质量，不补课。',
        TrainingCyclePhase.taper => '减少训练总量，保留少量状态唤醒。',
        TrainingCyclePhase.raceWeek => '比赛执行优先，训练只用于保持感觉。',
        TrainingCyclePhase.postRaceRecovery => '赛后恢复优先，记录疼痛和疲劳变化。',
      };
}

TrainingCyclePhase trainingCyclePhaseFromJson(String? value) => switch (value) {
      'build' => TrainingCyclePhase.build,
      'specific' => TrainingCyclePhase.specific,
      'deload' => TrainingCyclePhase.deload,
      'taper' => TrainingCyclePhase.taper,
      'race_week' => TrainingCyclePhase.raceWeek,
      'post_race_recovery' => TrainingCyclePhase.postRaceRecovery,
      _ => TrainingCyclePhase.baseline,
    };

class GeneratedPlanWeek {
  const GeneratedPlanWeek({
    required this.weekIndex,
    required this.startsOn,
    required this.phase,
    required this.focus,
    required this.workouts,
  });

  final int weekIndex;
  final DateTime startsOn;
  final TrainingCyclePhase phase;
  final String focus;
  final List<WorkoutDay> workouts;
}

class FourWeekPlanGeneration {
  const FourWeekPlanGeneration({
    required this.plan,
    required this.weeks,
    required this.primarySport,
    required this.secondarySport,
    required this.appliedRace,
  });

  final TrainingPlan plan;
  final List<GeneratedPlanWeek> weeks;
  final MainSport primarySport;
  final MainSport? secondarySport;
  final RacePlan? appliedRace;
}

class FourWeekPlanGenerator {
  FourWeekPlanGenerator({
    AbcStrengthCycleCompiler? abcStrengthCycleCompiler,
    TrainingStructurePolicy? trainingStructurePolicy,
    bool? structureEnabled,
  })  : _abcStrengthCycleCompiler =
            abcStrengthCycleCompiler ?? AbcStrengthCycleCompiler(),
        _trainingStructurePolicy =
            trainingStructurePolicy ?? const TrainingStructurePolicy(),
        _structureEnabled = structureEnabled ?? TrainingStructureConfig.enabled;

  final AbcStrengthCycleCompiler _abcStrengthCycleCompiler;
  final TrainingStructurePolicy _trainingStructurePolicy;
  final bool _structureEnabled;

  FourWeekPlanGeneration generate({
    required UserProfile profile,
    required DateTime startsOn,
    RacePlan? race,
    PlanGenerationPreferences? preferences,
  }) {
    final DateTime planStart = _dateOnly(startsOn);
    final MainSport primarySport = profile.mainSports.isEmpty
        ? MainSport.generalFitness
        : profile.mainSports.first;
    final MainSport? secondarySport =
        profile.mainSports.length > 1 && profile.mainSports[1] != primarySport
            ? profile.mainSports[1]
            : null;
    final RacePlan? appliedRace =
        race != null && _raceMatches(race, primarySport, secondarySport)
            ? race
            : null;
    final int weeklyTrainingDays = preferences == null
        ? profile.weeklyTrainingDays.clamp(1, 7)
        : preferences.weeklySessions.length.clamp(1, 6);
    final String planId = _planId(
      profile: profile,
      primarySport: primarySport,
      secondarySport: secondarySport,
      startsOn: planStart,
      race: appliedRace,
      generationId: preferences?.generationId,
    );
    final List<GeneratedPlanWeek> weeks = <GeneratedPlanWeek>[];
    final List<WorkoutDay> allWorkouts = <WorkoutDay>[];

    for (int weekIndex = 1; weekIndex <= 4; weekIndex += 1) {
      final DateTime weekStart =
          planStart.add(Duration(days: (weekIndex - 1) * 7));
      final TrainingCyclePhase phase = appliedRace == null
          ? _defaultPhase(weekIndex)
          : _racePhase(appliedRace.raceDate, weekStart);
      final List<_WorkoutTemplate> templates = _selectTemplates(
        primarySport: primarySport,
        secondarySport: secondarySport,
        trainingDays: weeklyTrainingDays,
        preferences: preferences,
        equipmentAccessType: profile.equipmentAccessType,
      );
      final List<WorkoutDay> weekWorkouts = <WorkoutDay>[];
      final List<int> calendarDays = preferences == null
          ? <int>[
              for (int index = 1; index <= weeklyTrainingDays; index += 1)
                index,
            ]
          : _calendarDays(weeklyTrainingDays);
      for (int sessionIndex = 0;
          sessionIndex < weeklyTrainingDays;
          sessionIndex += 1) {
        final int dayIndex = calendarDays[sessionIndex];
        final _WorkoutTemplate template = templates[sessionIndex];
        final WorkoutDay compiledWorkout = _buildWorkout(
          planId: planId,
          weekIndex: weekIndex,
          dayIndex: dayIndex,
          phase: phase,
          template: template,
          profile: profile,
          appliedRace: appliedRace,
          skillCompiled: preferences != null,
          progressionMode: preferences?.progressionMode,
        );
        final WorkoutDay workout = _structureEnabled
            ? _trainingStructurePolicy.apply(
                workout: compiledWorkout,
                phaseCode: phase.jsonValue,
                profile: profile,
              )
            : compiledWorkout;
        weekWorkouts.add(workout);
        allWorkouts.add(workout);
      }
      weeks.add(
        GeneratedPlanWeek(
          weekIndex: weekIndex,
          startsOn: weekStart,
          phase: phase,
          focus: phase.focus,
          workouts: List<WorkoutDay>.unmodifiable(weekWorkouts),
        ),
      );
    }

    final String secondaryLabel =
        secondarySport == null ? '' : '，兼顾${secondarySport.label}';
    final String raceLabel =
        appliedRace == null ? '' : '，并按「${appliedRace.name}」倒计时自动切换阶段';
    final TrainingPlan plan = TrainingPlan(
      id: planId,
      title: '${_planTitle(primarySport)}$secondaryLabel',
      description: preferences == null
          ? '根据当前档案生成的滚动 4 周计划$raceLabel。每周阶段和训练量均可追溯。'
          : '根据结构化 AI 处方由本地规则编译的 4 周计划$raceLabel。'
              '动作、负荷与安全边界均由 TrainMate 决定。',
      sportType: primarySport,
      level: preferences == null ? '个性化基础' : '个性化 Skill 编译',
      durationWeeks: 4,
      goal: profile.trainingGoal.trim().isEmpty
          ? '建立稳定、可恢复的训练习惯'
          : profile.trainingGoal.trim(),
      weeklyStructure:
          '每周 $weeklyTrainingDays 练；主目标为${primarySport.label}$secondaryLabel，不因次目标额外增加训练天数。',
      workoutDays: List<WorkoutDay>.unmodifiable(allWorkouts),
      evidenceSources: planEvidenceSources,
      knowledgeCitations: preferences?.knowledgeCitations ?? const [],
      createdAt: planStart,
      updatedAt: planStart,
    );
    return FourWeekPlanGeneration(
      plan: plan,
      weeks: List<GeneratedPlanWeek>.unmodifiable(weeks),
      primarySport: primarySport,
      secondarySport: secondarySport,
      appliedRace: appliedRace,
    );
  }

  TrainingCyclePhase _defaultPhase(int weekIndex) => switch (weekIndex) {
        1 => TrainingCyclePhase.baseline,
        2 => TrainingCyclePhase.build,
        3 => TrainingCyclePhase.specific,
        _ => TrainingCyclePhase.deload,
      };

  TrainingCyclePhase _racePhase(DateTime raceDate, DateTime weekStart) {
    final int daysUntilRace =
        _dateOnly(raceDate).difference(_dateOnly(weekStart)).inDays;
    if (daysUntilRace < 0) {
      return TrainingCyclePhase.postRaceRecovery;
    }
    if (daysUntilRace <= 7) {
      return TrainingCyclePhase.raceWeek;
    }
    if (daysUntilRace <= 21) {
      return TrainingCyclePhase.taper;
    }
    if (daysUntilRace <= 49) {
      return TrainingCyclePhase.specific;
    }
    if (daysUntilRace <= 84) {
      return TrainingCyclePhase.build;
    }
    return TrainingCyclePhase.baseline;
  }

  WorkoutDay _buildWorkout({
    required String planId,
    required int weekIndex,
    required int dayIndex,
    required TrainingCyclePhase phase,
    required _WorkoutTemplate template,
    required UserProfile profile,
    required RacePlan? appliedRace,
    required bool skillCompiled,
    required PlanProgressionMode? progressionMode,
  }) {
    final int availableMinutes = profile.dailyAvailableMinutes.clamp(15, 180);
    final int baseMinutes = template.baseMinutes.clamp(15, availableMinutes);
    final int estimatedMinutes = (baseMinutes *
            _volumeFactor(
              phase,
              progressionMode: progressionMode,
              abcStrengthCycle: template.abcStrengthSession != null,
            ))
        .round()
        .clamp(15, skillCompiled ? availableMinutes : 180);
    final List<String> mainSets = template.abcStrengthSession == null
        ? _phaseMainSets(template.mainSets, phase)
        : List<String>.from(template.mainSets);
    final List<String> accessoryWork = template.abcStrengthSession == null
        ? _accessoryFor(template, phase)
        : template.abcStrengthSession!.accessoryExercises
            .map(
              (AbcStrengthExerciseTemplate exercise) =>
                  '${exercise.label}：按本周处方完成',
            )
            .toList(growable: false);
    final TrainingDecisionType decisionType = _decisionType(phase, template);
    final String raceNote =
        appliedRace == null ? '' : ' 当前计划已关联 ${appliedRace.name}，比赛安全规则优先。';
    final WorkoutDay workout = WorkoutDay(
      id: '$planId-w$weekIndex-d$dayIndex',
      planId: planId,
      weekIndex: weekIndex,
      dayIndex: dayIndex,
      title: '${phase.label} · ${template.title}',
      trainingType: template.trainingType,
      decisionType: decisionType,
      estimatedMinutes: estimatedMinutes,
      intensity: _intensityFor(
        phase,
        template,
        experienceLevel: profile.trainingExperienceLevel,
        skillCompiled: skillCompiled,
      ),
      foamRollingSteps: const <String>['训练前对主要肌群轻柔放松 3-5 分钟'],
      dynamicStretchSteps: _dynamicWarmup(template.trainingType),
      activationSteps: _activation(template.trainingType),
      warmupSteps: const <String>['从低强度开始 5-8 分钟', '确认动作范围内无明显疼痛'],
      mainSets: mainSets,
      accessoryWork: accessoryWork,
      cooldownSteps: const <String>['低强度整理 5 分钟', '记录完成度、RPE 与疼痛变化'],
      coachNotes:
          '${phase.label}：${phase.focus} 本次目标是${template.purpose}。$raceNote',
      evidenceSources: planEvidenceSources,
      workoutExercises: skillCompiled
          ? _workoutExerciseLinks(
              workoutId: '$planId-w$weekIndex-d$dayIndex',
              template: template,
              weekIndex: weekIndex,
              progressionMode:
                  progressionMode ?? PlanProgressionMode.conservative,
              mainSetCount: mainSets.length,
              accessoryCount: accessoryWork.length,
            )
          : const <WorkoutExerciseLink>[],
    );
    if (skillCompiled &&
        (profile.equipmentAccessType == EquipmentAccessType.none ||
            profile.equipmentAccessType == EquipmentAccessType.basicHome)) {
      return ExerciseSubstitutionService()
          .applyNoEquipment(workout: workout, exercises: seedExercises)
          .workout;
    }
    return workout;
  }

  List<_WorkoutTemplate> _selectTemplates({
    required MainSport primarySport,
    required MainSport? secondarySport,
    required int trainingDays,
    required PlanGenerationPreferences? preferences,
    required EquipmentAccessType equipmentAccessType,
  }) {
    if (preferences != null) {
      final List<_WorkoutTemplate> templates = _preferenceTemplates(
        preferences.weeklySessions.take(trainingDays).toList(),
      );
      if (primarySport == MainSport.strength &&
          preferences.usesAbcStrengthCycle &&
          (equipmentAccessType == EquipmentAccessType.gym ||
              equipmentAccessType == EquipmentAccessType.mixed)) {
        return _applyAbcStrengthCycle(templates);
      }
      return templates;
    }
    final List<_WorkoutTemplate> source = _templatesFor(primarySport);
    final List<_WorkoutTemplate> selected = <_WorkoutTemplate>[
      for (int index = 0; index < trainingDays; index += 1)
        source[index % source.length],
    ];
    if (secondarySport != null && selected.length >= 2) {
      selected[selected.length - 1] = _secondaryTemplate(secondarySport);
    }
    return selected;
  }

  List<_WorkoutTemplate> _applyAbcStrengthCycle(
    List<_WorkoutTemplate> templates,
  ) {
    final int strengthSessionCount = templates
        .where(
          (_WorkoutTemplate item) => item.trainingType == TrainingType.strength,
        )
        .length;
    final List<AbcStrengthSessionTemplate> sessions =
        _abcStrengthCycleCompiler.sessionsFor(
      strengthSessionCount: strengthSessionCount,
    );
    int cursor = 0;
    return <_WorkoutTemplate>[
      for (final _WorkoutTemplate template in templates)
        if (template.trainingType == TrainingType.strength)
          template.copyWith(
            title: sessions[cursor].title,
            purpose: sessions[cursor].purpose,
            mainSets: sessions[cursor]
                .mainExercises
                .map(
                  (AbcStrengthExerciseTemplate exercise) =>
                      '${exercise.label}：按本周处方完成',
                )
                .toList(growable: false),
            abcStrengthSession: sessions[cursor++],
          )
        else
          template,
    ];
  }

  List<_WorkoutTemplate> _preferenceTemplates(
    List<PlanSessionPreference> preferences,
  ) {
    final List<PlanSessionPreference> ordered =
        List<PlanSessionPreference>.from(preferences);
    final List<PlanSessionPreference> hard = ordered
        .where(
          (PlanSessionPreference item) =>
              item.intensityBand == PlanIntensityBand.challenging,
        )
        .take(2)
        .toList();
    final List<PlanSessionPreference> others = ordered
        .where(
          (PlanSessionPreference item) =>
              item.intensityBand != PlanIntensityBand.challenging,
        )
        .toList();
    if (hard.isNotEmpty) {
      final List<PlanSessionPreference?> slots =
          List<PlanSessionPreference?>.filled(ordered.length, null);
      slots[0] = hard.first;
      if (hard.length > 1) {
        final List<int> days = _calendarDays(ordered.length);
        int secondHardSlot = days.indexWhere((int day) => day >= 4);
        if (secondHardSlot <= 0) secondHardSlot = ordered.length - 1;
        slots[secondHardSlot] = hard[1];
      }
      int cursor = 0;
      for (int index = 0; index < slots.length; index += 1) {
        if (slots[index] == null && cursor < others.length) {
          slots[index] = others[cursor];
          cursor += 1;
        }
      }
      ordered
        ..clear()
        ..addAll(slots.whereType<PlanSessionPreference>());
    }
    return ordered.map(_templateForPreference).toList(growable: false);
  }

  List<int> _calendarDays(int sessionCount) => switch (sessionCount) {
        1 => const <int>[1],
        2 => const <int>[1, 4],
        3 => const <int>[1, 3, 5],
        4 => const <int>[1, 3, 5, 7],
        5 => const <int>[1, 2, 4, 5, 7],
        _ => const <int>[1, 2, 3, 5, 6, 7],
      };

  _WorkoutTemplate _templateForPreference(PlanSessionPreference preference) {
    final Iterable<WorkoutDay> catalog =
        seedTrainingPlans.expand((TrainingPlan plan) => plan.workoutDays);
    WorkoutDay? source;
    for (final WorkoutDay workout in catalog) {
      if (workout.trainingType == preference.trainingType) {
        source = workout;
        break;
      }
    }
    source ??= catalog.firstWhere(
      (WorkoutDay workout) => switch (preference.trainingType) {
        TrainingType.easyRun ||
        TrainingType.tempoRun ||
        TrainingType.intervalRun ||
        TrainingType.longRun =>
          workout.trainingType == TrainingType.easyRun,
        TrainingType.strength => workout.trainingType == TrainingType.strength,
        TrainingType.hyrox => workout.trainingType == TrainingType.hyrox,
        _ => workout.trainingType == TrainingType.mobility,
      },
    );
    return _WorkoutTemplate(
      title: preference.trainingType.label,
      trainingType: preference.trainingType,
      baseMinutes: preference.durationMinutes,
      baseIntensity: source.intensity,
      purpose: _focusLabel(preference.focusCodes),
      mainSets: List<String>.from(source.mainSets),
      recovery: preference.intensityBand == PlanIntensityBand.recovery,
      preferredIntensity: preference.intensityBand,
    );
  }

  String _focusLabel(List<String> focusCodes) {
    const Map<String, String> labels = <String, String>{
      'aerobic_base': '建立有氧基础',
      'movement_quality': '巩固动作质量',
      'full_body_strength': '建立全身力量',
      'lower_body_strength': '建立下肢力量',
      'upper_body_strength': '建立上肢力量',
      'threshold': '提高可控节奏能力',
      'speed': '提高跑步速度耐受',
      'long_endurance': '累积持续运动时间',
      'hyrox_transition': '练习 HYROX 跑站转换',
      'hyrox_station': '巩固 HYROX 站点技术',
      'mobility': '维持关节活动度',
      'recovery': '促进恢复',
    };
    return focusCodes
        .map((String code) => labels[code] ?? '完成当前周期目标')
        .join('、');
  }

  List<WorkoutExerciseLink> _workoutExerciseLinks({
    required String workoutId,
    required _WorkoutTemplate template,
    required int weekIndex,
    required PlanProgressionMode progressionMode,
    required int mainSetCount,
    required int accessoryCount,
  }) {
    if (template.abcStrengthSession != null) {
      return _abcStrengthWorkoutExerciseLinks(
        workoutId: workoutId,
        session: template.abcStrengthSession!,
        weekIndex: weekIndex,
        progressionMode: progressionMode,
      );
    }
    final TrainingType trainingType = template.trainingType;
    final Iterable<WorkoutDay> catalog =
        seedTrainingPlans.expand((TrainingPlan plan) => plan.workoutDays);
    WorkoutDay? source;
    for (final WorkoutDay workout in catalog) {
      if (workout.trainingType == trainingType &&
          workout.workoutExercises.isNotEmpty) {
        source = workout;
        break;
      }
    }
    source ??= catalog.firstWhere(
      (WorkoutDay workout) => switch (trainingType) {
        TrainingType.easyRun ||
        TrainingType.tempoRun ||
        TrainingType.intervalRun ||
        TrainingType.longRun =>
          workout.trainingType == TrainingType.easyRun,
        TrainingType.strength => workout.trainingType == TrainingType.strength,
        TrainingType.hyrox => workout.trainingType == TrainingType.hyrox,
        _ => workout.trainingType == TrainingType.mobility,
      },
    );
    final List<WorkoutExerciseLink> links = <WorkoutExerciseLink>[
      for (final WorkoutExerciseLink link in source.workoutExercises)
        link.copyWith(
            id: '$workoutId-${link.module.jsonValue}-${link.sequence}'),
    ];
    WorkoutExerciseLink? firstMain;
    WorkoutExerciseLink? firstAccessory;
    for (final WorkoutExerciseLink link in links) {
      if (link.module == WorkoutExerciseModule.mainTraining) {
        firstMain ??= link;
      }
      if (link.module == WorkoutExerciseModule.accessory) {
        firstAccessory ??= link;
      }
    }
    int sequence = links.length + 1;
    int mainCount = links
        .where((WorkoutExerciseLink item) =>
            item.module == WorkoutExerciseModule.mainTraining)
        .length;
    while (mainCount < mainSetCount && firstMain != null) {
      links.add(firstMain.copyWith(
        id: '$workoutId-main-$mainCount',
        sequence: sequence++,
      ));
      mainCount += 1;
    }
    int currentAccessoryCount = links
        .where((WorkoutExerciseLink item) =>
            item.module == WorkoutExerciseModule.accessory)
        .length;
    while (currentAccessoryCount < accessoryCount) {
      final WorkoutExerciseLink sourceAccessory = firstAccessory ??
          WorkoutExerciseLink(
            id: '$workoutId-accessory-source',
            exerciseId: 'exercise-dead-bug',
            sequence: sequence,
            module: WorkoutExerciseModule.accessory,
            plannedSetCount: 2,
            repetitionsPerSet: 8,
            plannedWeightOrIntensity: '自重、可控完成',
            restSeconds: 45,
          );
      links.add(sourceAccessory.copyWith(
        id: '$workoutId-accessory-$currentAccessoryCount',
        sequence: sequence++,
      ));
      currentAccessoryCount += 1;
    }
    if (_isRunningType(trainingType)) {
      links.addAll(<WorkoutExerciseLink>[
        WorkoutExerciseLink(
          id: '$workoutId-hip-drive',
          exerciseId: 'exercise-high-knee',
          sequence: sequence++,
          module: WorkoutExerciseModule.hipDrive,
          plannedSetCount: 2,
          repetitionsPerSet: 20,
          plannedWeightOrIntensity: '自重，保持躯干稳定',
          restSeconds: 30,
        ),
        WorkoutExerciseLink(
          id: '$workoutId-calf',
          exerciseId: 'exercise-standing-calf-raise',
          sequence: sequence++,
          module: WorkoutExerciseModule.calf,
          plannedSetCount: 2,
          repetitionsPerSet: 12,
          plannedWeightOrIntensity: '自重，缓慢离心',
          restSeconds: 30,
        ),
      ]);
    }
    return List<WorkoutExerciseLink>.unmodifiable(links);
  }

  List<WorkoutExerciseLink> _abcStrengthWorkoutExerciseLinks({
    required String workoutId,
    required AbcStrengthSessionTemplate session,
    required int weekIndex,
    required PlanProgressionMode progressionMode,
  }) {
    final WorkoutDay source = seedTrainingPlans
        .expand((TrainingPlan plan) => plan.workoutDays)
        .firstWhere(
          (WorkoutDay workout) =>
              workout.trainingType == TrainingType.strength &&
              workout.workoutExercises.isNotEmpty,
        );
    final AbcStrengthWeekPrescription prescription =
        _abcStrengthCycleCompiler.progressionFor(
      weekIndex: weekIndex,
      mode: progressionMode,
    );
    final List<WorkoutExerciseLink> links = <WorkoutExerciseLink>[];
    int sequence = 1;

    void appendSourceModule(WorkoutExerciseModule module) {
      for (final WorkoutExerciseLink link in source.workoutExercises.where(
        (WorkoutExerciseLink item) => item.module == module,
      )) {
        links.add(
          link.copyWith(
            id: '$workoutId-${module.jsonValue}-$sequence',
            sequence: sequence++,
          ),
        );
      }
    }

    for (final WorkoutExerciseModule module in const <WorkoutExerciseModule>[
      WorkoutExerciseModule.foamRolling,
      WorkoutExerciseModule.dynamicStretch,
      WorkoutExerciseModule.activation,
      WorkoutExerciseModule.warmup,
    ]) {
      appendSourceModule(module);
    }
    for (final AbcStrengthExerciseTemplate exercise in session.mainExercises) {
      links.add(
        WorkoutExerciseLink(
          id: '$workoutId-main-$sequence',
          exerciseId: exercise.exerciseId,
          sequence: sequence++,
          module: WorkoutExerciseModule.mainTraining,
          plannedSetCount: prescription.mainSetCount,
          repetitionsPerSet: prescription.repetitionsPerSet,
          plannedWeightOrIntensity: prescription.intensityLabel,
          restSeconds: prescription.mainRestSeconds,
        ),
      );
    }
    for (final AbcStrengthExerciseTemplate exercise
        in session.accessoryExercises) {
      links.add(
        WorkoutExerciseLink(
          id: '$workoutId-accessory-$sequence',
          exerciseId: exercise.exerciseId,
          sequence: sequence++,
          module: WorkoutExerciseModule.accessory,
          plannedSetCount: prescription.accessorySetCount,
          repetitionsPerSet: prescription.repetitionsPerSet,
          plannedWeightOrIntensity: prescription.intensityLabel,
          restSeconds: prescription.accessoryRestSeconds,
        ),
      );
    }
    appendSourceModule(WorkoutExerciseModule.cooldown);
    return List<WorkoutExerciseLink>.unmodifiable(links);
  }

  bool _isRunningType(TrainingType type) =>
      type == TrainingType.easyRun ||
      type == TrainingType.tempoRun ||
      type == TrainingType.intervalRun ||
      type == TrainingType.longRun;

  List<_WorkoutTemplate> _templatesFor(MainSport sport) {
    switch (sport) {
      case MainSport.marathon:
      case MainSport.trailRunning:
        return const <_WorkoutTemplate>[
          _WorkoutTemplate(
            title: '低强度有氧跑',
            trainingType: TrainingType.easyRun,
            baseMinutes: 45,
            baseIntensity: 'RPE 4-5',
            purpose: '建立有氧基础',
            mainSets: <String>['轻松跑，保持可以完整说话的强度'],
          ),
          _WorkoutTemplate(
            title: '跑步质量课',
            trainingType: TrainingType.tempoRun,
            baseMinutes: 45,
            baseIntensity: 'RPE 6-7',
            purpose: '提高稳定配速能力',
            mainSets: <String>['热身后完成 3 组可控节奏跑', '组间慢跑恢复'],
          ),
          _WorkoutTemplate(
            title: '跑者力量基础',
            trainingType: TrainingType.strength,
            baseMinutes: 45,
            baseIntensity: 'RPE 6',
            purpose: '提高髋膝踝力量耐受',
            mainSets: <String>['深蹲模式 3 组', '髋铰链模式 3 组', '单腿稳定 2 组'],
          ),
          _WorkoutTemplate(
            title: '周末耐力跑',
            trainingType: TrainingType.longRun,
            baseMinutes: 70,
            baseIntensity: 'RPE 4-6',
            purpose: '积累持续运动时间',
            mainSets: <String>['全程保守完成，不在后半程追配速'],
          ),
          _WorkoutTemplate(
            title: '跑步活动度恢复',
            trainingType: TrainingType.mobility,
            baseMinutes: 30,
            baseIntensity: 'RPE 2-3',
            purpose: '促进恢复并维护活动度',
            mainSets: <String>['低强度步行', '踝、髋活动度循环'],
            recovery: true,
          ),
        ];
      case MainSport.strength:
        return const <_WorkoutTemplate>[
          _WorkoutTemplate(
            title: '下肢力量基础',
            trainingType: TrainingType.strength,
            baseMinutes: 50,
            baseIntensity: 'RPE 6',
            purpose: '建立下肢动作质量和力量基础',
            mainSets: <String>['深蹲模式 4 组', '髋铰链模式 3 组', '核心稳定 3 组'],
          ),
          _WorkoutTemplate(
            title: '上肢推拉基础',
            trainingType: TrainingType.strength,
            baseMinutes: 45,
            baseIntensity: 'RPE 6',
            purpose: '建立上肢推拉平衡',
            mainSets: <String>['水平推 3 组', '水平拉 3 组', '肩胛稳定 2 组'],
          ),
          _WorkoutTemplate(
            title: '全身力量整合',
            trainingType: TrainingType.strength,
            baseMinutes: 50,
            baseIntensity: 'RPE 6-7',
            purpose: '整合全身力量动作',
            mainSets: <String>['下肢主动作 3 组', '上肢主动作 3 组', '负重行走 3 组'],
          ),
          _WorkoutTemplate(
            title: '力量恢复与活动度',
            trainingType: TrainingType.mobility,
            baseMinutes: 30,
            baseIntensity: 'RPE 2-3',
            purpose: '维持关节活动度并促进恢复',
            mainSets: <String>['全身活动度循环 3 轮'],
            recovery: true,
          ),
        ];
      case MainSport.hyrox:
        return const <_WorkoutTemplate>[
          _WorkoutTemplate(
            title: 'HYROX 有氧基础',
            trainingType: TrainingType.easyRun,
            baseMinutes: 40,
            baseIntensity: 'RPE 4-5',
            purpose: '建立跑段有氧储备',
            mainSets: <String>['轻松跑 30 分钟', '4 次短加速但不冲刺'],
          ),
          _WorkoutTemplate(
            title: 'HYROX 力量基础',
            trainingType: TrainingType.strength,
            baseMinutes: 50,
            baseIntensity: 'RPE 6',
            purpose: '建立雪橇、弓步和负重行走所需力量',
            mainSets: <String>['深蹲模式 3 组', '负重行走 4 组', '核心抗旋转 3 组'],
          ),
          _WorkoutTemplate(
            title: 'HYROX 站点技术',
            trainingType: TrainingType.hyrox,
            baseMinutes: 45,
            baseIntensity: 'RPE 6',
            purpose: '提高站点动作效率',
            mainSets: <String>['划船机技术', '墙球分组策略', '波比节奏练习'],
          ),
          _WorkoutTemplate(
            title: 'HYROX 跑站衔接',
            trainingType: TrainingType.hyrox,
            baseMinutes: 55,
            baseIntensity: 'RPE 6-7',
            purpose: '练习跑后动作转换',
            mainSets: <String>['完成 3 轮短跑 + 功能动作组合', '每轮保留 2 次余量'],
          ),
          _WorkoutTemplate(
            title: 'HYROX 恢复课',
            trainingType: TrainingType.mobility,
            baseMinutes: 30,
            baseIntensity: 'RPE 2-3',
            purpose: '恢复肩髋和下肢',
            mainSets: <String>['低强度单车或步行', '肩髋活动度循环'],
            recovery: true,
          ),
        ];
      case MainSport.rehab:
        return const <_WorkoutTemplate>[
          _WorkoutTemplate(
            title: '无痛活动度',
            trainingType: TrainingType.rehab,
            baseMinutes: 25,
            baseIntensity: 'RPE 2-3',
            purpose: '在无痛范围内恢复活动能力',
            mainSets: <String>['无痛活动度循环', '低强度稳定练习'],
            recovery: true,
          ),
          _WorkoutTemplate(
            title: '低强度基础体能',
            trainingType: TrainingType.crossTraining,
            baseMinutes: 30,
            baseIntensity: 'RPE 3-4',
            purpose: '维持基础体能且避免刺激疼痛',
            mainSets: <String>['无痛步行、单车或椭圆机'],
            recovery: true,
          ),
        ];
      case MainSport.fatLoss:
      case MainSport.generalFitness:
        return const <_WorkoutTemplate>[
          _WorkoutTemplate(
            title: '全身基础力量',
            trainingType: TrainingType.strength,
            baseMinutes: 45,
            baseIntensity: 'RPE 6',
            purpose: '建立全身力量基础',
            mainSets: <String>['蹲、推、拉各 3 组', '核心稳定 2 组'],
          ),
          _WorkoutTemplate(
            title: '低强度心肺',
            trainingType: TrainingType.crossTraining,
            baseMinutes: 40,
            baseIntensity: 'RPE 4-5',
            purpose: '建立可恢复的心肺基础',
            mainSets: <String>['选择跑步、单车或椭圆机持续完成'],
          ),
          _WorkoutTemplate(
            title: '基础体能循环',
            trainingType: TrainingType.crossTraining,
            baseMinutes: 40,
            baseIntensity: 'RPE 5-6',
            purpose: '提高日常体能和动作耐受',
            mainSets: <String>['完成 3 轮低冲击全身循环'],
          ),
          _WorkoutTemplate(
            title: '活动度恢复',
            trainingType: TrainingType.mobility,
            baseMinutes: 25,
            baseIntensity: 'RPE 2-3',
            purpose: '促进恢复并维持活动度',
            mainSets: <String>['全身活动度循环 3 轮'],
            recovery: true,
          ),
        ];
    }
  }

  _WorkoutTemplate _secondaryTemplate(MainSport sport) => switch (sport) {
        MainSport.marathon || MainSport.trailRunning => const _WorkoutTemplate(
            title: '次目标跑步技术',
            trainingType: TrainingType.easyRun,
            baseMinutes: 35,
            baseIntensity: 'RPE 4-5',
            purpose: '用低成本跑步支持次目标',
            mainSets: <String>['轻松跑与跑姿技术练习'],
          ),
        MainSport.strength => const _WorkoutTemplate(
            title: '次目标全身力量',
            trainingType: TrainingType.strength,
            baseMinutes: 40,
            baseIntensity: 'RPE 6',
            purpose: '用全身力量支持次目标',
            mainSets: <String>['蹲、推、拉各 3 组'],
          ),
        MainSport.hyrox => const _WorkoutTemplate(
            title: '次目标 HYROX 技术',
            trainingType: TrainingType.hyrox,
            baseMinutes: 40,
            baseIntensity: 'RPE 5-6',
            purpose: '用技术课支持 HYROX 次目标',
            mainSets: <String>['低乳酸站点技术循环'],
          ),
        MainSport.rehab => const _WorkoutTemplate(
            title: '次目标恢复维护',
            trainingType: TrainingType.rehab,
            baseMinutes: 25,
            baseIntensity: 'RPE 2-3',
            purpose: '把恢复要求纳入当前计划',
            mainSets: <String>['无痛活动度和稳定练习'],
            recovery: true,
          ),
        MainSport.fatLoss || MainSport.generalFitness => const _WorkoutTemplate(
            title: '次目标基础体能',
            trainingType: TrainingType.crossTraining,
            baseMinutes: 35,
            baseIntensity: 'RPE 4-5',
            purpose: '用基础体能课支持次目标',
            mainSets: <String>['低冲击全身循环 3 轮'],
          ),
      };

  TrainingDecisionType _decisionType(
    TrainingCyclePhase phase,
    _WorkoutTemplate template,
  ) {
    if (phase == TrainingCyclePhase.raceWeek) {
      return TrainingDecisionType.technique;
    }
    if (phase == TrainingCyclePhase.postRaceRecovery) {
      return TrainingDecisionType.recovery;
    }
    if (phase == TrainingCyclePhase.deload ||
        phase == TrainingCyclePhase.taper) {
      return template.recovery
          ? TrainingDecisionType.recovery
          : TrainingDecisionType.deload;
    }
    return template.recovery
        ? TrainingDecisionType.recovery
        : TrainingDecisionType.normal;
  }

  double _volumeFactor(
    TrainingCyclePhase phase, {
    required PlanProgressionMode? progressionMode,
    bool abcStrengthCycle = false,
  }) {
    if (abcStrengthCycle && progressionMode == PlanProgressionMode.balanced) {
      return switch (phase) {
        TrainingCyclePhase.baseline ||
        TrainingCyclePhase.build ||
        TrainingCyclePhase.specific =>
          1,
        TrainingCyclePhase.deload => 0.55,
        TrainingCyclePhase.taper => 0.65,
        TrainingCyclePhase.raceWeek => 0.45,
        TrainingCyclePhase.postRaceRecovery => 0.5,
      };
    }
    if (progressionMode == PlanProgressionMode.conservative) {
      return switch (phase) {
        TrainingCyclePhase.baseline => 0.98,
        TrainingCyclePhase.build => 1,
        TrainingCyclePhase.specific => 1.02,
        TrainingCyclePhase.deload => 0.56,
        TrainingCyclePhase.taper => 0.65,
        TrainingCyclePhase.raceWeek => 0.45,
        TrainingCyclePhase.postRaceRecovery => 0.5,
      };
    }
    if (progressionMode == PlanProgressionMode.balanced) {
      return switch (phase) {
        TrainingCyclePhase.baseline => 0.95,
        TrainingCyclePhase.build => 1,
        TrainingCyclePhase.specific => 1.04,
        TrainingCyclePhase.deload => 0.572,
        TrainingCyclePhase.taper => 0.65,
        TrainingCyclePhase.raceWeek => 0.45,
        TrainingCyclePhase.postRaceRecovery => 0.5,
      };
    }
    return switch (phase) {
      TrainingCyclePhase.baseline => 0.9,
      TrainingCyclePhase.build => 1,
      TrainingCyclePhase.specific => 1.05,
      TrainingCyclePhase.deload => 0.7,
      TrainingCyclePhase.taper => 0.65,
      TrainingCyclePhase.raceWeek => 0.45,
      TrainingCyclePhase.postRaceRecovery => 0.5,
    };
  }

  String _intensityFor(
    TrainingCyclePhase phase,
    _WorkoutTemplate template, {
    required TrainingExperienceLevel experienceLevel,
    required bool skillCompiled,
  }) {
    if (phase == TrainingCyclePhase.postRaceRecovery) return 'RPE 2-3';
    if (phase == TrainingCyclePhase.raceWeek) return 'RPE 3-5';
    if (phase == TrainingCyclePhase.deload ||
        phase == TrainingCyclePhase.taper) {
      return 'RPE 3-5';
    }
    if (!skillCompiled) return template.baseIntensity;
    if (experienceLevel == TrainingExperienceLevel.beginner &&
        template.preferredIntensity == PlanIntensityBand.challenging) {
      return 'RPE 5-6';
    }
    return switch (template.preferredIntensity) {
      PlanIntensityBand.recovery => 'RPE 2-3',
      PlanIntensityBand.easy => 'RPE 4-5',
      PlanIntensityBand.moderate => 'RPE 5-6',
      PlanIntensityBand.challenging => 'RPE 6-7',
      null => template.baseIntensity,
    };
  }

  List<String> _phaseMainSets(
    List<String> source,
    TrainingCyclePhase phase,
  ) {
    if (phase == TrainingCyclePhase.raceWeek) {
      return <String>['短时状态唤醒，不产生明显疲劳', ...source.take(1)];
    }
    if (phase == TrainingCyclePhase.postRaceRecovery) {
      return const <String>['低强度恢复 15-25 分钟', '复测疼痛和疲劳，不补比赛前训练'];
    }
    if (phase == TrainingCyclePhase.deload ||
        phase == TrainingCyclePhase.taper) {
      return source.take(2).toList();
    }
    return List<String>.from(source);
  }

  List<String> _accessoryFor(
    _WorkoutTemplate template,
    TrainingCyclePhase phase,
  ) {
    if (phase == TrainingCyclePhase.deload ||
        phase == TrainingCyclePhase.taper ||
        phase == TrainingCyclePhase.raceWeek ||
        phase == TrainingCyclePhase.postRaceRecovery) {
      return const <String>[];
    }
    return template.trainingType == TrainingType.strength
        ? const <String>['选择 1 个核心动作完成 2 组']
        : const <String>['完成 5 分钟低强度活动度维护'];
  }

  List<String> _dynamicWarmup(TrainingType type) {
    if (type == TrainingType.strength || type == TrainingType.hyrox) {
      return const <String>['髋、踝、肩动态活动 2 轮', '主动作徒手预演 2 组'];
    }
    return const <String>['踝髋动态活动 2 轮', '行进高抬腿与弓步各 2 组'];
  }

  List<String> _activation(TrainingType type) {
    if (type == TrainingType.strength || type == TrainingType.hyrox) {
      return const <String>['臀桥 2 组', '核心抗伸展 2 组'];
    }
    return const <String>['臀中肌激活 2 组', '踝弹跳或提踵 2 组'];
  }

  bool _raceMatches(
    RacePlan race,
    MainSport primary,
    MainSport? secondary,
  ) {
    final MainSport raceSport = switch (race.type) {
      RaceType.hyrox => MainSport.hyrox,
      RaceType.trailRunning => MainSport.trailRunning,
      RaceType.marathon || RaceType.roadRunning => MainSport.marathon,
    };
    return raceSport == primary || raceSport == secondary;
  }

  String _planTitle(MainSport sport) => switch (sport) {
        MainSport.marathon || MainSport.trailRunning => '跑步 4 周计划',
        MainSport.strength => '健身力量 4 周计划',
        MainSport.hyrox => 'HYROX 基础 4 周计划',
        MainSport.rehab => '恢复基础 4 周计划',
        MainSport.fatLoss || MainSport.generalFitness => '基础体能 4 周计划',
      };

  String _planId({
    required UserProfile profile,
    required MainSport primarySport,
    required MainSport? secondarySport,
    required DateTime startsOn,
    required RacePlan? race,
    String? generationId,
  }) {
    final String date = '${startsOn.year}'
        '${startsOn.month.toString().padLeft(2, '0')}'
        '${startsOn.day.toString().padLeft(2, '0')}';
    final String secondary = secondarySport?.jsonValue ?? 'none';
    final String raceId =
        race?.id.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '-') ?? 'no-race';
    final String generationSuffix = generationId == null
        ? ''
        : '-${generationId.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '-')}';
    return 'generated-${profile.id}-${primarySport.jsonValue}-$secondary-'
        'd${profile.weeklyTrainingDays}-m${profile.dailyAvailableMinutes}-'
        '$date-$raceId$generationSuffix';
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class _WorkoutTemplate {
  const _WorkoutTemplate({
    required this.title,
    required this.trainingType,
    required this.baseMinutes,
    required this.baseIntensity,
    required this.purpose,
    required this.mainSets,
    this.recovery = false,
    this.preferredIntensity,
    this.abcStrengthSession,
  });

  final String title;
  final TrainingType trainingType;
  final int baseMinutes;
  final String baseIntensity;
  final String purpose;
  final List<String> mainSets;
  final bool recovery;
  final PlanIntensityBand? preferredIntensity;
  final AbcStrengthSessionTemplate? abcStrengthSession;

  _WorkoutTemplate copyWith({
    String? title,
    String? purpose,
    List<String>? mainSets,
    AbcStrengthSessionTemplate? abcStrengthSession,
  }) {
    return _WorkoutTemplate(
      title: title ?? this.title,
      trainingType: trainingType,
      baseMinutes: baseMinutes,
      baseIntensity: baseIntensity,
      purpose: purpose ?? this.purpose,
      mainSets: mainSets ?? this.mainSets,
      recovery: recovery,
      preferredIntensity: preferredIntensity,
      abcStrengthSession: abcStrengthSession ?? this.abcStrengthSession,
    );
  }
}
