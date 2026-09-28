import '../plugins/core/plugin_ref.dart';
import '../plugins/sports/sport_plan_strategy.dart';
import '../plugins/sports/sport_workout_template.dart';
import '../plugins/sports/sport_capability_directory.dart';
import '../core/constants/app_brand.dart';
import '../core/config/training_structure_config.dart';
import '../data/models/race.dart';
import '../data/models/plan_generation_preferences.dart';
import '../data/models/training_plan.dart';
import '../data/models/user_profile.dart';
import '../data/models/workout_day.dart';
import '../data/seed/seed_training_plans.dart';
import '../data/seed/seed_exercises.dart';
import 'abc_strength_cycle_compiler.dart';
import 'resource_workout_binding_service.dart';
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
    this.pluginRefs = const [],
  });

  final TrainingPlan plan;
  final List<GeneratedPlanWeek> weeks;
  final MainSport primarySport;
  final MainSport? secondarySport;
  final RacePlan? appliedRace;
  final List<PluginRef> pluginRefs;
}

class FourWeekPlanGenerator {
  FourWeekPlanGenerator({
    AbcStrengthCycleCompiler? abcStrengthCycleCompiler,
    TrainingStructurePolicy? trainingStructurePolicy,
    bool? structureEnabled,
    SportCapabilityDirectory? sportDirectory,
  })  : _sportDirectory = sportDirectory ?? SportCapabilityDirectory.builtIn(),
        _abcStrengthCycleCompiler =
            abcStrengthCycleCompiler ?? AbcStrengthCycleCompiler(),
        _trainingStructurePolicy =
            trainingStructurePolicy ?? const TrainingStructurePolicy(),
        _structureEnabled = structureEnabled ?? TrainingStructureConfig.enabled;

  final SportCapabilityDirectory _sportDirectory;
  final AbcStrengthCycleCompiler _abcStrengthCycleCompiler;
  final TrainingStructurePolicy _trainingStructurePolicy;
  final bool _structureEnabled;

  FourWeekPlanGeneration generate({
    required UserProfile profile,
    required DateTime startsOn,
    RacePlan? race,
    PlanGenerationPreferences? preferences,
    bool bindResourceExercises = false,
  }) {
    final DateTime planStart = _dateOnly(startsOn);
    final MainSport primarySport = profile.mainSports.isEmpty
        ? MainSport.generalFitness
        : profile.mainSports.first;
    final MainSport? secondarySport =
        profile.mainSports.length > 1 && profile.mainSports[1] != primarySport
            ? profile.mainSports[1]
            : null;
    final SportPlanStrategy primaryStrategy =
        _sportDirectory.require(primarySport);
    final bool primaryMatchesRace =
        race != null && primaryStrategy.matchesRace(race.type);
    final bool secondaryMatchesRace = race != null &&
        !primaryMatchesRace &&
        secondarySport != null &&
        _sportDirectory.require(secondarySport).matchesRace(race.type);
    final RacePlan? appliedRace =
        primaryMatchesRace || secondaryMatchesRace ? race : null;
    final int weeklyTrainingDays = preferences == null
        ? profile.weeklyTrainingDays.clamp(1, 7)
        : preferences.weeklySessions.length.clamp(1, 6);
    final context = SportPlanContext(
        profile: profile,
        startsOn: planStart,
        race: appliedRace,
        preferences: preferences,
        trainingDays: weeklyTrainingDays);
    final List<PluginRef> pluginRefs = [primaryStrategy.definition.pluginRef];
    if (secondarySport != null &&
        (secondaryMatchesRace ||
            (preferences == null && weeklyTrainingDays >= 2))) {
      pluginRefs
          .add(_sportDirectory.require(secondarySport).definition.pluginRef);
    }
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
      final List<SportWorkoutTemplate> templates = _selectTemplates(
        primaryStrategy: primaryStrategy,
        secondarySport: secondarySport,
        context: context,
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
        final SportWorkoutTemplate template = templates[sessionIndex];
        final WorkoutDay compiledWorkout = _buildWorkout(
          planId: planId,
          weekIndex: weekIndex,
          dayIndex: dayIndex,
          phase: phase,
          template: template,
          profile: profile,
          appliedRace: appliedRace,
          skillCompiled: preferences != null,
          resourceDeload: bindResourceExercises && preferences == null &&
              appliedRace == null && weekIndex == 4,
          progressionMode: preferences?.progressionMode,
        );
        final WorkoutDay structuredWorkout = _structureEnabled
            ? _trainingStructurePolicy.apply(
                workout: compiledWorkout,
                phaseCode: phase.jsonValue,
                profile: profile,
              )
            : compiledWorkout;
        final workout = bindResourceExercises && preferences == null
            ? const ResourceWorkoutBindingService().bind(
                structuredWorkout,
                _workoutExerciseLinks(
                  workoutId: compiledWorkout.id, template: template,
                  weekIndex: weekIndex, progressionMode: PlanProgressionMode.conservative,
                  mainSetCount: compiledWorkout.mainSets.length,
                  accessoryCount: compiledWorkout.accessoryWork.length),
              )
            : structuredWorkout;
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
      title: '${primaryStrategy.planTitle}$secondaryLabel',
      description: preferences == null
          ? '根据当前档案生成的滚动 4 周计划$raceLabel。每周阶段和训练量均可追溯。'
          : '根据结构化 AI 处方由本地规则编译的 4 周计划$raceLabel。'
              '动作、负荷与安全边界均由${AppBrand.displayName} 决定。',
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
      pluginRefs: List.unmodifiable(pluginRefs),
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
    required SportWorkoutTemplate template,
    required UserProfile profile,
    required RacePlan? appliedRace,
    required bool skillCompiled,
    bool resourceDeload = false,
    required PlanProgressionMode? progressionMode,
  }) {
    final int availableMinutes = profile.dailyAvailableMinutes.clamp(15, 180);
    final int baseMinutes = template.baseMinutes.clamp(15, availableMinutes);
    // 用户批准仅资源默认计划第四周缩短；赛事阶段和其他生成路径不变。
    final int estimatedMinutes = (baseMinutes *
            (resourceDeload ? 0.55 : _volumeFactor(
              phase,
              progressionMode: progressionMode,
              abcStrengthCycle: template.abcStrengthSession != null,
            )))
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

  List<SportWorkoutTemplate> _selectTemplates({
    required SportPlanStrategy primaryStrategy,
    required MainSport? secondarySport,
    required SportPlanContext context,
  }) {
    final source =
        primaryStrategy.primaryCandidates(context, _compilePreferences);
    if (source.isEmpty ||
        (context.preferences != null &&
            source.length != context.trainingDays)) {
      throw StateError(
          '${primaryStrategy.definition.sport.label}候选课程数量无效，请重新生成。');
    }
    if (context.preferences != null) return source;
    final selected = <SportWorkoutTemplate>[
      for (int index = 0; index < context.trainingDays; index += 1)
        source[index % source.length],
    ];
    if (secondarySport != null && selected.length >= 2) {
      selected[selected.length - 1] =
          _sportDirectory.require(secondarySport).secondaryCandidate(context);
    }
    return selected;
  }

  List<SportWorkoutTemplate> _compilePreferences(SportPlanContext context) {
    final preferences = context.preferences!;
    final templates = _preferenceTemplates(
        preferences.weeklySessions.take(context.trainingDays).toList());
    if (context.compileAbcStrengthCycle) {
      return _applyAbcStrengthCycle(templates);
    }
    return templates;
  }

  List<SportWorkoutTemplate> _applyAbcStrengthCycle(
    List<SportWorkoutTemplate> templates,
  ) {
    final int strengthSessionCount = templates
        .where(
          (SportWorkoutTemplate item) =>
              item.trainingType == TrainingType.strength,
        )
        .length;
    final List<AbcStrengthSessionTemplate> sessions =
        _abcStrengthCycleCompiler.sessionsFor(
      strengthSessionCount: strengthSessionCount,
    );
    int cursor = 0;
    return <SportWorkoutTemplate>[
      for (final SportWorkoutTemplate template in templates)
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

  List<SportWorkoutTemplate> _preferenceTemplates(
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

  SportWorkoutTemplate _templateForPreference(
      PlanSessionPreference preference) {
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
    return SportWorkoutTemplate(
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
    required SportWorkoutTemplate template,
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

  TrainingDecisionType _decisionType(
    TrainingCyclePhase phase,
    SportWorkoutTemplate template,
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
    SportWorkoutTemplate template, {
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
    SportWorkoutTemplate template,
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
