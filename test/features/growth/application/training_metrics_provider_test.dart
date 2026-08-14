import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/models/training_schedule.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/features/growth/application/training_metrics_projection_service.dart';
import 'package:trainflow_ai/features/growth/application/training_metrics_provider.dart';
import 'package:trainflow_ai/services/training_metrics_engine.dart';

void main() {
  test('仓储 Provider 可被 SQLite 实现覆盖，查询层只依赖抽象接口', () async {
    final InMemoryTrainingMetricsRepository repository =
        InMemoryTrainingMetricsRepository();
    await repository.saveAggregate(_aggregate());
    final ProviderContainer container = ProviderContainer(
      overrides: [
        trainingMetricsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    const TrainingMetricsQuery query = TrainingMetricsQuery(
      athleteProfileId: 'athlete-1',
      period: MetricPeriod.week,
    );

    final List<MetricAggregate> metrics =
        await container.read(trainingMetricAggregatesProvider(query).future);

    expect(metrics, hasLength(1));
    expect(metrics.single.metricCode, 'weekly_consistency');
  });

  test('兼容计划没有明确日期时不推测 0% 或 100%', () {
    final L1DashboardProjection projection =
        const TrainingMetricsProjectionService().project(
      logs: const [],
      scheduledTodayWorkout: null,
      metrics: const [],
      now: DateTime(2026, 7, 15, 12),
    );

    expect(projection.weeklyConsistencyLabel, '暂无可计算计划');
    expect(projection.todayDecisionLabel, '暂无可计算计划');
    expect(projection.weeklyConsistencyLabel, isNot(anyOf('0%', '100%')));
    expect(projection.calculationBasis, contains('未猜测'));
  });

  test('旧排期即使有明确日期，缺少主目标时仍保持待核对', () {
    final DateTime now = DateTime(2026, 7, 15, 12);
    final L1DashboardProjection projection =
        const TrainingMetricsProjectionService().project(
      logs: const [],
      scheduledTodayWorkout: ScheduledWorkout(
        id: 'schedule-1',
        workoutDayId: 'workout-1',
        scheduledDate: now,
        startMinute: 18 * 60,
        allocatedMinutes: 45,
        period: TrainingTimePeriod.evening,
        version: ScheduledWorkoutVersion.full,
      ),
      metrics: const [],
      now: now,
    );

    expect(projection.todayDecisionLabel, '待核对主目标');
    expect(projection.calculationBasis, contains('primary_target_kind'));
  });

  test('成长证据尚未同步时使用真实用户资料 ID，不切换到硬编码用户', () {
    final String athleteProfileId = resolveTrainingMetricsAthleteProfileId(
      growthEvidenceAthleteProfileId: '',
      profileAthleteProfileId: 'user-local-demo',
    );

    expect(athleteProfileId, 'user-local-demo');
    expect(athleteProfileId, isNot('local-athlete'));
  });

  test('本周排期按 90% 与 50% 阈值计算一致性和今日判定', () {
    final DateTime now = DateTime(2026, 7, 16, 20);
    final List<ScheduledWorkout> workouts = <ScheduledWorkout>[
      _scheduled('schedule-1', 'day-1', DateTime(2026, 7, 13), 60),
      _scheduled('schedule-2', 'day-2', DateTime(2026, 7, 16), 60),
    ];
    final L1DashboardProjection projection =
        const TrainingMetricsProjectionService().project(
      logs: <TrainingLog>[
        _log('log-1', 'day-1', DateTime(2026, 7, 13, 9), 54),
        _log('log-2', 'day-2', DateTime(2026, 7, 16, 19), 30),
      ],
      scheduledTodayWorkout: workouts.last,
      scheduledWeekWorkouts: workouts,
      metrics: const <MetricAggregate>[],
      now: now,
    );

    expect(projection.weeklyConsistencyLabel, '50%');
    expect(projection.todayDecisionLabel, '部分完成');
    expect(projection.calculationBasis, contains('90%/50%'));
  });

  test('同一训练日志只匹配一个计划项，计划日未结束时保持待训练', () {
    final DateTime today = DateTime(2026, 7, 15);
    final List<ScheduledWorkout> duplicatePlans = <ScheduledWorkout>[
      _scheduled('schedule-1', 'day-1', today, 60),
      _scheduled('schedule-2', 'day-1', today, 60),
    ];
    final L1DashboardProjection pending =
        const TrainingMetricsProjectionService().project(
      logs: const <TrainingLog>[],
      scheduledTodayWorkout: duplicatePlans.first,
      scheduledWeekWorkouts: duplicatePlans,
      metrics: const <MetricAggregate>[],
      now: DateTime(2026, 7, 15, 12),
    );
    expect(pending.weeklyConsistencyLabel, '数据积累中');
    expect(pending.todayDecisionLabel, '待训练');

    final L1DashboardProjection afterDay =
        const TrainingMetricsProjectionService().project(
      logs: <TrainingLog>[
        _log('log-1', 'day-1', DateTime(2026, 7, 15, 9), 60),
      ],
      scheduledTodayWorkout: null,
      scheduledWeekWorkouts: duplicatePlans,
      metrics: const <MetricAggregate>[],
      now: DateTime(2026, 7, 16, 12),
    );
    expect(afterDay.weeklyConsistencyLabel, '50%');
  });

  test('新训练日志优先用独立 planItemId 匹配，不依赖训练日 ID', () {
    final ScheduledWorkout scheduled = _scheduled(
        'schedule-explicit', 'day-planned', DateTime(2026, 7, 15), 60);
    final List<ScheduledWorkoutEvaluation> evaluations =
        const TrainingMetricsProjectionService().evaluateSchedule(
      workouts: <ScheduledWorkout>[scheduled],
      logs: <TrainingLog>[
        _log(
          'log-explicit',
          'day-from-player',
          DateTime(2026, 7, 15, 9),
          60,
          planItemId: 'schedule-explicit',
        ),
      ],
      now: DateTime(2026, 7, 15, 20),
      engine: TrainingMetricsEngine(),
    );

    expect(evaluations.single.matchedLog?.id, 'log-explicit');
    expect(evaluations.single.matchingBasis, contains('match=plan_item_id'));
    expect(
      evaluations.single.result.status,
      WorkoutCompletionStatus.completed,
    );
  });

  test('已持久化周一致性优先于本地兼容投影', () {
    final DateTime now = DateTime(2026, 7, 16, 20);
    final List<ScheduledWorkout> workouts = <ScheduledWorkout>[
      _scheduled('schedule-1', 'day-1', DateTime(2026, 7, 13), 60),
      _scheduled('schedule-2', 'day-2', DateTime(2026, 7, 14), 60),
    ];
    final L1DashboardProjection projection =
        const TrainingMetricsProjectionService().project(
      logs: <TrainingLog>[
        _log('log-1', 'day-1', DateTime(2026, 7, 13, 9), 60),
      ],
      scheduledTodayWorkout: null,
      scheduledWeekWorkouts: workouts,
      metrics: <MetricAggregate>[_aggregate()],
      now: now,
    );

    expect(projection.weeklyConsistencyLabel, '75%');
    expect(projection.calculationBasis, contains('结构化聚合'));
  });

  test('首页优先使用已持久化 L1 判定，人工覆盖改变有效结果', () {
    final DateTime now = DateTime(2026, 7, 15, 20);
    final ScheduledWorkout scheduled =
        _scheduled('schedule-1', 'day-1', DateTime(2026, 7, 15), 60);
    final L1DashboardProjection projection =
        const TrainingMetricsProjectionService().project(
      // 兼容日志若重算会得到已完成，但结构化人工覆盖必须优先。
      logs: <TrainingLog>[
        _log('log-1', 'day-1', DateTime(2026, 7, 15, 9), 60),
      ],
      scheduledTodayWorkout: scheduled,
      scheduledWeekWorkouts: <ScheduledWorkout>[scheduled],
      metrics: const <MetricAggregate>[],
      now: now,
      source: L1ProjectionSource.structured,
      persistedScheduledResults: <ScheduledWorkoutResult>[
        ScheduledWorkoutResult(
          planItemId: 'schedule-1',
          workoutId: 'local-workout-1',
          status: WorkoutCompletionStatus.completed,
          completionRatio: 1,
          evaluatedAt: now,
          algorithmVersion: 'trainmate-l1-completion-v1',
          reason: '结构化系统判定',
          manualStatus: WorkoutCompletionStatus.missed,
          manualReason: '用户确认训练未按计划完成',
        ),
      ],
    );

    expect(projection.weeklyConsistencyLabel, '0%');
    expect(projection.todayDecisionLabel, '未完成');
    expect(projection.calculationBasis, contains('已持久化'));
    expect(projection.calculationBasis, contains('系统原判定仍保留'));
    expect(projection.calculationBasis, isNot(contains('兼容预览')));
  });

  test('结构化快照缺少当前计划项时不猜测一致性', () {
    final DateTime now = DateTime(2026, 7, 15, 20);
    final ScheduledWorkout scheduled =
        _scheduled('schedule-1', 'day-1', DateTime(2026, 7, 15), 60);

    final L1DashboardProjection projection =
        const TrainingMetricsProjectionService().project(
      logs: const <TrainingLog>[],
      scheduledTodayWorkout: scheduled,
      scheduledWeekWorkouts: <ScheduledWorkout>[scheduled],
      metrics: const <MetricAggregate>[],
      now: now,
      source: L1ProjectionSource.structured,
    );

    expect(projection.weeklyConsistencyLabel, '等待结构化判定补齐');
    expect(projection.calculationBasis, contains('暂不给出比例'));
  });
}

ScheduledWorkout _scheduled(
  String id,
  String workoutDayId,
  DateTime date,
  int targetMinutes,
) {
  return ScheduledWorkout(
    id: id,
    workoutDayId: workoutDayId,
    scheduledDate: date,
    startMinute: 8 * 60,
    allocatedMinutes: targetMinutes,
    period: TrainingTimePeriod.morning,
    version: ScheduledWorkoutVersion.full,
    discipline: WorkoutDiscipline.roadRun,
    primaryTargetKind: CompletionTargetKind.duration,
    targetMinutes: targetMinutes,
  );
}

TrainingLog _log(
  String id,
  String workoutDayId,
  DateTime date,
  int actualMinutes, {
  String? planItemId,
}) {
  return TrainingLog(
    id: id,
    workoutDayId: workoutDayId,
    planItemId: planItemId,
    date: date,
    completed: true,
    rpe: 5,
    fatigueLevel: 2,
    sleepQuality: 4,
    painNote: null,
    userNote: null,
    createdAt: date,
    kind: TrainingLogKind.sessionReview,
    actualDurationMinutes: actualMinutes,
  );
}

MetricAggregate _aggregate() {
  return MetricAggregate(
    id: 'metric-1',
    athleteProfileId: 'athlete-1',
    metricCode: 'weekly_consistency',
    period: MetricPeriod.week,
    periodStart: DateTime(2026, 7, 13),
    value: 0.75,
    unit: 'ratio',
    sampleCount: 4,
    sampleDurationSeconds: 0,
    coverage: 1,
    status: MetricStatus.ready,
    algorithmVersion: 'test-v1',
    inputFingerprint: 'input-1',
    computedAt: DateTime(2026, 7, 15),
  );
}
