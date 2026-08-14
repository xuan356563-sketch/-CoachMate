import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/ai_training_prescription.dart';
import 'package:trainflow_ai/data/models/plan_generation_preferences.dart';
import 'package:trainflow_ai/data/models/training_plan.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/models/exercise_training_profile.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'package:trainflow_ai/services/training_prescription_safety_audit_service.dart';

void main() {
  test('经验未知、超时或一周超过两次挑战课会阻断', () {
    final AiTrainingPrescription prescription = _prescription(
      sessions: const <AiSessionBlueprint>[
        AiSessionBlueprint(
          trainingType: TrainingType.tempoRun,
          durationMinutes: 90,
          intensityBand: AiIntensityBand.challenging,
          focusCodes: <String>['speed'],
        ),
        AiSessionBlueprint(
          trainingType: TrainingType.hyrox,
          durationMinutes: 45,
          intensityBand: AiIntensityBand.challenging,
          focusCodes: <String>['hyrox_transition'],
        ),
        AiSessionBlueprint(
          trainingType: TrainingType.intervalRun,
          durationMinutes: 40,
          intensityBand: AiIntensityBand.challenging,
          focusCodes: <String>['speed'],
        ),
      ],
    );
    final profile = InMemoryUserProfileRepository.defaultProfile.copyWith(
      trainingExperienceLevel: TrainingExperienceLevel.unknown,
      dailyAvailableMinutes: 45,
    );

    final report = TrainingPrescriptionSafetyAuditService().auditPrescription(
      prescription: prescription,
      profile: profile,
    );

    expect(report.canActivate, isFalse);
    expect(report.failures, contains(contains('训练经验')));
    expect(report.failures, contains(contains('可用时间')));
    expect(report.failures, contains(contains('挑战强度')));
  });

  test('未成年或档案包含康复目标时不能激活 Skill 计划', () {
    final AiTrainingPrescription prescription = _prescription(
      sessions: const <AiSessionBlueprint>[
        AiSessionBlueprint(
          trainingType: TrainingType.strength,
          durationMinutes: 45,
          intensityBand: AiIntensityBand.moderate,
          focusCodes: <String>['full_body_strength'],
        ),
      ],
    );
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      age: 17,
      mainSports: const <MainSport>[MainSport.strength, MainSport.rehab],
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
      weeklyTrainingDays: 1,
      dailyAvailableMinutes: 60,
    );

    final report = TrainingPrescriptionSafetyAuditService().auditPrescription(
      prescription: prescription,
      profile: profile,
    );

    expect(report.canActivate, isFalse);
    expect(report.failures, contains(contains('18 岁')));
    expect(report.failures, contains(contains('康复目标')));
  });

  test('缺少低强度课、无赛事减量期和初学者平衡进阶均会阻断', () {
    final AiTrainingPrescription prescription = _prescription(
      cycleFocus: 'taper',
      progressionMode: AiProgressionMode.balanced,
      sessions: const <AiSessionBlueprint>[
        AiSessionBlueprint(
          trainingType: TrainingType.strength,
          durationMinutes: 45,
          intensityBand: AiIntensityBand.moderate,
          focusCodes: <String>['full_body_strength'],
        ),
        AiSessionBlueprint(
          trainingType: TrainingType.crossTraining,
          durationMinutes: 45,
          intensityBand: AiIntensityBand.moderate,
          focusCodes: <String>['aerobic_base'],
        ),
        AiSessionBlueprint(
          trainingType: TrainingType.mobility,
          durationMinutes: 30,
          intensityBand: AiIntensityBand.moderate,
          focusCodes: <String>['mobility'],
        ),
      ],
    );
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      trainingExperienceLevel: TrainingExperienceLevel.beginner,
      weeklyTrainingDays: 3,
      dailyAvailableMinutes: 60,
    );

    final report = TrainingPrescriptionSafetyAuditService().auditPrescription(
      prescription: prescription,
      profile: profile,
    );

    expect(report.failures, contains(contains('恢复或轻松')));
    expect(report.failures, contains(contains('没有有效赛事')));
    expect(report.failures, contains(contains('保守进阶')));
  });

  test('编译后计划阻断越界日序和同周重复日序', () {
    final UserProfile profile = _auditProfile();
    final TrainingPlan original = FourWeekPlanGenerator()
        .generate(profile: profile, startsOn: DateTime(2026, 7, 13))
        .plan;
    final List<WorkoutDay> damaged =
        List<WorkoutDay>.from(original.workoutDays);
    final int secondIndex = damaged.indexWhere(
      (WorkoutDay day) =>
          day.weekIndex == damaged.first.weekIndex &&
          day.id != damaged.first.id,
    );
    damaged[secondIndex] = damaged[secondIndex].copyWith(
      dayIndex: damaged.first.dayIndex,
    );
    damaged[2] = damaged[2].copyWith(dayIndex: 8);

    final report = TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
      plan: original.copyWith(workoutDays: damaged),
      profile: profile,
      enforceFourWeekDeload: false,
      racePhaseOverride: true,
    );

    expect(report.failures, contains(contains('1–7')));
    expect(report.failures, contains(contains('重复训练日')));
  });

  test('赛事阶段也不允许训练量暴增或同时提高时长与强度', () {
    final UserProfile profile = _auditProfile();
    final TrainingPlan original = FourWeekPlanGenerator()
        .generate(profile: profile, startsOn: DateTime(2026, 7, 13))
        .plan;
    final List<WorkoutDay> damaged = original.workoutDays
        .map(
          (WorkoutDay day) => day.weekIndex == 2
              ? day.copyWith(estimatedMinutes: 180, intensity: 'RPE 7')
              : day,
        )
        .toList();

    final report = TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
      plan: original.copyWith(workoutDays: damaged),
      profile: profile,
      enforceFourWeekDeload: false,
      racePhaseOverride: true,
    );

    expect(report.failures, contains(contains('训练量增长超过 10%')));
    expect(report.failures, contains(contains('同时推进了时长和强度')));
  });

  test('ABC 编译结果会阻断动作漂移、固定重量和力竭指令', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
      weeklyTrainingDays: 3,
      dailyAvailableMinutes: 60,
      equipmentAccessType: EquipmentAccessType.gym,
    );
    final TrainingPlan original = FourWeekPlanGenerator()
        .generate(
          profile: profile,
          startsOn: DateTime(2026, 7, 13),
          preferences: const PlanGenerationPreferences(
            generationId: 'abc-audit',
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
                trainingType: TrainingType.strength,
                durationMinutes: 50,
                intensityBand: PlanIntensityBand.easy,
                focusCodes: <String>['lower_body_strength'],
              ),
            ],
          ),
        )
        .plan;
    final List<WorkoutDay> damaged = original.workoutDays.map((WorkoutDay day) {
      if (day.weekIndex != 4 || !day.title.contains('ABC 推')) return day;
      final List<WorkoutExerciseLink> links = day.workoutExercises
          .map(
            (WorkoutExerciseLink link) =>
                link.module == WorkoutExerciseModule.mainTraining &&
                        link.sequence ==
                            day.workoutExercises
                                .firstWhere(
                                  (WorkoutExerciseLink item) =>
                                      item.module ==
                                      WorkoutExerciseModule.mainTraining,
                                )
                                .sequence
                    ? link.copyWith(
                        exerciseId: 'exercise-goblet-squat',
                        plannedWeightOrIntensity: '85 公斤做到力竭',
                      )
                    : link,
          )
          .toList();
      return day.copyWith(workoutExercises: links);
    }).toList();

    final report = TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
      plan: original.copyWith(workoutDays: damaged),
      profile: profile,
    );

    expect(report.failures, contains(contains('ABC 动作必须在四周保持稳定')));
    expect(report.failures, contains(contains('固定重量或力竭指令')));
  });

  test('结构计划会阻断爆发动作休息不足和初学者腾空动作', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
      trainingExperienceLevel: TrainingExperienceLevel.beginner,
      weeklyTrainingDays: 2,
      dailyAvailableMinutes: 60,
    );
    final TrainingPlan original = FourWeekPlanGenerator(structureEnabled: true)
        .generate(profile: profile, startsOn: DateTime(2026, 7, 13))
        .plan;
    final WorkoutDay first = original.workoutDays.first;
    final List<WorkoutExerciseLink> damagedLinks = <WorkoutExerciseLink>[
      ...first.workoutExercises,
      const WorkoutExerciseLink(
        id: 'unsafe-jump',
        exerciseId: 'exercise-box-jump',
        sequence: 99,
        module: WorkoutExerciseModule.mainTraining,
        plannedSetCount: 3,
        repetitionsPerSet: 3,
        plannedWeightOrIntensity: '自重',
        restSeconds: 30,
        executionIntent: ExecutionIntent.explosive,
      ),
    ];
    final TrainingPlan damaged = original.copyWith(
      workoutDays: <WorkoutDay>[
        first.copyWith(workoutExercises: damagedLinks),
        ...original.workoutDays.skip(1),
      ],
    );

    final report = TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
      plan: damaged,
      profile: profile,
    );

    expect(report.failures, contains(contains('爆发动作组间休息')));
    expect(report.failures, contains(contains('初学者计划不能包含腾空动作')));
    expect(report.failures, contains(contains('爆发动作必须排在主训练最前')));
  });

  test('结构腿部课会阻断足踝力量提前导致小腿疲劳', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
      weeklyTrainingDays: 2,
      dailyAvailableMinutes: 60,
    );
    final TrainingPlan original = FourWeekPlanGenerator(structureEnabled: true)
        .generate(profile: profile, startsOn: DateTime(2026, 7, 13))
        .plan;
    final WorkoutDay first = original.workoutDays.firstWhere(
      (WorkoutDay day) => day.workoutExercises.any(
        (WorkoutExerciseLink link) =>
            link.exerciseId == 'exercise-single-leg-calf-raise',
      ),
    );
    final List<WorkoutExerciseLink> damagedLinks = first.workoutExercises
        .map(
          (WorkoutExerciseLink link) =>
              link.exerciseId == 'exercise-single-leg-calf-raise'
                  ? link.copyWith(sequence: 1)
                  : link.copyWith(sequence: link.sequence + 1),
        )
        .toList(growable: false);
    final TrainingPlan damaged = original.copyWith(
      workoutDays: <WorkoutDay>[
        for (final WorkoutDay day in original.workoutDays)
          if (day.id == first.id)
            day.copyWith(workoutExercises: damagedLinks)
          else
            day,
      ],
    );

    final report = TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
      plan: damaged,
      profile: profile,
      enforceFourWeekDeload: false,
    );

    expect(report.failures, contains(contains('足踝力量动作必须')));
  });
}

UserProfile _auditProfile() =>
    InMemoryUserProfileRepository.defaultProfile.copyWith(
      mainSports: const <MainSport>[MainSport.marathon],
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
      weeklyTrainingDays: 4,
      dailyAvailableMinutes: 180,
    );

AiTrainingPrescription _prescription({
  required List<AiSessionBlueprint> sessions,
  String cycleFocus = 'base',
  AiProgressionMode progressionMode = AiProgressionMode.conservative,
}) {
  return AiTrainingPrescription(
    cycleFocus: cycleFocus,
    progressionMode: progressionMode,
    weeklySessions: sessions,
    skill: const AiSkillRef(
      id: 'training-plan-builder',
      version: '1.0.0',
      displayName: '训练计划生成器',
      sourceSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      runtimeSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      coverage: 'general',
      selectionReason: '通用规则',
    ),
    generationMeta: const AiGenerationMeta(
      contractVersion: '1.0.0',
      clientContextDigest:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      model: 'deepseek-chat',
      cacheHit: false,
      tokenUsage: 12,
    ),
  );
}
