import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/generated_training_plan.dart';
import 'package:trainflow_ai/data/models/plan_generation_context_snapshot.dart';
import 'package:trainflow_ai/data/models/plan_revision_trigger_snapshot.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/training_plan.dart';
import 'package:trainflow_ai/data/models/training_schedule.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';

void main() {
  test('从真实训练日志计算完成次数和过期漏练次数', () {
    final DateTime now = DateTime(2026, 8, 10, 12);
    final GeneratedPlanVersion version = _version();
    final PlanRevisionTriggerSnapshot snapshot =
        const PlanRevisionTriggerService().evaluate(
      activeVersion: version,
      schedule: <ScheduledWorkout>[
        _scheduled('w1', DateTime(2026, 8, 7)),
        _scheduled('w2', DateTime(2026, 8, 8)),
        _scheduled('w3', DateTime(2026, 8, 9)),
      ],
      logs: <TrainingLog>[
        _log('w1', DateTime(2026, 8, 7), completed: true),
      ],
      currentEquipmentCodes: const <String>['bodyweight'],
      currentRace: null,
      latestWeeklyReport: null,
      now: now,
    );

    expect(snapshot.completedSessions, 1);
    expect(snapshot.missedSessions, 2);
    expect(snapshot.shouldSuggest, isTrue);
    expect(snapshot.reasonCodes, contains('consecutive_missed'));
  });

  test('疼痛记录只形成本地安全建议且不允许云端重排', () {
    final DateTime now = DateTime(2026, 8, 10, 12);
    final PlanRevisionTriggerSnapshot snapshot =
        const PlanRevisionTriggerService().evaluate(
      activeVersion: _version(),
      schedule: const <ScheduledWorkout>[],
      logs: <TrainingLog>[
        _log(
          'w1',
          DateTime(2026, 8, 9),
          completed: false,
          painNote: '膝部疼痛',
        ),
      ],
      currentEquipmentCodes: const <String>['bodyweight'],
      currentRace: null,
      latestWeeklyReport: null,
      now: now,
    );

    expect(snapshot.localSafetyOnly, isTrue);
    expect(snapshot.reasonCodes, contains('pain_red_line'));
    expect(snapshot.shouldSuggest, isTrue);
  });
}

GeneratedPlanVersion _version() {
  final List<WorkoutDay> workouts = <WorkoutDay>[
    _workout('w1', 1),
    _workout('w2', 2),
    _workout('w3', 3),
  ];
  final TrainingPlan plan = TrainingPlan(
    id: 'plan-1',
    title: '测试计划',
    description: '',
    sportType: MainSport.generalFitness,
    level: '基础',
    durationWeeks: 4,
    goal: '保持训练',
    weeklyStructure: '每周 3 练',
    workoutDays: workouts,
    evidenceSources: const [],
    createdAt: DateTime(2026, 8, 1),
    updatedAt: DateTime(2026, 8, 1),
  );
  return GeneratedPlanVersion(
    id: 'version-1',
    plan: plan,
    weekPhases: const <String>[],
    source: GeneratedPlanSource.skillAi,
    createdAt: DateTime(2026, 8, 1),
    activatedAt: DateTime(2026, 8, 1),
    inputDigest: 'digest',
    artifactId: 'artifact-1',
    skillRef: null,
    compilerVersion: 'skill-compiler-v2',
    auditSummary: const PlanAuditSummary(
      passCount: 1,
      warningCount: 0,
      failCount: 0,
      blockingReasons: <String>[],
    ),
    generationContextSnapshot: const PlanGenerationContextSnapshot(
      weeklyTrainingDays: 3,
      availableMinutes: 40,
      equipmentCodes: <String>['bodyweight'],
    ),
  );
}

WorkoutDay _workout(String id, int day) => WorkoutDay(
      id: id,
      planId: 'plan-1',
      weekIndex: 1,
      dayIndex: day,
      title: '训练 $day',
      trainingType: TrainingType.strength,
      decisionType: TrainingDecisionType.normal,
      estimatedMinutes: 40,
      intensity: 'RPE 5',
      foamRollingSteps: const [],
      dynamicStretchSteps: const [],
      activationSteps: const [],
      warmupSteps: const [],
      mainSets: const [],
      accessoryWork: const [],
      cooldownSteps: const [],
      coachNotes: '',
      evidenceSources: const [],
    );

ScheduledWorkout _scheduled(String workoutId, DateTime date) =>
    ScheduledWorkout(
      id: 'schedule-$workoutId',
      workoutDayId: workoutId,
      scheduledDate: date,
      startMinute: 18 * 60,
      allocatedMinutes: 40,
      period: TrainingTimePeriod.evening,
      version: ScheduledWorkoutVersion.full,
    );

TrainingLog _log(
  String workoutId,
  DateTime date, {
  required bool completed,
  String? painNote,
}) =>
    TrainingLog(
      id: 'log-$workoutId',
      workoutDayId: workoutId,
      date: date,
      completed: completed,
      rpe: 5,
      fatigueLevel: 4,
      sleepQuality: 4,
      painNote: painNote,
      userNote: null,
      createdAt: date,
    );
