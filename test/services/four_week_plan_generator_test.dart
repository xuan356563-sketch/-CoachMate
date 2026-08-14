import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/exercise_training_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/models/plan_generation_preferences.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/seed/seed_exercises.dart';
import 'package:trainflow_ai/data/seed/seed_races.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'package:trainflow_ai/services/training_prescription_safety_audit_service.dart';
import 'package:trainflow_ai/services/training_rule_audit_service.dart';

void main() {
  test('结构开关开启后四周计划写入五维重点且初学者不会保留腾空动作', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
      trainingExperienceLevel: TrainingExperienceLevel.beginner,
      weeklyTrainingDays: 3,
    );

    final FourWeekPlanGeneration generation =
        FourWeekPlanGenerator(structureEnabled: true).generate(
      profile: profile,
      startsOn: DateTime(2026, 7, 13),
    );

    expect(
      generation.weeks[0].workouts.first.dimensionFocus.primary,
      <TrainingDimension>[
        TrainingDimension.stability,
        TrainingDimension.breathing,
      ],
    );
    expect(
      generation.weeks[1].workouts.first.dimensionFocus.primary,
      <TrainingDimension>[
        TrainingDimension.strength,
        TrainingDimension.eccentric,
      ],
    );
    expect(
      generation.weeks[2].workouts.first.dimensionFocus.primary,
      <TrainingDimension>[
        TrainingDimension.strength,
        TrainingDimension.neural,
      ],
    );
    expect(
      generation.plan.workoutDays.every(
        (WorkoutDay workout) =>
            workout.structurePolicyVersion == trainingStructurePolicyVersion,
      ),
      isTrue,
    );
    expect(
      generation.plan.workoutDays
          .expand((WorkoutDay workout) => workout.workoutExercises)
          .where((WorkoutExerciseLink link) =>
              link.executionIntent == ExecutionIntent.explosive),
      isEmpty,
    );
  });

  test('腿部结构按足踝激活、爆发、力量稳定和小腿收尾排序', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
      weeklyTrainingDays: 3,
      dailyAvailableMinutes: 60,
    );
    final FourWeekPlanGeneration generation =
        FourWeekPlanGenerator(structureEnabled: true).generate(
      profile: profile,
      startsOn: DateTime(2026, 7, 13),
    );
    final WorkoutDay specific = generation.weeks[2].workouts.firstWhere(
      (WorkoutDay workout) => workout.trainingType == TrainingType.strength,
    );
    final List<String> ids = specific.workoutExercises
        .map((WorkoutExerciseLink link) => link.exerciseId)
        .toList(growable: false);
    final Set<LegTrainingElement> elements = ids
        .expand(
          (String id) => trainingProfileForExercise(id).legElements,
        )
        .toSet();

    expect(ids.indexOf('exercise-short-foot'),
        lessThan(ids.indexOf('exercise-box-jump')));
    expect(ids.indexOf('exercise-box-jump'),
        lessThan(ids.indexOf('exercise-single-leg-rdl')));
    expect(ids.indexOf('exercise-single-leg-rdl'),
        lessThan(ids.indexOf('exercise-single-leg-calf-raise')));
    expect(elements, containsAll(LegTrainingElement.values));
    final WorkoutExerciseLink jump = specific.workoutExercises.singleWhere(
      (WorkoutExerciseLink link) => link.exerciseId == 'exercise-box-jump',
    );
    expect(jump.restSeconds, greaterThanOrEqualTo(90));
    final safety = TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
      plan: generation.plan,
      profile: profile,
      enforceFourWeekDeload: false,
    );
    expect(safety.canActivate, isTrue, reason: safety.failures.join('\n'));
  });

  test('跑步主目标会生成基线、提升、专项、减量四周且次目标不增加训练天数', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      trainingGoal: '10 公里稳定跑进 55 分钟',
      mainSports: const <MainSport>[
        MainSport.marathon,
        MainSport.strength,
      ],
      weeklyTrainingDays: 4,
      dailyAvailableMinutes: 50,
    );

    final FourWeekPlanGeneration generation = FourWeekPlanGenerator().generate(
      profile: profile,
      startsOn: DateTime(2026, 7, 13),
    );

    expect(generation.plan.durationWeeks, 4);
    expect(generation.plan.workoutDays, hasLength(16));
    expect(
      generation.weeks.map((GeneratedPlanWeek week) => week.phase),
      const <TrainingCyclePhase>[
        TrainingCyclePhase.baseline,
        TrainingCyclePhase.build,
        TrainingCyclePhase.specific,
        TrainingCyclePhase.deload,
      ],
    );
    for (int weekIndex = 1; weekIndex <= 4; weekIndex += 1) {
      final List<WorkoutDay> week = generation.plan.workoutDays
          .where((WorkoutDay workout) => workout.weekIndex == weekIndex)
          .toList();
      expect(week, hasLength(4));
      expect(
        week.any((WorkoutDay workout) =>
            workout.trainingType == TrainingType.strength),
        isTrue,
      );
    }
    expect(
      generation.weeks.last.workouts.every((WorkoutDay workout) =>
          workout.decisionType != TrainingDecisionType.normal),
      isTrue,
    );
  });

  test('力量主目标会生成健身计划并遵守每周三练', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      trainingGoal: '提升全身力量基础',
      mainSports: const <MainSport>[MainSport.strength],
      weeklyTrainingDays: 3,
      dailyAvailableMinutes: 40,
    );

    final FourWeekPlanGeneration generation = FourWeekPlanGenerator().generate(
      profile: profile,
      startsOn: DateTime(2026, 7, 14),
    );

    expect(generation.plan.title, contains('健身力量'));
    expect(generation.plan.workoutDays, hasLength(12));
    expect(
      generation.plan.workoutDays
          .where(
              (WorkoutDay item) => item.trainingType == TrainingType.strength)
          .length,
      greaterThanOrEqualTo(8),
    );
  });

  test('匹配主目标的临近比赛会自动切换减量、比赛周和赛后恢复阶段', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.hyrox],
      weeklyTrainingDays: 4,
    );
    final FourWeekPlanGeneration generation = FourWeekPlanGenerator().generate(
      profile: profile,
      startsOn: DateTime(2026, 10, 3),
      race: seedRaces[1],
    );

    expect(generation.weeks[0].phase, TrainingCyclePhase.taper);
    expect(generation.weeks[1].phase, TrainingCyclePhase.taper);
    expect(generation.weeks[2].phase, TrainingCyclePhase.raceWeek);
    expect(generation.weeks[3].phase, TrainingCyclePhase.postRaceRecovery);
    expect(generation.plan.description, contains('HYROX Open 备赛'));
  });

  test('不匹配训练目标的赛事不会改写四周基础周期', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
    );
    final FourWeekPlanGeneration generation = FourWeekPlanGenerator().generate(
      profile: profile,
      startsOn: DateTime(2026, 10, 3),
      race: seedRaces[1],
    );

    expect(generation.weeks.first.phase, TrainingCyclePhase.baseline);
    expect(generation.plan.description, isNot(contains('HYROX Open 备赛')));
  });

  test('Skill 偏好只生成六练且通过完整动作与安全审计', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.marathon],
      weeklyTrainingDays: 7,
      dailyAvailableMinutes: 60,
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
    );
    const List<PlanSessionPreference> sessions = <PlanSessionPreference>[
      PlanSessionPreference(
        trainingType: TrainingType.easyRun,
        durationMinutes: 45,
        intensityBand: PlanIntensityBand.easy,
        focusCodes: <String>['aerobic_base'],
      ),
      PlanSessionPreference(
        trainingType: TrainingType.strength,
        durationMinutes: 45,
        intensityBand: PlanIntensityBand.moderate,
        focusCodes: <String>['lower_body_strength'],
      ),
      PlanSessionPreference(
        trainingType: TrainingType.tempoRun,
        durationMinutes: 50,
        intensityBand: PlanIntensityBand.challenging,
        focusCodes: <String>['threshold'],
      ),
      PlanSessionPreference(
        trainingType: TrainingType.mobility,
        durationMinutes: 30,
        intensityBand: PlanIntensityBand.recovery,
        focusCodes: <String>['recovery'],
      ),
      PlanSessionPreference(
        trainingType: TrainingType.longRun,
        durationMinutes: 60,
        intensityBand: PlanIntensityBand.moderate,
        focusCodes: <String>['long_endurance'],
      ),
      PlanSessionPreference(
        trainingType: TrainingType.intervalRun,
        durationMinutes: 40,
        intensityBand: PlanIntensityBand.challenging,
        focusCodes: <String>['speed'],
      ),
    ];

    final FourWeekPlanGeneration generation = FourWeekPlanGenerator().generate(
      profile: profile,
      startsOn: DateTime(2026, 7, 13),
      preferences: const PlanGenerationPreferences(
        generationId: 'artifact-1',
        cycleFocus: 'base',
        progressionMode: PlanProgressionMode.conservative,
        weeklySessions: sessions,
      ),
    );
    final fullAudit = TrainingRuleAuditService().buildReport(
      generation.plan,
      exercises: seedExercises,
      availableMinutes: profile.dailyAvailableMinutes,
    );
    final safetyAudit =
        TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
      plan: generation.plan,
      profile: profile,
    );

    expect(generation.plan.workoutDays, hasLength(24));
    expect(fullAudit.failCount, 0,
        reason: fullAudit.items
            .where((item) => item.severity.name == 'fail')
            .map((item) => item.description)
            .join('\n'));
    expect(safetyAudit.canActivate, isTrue,
        reason: safetyAudit.failures.join('\n'));
    final int peakMinutes = generation.weeks
        .take(3)
        .map((week) => week.workouts.fold<int>(
              0,
              (total, workout) => total + workout.estimatedMinutes,
            ))
        .reduce((first, second) => first > second ? first : second);
    final int deloadMinutes = generation.weeks.last.workouts.fold<int>(
      0,
      (total, workout) => total + workout.estimatedMinutes,
    );
    expect(deloadMinutes / peakMinutes, closeTo(0.55, 0.02));
    final List<int> hardOrdinals = generation.plan.workoutDays
        .where((WorkoutDay workout) => workout.intensity.contains('7'))
        .map((WorkoutDay workout) =>
            (workout.weekIndex - 1) * 7 + workout.dayIndex)
        .toList()
      ..sort();
    for (int index = 1; index < hardOrdinals.length; index += 1) {
      expect(hardOrdinals[index] - hardOrdinals[index - 1],
          greaterThanOrEqualTo(3));
    }
    for (int weekIndex = 2; weekIndex <= 3; weekIndex += 1) {
      final previous = generation.weeks[weekIndex - 2].workouts;
      final current = generation.weeks[weekIndex - 1].workouts;
      for (int session = 0; session < current.length; session += 1) {
        final bool durationChanged = previous[session].estimatedMinutes !=
            current[session].estimatedMinutes;
        final bool intensityChanged =
            previous[session].intensity != current[session].intensity;
        expect(durationChanged && intensityChanged, isFalse);
      }
    }
  });

  test('Skill 无器械计划会在本地替换负重动作', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
      weeklyTrainingDays: 2,
      dailyAvailableMinutes: 50,
      equipmentAccessType: EquipmentAccessType.none,
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
    );
    final FourWeekPlanGeneration generation = FourWeekPlanGenerator().generate(
      profile: profile,
      startsOn: DateTime(2026, 7, 13),
      preferences: const PlanGenerationPreferences(
        generationId: 'artifact-no-equipment',
        cycleFocus: 'base',
        progressionMode: PlanProgressionMode.conservative,
        weeklySessions: <PlanSessionPreference>[
          PlanSessionPreference(
            trainingType: TrainingType.strength,
            durationMinutes: 45,
            intensityBand: PlanIntensityBand.moderate,
            focusCodes: <String>['full_body_strength'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.mobility,
            durationMinutes: 30,
            intensityBand: PlanIntensityBand.recovery,
            focusCodes: <String>['recovery'],
          ),
        ],
      ),
    );
    final Set<String> exerciseIds = generation.plan.workoutDays
        .expand((WorkoutDay day) => day.workoutExercises)
        .map((link) => link.exerciseId)
        .toSet();

    expect(exerciseIds, isNot(contains('exercise-goblet-squat')));
    expect(exerciseIds, isNot(contains('exercise-rdl')));
    expect(
      generation.plan.workoutDays
          .any((WorkoutDay day) => day.coachNotes.contains('无器械替代已生效')),
      isTrue,
    );
  });

  test('本地编译器以不同斜率消费保守与平衡进阶模式', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.marathon],
      weeklyTrainingDays: 1,
      dailyAvailableMinutes: 60,
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
    );
    FourWeekPlanGeneration generate(PlanProgressionMode mode) =>
        FourWeekPlanGenerator().generate(
          profile: profile,
          startsOn: DateTime(2026, 7, 13),
          preferences: PlanGenerationPreferences(
            generationId: mode.name,
            cycleFocus: 'base',
            progressionMode: mode,
            weeklySessions: const <PlanSessionPreference>[
              PlanSessionPreference(
                trainingType: TrainingType.easyRun,
                durationMinutes: 60,
                intensityBand: PlanIntensityBand.easy,
                focusCodes: <String>['aerobic_base'],
              ),
            ],
          ),
        );
    final FourWeekPlanGeneration conservative =
        generate(PlanProgressionMode.conservative);
    final FourWeekPlanGeneration balanced =
        generate(PlanProgressionMode.balanced);
    final int conservativeRise =
        conservative.weeks[2].workouts.single.estimatedMinutes -
            conservative.weeks.first.workouts.single.estimatedMinutes;
    final int balancedRise =
        balanced.weeks[2].workouts.single.estimatedMinutes -
            balanced.weeks.first.workouts.single.estimatedMinutes;

    expect(conservativeRise, lessThan(balancedRise));
  });

  test('Skill 三练两挑战课会排到至少间隔两个完整日', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.marathon],
      weeklyTrainingDays: 3,
      dailyAvailableMinutes: 60,
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
    );
    final FourWeekPlanGeneration generation = FourWeekPlanGenerator().generate(
      profile: profile,
      startsOn: DateTime(2026, 7, 13),
      preferences: const PlanGenerationPreferences(
        generationId: 'artifact-three-days',
        cycleFocus: 'base',
        progressionMode: PlanProgressionMode.conservative,
        weeklySessions: <PlanSessionPreference>[
          PlanSessionPreference(
            trainingType: TrainingType.tempoRun,
            durationMinutes: 45,
            intensityBand: PlanIntensityBand.challenging,
            focusCodes: <String>['threshold'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.intervalRun,
            durationMinutes: 40,
            intensityBand: PlanIntensityBand.challenging,
            focusCodes: <String>['speed'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.easyRun,
            durationMinutes: 45,
            intensityBand: PlanIntensityBand.easy,
            focusCodes: <String>['aerobic_base'],
          ),
        ],
      ),
    );
    final report = TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
      plan: generation.plan,
      profile: profile,
    );

    expect(report.canActivate, isTrue, reason: report.failures.join('\n'));
  });

  test('临近赛事时本地阶段覆盖可调整多变量且仍通过安全上限', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.hyrox],
      weeklyTrainingDays: 4,
      dailyAvailableMinutes: 60,
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
    );
    final FourWeekPlanGeneration generation = FourWeekPlanGenerator().generate(
      profile: profile,
      startsOn: DateTime(2026, 10, 3),
      race: seedRaces[1],
      preferences: const PlanGenerationPreferences(
        generationId: 'artifact-race',
        cycleFocus: 'taper',
        progressionMode: PlanProgressionMode.conservative,
        weeklySessions: <PlanSessionPreference>[
          PlanSessionPreference(
            trainingType: TrainingType.easyRun,
            durationMinutes: 45,
            intensityBand: PlanIntensityBand.easy,
            focusCodes: <String>['aerobic_base'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.strength,
            durationMinutes: 45,
            intensityBand: PlanIntensityBand.moderate,
            focusCodes: <String>['full_body_strength'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.hyrox,
            durationMinutes: 50,
            intensityBand: PlanIntensityBand.challenging,
            focusCodes: <String>['hyrox_transition'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.mobility,
            durationMinutes: 30,
            intensityBand: PlanIntensityBand.recovery,
            focusCodes: <String>['recovery'],
          ),
        ],
      ),
    );
    final report = TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
      plan: generation.plan,
      profile: profile,
      enforceFourWeekDeload: false,
      racePhaseOverride: true,
    );

    expect(report.canActivate, isTrue, reason: report.failures.join('\n'));
  });

  test('ABC strength 片段在本地生成推拉腿分化并完成四周渐进减量', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
      weeklyTrainingDays: 4,
      dailyAvailableMinutes: 60,
      equipmentAccessType: EquipmentAccessType.gym,
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
    );
    final FourWeekPlanGeneration generation = FourWeekPlanGenerator().generate(
      profile: profile,
      startsOn: DateTime(2026, 7, 13),
      preferences: const PlanGenerationPreferences(
        generationId: 'artifact-abc-strength',
        cycleFocus: 'base',
        progressionMode: PlanProgressionMode.balanced,
        generationMethod: PlanGenerationMethod.abcStrengthCycle,
        weeklySessions: <PlanSessionPreference>[
          PlanSessionPreference(
            trainingType: TrainingType.strength,
            durationMinutes: 50,
            intensityBand: PlanIntensityBand.moderate,
            focusCodes: <String>['upper_body_strength'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.strength,
            durationMinutes: 50,
            intensityBand: PlanIntensityBand.moderate,
            focusCodes: <String>['upper_body_strength'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.mobility,
            durationMinutes: 30,
            intensityBand: PlanIntensityBand.easy,
            focusCodes: <String>['recovery'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.strength,
            durationMinutes: 50,
            intensityBand: PlanIntensityBand.moderate,
            focusCodes: <String>['lower_body_strength'],
          ),
        ],
      ),
    );

    final List<WorkoutDay> firstWeekStrength = generation.weeks.first.workouts
        .where((WorkoutDay item) => item.trainingType == TrainingType.strength)
        .toList();
    expect(
      firstWeekStrength.map((WorkoutDay item) => item.title).join('、'),
      allOf(contains('ABC 推'), contains('ABC 拉'), contains('ABC 腿')),
    );

    for (final String titlePart in <String>['ABC 推', 'ABC 拉', 'ABC 腿']) {
      final List<WorkoutDay> sameSession = generation.weeks
          .map(
            (GeneratedPlanWeek week) => week.workouts.firstWhere(
              (WorkoutDay item) => item.title.contains(titlePart),
            ),
          )
          .toList();
      final Set<String> firstExerciseIds = sameSession.first.workoutExercises
          .map((WorkoutExerciseLink item) => item.exerciseId)
          .toSet();
      for (final WorkoutDay workout in sameSession.skip(1)) {
        expect(
          workout.workoutExercises
              .map((WorkoutExerciseLink item) => item.exerciseId)
              .toSet(),
          firstExerciseIds,
        );
      }
      expect(
        sameSession.take(3).map((WorkoutDay item) => item.estimatedMinutes),
        everyElement(sameSession.first.estimatedMinutes),
      );
    }

    final List<int> repetitions =
        generation.weeks.map((GeneratedPlanWeek week) {
      final WorkoutDay push = week.workouts.firstWhere(
        (WorkoutDay item) => item.title.contains('ABC 推'),
      );
      return push.workoutExercises
          .firstWhere(
            (WorkoutExerciseLink item) =>
                item.module == WorkoutExerciseModule.mainTraining,
          )
          .repetitionsPerSet;
    }).toList();
    expect(repetitions, const <int>[12, 10, 8, 10]);

    final fullAudit = TrainingRuleAuditService().buildReport(
      generation.plan,
      exercises: seedExercises,
      availableMinutes: profile.dailyAvailableMinutes,
    );
    final safetyAudit =
        TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
      plan: generation.plan,
      profile: profile,
    );
    expect(fullAudit.failCount, 0,
        reason: fullAudit.items
            .where((item) => item.severity.name == 'fail')
            .map((item) => item.description)
            .join('\n'));
    expect(safetyAudit.canActivate, isTrue,
        reason: safetyAudit.failures.join('\n'));
  });

  test('ABC 计划在无器械条件下由本地规则降级且不保留 ABC 动作分化', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
      weeklyTrainingDays: 2,
      dailyAvailableMinutes: 50,
      equipmentAccessType: EquipmentAccessType.none,
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
    );
    final FourWeekPlanGeneration generation = FourWeekPlanGenerator().generate(
      profile: profile,
      startsOn: DateTime(2026, 7, 13),
      preferences: const PlanGenerationPreferences(
        generationId: 'artifact-abc-no-equipment',
        cycleFocus: 'base',
        progressionMode: PlanProgressionMode.conservative,
        generationMethod: PlanGenerationMethod.abcStrengthCycle,
        weeklySessions: <PlanSessionPreference>[
          PlanSessionPreference(
            trainingType: TrainingType.strength,
            durationMinutes: 45,
            intensityBand: PlanIntensityBand.moderate,
            focusCodes: <String>['full_body_strength'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.mobility,
            durationMinutes: 30,
            intensityBand: PlanIntensityBand.easy,
            focusCodes: <String>['recovery'],
          ),
        ],
      ),
    );
    final safetyAudit =
        TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
      plan: generation.plan,
      profile: profile,
    );

    expect(
      generation.plan.workoutDays
          .any((WorkoutDay item) => item.title.contains('ABC')),
      isFalse,
    );
    expect(safetyAudit.canActivate, isTrue,
        reason: safetyAudit.failures.join('\n'));
  });

  test('ABC 六次力量课重复推拉腿时仍保留休息日并通过专用审计', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
      weeklyTrainingDays: 6,
      dailyAvailableMinutes: 60,
      equipmentAccessType: EquipmentAccessType.gym,
      trainingExperienceLevel: TrainingExperienceLevel.advanced,
    );
    final FourWeekPlanGeneration generation = FourWeekPlanGenerator().generate(
      profile: profile,
      startsOn: DateTime(2026, 7, 13),
      preferences: const PlanGenerationPreferences(
        generationId: 'artifact-abc-six-days',
        cycleFocus: 'base',
        progressionMode: PlanProgressionMode.balanced,
        generationMethod: PlanGenerationMethod.abcStrengthCycle,
        weeklySessions: <PlanSessionPreference>[
          PlanSessionPreference(
            trainingType: TrainingType.strength,
            durationMinutes: 50,
            intensityBand: PlanIntensityBand.easy,
            focusCodes: <String>['upper_body_strength'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.strength,
            durationMinutes: 50,
            intensityBand: PlanIntensityBand.moderate,
            focusCodes: <String>['upper_body_strength'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.strength,
            durationMinutes: 50,
            intensityBand: PlanIntensityBand.moderate,
            focusCodes: <String>['lower_body_strength'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.strength,
            durationMinutes: 50,
            intensityBand: PlanIntensityBand.moderate,
            focusCodes: <String>['upper_body_strength'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.strength,
            durationMinutes: 50,
            intensityBand: PlanIntensityBand.moderate,
            focusCodes: <String>['upper_body_strength'],
          ),
          PlanSessionPreference(
            trainingType: TrainingType.strength,
            durationMinutes: 50,
            intensityBand: PlanIntensityBand.moderate,
            focusCodes: <String>['lower_body_strength'],
          ),
        ],
      ),
    );
    final safetyAudit =
        TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
      plan: generation.plan,
      profile: profile,
    );

    expect(generation.weeks.first.workouts, hasLength(6));
    expect(
      generation.weeks.first.workouts.map((WorkoutDay item) => item.dayIndex),
      isNot(contains(4)),
    );
    expect(safetyAudit.canActivate, isTrue,
        reason: safetyAudit.failures.join('\n'));
  });
}
