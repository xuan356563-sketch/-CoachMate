import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/exercise_training_profile.dart';
import 'package:trainflow_ai/data/models/health_snapshot.dart';
import 'package:trainflow_ai/data/models/monthly_summary.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/models/weekly_report.dart';
import 'package:trainflow_ai/services/monthly_summary_builder.dart';

void main() {
  const MonthlySummaryBuilder builder = MonthlySummaryBuilder();

  test('生成四个能力维度，并同时给出月环比和月内身体变化', () {
    final MonthlySummary summary = builder.build(
      athleteProfileId: 'athlete-1',
      monthStart: DateTime(2026, 6),
      metricHistory: <MetricAggregate>[
        _metric(
          id: 'hr-may',
          code: 'same_pace_heart_rate',
          periodStart: DateTime(2026, 5, 18),
          value: 152,
          unit: 'bpm',
        ),
        _metric(
          id: 'hr-june-first',
          code: 'same_pace_heart_rate',
          periodStart: DateTime(2026, 6, 1),
          value: 150,
          unit: 'bpm',
        ),
        _metric(
          id: 'hr-june-last',
          code: 'same_pace_heart_rate',
          periodStart: DateTime(2026, 6, 22),
          value: 147,
          unit: 'bpm',
        ),
        _metric(
          id: 'strength-may',
          code: 'strength_e1rm',
          periodStart: DateTime(2026, 5, 18),
          value: 100,
          unit: 'kg',
          metadata: const <String, Object?>{'exerciseKey': 'squat'},
        ),
        _metric(
          id: 'strength-june',
          code: 'strength_e1rm',
          periodStart: DateTime(2026, 6, 22),
          value: 104,
          unit: 'kg',
          metadata: const <String, Object?>{'exerciseKey': 'squat'},
        ),
      ],
      bodyMetrics: <BodyMetric>[
        ..._bodyWindow(DateTime(2026, 5, 25), 71),
        ..._bodyWindow(DateTime(2026, 6, 1), 70),
        ..._bodyWindow(DateTime(2026, 6, 24), 69),
      ],
      healthSnapshots: <HealthSnapshot>[
        _health(DateTime(2026, 6, 24), weight: 99),
      ],
      weeklyReports: <WeeklyReport>[
        _weekly(DateTime(2026, 5, 11), completed: 3, planned: 4),
        _weekly(DateTime(2026, 5, 25), completed: 3, planned: 4),
        _weekly(DateTime(2026, 6, 8), completed: 4, planned: 4),
        _weekly(DateTime(2026, 6, 22), completed: 3, planned: 4),
      ],
    );

    expect(summary.dimensions, hasLength(4));
    expect(
      summary.dimensions.map((MonthlyDimensionSummary item) => item.dimension),
      containsAll(MonthlySummaryDimension.values),
    );
    final MonthlyMetricChange weight = summary.bodyChanges.firstWhere(
      (MonthlyMetricChange item) => item.code == 'weight',
    );
    expect(weight.currentValue, closeTo(69, 0.01));
    expect(weight.monthOverMonthDelta, closeTo(-2, 0.01));
    expect(weight.withinMonthDelta, closeTo(-1, 0.01));
    expect(weight.directionIsNeutral, isTrue);
    expect(summary.inputFingerprint, isNotEmpty);
    final TrainingDimensionExposure strengthExposure =
        summary.trainingDimensionExposure.singleWhere(
      (TrainingDimensionExposure item) =>
          item.dimension == TrainingDimension.strength,
    );
    expect(strengthExposure.plannedSessions, 2);
    expect(strengthExposure.completedSessions, 2);
  });

  test('身体样本不足时保持积累中，不用零值补齐趋势', () {
    final MonthlySummary summary = builder.build(
      athleteProfileId: 'athlete-1',
      monthStart: DateTime(2026, 6),
      metricHistory: const <MetricAggregate>[],
      bodyMetrics: <BodyMetric>[
        _body(DateTime(2026, 6, 2), weight: 70),
        _body(DateTime(2026, 6, 29), weight: 69),
      ],
      healthSnapshots: const <HealthSnapshot>[],
      weeklyReports: const <WeeklyReport>[],
    );

    final MonthlyMetricChange weight = summary.bodyChanges.firstWhere(
      (MonthlyMetricChange item) => item.code == 'weight',
    );
    expect(weight.state, MonthlyChangeState.accumulating);
    expect(weight.monthOverMonthDelta, isNull);
    expect(weight.withinMonthDelta, isNull);
    expect(weight.reason, contains('至少 3 个有效日'));
  });

  test('算法版本或主力动作不同的能力指标不跨口径比较', () {
    final MonthlySummary summary = builder.build(
      athleteProfileId: 'athlete-1',
      monthStart: DateTime(2026, 6),
      metricHistory: <MetricAggregate>[
        _metric(
          id: 'old',
          code: 'strength_e1rm',
          periodStart: DateTime(2026, 5, 20),
          value: 100,
          unit: 'kg',
          algorithmVersion: 'strength-v1',
          metadata: const <String, Object?>{'exerciseKey': 'squat'},
        ),
        _metric(
          id: 'new',
          code: 'strength_e1rm',
          periodStart: DateTime(2026, 6, 20),
          value: 110,
          unit: 'kg',
          algorithmVersion: 'strength-v2',
          metadata: const <String, Object?>{'exerciseKey': 'deadlift'},
        ),
      ],
      bodyMetrics: const <BodyMetric>[],
      healthSnapshots: const <HealthSnapshot>[],
      weeklyReports: const <WeeklyReport>[],
    );

    final MonthlyMetricChange strength = summary.dimensions
        .firstWhere(
          (MonthlyDimensionSummary item) =>
              item.dimension == MonthlySummaryDimension.strength,
        )
        .metrics
        .single;
    expect(strength.state, MonthlyChangeState.accumulating);
    expect(strength.monthOverMonthDelta, isNull);
    expect(strength.reason, contains('口径'));
  });
}

MetricAggregate _metric({
  required String id,
  required String code,
  required DateTime periodStart,
  required double value,
  required String unit,
  String algorithmVersion = 'metric-v1',
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return MetricAggregate(
    id: id,
    athleteProfileId: 'athlete-1',
    metricCode: code,
    period: MetricPeriod.week,
    periodStart: periodStart,
    value: value,
    unit: unit,
    sampleCount: 3,
    sampleDurationSeconds: 3600,
    coverage: 1,
    status: MetricStatus.ready,
    algorithmVersion: algorithmVersion,
    inputFingerprint: 'fingerprint-$id',
    computedAt: periodStart.add(const Duration(days: 6)),
    metadata: metadata,
  );
}

List<BodyMetric> _bodyWindow(DateTime start, double weight) {
  return List<BodyMetric>.generate(
    3,
    (int index) => _body(
      start.add(Duration(days: index)),
      weight: weight,
    ),
  );
}

BodyMetric _body(DateTime date, {required double weight}) {
  return BodyMetric(
    id: 'body-${date.toIso8601String()}',
    measuredAt: date,
    weightKg: weight,
    bodyFatPercentage: 18,
    restingHeartRate: 55,
    hrvMs: 60,
    sleepHours: 7.5,
    fatigueLevel: 2,
    sorenessLevel: 2,
    moodLabel: '稳定',
    source: BodyMetricSource.manual,
    note: '',
  );
}

HealthSnapshot _health(DateTime date, {required double weight}) {
  return HealthSnapshot(
    id: 'health-${date.toIso8601String()}',
    date: date,
    sleepHours: 8,
    restingHeartRate: 50,
    hrvMs: 65,
    weightKg: weight,
    bodyFatPercentage: 17,
    syncedAt: date,
  );
}

WeeklyReport _weekly(
  DateTime generatedAt, {
  required int completed,
  required int planned,
}) {
  return WeeklyReport(
    id: 'weekly-${generatedAt.toIso8601String()}',
    weekLabel: '${generatedAt.month}/${generatedAt.day}',
    generatedAt: generatedAt,
    completedWorkouts: completed,
    plannedWorkouts: planned,
    completionRate: completed / planned,
    loadTrendLabel: '稳定',
    decisionReview: '',
    recoverySummary: '',
    highlights: const <String>[],
    nextWeekFocus: const <String>[],
    dimensionExposure: const <TrainingDimensionExposure>[
      TrainingDimensionExposure(
        dimension: TrainingDimension.strength,
        plannedSessions: 1,
        completedSessions: 1,
      ),
    ],
  );
}
