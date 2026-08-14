import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/trainmate_structured_database_gateway.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/models/training_schedule.dart';
import 'package:trainflow_ai/features/growth/application/local_training_fact_sync.dart';

void main() {
  test('真实 session 原子投影为无外部 UUID 的 workout、L1 判定和力量组次', () async {
    final _RecordingStructuredGateway database = _RecordingStructuredGateway();
    final DateTime now = DateTime(2026, 7, 15, 20);
    final LocalTrainingFactSyncState state =
        await LocalTrainingFactSyncCoordinator(
      database: database,
      clock: () => now,
    ).synchronize(
      athleteProfileId: 'athlete-a',
      logs: <TrainingLog>[
        _log(
          id: 'player-step',
          kind: TrainingLogKind.playerStep,
          durationMinutes: 10,
        ),
        _log(id: 'zero-check-in', durationMinutes: 0),
        _log(
          id: 'session-1',
          workoutDayId: 'day-1',
          kind: TrainingLogKind.sessionReview,
          durationMinutes: 54,
          exerciseRecords: const <ExerciseExecutionRecord>[
            ExerciseExecutionRecord(
              exerciseId: 'goblet-squat',
              exerciseName: '高脚杯深蹲',
              plannedSetCount: 3,
              completedSetCount: 2,
              repetitionsPerSet: 0,
              weightKg: 26,
              sets: <StrengthSetExecutionRecord>[
                StrengthSetExecutionRecord(
                  setIndex: 1,
                  repetitions: 10,
                  weightKg: 24,
                  rpe: 7,
                  durationSeconds: 40,
                ),
                StrengthSetExecutionRecord(
                  setIndex: 2,
                  repetitions: 8,
                  weightKg: 26,
                  rpe: 8,
                  durationSeconds: 44,
                ),
              ],
            ),
          ],
        ),
      ],
      scheduledWorkouts: <ScheduledWorkout>[
        _scheduled(
          id: 'schedule-1',
          workoutDayId: 'day-1',
          targetMinutes: 60,
        ),
      ],
    );

    expect(state.savedCount, 1);
    expect(state.skippedCount, 2);
    expect(database.writes, hasLength(1));
    final LocalTrainingFactWrite write = database.writes.single;
    expect(write.workoutRow['external_uuid'], isNull);
    expect(write.workoutRow['source_kind'], 'local_sessionReview');
    expect(write.workoutRow['active_duration_seconds'], 54 * 60);
    expect(
      write.scheduledWorkoutResultRow['id'],
      contains('schedule-1'),
    );
    expect(
      write.scheduledWorkoutResultRow['matching_basis'],
      allOf(contains('plan_item_id=schedule-1'), contains('workout_day_id')),
    );
    expect(
      write.scheduledWorkoutResultRow['scheduled_workout_id'],
      'l1-scheduled:athlete-a:schedule-1',
    );
    expect(write.scheduledWorkoutResultRow['system_status'], 'completed');
    expect(
      write.scheduledWorkoutResultRow['system_completion_ratio'],
      closeTo(0.9, 0.000001),
    );
    expect(write.scheduledWorkoutResultRow['manual_override_status'], isNull);
    expect(write.strengthSetRows, hasLength(2));
    expect(write.strengthSetRows.first['weight_kg'], 24);
    expect(write.strengthSetRows.first['repetitions'], 10);
    expect(write.strengthSetRows.first['rpe'], 7);
    expect(write.strengthSetRows.last['weight_kg'], 26);
    expect(write.strengthSetRows.last['repetitions'], 8);
    expect(write.strengthSetRows.last['duration_seconds'], 44);
    expect(database.latestProjection.planVersionRow['id'], 'l1-plan:athlete-a');
    expect(database.latestProjection.scheduledWorkoutRows, hasLength(1));
    expect(
      database
          .latestProjection.scheduledWorkoutRows.single['source_workout_id'],
      'schedule-1',
    );
  });

  test('没有训练日志时仍保存计划项判定，计划日结束前 pending、结束后 missed', () async {
    final ScheduledWorkout scheduled = _scheduled(
      id: 'schedule-no-log',
      workoutDayId: 'day-no-log',
      targetMinutes: 60,
    );
    final _RecordingStructuredGateway pendingDatabase =
        _RecordingStructuredGateway();
    await LocalTrainingFactSyncCoordinator(
      database: pendingDatabase,
      clock: () => DateTime(2026, 7, 15, 12),
    ).synchronize(
      athleteProfileId: 'athlete-a',
      logs: const <TrainingLog>[],
      scheduledWorkouts: <ScheduledWorkout>[scheduled],
    );

    final Map<String, Object?> pendingResult =
        pendingDatabase.latestProjection.unmatchedScheduledResultRows.single;
    expect(pendingResult['scheduled_workout_id'], isNotNull);
    expect(pendingResult['workout_id'], isNull);
    expect(pendingResult['system_status'], 'pending');

    final _RecordingStructuredGateway missedDatabase =
        _RecordingStructuredGateway();
    await LocalTrainingFactSyncCoordinator(
      database: missedDatabase,
      clock: () => DateTime(2026, 7, 16, 12),
    ).synchronize(
      athleteProfileId: 'athlete-a',
      logs: const <TrainingLog>[],
      scheduledWorkouts: <ScheduledWorkout>[scheduled],
    );

    final Map<String, Object?> missedResult =
        missedDatabase.latestProjection.unmatchedScheduledResultRows.single;
    expect(missedResult['system_status'], 'missed');
    expect(missedResult['id'], pendingResult['id']);
  });

  test('旧计划缺少显式 L1 字段时写 needsReview，不从分钟字段补猜', () async {
    final _RecordingStructuredGateway database = _RecordingStructuredGateway();
    await LocalTrainingFactSyncCoordinator(
      database: database,
      clock: () => DateTime(2026, 7, 15, 20),
    ).synchronize(
      athleteProfileId: 'athlete-a',
      logs: <TrainingLog>[
        _log(
          id: 'legacy-log',
          workoutDayId: 'legacy-day',
          durationMinutes: 45,
        ),
      ],
      scheduledWorkouts: <ScheduledWorkout>[
        ScheduledWorkout(
          id: 'legacy-schedule',
          workoutDayId: 'legacy-day',
          scheduledDate: DateTime(2026, 7, 15, 8),
          startMinute: 8 * 60,
          allocatedMinutes: 60,
          period: TrainingTimePeriod.morning,
          version: ScheduledWorkoutVersion.full,
        ),
      ],
    );

    final Map<String, Object?> result =
        database.writes.single.scheduledWorkoutResultRow;
    expect(result['system_status'], 'needsReview');
    expect(result['system_completion_ratio'], isNull);
    expect(result['id'], contains('legacy-schedule'));
    expect(result['matching_basis'], contains('legacy-schedule'));
  });

  test('无计划的手动训练仍保存为无 UUID 事实，并明确标记 notPlanned', () async {
    final _RecordingStructuredGateway database = _RecordingStructuredGateway();
    await LocalTrainingFactSyncCoordinator(
      database: database,
      clock: () => DateTime(2026, 7, 15, 20),
    ).synchronize(
      athleteProfileId: 'athlete-a',
      logs: <TrainingLog>[
        _log(id: 'manual-1', durationMinutes: 30),
      ],
      scheduledWorkouts: const <ScheduledWorkout>[],
    );

    final LocalTrainingFactWrite write = database.writes.single;
    expect(write.workoutRow['external_uuid'], isNull);
    expect(write.scheduledWorkoutResultRow['system_status'], 'notPlanned');
    expect(write.scheduledWorkoutResultRow['matching_basis'],
        contains('unplanned'));
  });

  test('确认热量与运动项目会投影到结构化训练事实', () async {
    final _RecordingStructuredGateway database = _RecordingStructuredGateway();
    await LocalTrainingFactSyncCoordinator(
      database: database,
      clock: () => DateTime(2026, 7, 15, 20),
    ).synchronize(
      athleteProfileId: 'athlete-a',
      logs: <TrainingLog>[
        _log(
          id: 'extra-running',
          durationMinutes: 65,
          activityType: TrainingActivityType.running,
          energyKcal: 371,
        ),
      ],
      scheduledWorkouts: const <ScheduledWorkout>[],
    );

    final Map<String, Object?> workout = database.writes.single.workoutRow;
    expect(workout['discipline'], WorkoutDiscipline.roadRun.name);
    expect(workout['energy_kcal'], 371);
  });

  test('导入训练把 log.date 作为开始时间，不会按时长整体前移', () async {
    final _RecordingStructuredGateway database = _RecordingStructuredGateway();
    await LocalTrainingFactSyncCoordinator(
      database: database,
      clock: () => DateTime(2026, 7, 15, 20),
    ).synchronize(
      athleteProfileId: 'athlete-a',
      logs: <TrainingLog>[
        _log(
          id: 'import-1',
          kind: TrainingLogKind.activityImport,
          durationMinutes: 30,
          date: DateTime.utc(2026, 7, 15, 9),
        ),
      ],
      scheduledWorkouts: const <ScheduledWorkout>[],
    );

    final Map<String, Object?> workout = database.writes.single.workoutRow;
    expect(workout['started_at_utc'], '2026-07-15T09:00:00.000Z');
    expect(workout['ended_at_utc'], '2026-07-15T09:30:00.000Z');
  });

  test('结构化数据库未注入时 Provider 返回降级状态，不抛出页面错误', () async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    final LocalTrainingFactSyncState state =
        await container.read(localTrainingFactSyncProvider.future);

    expect(state.status, LocalTrainingFactSyncStatus.unavailable);
    expect(state.message, contains('继续使用本地兼容数据'));
  });
}

ScheduledWorkout _scheduled({
  required String id,
  required String workoutDayId,
  required int targetMinutes,
}) {
  return ScheduledWorkout(
    id: id,
    workoutDayId: workoutDayId,
    scheduledDate: DateTime(2026, 7, 15, 8),
    startMinute: 8 * 60,
    allocatedMinutes: targetMinutes,
    period: TrainingTimePeriod.morning,
    version: ScheduledWorkoutVersion.full,
    discipline: WorkoutDiscipline.roadRun,
    primaryTargetKind: CompletionTargetKind.duration,
    targetMinutes: targetMinutes,
  );
}

TrainingLog _log({
  required String id,
  String workoutDayId = 'unplanned-day',
  TrainingLogKind kind = TrainingLogKind.manual,
  required int durationMinutes,
  DateTime? date,
  List<ExerciseExecutionRecord> exerciseRecords =
      const <ExerciseExecutionRecord>[],
  TrainingActivityType? activityType,
  double? energyKcal,
}) {
  final DateTime occurredAt = date ?? DateTime(2026, 7, 15, 9);
  return TrainingLog(
    id: id,
    workoutDayId: workoutDayId,
    date: occurredAt,
    completed: durationMinutes > 0,
    rpe: 6,
    fatigueLevel: 3,
    sleepQuality: 4,
    painNote: null,
    userNote: null,
    createdAt: occurredAt,
    kind: kind,
    actualDurationMinutes: durationMinutes,
    exerciseRecords: exerciseRecords,
    activityType: activityType,
    energyKcal: energyKcal,
    energySource:
        energyKcal == null ? null : TrainingEnergySource.healthKitConfirmed,
  );
}

class _RecordingStructuredGateway
    implements TrainMateStructuredDatabaseGateway {
  final List<L1ScheduleProjectionWrite> projectionWrites =
      <L1ScheduleProjectionWrite>[];

  L1ScheduleProjectionWrite get latestProjection => projectionWrites.last;

  List<LocalTrainingFactWrite> get writes =>
      latestProjection.localTrainingFacts;

  @override
  Future<L1ScheduleProjectionWriteResult> saveL1ScheduleProjection(
    L1ScheduleProjectionWrite write,
  ) async {
    projectionWrites.add(write);
    return L1ScheduleProjectionWriteResult(
      planVersionId: write.planVersionRow['id']! as String,
      scheduledWorkoutCount: write.scheduledWorkoutRows.length,
      workoutCount: write.localTrainingFacts.length,
      resultCount: write.localTrainingFacts.length +
          write.unmatchedScheduledResultRows.length,
      strengthSetCount: write.localTrainingFacts.fold<int>(
        0,
        (int count, LocalTrainingFactWrite item) =>
            count + item.strengthSetRows.length,
      ),
    );
  }

  @override
  Future<LocalTrainingFactWriteResult> saveLocalTrainingFact(
    LocalTrainingFactWrite write,
  ) async {
    return LocalTrainingFactWriteResult(
      workoutId: write.workoutRow['id']! as String,
      scheduledWorkoutResultId:
          write.scheduledWorkoutResultRow['id']! as String,
      strengthSetCount: write.strengthSetRows.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试未实现的结构化网关调用。');
}
