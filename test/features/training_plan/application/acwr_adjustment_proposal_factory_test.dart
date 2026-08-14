import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/models/training_plan.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/seed/seed_training_plans.dart';
import 'package:trainflow_ai/features/training_plan/application/adjustment_proposal_controller.dart';
import 'package:trainflow_ai/services/training_metrics_engine.dart';

void main() {
  const AcwrAdjustmentProposalFactory factory = AcwrAdjustmentProposalFactory();
  final DateTime now = DateTime(2026, 7, 15, 12);

  test('ACWR 1.6 为下周高强度训练生成明确 RPE 降一级预览', () {
    final TrainingPlan plan = _planWithNextWeek(
      <WorkoutDay>[
        _nextWeekWorkout(
          id: 'day-easy',
          dayIndex: 1,
          type: TrainingType.easyRun,
          minutes: 45,
          intensity: 'RPE 4-5',
        ),
        _nextWeekWorkout(
          id: 'day-tempo',
          dayIndex: 2,
          type: TrainingType.tempoRun,
          minutes: 60,
          intensity: 'RPE 6-7',
        ),
      ],
    );

    final AdjustmentProposal? proposal = factory.build(
      metrics: <MetricAggregate>[_acwrMetric(value: 1.6)],
      plan: plan,
      athleteProfileId: 'athlete-a',
      now: now,
    );

    expect(proposal, isNotNull);
    expect(proposal!.workoutDayId, 'day-tempo');
    expect(proposal.originalMinutes, 60);
    expect(proposal.adjustedMinutes, 60);
    expect(proposal.originalIntensity, 'RPE 6-7');
    expect(proposal.adjustedIntensity, 'RPE 5-6');
    expect(proposal.status, AdjustmentProposalStatus.proposed);
    expect(proposal.triggerAlgorithmVersion,
        TrainingMetricsEngine.acwrAlgorithmVersion);
  });

  test('没有可明确降级的高强度项时只生成下周总量降低 10% 预览', () {
    final TrainingPlan plan = _planWithNextWeek(
      <WorkoutDay>[
        _nextWeekWorkout(
          id: 'day-easy',
          dayIndex: 1,
          type: TrainingType.easyRun,
          minutes: 40,
          intensity: 'RPE 4-5',
        ),
        _nextWeekWorkout(
          id: 'day-strength',
          dayIndex: 2,
          type: TrainingType.strength,
          minutes: 60,
          intensity: 'RPE 6',
        ),
      ],
    );

    final AdjustmentProposal? proposal = factory.build(
      metrics: <MetricAggregate>[_acwrMetric(value: 1.6)],
      plan: plan,
      athleteProfileId: 'athlete-a',
      now: now,
    );

    expect(proposal, isNotNull);
    expect(proposal!.workoutDayId, isNull);
    expect(proposal.workoutTitle, '下周训练总目标');
    expect(proposal.originalMinutes, 100);
    expect(proposal.adjustedMinutes, 90);
    expect(proposal.explanation, contains('降低 10%'));
    expect(proposal.workoutChanges, hasLength(2));
    expect(
      proposal.workoutChanges.fold<int>(
        0,
        (int total, AdjustmentProposalWorkoutChange change) =>
            total + change.adjustedMinutes,
      ),
      90,
    );
    expect(
      proposal.workoutChanges.every(
        (AdjustmentProposalWorkoutChange change) =>
            change.adjustedMinutes >= 5 &&
            change.adjustedMinutes <= change.originalMinutes,
      ),
      isTrue,
    );
  });

  test('低 ACWR、未验证完整窗口或过期指标均不生成建议', () {
    final TrainingPlan plan = _planWithNextWeek(
      <WorkoutDay>[
        _nextWeekWorkout(
          id: 'day-tempo',
          dayIndex: 1,
          type: TrainingType.tempoRun,
          minutes: 60,
          intensity: 'RPE 6-7',
        ),
      ],
    );

    expect(
      factory.build(
        metrics: <MetricAggregate>[_acwrMetric(value: 1.5)],
        plan: plan,
        athleteProfileId: 'athlete-a',
        now: now,
      ),
      isNull,
    );
    expect(
      factory.build(
        metrics: <MetricAggregate>[
          _acwrMetric(
            id: 'older-high',
            value: 1.7,
            computedAt: DateTime(2026, 7, 15, 9),
          ),
          _acwrMetric(
            id: 'newer-low',
            value: 1.2,
            computedAt: DateTime(2026, 7, 15, 11),
          ),
        ],
        plan: plan,
        athleteProfileId: 'athlete-a',
        now: now,
      ),
      isNull,
    );
    expect(
      factory.build(
        metrics: <MetricAggregate>[
          _acwrMetric(value: 1.6, windowCoverageVerified: false),
        ],
        plan: plan,
        athleteProfileId: 'athlete-a',
        now: now,
      ),
      isNull,
    );
    expect(
      factory.build(
        metrics: <MetricAggregate>[
          _acwrMetric(
            value: 1.6,
            periodStart: DateTime(2026, 6, 22),
          ),
        ],
        plan: plan,
        athleteProfileId: 'athlete-a',
        now: now,
      ),
      isNull,
    );
  });
}

TrainingPlan _planWithNextWeek(List<WorkoutDay> nextWeek) {
  final TrainingPlan base = seedTrainingPlans.first;
  return base.copyWith(
    id: 'plan-a',
    workoutDays: <WorkoutDay>[
      base.workoutDays.first.copyWith(
        id: 'day-current',
        planId: 'plan-a',
        weekIndex: 1,
      ),
      ...nextWeek,
    ],
  );
}

WorkoutDay _nextWeekWorkout({
  required String id,
  required int dayIndex,
  required TrainingType type,
  required int minutes,
  required String intensity,
}) {
  return seedTrainingPlans.first.workoutDays.first.copyWith(
    id: id,
    planId: 'plan-a',
    weekIndex: 2,
    dayIndex: dayIndex,
    title: id,
    trainingType: type,
    estimatedMinutes: minutes,
    intensity: intensity,
  );
}

MetricAggregate _acwrMetric({
  String id = 'metric-acwr',
  required double value,
  bool windowCoverageVerified = true,
  DateTime? periodStart,
  DateTime? computedAt,
}) {
  return MetricAggregate(
    id: id,
    athleteProfileId: 'athlete-a',
    metricCode: 'acwr.session_rpe',
    period: MetricPeriod.week,
    periodStart: periodStart ?? DateTime(2026, 7, 13),
    value: value,
    unit: 'ratio',
    sampleCount: 28,
    sampleDurationSeconds: 120000,
    coverage: 1,
    status: MetricStatus.ready,
    algorithmVersion: TrainingMetricsEngine.acwrAlgorithmVersion,
    inputFingerprint: 'acwr-input',
    computedAt: computedAt ?? DateTime(2026, 7, 15, 10),
    loadMethod: LoadMethod.sessionRpe,
    metadata: <String, Object?>{
      'windowCoverageVerified': windowCoverageVerified,
      'acuteTotal': 2100.0,
      'chronicTotal': 2800.0,
      'reason': '同口径完整窗口。',
    },
  );
}
