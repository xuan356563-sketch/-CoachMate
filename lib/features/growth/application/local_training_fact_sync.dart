import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/trainmate_structured_database_gateway.dart';
import '../../../data/models/training_log.dart';
import '../../../data/models/training_metrics.dart';
import '../../../data/models/training_schedule.dart';
import '../../../services/training_metrics_engine.dart';
import '../../../services/training_metrics_pipeline.dart';
import '../../dashboard/training_mvp_controller.dart';
import '../../profile/application/health_sync_controller.dart';
import '../../profile/application/training_schedule_controller.dart';
import 'training_metrics_projection_service.dart';
import 'training_metrics_provider.dart';

enum LocalTrainingFactSyncStatus { ready, unavailable, failed }

class LocalTrainingFactSyncState {
  const LocalTrainingFactSyncState({
    required this.status,
    required this.savedCount,
    required this.skippedCount,
    required this.message,
    this.analyzedCount = 0,
    this.analysisFailureCount = 0,
  });

  final LocalTrainingFactSyncStatus status;
  final int savedCount;
  final int skippedCount;
  final String message;
  final int analyzedCount;
  final int analysisFailureCount;

  LocalTrainingFactSyncState copyWith({
    LocalTrainingFactSyncStatus? status,
    int? savedCount,
    int? skippedCount,
    String? message,
    int? analyzedCount,
    int? analysisFailureCount,
  }) {
    return LocalTrainingFactSyncState(
      status: status ?? this.status,
      savedCount: savedCount ?? this.savedCount,
      skippedCount: skippedCount ?? this.skippedCount,
      message: message ?? this.message,
      analyzedCount: analyzedCount ?? this.analyzedCount,
      analysisFailureCount: analysisFailureCount ?? this.analysisFailureCount,
    );
  }
}

final localTrainingFactSyncProvider =
    FutureProvider.autoDispose<LocalTrainingFactSyncState>((Ref ref) async {
  final TrainMateStructuredDatabaseGateway? database =
      ref.watch(healthSyncStructuredDatabaseGatewayProvider);
  if (database == null) {
    return const LocalTrainingFactSyncState(
      status: LocalTrainingFactSyncStatus.unavailable,
      savedCount: 0,
      skippedCount: 0,
      message: '结构化训练存储暂不可用，首页已继续使用本地兼容数据。',
    );
  }
  final String athleteProfileId = ref.watch(
    trainingMvpProvider.select(
      (TrainingMvpState state) => state.profile.id,
    ),
  );
  final List<TrainingLog> logs = ref.watch(
    trainingMvpProvider.select(
      (TrainingMvpState state) => state.logs,
    ),
  );
  final List<ScheduledWorkout> schedule = ref.watch(
    trainingScheduleControllerProvider.select(
      (TrainingScheduleState state) => state.workouts,
    ),
  );
  final TrainingMetricsPipeline? pipeline =
      ref.watch(healthSyncMetricsPipelineProvider);
  try {
    final LocalTrainingFactSyncState persisted =
        await LocalTrainingFactSyncCoordinator(database: database).synchronize(
      athleteProfileId: athleteProfileId,
      logs: logs,
      scheduledWorkouts: schedule,
    );
    if (pipeline == null || persisted.savedCount == 0) return persisted;
    final LocalTrainingFactSyncState analyzed = await _analyzeLocalFacts(
      pipeline: pipeline,
      athleteProfileId: athleteProfileId,
      logs: logs,
      persisted: persisted,
    );
    if (ref.mounted && analyzed.analyzedCount > 0) {
      ref.invalidate(trainingMetricAggregatesProvider);
      ref.invalidate(trainingReportRevisionsProvider);
      ref.invalidate(growthMetricsControllerProvider);
    }
    return analyzed;
  } catch (_) {
    return const LocalTrainingFactSyncState(
      status: LocalTrainingFactSyncStatus.failed,
      savedCount: 0,
      skippedCount: 0,
      message: '结构化训练记录暂未写入，首页功能不受影响，稍后可自动重试。',
    );
  }
});

Future<LocalTrainingFactSyncState> _analyzeLocalFacts({
  required TrainingMetricsPipeline pipeline,
  required String athleteProfileId,
  required List<TrainingLog> logs,
  required LocalTrainingFactSyncState persisted,
}) async {
  final Set<DateTime> analyzedDays = <DateTime>{};
  int analyzedCount = 0;
  int failureCount = 0;
  for (final TrainingLog log in logs) {
    if (!log.isSessionRecord || log.actualDurationMinutes <= 0) continue;
    try {
      final WorkoutAnalysisOutcome outcome = await pipeline.analyzeWorkout(
        athleteProfileId: athleteProfileId,
        workoutId: _localWorkoutId(athleteProfileId, log.id),
      );
      analyzedDays.add(DateTime(
        outcome.occurredOn.year,
        outcome.occurredOn.month,
        outcome.occurredOn.day,
      ));
      analyzedCount += 1;
    } catch (_) {
      // 训练事实已经安全落库；单个派生指标失败只进入可重试状态，不能把事实回滚。
      failureCount += 1;
    }
  }

  final Map<String, ({MetricPeriod period, DateTime start})> periods =
      <String, ({MetricPeriod period, DateTime start})>{};
  for (final DateTime day in analyzedDays) {
    final DateTime weekStart = day.subtract(
      Duration(days: day.weekday - DateTime.monday),
    );
    final DateTime monthStart = DateTime(day.year, day.month);
    periods['week:${_dateKey(weekStart)}'] = (
      period: MetricPeriod.week,
      start: weekStart,
    );
    periods['month:${_dateKey(monthStart)}'] = (
      period: MetricPeriod.month,
      start: monthStart,
    );
  }
  final List<String> orderedKeys = periods.keys.toList()..sort();
  for (final String key in orderedKeys) {
    final ({MetricPeriod period, DateTime start}) window = periods[key]!;
    try {
      await pipeline.aggregatePeriod(
        athleteProfileId: athleteProfileId,
        period: window.period,
        periodStart: window.start,
      );
    } catch (_) {
      failureCount += 1;
    }
  }

  final String analysisMessage = failureCount == 0
      ? '已分析 $analyzedCount 条本地训练事实并刷新周/月指标。'
      : '已分析 $analyzedCount 条本地训练事实；'
          '$failureCount 个派生计算待稍后重试，已落库事实不受影响。';
  return persisted.copyWith(
    message: '${persisted.message} $analysisMessage',
    analyzedCount: analyzedCount,
    analysisFailureCount: failureCount,
  );
}

enum L1ScheduledResultReadSource {
  structured,
  compatibilityUnavailable,
  compatibilityFailed,
}

class L1ScheduledResultQuery {
  const L1ScheduledResultQuery({
    required this.athleteProfileId,
    required this.startLocalDate,
    required this.endExclusiveLocalDate,
  });

  final String athleteProfileId;
  final DateTime startLocalDate;
  final DateTime endExclusiveLocalDate;

  @override
  bool operator ==(Object other) =>
      other is L1ScheduledResultQuery &&
      other.athleteProfileId == athleteProfileId &&
      other.startLocalDate == startLocalDate &&
      other.endExclusiveLocalDate == endExclusiveLocalDate;

  @override
  int get hashCode => Object.hash(
        athleteProfileId,
        startLocalDate,
        endExclusiveLocalDate,
      );
}

class L1ScheduledResultReadState {
  const L1ScheduledResultReadState({
    required this.source,
    required this.results,
    required this.message,
  });

  final L1ScheduledResultReadSource source;
  final List<StructuredScheduledWorkoutResult> results;
  final String message;

  bool get usesStructuredFacts =>
      source == L1ScheduledResultReadSource.structured;
}

/// 先提交当前排期与训练日志，再从 SQLite 读取首页要展示的 L1 唯一事实。
///
/// 结构化存储不可用或失败时返回显式兼容状态；调用方不得把兼容重算结果描述为
/// 已持久化事实。
final l1ScheduledResultReadProvider = FutureProvider.autoDispose
    .family<L1ScheduledResultReadState, L1ScheduledResultQuery>(
  (Ref ref, L1ScheduledResultQuery query) async {
    final TrainMateStructuredDatabaseGateway? database =
        ref.watch(healthSyncStructuredDatabaseGatewayProvider);
    final LocalTrainingFactSyncState sync =
        await ref.watch(localTrainingFactSyncProvider.future);
    if (database == null ||
        sync.status == LocalTrainingFactSyncStatus.unavailable) {
      return L1ScheduledResultReadState(
        source: L1ScheduledResultReadSource.compatibilityUnavailable,
        results: const <StructuredScheduledWorkoutResult>[],
        message: sync.message,
      );
    }
    if (sync.status == LocalTrainingFactSyncStatus.failed) {
      return L1ScheduledResultReadState(
        source: L1ScheduledResultReadSource.compatibilityFailed,
        results: const <StructuredScheduledWorkoutResult>[],
        message: sync.message,
      );
    }
    try {
      final List<StructuredScheduledWorkoutResult> results =
          await database.listScheduledWorkoutResults(
        athleteProfileId: query.athleteProfileId,
        startLocalDate: query.startLocalDate,
        endExclusiveLocalDate: query.endExclusiveLocalDate,
      );
      return L1ScheduledResultReadState(
        source: L1ScheduledResultReadSource.structured,
        results: results,
        message: '已读取 ${results.length} 条结构化 L1 判定。',
      );
    } catch (_) {
      return const L1ScheduledResultReadState(
        source: L1ScheduledResultReadSource.compatibilityFailed,
        results: <StructuredScheduledWorkoutResult>[],
        message: '结构化 L1 判定暂时无法读取，已切换为明确的兼容预览。',
      );
    }
  },
);

class LocalTrainingFactSyncCoordinator {
  LocalTrainingFactSyncCoordinator({
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TrainMateStructuredDatabaseGateway database;
  final DateTime Function() _clock;

  Future<LocalTrainingFactSyncState> synchronize({
    required String athleteProfileId,
    required List<TrainingLog> logs,
    required List<ScheduledWorkout> scheduledWorkouts,
  }) async {
    if (athleteProfileId.trim().isEmpty) {
      throw const FormatException('本地训练事实缺少运动员资料 ID。');
    }
    final List<TrainingLog> sessionLogs = logs
        .where((TrainingLog log) =>
            log.isSessionRecord && log.actualDurationMinutes > 0)
        .toList(growable: false);
    final int skippedCount = logs.length - sessionLogs.length;

    final DateTime evaluatedAt = _clock();
    final TrainingMetricsEngine engine = TrainingMetricsEngine();
    final List<ScheduledWorkoutEvaluation> evaluations =
        const TrainingMetricsProjectionService().evaluateSchedule(
      workouts: scheduledWorkouts,
      logs: sessionLogs,
      now: evaluatedAt,
      engine: engine,
    );
    final Map<String, ScheduledWorkoutEvaluation> evaluationByLogId =
        <String, ScheduledWorkoutEvaluation>{};
    for (final ScheduledWorkoutEvaluation evaluation in evaluations) {
      final String? logId = evaluation.matchedLog?.id;
      if (logId != null) {
        evaluationByLogId.putIfAbsent(logId, () => evaluation);
      }
    }

    final String planVersionId = _structuredPlanVersionId(athleteProfileId);
    final List<Map<String, Object?>> scheduledRows = scheduledWorkouts
        .map(
          (ScheduledWorkout workout) => _scheduledWorkoutRow(
            athleteProfileId: athleteProfileId,
            planVersionId: planVersionId,
            workout: workout,
            scheduleStart: _scheduleStart(scheduledWorkouts, evaluatedAt),
            evaluatedAt: evaluatedAt,
          ),
        )
        .toList(growable: false);
    final List<LocalTrainingFactWrite> localFacts = <LocalTrainingFactWrite>[];
    for (final TrainingLog log in sessionLogs) {
      final ScheduledWorkoutEvaluation? evaluation = evaluationByLogId[log.id];
      localFacts.add(_buildWrite(
        athleteProfileId: athleteProfileId,
        log: log,
        evaluation: evaluation,
        evaluatedAt: evaluatedAt,
        engine: engine,
      ));
    }
    final List<Map<String, Object?>> unmatchedScheduledResults = evaluations
        .where((ScheduledWorkoutEvaluation item) => item.matchedLog == null)
        .map(
          (ScheduledWorkoutEvaluation item) => _scheduledResultRow(
            athleteProfileId: athleteProfileId,
            scheduled: item.workout,
            completion: item.result,
            structuredWorkoutId: null,
            matchingBasis: item.matchingBasis,
            updatedAt: evaluatedAt,
          ),
        )
        .toList(growable: false);
    final L1ScheduleProjectionWriteResult persisted =
        await database.saveL1ScheduleProjection(
      L1ScheduleProjectionWrite(
        planVersionRow: _planVersionRow(
          athleteProfileId: athleteProfileId,
          planVersionId: planVersionId,
          scheduledWorkouts: scheduledWorkouts,
          evaluatedAt: evaluatedAt,
        ),
        scheduledWorkoutRows: scheduledRows,
        localTrainingFacts: localFacts,
        unmatchedScheduledResultRows: unmatchedScheduledResults,
      ),
    );
    return LocalTrainingFactSyncState(
      status: LocalTrainingFactSyncStatus.ready,
      savedCount: persisted.workoutCount,
      skippedCount: skippedCount,
      message: '已同步 ${persisted.scheduledWorkoutCount} 个计划项、'
          '${persisted.resultCount} 条 L1 判定和 ${persisted.workoutCount} 条本地训练事实。',
    );
  }

  LocalTrainingFactWrite _buildWrite({
    required String athleteProfileId,
    required TrainingLog log,
    required ScheduledWorkoutEvaluation? evaluation,
    required DateTime evaluatedAt,
    required TrainingMetricsEngine engine,
  }) {
    final ScheduledWorkout? scheduled = evaluation?.workout;
    final WorkoutDiscipline discipline = scheduled?.discipline ??
        _disciplineForTrainingActivity(log.activityType);
    final ScheduledWorkoutResult completion = evaluation?.result ??
        engine.evaluateCompletion(
          plan: null,
          workout: CompletedWorkoutFact(
            workoutId: log.id,
            planItemId: null,
            occurredAt: log.date,
            discipline: discipline,
            actualValues: <CompletionTargetKind, double>{
              CompletionTargetKind.duration:
                  log.actualDurationMinutes.toDouble(),
            },
          ),
          now: evaluatedAt,
        );
    final String workoutId = _localWorkoutId(athleteProfileId, log.id);
    final String matchingBasis = evaluation?.matchingBasis ??
        'plan_item_id=none;workout_day_id='
            '${Uri.encodeComponent(log.workoutDayId)};'
            'local_date=${_dateKey(log.date)};match=unplanned';
    final Duration duration = Duration(minutes: log.actualDurationMinutes);
    final DateTime startedAtUtc;
    final DateTime endedAtUtc;
    if (log.kind == TrainingLogKind.activityImport) {
      startedAtUtc = log.date.toUtc();
      endedAtUtc = startedAtUtc.add(duration);
    } else {
      endedAtUtc = log.date.toUtc();
      startedAtUtc = endedAtUtc.subtract(duration);
    }
    final String updatedAt = evaluatedAt.toUtc().toIso8601String();
    final Map<String, Object?> workoutRow = <String, Object?>{
      'id': workoutId,
      'athlete_profile_id': athleteProfileId,
      'external_uuid': null,
      'source_bundle_id': 'trainmate.local',
      'source_product_type': null,
      'source_kind': 'local_${log.kind.jsonValue}',
      'discipline': discipline.name,
      'run_context': switch (discipline) {
        WorkoutDiscipline.roadRun => 'road',
        WorkoutDiscipline.trailRun => 'trail',
        _ => null,
      },
      'started_at_utc': startedAtUtc.toIso8601String(),
      'ended_at_utc': endedAtUtc.toIso8601String(),
      'local_date': _dateKey(log.date),
      'time_zone_name': log.date.isUtc ? 'UTC' : 'device-local',
      'utc_offset_minutes': log.date.timeZoneOffset.inMinutes,
      'active_duration_seconds': log.actualDurationMinutes * 60,
      'elapsed_duration_seconds': log.actualDurationMinutes * 60,
      'distance_meters': log.distanceKm > 0 ? log.distanceKm * 1000 : null,
      'energy_kcal': log.energyKcal,
      'elevation_gain_meters': null,
      'average_heart_rate':
          log.averageHeartRate > 0 ? log.averageHeartRate : null,
      'maximum_heart_rate': null,
      'heart_rate_sample_count': 0,
      'heart_rate_coverage': 0.0,
      'route_status': 'unavailable',
      'route_external_uuid': null,
      'payload_json': jsonEncode(<String, Object?>{
        'source': 'local_training_log',
        'rpe': log.rpe >= 1 && log.rpe <= 10 ? log.rpe : null,
        'trainingLog': log.toJson(),
        'matchedPlanItemId': scheduled?.id,
        'matchingBasis': matchingBasis,
      }),
      'source_deleted_at': null,
      'created_at': log.createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt,
    };
    final Map<String, Object?> resultRow = _scheduledResultRow(
      athleteProfileId: athleteProfileId,
      scheduled: scheduled,
      completion: completion,
      structuredWorkoutId: workoutId,
      matchingBasis: matchingBasis,
      updatedAt: evaluatedAt,
      unplannedLogId: log.id,
    );
    return LocalTrainingFactWrite(
      workoutRow: workoutRow,
      scheduledWorkoutResultRow: resultRow,
      strengthSetRows: _strengthSetRows(
        athleteProfileId: athleteProfileId,
        workoutId: workoutId,
        log: log,
      ),
    );
  }

  List<Map<String, Object?>> _strengthSetRows({
    required String athleteProfileId,
    required String workoutId,
    required TrainingLog log,
  }) {
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (int exerciseIndex = 0;
        exerciseIndex < log.exerciseRecords.length;
        exerciseIndex += 1) {
      final ExerciseExecutionRecord exercise =
          log.exerciseRecords[exerciseIndex];
      final String explicitKey = exercise.exerciseId?.trim() ?? '';
      final String exerciseKey = explicitKey.isNotEmpty
          ? explicitKey
          : 'local-name-${_stableToken(exercise.exerciseName)}';
      // 旧记录只有动作级汇总，无法证明每一组的重量与次数。
      // 它们继续保留在 TrainingLog 中展示，但不再复制成多条虚假 strength_sets。
      for (final StrengthSetExecutionRecord set in exercise.sets) {
        rows.add(<String, Object?>{
          'id': 'local-strength-set:${Uri.encodeComponent(workoutId)}:'
              '${Uri.encodeComponent(exerciseKey)}:$exerciseIndex:${set.setIndex}',
          'athlete_profile_id': athleteProfileId,
          'workout_id': workoutId,
          'exercise_key': exerciseKey,
          'exercise_name': exercise.exerciseName,
          'set_index': set.setIndex,
          'repetitions':
              set.repetitions > 0 ? set.repetitions.toDouble() : null,
          'weight_kg': set.weightKg > 0 ? set.weightKg : null,
          'rpe': set.rpe,
          'duration_seconds': set.durationSeconds,
          'payload_json': jsonEncode(<String, Object?>{
            'sourceLogId': log.id,
            'exerciseIndex': exerciseIndex,
            'setIndex': set.setIndex,
            'recordingMode': 'actual_set',
          }),
          'created_at': log.createdAt.toUtc().toIso8601String(),
        });
      }
    }
    return List<Map<String, Object?>>.unmodifiable(rows);
  }
}

WorkoutDiscipline _disciplineForTrainingActivity(
  TrainingActivityType? activityType,
) {
  return switch (activityType) {
    TrainingActivityType.running ||
    TrainingActivityType.fastWalking =>
      WorkoutDiscipline.roadRun,
    TrainingActivityType.hiking => WorkoutDiscipline.trailRun,
    TrainingActivityType.strength => WorkoutDiscipline.strength,
    TrainingActivityType.badminton => WorkoutDiscipline.badminton,
    TrainingActivityType.hiit => WorkoutDiscipline.hyrox,
    _ => WorkoutDiscipline.other,
  };
}

String _localWorkoutId(String athleteProfileId, String logId) =>
    'local-workout:${Uri.encodeComponent(athleteProfileId)}:'
    '${Uri.encodeComponent(logId)}';

Map<String, Object?> _planVersionRow({
  required String athleteProfileId,
  required String planVersionId,
  required List<ScheduledWorkout> scheduledWorkouts,
  required DateTime evaluatedAt,
}) {
  final DateTime start = _scheduleStart(scheduledWorkouts, evaluatedAt);
  final DateTime end = _scheduleEnd(scheduledWorkouts, evaluatedAt);
  final String timestamp = evaluatedAt.toUtc().toIso8601String();
  return <String, Object?>{
    'id': planVersionId,
    'athlete_profile_id': athleteProfileId,
    'primary_goal_id': null,
    'secondary_goal_id': null,
    'race_id': null,
    'version_number': 1,
    'starts_on': _dateKey(start),
    'ends_on': _dateKey(end),
    'status': 'active',
    'generation_reason': '兼容训练日程投影为 L1 唯一事实',
    'payload_json': jsonEncode(<String, Object?>{
      'source': 'trainflow.training_schedule.v1',
      'scheduledWorkoutIds': scheduledWorkouts
          .map((ScheduledWorkout item) => item.id)
          .toList(growable: false),
    }),
    'created_at': timestamp,
    'activated_at': timestamp,
  };
}

Map<String, Object?> _scheduledWorkoutRow({
  required String athleteProfileId,
  required String planVersionId,
  required ScheduledWorkout workout,
  required DateTime scheduleStart,
  required DateTime evaluatedAt,
}) {
  final String timestamp = evaluatedAt.toUtc().toIso8601String();
  final DateTime scheduledDate = _localDateOnly(workout.scheduledDate);
  final DateTime normalizedScheduleStart = _localDateOnly(scheduleStart);
  return <String, Object?>{
    'id': _structuredScheduledWorkoutId(athleteProfileId, workout.id),
    'plan_version_id': planVersionId,
    // 保存兼容排期 ID，读取时据此还原当前领域计划项。
    'source_workout_id': workout.id,
    'title': '${workout.period.label}计划训练',
    'discipline': workout.discipline?.name ?? WorkoutDiscipline.other.name,
    'scheduled_date': _dateKey(scheduledDate),
    'week_index':
        scheduledDate.difference(normalizedScheduleStart).inDays ~/ 7 + 1,
    'phase': 'l1_execution',
    'status': 'planned',
    'estimated_minutes': workout.allocatedMinutes,
    'intensity': workout.version.label,
    'content_json': jsonEncode(<String, Object?>{
      'source': 'trainflow.training_schedule.v1',
      'workoutDayId': workout.workoutDayId,
      'schedule': workout.toJson(),
    }),
    'created_at': timestamp,
    'updated_at': timestamp,
    'started_at': null,
    'completed_at': null,
  };
}

Map<String, Object?> _scheduledResultRow({
  required String athleteProfileId,
  required ScheduledWorkout? scheduled,
  required ScheduledWorkoutResult completion,
  required String? structuredWorkoutId,
  required String matchingBasis,
  required DateTime updatedAt,
  String? unplannedLogId,
}) {
  final String? structuredScheduledId = scheduled == null
      ? null
      : _structuredScheduledWorkoutId(athleteProfileId, scheduled.id);
  final String resultId = scheduled == null
      ? 'local-result:${Uri.encodeComponent(athleteProfileId)}:unplanned:'
          '${Uri.encodeComponent(unplannedLogId!)}'
      : 'local-result:${Uri.encodeComponent(athleteProfileId)}:scheduled:'
          '${Uri.encodeComponent(scheduled.id)}';
  return <String, Object?>{
    'id': resultId,
    'athlete_profile_id': athleteProfileId,
    'scheduled_workout_id': structuredScheduledId,
    'workout_id': structuredWorkoutId,
    'system_status': completion.status.name,
    'system_completion_ratio': completion.completionRatio,
    'manual_override_status': null,
    'override_reason': null,
    'matching_basis': matchingBasis,
    'decided_at': completion.evaluatedAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

String _structuredPlanVersionId(String athleteProfileId) =>
    'l1-plan:${Uri.encodeComponent(athleteProfileId)}';

String _structuredScheduledWorkoutId(
  String athleteProfileId,
  String scheduledWorkoutId,
) =>
    'l1-scheduled:${Uri.encodeComponent(athleteProfileId)}:'
    '${Uri.encodeComponent(scheduledWorkoutId)}';

DateTime _scheduleStart(
  List<ScheduledWorkout> workouts,
  DateTime fallback,
) {
  if (workouts.isEmpty) {
    return _localDateOnly(fallback);
  }
  return workouts
      .map((ScheduledWorkout item) => _localDateOnly(item.scheduledDate))
      .reduce((DateTime first, DateTime second) =>
          first.isBefore(second) ? first : second);
}

DateTime _scheduleEnd(
  List<ScheduledWorkout> workouts,
  DateTime fallback,
) {
  if (workouts.isEmpty) {
    return _localDateOnly(fallback);
  }
  return workouts
      .map((ScheduledWorkout item) => _localDateOnly(item.scheduledDate))
      .reduce((DateTime first, DateTime second) =>
          first.isAfter(second) ? first : second);
}

DateTime _localDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _stableToken(String value) {
  int hash = 2166136261;
  for (final int codeUnit in value.codeUnits) {
    hash = ((hash ^ codeUnit) * 16777619) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
