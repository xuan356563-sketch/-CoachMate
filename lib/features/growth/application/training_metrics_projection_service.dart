import '../../../data/models/training_log.dart';
import '../../../data/models/training_metrics.dart';
import '../../../data/models/training_schedule.dart';
import '../../../services/training_metrics_engine.dart';

class L1DashboardProjection {
  const L1DashboardProjection({
    required this.weeklyConsistencyLabel,
    required this.todayDecisionLabel,
    required this.loadStateLabel,
    required this.calculationBasis,
  });

  final String weeklyConsistencyLabel;
  final String todayDecisionLabel;
  final String loadStateLabel;
  final String calculationBasis;
}

enum L1ProjectionSource {
  structured,
  structuredLoading,
  compatibilityUnavailable,
  compatibilityFailed,
}

class ScheduledWorkoutEvaluation {
  const ScheduledWorkoutEvaluation({
    required this.workout,
    required this.result,
    required this.matchedLog,
    required this.matchingBasis,
  });

  final ScheduledWorkout workout;
  final ScheduledWorkoutResult result;
  final TrainingLog? matchedLog;
  final String matchingBasis;
}

/// 将本地排期和训练日志保守投影到 L1。
///
/// 已持久化的结构化指标优先；本地兼容计算只使用明确的主目标、计划关联和
/// 同一自然日训练日志，不从旧字段推测目标或完成度。
class TrainingMetricsProjectionService {
  const TrainingMetricsProjectionService();

  L1DashboardProjection project({
    required List<TrainingLog> logs,
    required ScheduledWorkout? scheduledTodayWorkout,
    required List<MetricAggregate> metrics,
    required DateTime now,
    List<ScheduledWorkout> scheduledWeekWorkouts = const <ScheduledWorkout>[],
    List<ScheduledWorkoutResult> persistedScheduledResults =
        const <ScheduledWorkoutResult>[],
    L1ProjectionSource source = L1ProjectionSource.compatibilityUnavailable,
  }) {
    final TrainingMetricsEngine engine = TrainingMetricsEngine();
    final List<ScheduledWorkout> weekWorkouts = _weekWorkouts(
      workouts: scheduledWeekWorkouts,
      scheduledTodayWorkout: scheduledTodayWorkout,
      now: now,
    );
    final bool usesStructuredFacts = source == L1ProjectionSource.structured;
    final List<ScheduledWorkoutEvaluation> evaluated =
        usesStructuredFacts || source == L1ProjectionSource.structuredLoading
            ? const <ScheduledWorkoutEvaluation>[]
            : evaluateSchedule(
                workouts: weekWorkouts,
                logs: logs,
                now: now,
                engine: engine,
              );
    final Set<String> weekPlanItemIds =
        weekWorkouts.map((ScheduledWorkout item) => item.id).toSet();
    final List<ScheduledWorkoutResult> weekResults = usesStructuredFacts
        ? persistedScheduledResults
            .where((ScheduledWorkoutResult item) =>
                item.planItemId != null &&
                weekPlanItemIds.contains(item.planItemId))
            .toList(growable: false)
        : evaluated
            .map((ScheduledWorkoutEvaluation item) => item.result)
            .toList(growable: false);
    final Set<String> persistedPlanItemIds = weekResults
        .map((ScheduledWorkoutResult item) => item.planItemId)
        .whereType<String>()
        .toSet();
    final bool structuredSnapshotIncomplete = usesStructuredFacts &&
        weekPlanItemIds.any(
          (String planItemId) => !persistedPlanItemIds.contains(planItemId),
        );

    final MetricAggregate? storedConsistency = _findMetric(
      metrics,
      (MetricAggregate item) => item.metricCode == 'weekly_consistency',
    );
    final WeeklyConsistencyResult localConsistency =
        engine.calculateWeeklyConsistency(weekResults);
    final String weeklyConsistencyLabel = switch (source) {
      L1ProjectionSource.structuredLoading => '正在读取',
      L1ProjectionSource.structured when structuredSnapshotIncomplete =>
        '等待结构化判定补齐',
      L1ProjectionSource.structured => _localConsistencyLabel(localConsistency),
      _ => storedConsistency == null
          ? _localConsistencyLabel(localConsistency)
          : _consistencyLabel(storedConsistency),
    };

    final Set<String> todayPlanItemIds = weekWorkouts
        .where(
            (ScheduledWorkout item) => _sameLocalDate(item.scheduledDate, now))
        .map((ScheduledWorkout item) => item.id)
        .toSet();
    final List<ScheduledWorkoutResult> todayResults = usesStructuredFacts
        ? weekResults
            .where((ScheduledWorkoutResult item) =>
                item.planItemId != null &&
                todayPlanItemIds.contains(item.planItemId))
            .toList(growable: false)
        : evaluated
            .where((ScheduledWorkoutEvaluation item) =>
                _sameLocalDate(item.workout.scheduledDate, now))
            .map((ScheduledWorkoutEvaluation item) => item.result)
            .toList(growable: false);
    final String todayDecisionLabel = _todayDecisionLabel(todayResults);

    final MetricAggregate? storedAcwr = _findMetric(
      metrics,
      (MetricAggregate item) =>
          item.metricCode == 'acwr' || item.metricCode.startsWith('acwr.'),
    );
    final String loadStateLabel = storedAcwr == null
        ? _compatibleLoadLabel(logs: logs, now: now)
        : _storedLoadLabel(storedAcwr);

    final String metricBasis = switch (source) {
      L1ProjectionSource.structuredLoading => '正在读取结构化 L1 判定，未使用兼容重算冒充事实。',
      L1ProjectionSource.structured when structuredSnapshotIncomplete =>
        '结构化 L1 判定与当前计划尚未完整对齐，本周一致性暂不给出比例。',
      L1ProjectionSource.structured =>
        '本周一致性由已持久化的结构化 L1 判定汇总，人工覆盖仅改变有效判定，系统原判定仍保留。',
      _ when storedConsistency != null => '结构化 L1 事实暂不可用；兼容预览读取了带版本的结构化聚合（周）。',
      _ when weekWorkouts.isEmpty => '结构化 L1 事实暂不可用；兼容预览缺少计划分母，未猜测 0% 或 100%。',
      _ => '结构化 L1 事实暂不可用；兼容预览按明确主目标与日志一对一匹配，并使用 90%/50% 阈值。',
    };
    final bool hasLegacyItem = todayResults.any(
      (ScheduledWorkoutResult item) =>
          item.effectiveStatus == WorkoutCompletionStatus.needsReview,
    );
    final String todayBasis = source == L1ProjectionSource.structuredLoading
        ? '今日判定正在从结构化存储读取。'
        : todayResults.isEmpty
            ? '今天暂无明确排期。'
            : hasLegacyItem
                ? '旧计划未声明 primary_target_kind 或其他必需字段，已保留待核对状态。'
                : usesStructuredFacts
                    ? '今日判定读取已持久化的计划项结果。'
                    : '今日判定是兼容预览，不作为结构化事实。';
    final String fallbackNotice = switch (source) {
      L1ProjectionSource.compatibilityUnavailable => '结构化数据库不可用，当前仅显示兼容预览。 ',
      L1ProjectionSource.compatibilityFailed => '结构化 L1 读写失败，当前仅显示兼容预览。 ',
      _ => '',
    };

    return L1DashboardProjection(
      weeklyConsistencyLabel: weeklyConsistencyLabel,
      todayDecisionLabel: source == L1ProjectionSource.structuredLoading
          ? '正在读取'
          : todayDecisionLabel,
      loadStateLabel: loadStateLabel,
      calculationBasis:
          '$fallbackNotice$metricBasis $todayBasis 负荷仅使用完整同口径 28 天序列。',
    );
  }

  List<ScheduledWorkoutEvaluation> evaluateSchedule({
    required List<ScheduledWorkout> workouts,
    required List<TrainingLog> logs,
    required DateTime now,
    required TrainingMetricsEngine engine,
  }) {
    final List<ScheduledWorkout> orderedWorkouts = List.of(workouts)
      ..sort((ScheduledWorkout first, ScheduledWorkout second) {
        final int dateOrder =
            first.scheduledDate.compareTo(second.scheduledDate);
        if (dateOrder != 0) return dateOrder;
        final int timeOrder = first.startMinute.compareTo(second.startMinute);
        return timeOrder != 0 ? timeOrder : first.id.compareTo(second.id);
      });
    final Set<int> usedLogIndexes = <int>{};
    final List<ScheduledWorkoutEvaluation> result =
        <ScheduledWorkoutEvaluation>[];

    for (final ScheduledWorkout scheduled in orderedWorkouts) {
      final _TrainingLogMatch? match = _matchingLog(
        scheduled: scheduled,
        logs: logs,
        usedLogIndexes: usedLogIndexes,
      );
      final TrainingLog? log = match == null ? null : logs[match.index];
      if (match != null) usedLogIndexes.add(match.index);
      final String matchingBasis = _matchingBasis(
        scheduled: scheduled,
        matchKind: match?.kind,
      );

      final bool hasExplicitDurationTarget =
          scheduled.primaryTargetKind == CompletionTargetKind.duration &&
              scheduled.targetMinutes != null &&
              scheduled.targetMinutes! > 0;
      final WorkoutDiscipline? discipline = scheduled.discipline;
      if (!hasExplicitDurationTarget || discipline == null) {
        result.add(
          ScheduledWorkoutEvaluation(
            workout: scheduled,
            matchedLog: log,
            matchingBasis: matchingBasis,
            result: ScheduledWorkoutResult(
              planItemId: scheduled.id,
              workoutId: log?.id,
              status: WorkoutCompletionStatus.needsReview,
              completionRatio: null,
              evaluatedAt: now,
              algorithmVersion:
                  TrainingMetricsEngine.completionAlgorithmVersion,
              reason: '计划缺少明确的主目标、目标分钟或训练项目，需要人工核对。',
            ),
          ),
        );
        continue;
      }

      final PlannedWorkoutTarget plan = PlannedWorkoutTarget(
        planItemId: scheduled.id,
        scheduledAt: scheduled.scheduledDate,
        discipline: discipline,
        targets: <CompletionTargetKind, double>{
          CompletionTargetKind.duration: scheduled.targetMinutes!.toDouble(),
        },
        primaryTargetKind: scheduled.primaryTargetKind,
      );
      final CompletedWorkoutFact? workoutFact = log == null
          ? null
          : CompletedWorkoutFact(
              workoutId: log.id,
              planItemId: scheduled.id,
              occurredAt: log.date,
              discipline: discipline,
              actualValues: <CompletionTargetKind, double>{
                CompletionTargetKind.duration:
                    log.actualDurationMinutes.toDouble(),
              },
            );
      result.add(
        ScheduledWorkoutEvaluation(
          workout: scheduled,
          matchedLog: log,
          matchingBasis: matchingBasis,
          result: engine.evaluateCompletion(
            plan: plan,
            workout: workoutFact,
            now: now,
          ),
        ),
      );
    }
    return result;
  }

  _TrainingLogMatch? _matchingLog({
    required ScheduledWorkout scheduled,
    required List<TrainingLog> logs,
    required Set<int> usedLogIndexes,
  }) {
    bool isCandidate(int index) {
      final TrainingLog log = logs[index];
      return !usedLogIndexes.contains(index) &&
          log.isSessionRecord &&
          _sameLocalDate(log.date, scheduled.scheduledDate);
    }

    // 新日志使用独立 planItemId；旧日志仅通过 workoutDayId
    // 兼容匹配，避免把训练日 ID 冒充计划项 ID。
    for (int index = 0; index < logs.length; index += 1) {
      if (isCandidate(index) && logs[index].planItemId == scheduled.id) {
        return _TrainingLogMatch(index, 'plan_item_id');
      }
    }
    for (int index = 0; index < logs.length; index += 1) {
      if (isCandidate(index) && logs[index].workoutDayId == scheduled.id) {
        return _TrainingLogMatch(index, 'legacy_plan_item_id');
      }
    }
    for (int index = 0; index < logs.length; index += 1) {
      if (isCandidate(index) &&
          logs[index].workoutDayId == scheduled.workoutDayId) {
        return _TrainingLogMatch(index, 'workout_day_id');
      }
    }
    return null;
  }

  String _matchingBasis({
    required ScheduledWorkout scheduled,
    required String? matchKind,
  }) {
    return 'plan_item_id=${Uri.encodeComponent(scheduled.id)};'
        'workout_day_id=${Uri.encodeComponent(scheduled.workoutDayId)};'
        'local_date=${_dateKey(scheduled.scheduledDate)};'
        'match=${matchKind ?? 'none'}';
  }

  List<ScheduledWorkout> _weekWorkouts({
    required List<ScheduledWorkout> workouts,
    required ScheduledWorkout? scheduledTodayWorkout,
    required DateTime now,
  }) {
    final DateTime start = _weekStart(now);
    final DateTime end = start.add(const Duration(days: 7));
    final List<ScheduledWorkout> result = workouts
        .where((ScheduledWorkout item) =>
            !item.scheduledDate.isBefore(start) &&
            item.scheduledDate.isBefore(end))
        .toList();
    final ScheduledWorkout? today = scheduledTodayWorkout;
    if (today != null &&
        !today.scheduledDate.isBefore(start) &&
        today.scheduledDate.isBefore(end) &&
        !result.any((ScheduledWorkout item) => item.id == today.id)) {
      result.add(today);
    }
    return result;
  }

  String _todayDecisionLabel(List<ScheduledWorkoutResult> results) {
    if (results.isEmpty) return '暂无可计算计划';
    if (results.any((ScheduledWorkoutResult item) =>
        item.effectiveStatus == WorkoutCompletionStatus.needsReview)) {
      final bool hasLog =
          results.any((ScheduledWorkoutResult item) => item.workoutId != null);
      return hasLog ? '已记录，待核对主目标' : '待核对主目标';
    }
    if (results.every((ScheduledWorkoutResult item) =>
        item.effectiveStatus == WorkoutCompletionStatus.cancelled)) {
      return '今日计划已取消';
    }
    if (results.every((ScheduledWorkoutResult item) =>
        item.effectiveStatus == WorkoutCompletionStatus.completed)) {
      return '已完成';
    }
    if (results.any((ScheduledWorkoutResult item) =>
            item.effectiveStatus == WorkoutCompletionStatus.partial) ||
        results.any((ScheduledWorkoutResult item) =>
            item.effectiveStatus == WorkoutCompletionStatus.completed)) {
      return '部分完成';
    }
    if (results.any((ScheduledWorkoutResult item) =>
        item.effectiveStatus == WorkoutCompletionStatus.pending)) {
      return '待训练';
    }
    return '未完成';
  }

  String _localConsistencyLabel(WeeklyConsistencyResult result) {
    if (result.status == MetricStatus.unavailable) {
      return '暂无可计算计划';
    }
    if (result.status != MetricStatus.ready || result.value == null) {
      return '数据积累中';
    }
    return '${(result.value!.clamp(0, 1) * 100).round()}%';
  }

  String _compatibleLoadLabel({
    required List<TrainingLog> logs,
    required DateTime now,
  }) {
    final TrainingMetricsEngine engine = TrainingMetricsEngine();
    final List<TrainingLoadValue> values = <TrainingLoadValue>[];
    for (final TrainingLog log in logs) {
      if (!log.isSessionRecord || log.actualDurationMinutes <= 0) continue;
      values.addAll(
        engine.calculateLoadSeries(
          input: TrainingLoadInput(
            workoutId: log.id,
            occurredOn: log.date,
            discipline: WorkoutDiscipline.other,
            durationMinutes: log.actualDurationMinutes.toDouble(),
            rpe: log.rpe >= 1 && log.rpe <= 10 ? log.rpe.toDouble() : null,
            averageHeartRate: null,
            restingHeartRate: null,
            maxHeartRate: null,
            heartRateCoverage: 0,
            biologicalSex: BiologicalSex.unknown,
          ),
        ),
      );
    }
    return engine.calculateAcwr(values: values, asOf: now).loadStateLabel;
  }

  String _storedLoadLabel(MetricAggregate metric) {
    if (metric.status != MetricStatus.ready || metric.value == null) {
      return _statusLabel(metric.status, prefix: '负荷状态：');
    }
    final double ratio = metric.value!;
    if (ratio < 0.8) return '负荷状态：恢复';
    if (ratio <= 1.3) return '负荷状态：适中';
    return '负荷状态：偏高';
  }

  String _consistencyLabel(MetricAggregate metric) {
    if (metric.status != MetricStatus.ready || metric.value == null) {
      return _statusLabel(metric.status);
    }
    return '${(metric.value!.clamp(0, 1) * 100).round()}%';
  }

  String _statusLabel(MetricStatus status, {String prefix = ''}) {
    final String label = switch (status) {
      MetricStatus.ready => '数据不足',
      MetricStatus.accumulating => '数据积累中',
      MetricStatus.unavailable => '当前不可用',
      MetricStatus.invalidated => '等待重算',
      MetricStatus.failed => '计算失败',
    };
    return '$prefix$label';
  }
}

class _TrainingLogMatch {
  const _TrainingLogMatch(this.index, this.kind);

  final int index;
  final String kind;
}

MetricAggregate? _findMetric(
  List<MetricAggregate> metrics,
  bool Function(MetricAggregate item) matches,
) {
  for (final MetricAggregate metric in metrics) {
    if (matches(metric)) return metric;
  }
  return null;
}

DateTime _weekStart(DateTime value) {
  final DateTime date = DateTime(value.year, value.month, value.day);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

bool _sameLocalDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
