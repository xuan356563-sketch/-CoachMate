import '../data/models/body_metric.dart';
import '../data/models/growth_evidence.dart';
import '../data/models/pain_log.dart';
import '../data/models/race.dart';
import '../data/models/training_log.dart';
import '../data/models/workout_day.dart';

/// 统一计算成长证据、XP 和模型贡献。所有可重复计算的规则放在这里，避免 UI 层产生不同口径。
class GrowthEngine {
  GrowthEngine({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const int currentModelVersion = 1;
  static const int dailyXpCap = 50;
  static const int levelStepXp = 500;

  final DateTime Function() _clock;

  GrowthOccurrence captureOccurrence(
    DateTime occurredAt, {
    DateTime Function(DateTime value)? localize,
    String? timeZoneName,
  }) {
    final DateTime local = localize?.call(occurredAt) ?? occurredAt.toLocal();
    final int offset = localize == null
        ? local.timeZoneOffset.inMinutes
        : local.difference(occurredAt).inMinutes;
    return GrowthOccurrence(
      occurredOn: DateTime(local.year, local.month, local.day),
      timeZoneOffsetMinutes: offset,
      timeZoneName: timeZoneName ?? local.timeZoneName,
    );
  }

  GrowthEvidenceEvent buildTrainingEvent({
    required String athleteProfileId,
    required TrainingLog log,
    required WorkoutDay workout,
    PainLog? painLog,
    DateTime? now,
    GrowthEvidenceEvent? existingEvent,
  }) {
    final DateTime timestamp = now ?? _clock();
    final GrowthOccurrence occurrence = existingEvent == null
        ? captureOccurrence(log.date)
        : GrowthOccurrence(
            occurredOn: existingEvent.occurredOn,
            timeZoneOffsetMinutes: existingEvent.timeZoneOffsetMinutes,
            timeZoneName: existingEvent.timeZoneName,
          );
    final int completion = log.normalizedCompletionPercentage;
    final List<GrowthXpComponent> components = <GrowthXpComponent>[];
    if (completion >= 50) {
      components.add(
        GrowthXpComponent(
          type: GrowthXpComponentType.completion,
          amount: (30 * completion / 100).round(),
          reason: '训练完成率 $completion%',
        ),
      );
    }

    final List<String> dataQualityReasons = <String>[];
    if (log.actualDurationMinutes > 0) dataQualityReasons.add('实际时长');
    if (log.averageHeartRate > 0) dataQualityReasons.add('平均心率');
    if (log.distanceKm > 0 || log.averagePaceSecondsPerKm > 0) {
      dataQualityReasons.add('距离或配速');
    }
    if (log.completedSetCount > 0 || log.exerciseRecords.isNotEmpty) {
      dataQualityReasons.add('动作或组数');
    }
    if (log.rpe >= 1 &&
        log.rpe <= 10 &&
        (log.completionPercentage > 0 || log.isSessionReview)) {
      dataQualityReasons.add('完成率与 RPE');
    }
    if (dataQualityReasons.isNotEmpty) {
      components.add(
        GrowthXpComponent(
          type: GrowthXpComponentType.dataQuality,
          amount: (dataQualityReasons.length * 2).clamp(0, 10).toInt(),
          reason: '已记录${dataQualityReasons.join('、')}',
        ),
      );
    }

    final bool hasSafetyBasis = (painLog?.requiresMedicalAttention ?? false) ||
        workout.decisionType == TrainingDecisionType.deload ||
        workout.decisionType == TrainingDecisionType.recovery ||
        workout.decisionType == TrainingDecisionType.rest;
    if (hasSafetyBasis && (log.downgradeAccepted || log.abortedByUser)) {
      components.add(
        const GrowthXpComponent(
          type: GrowthXpComponentType.safetyDecision,
          amount: 5,
          reason: '接受系统安全降级或主动中止',
        ),
      );
    }

    final List<String> missingData = <String>[];
    if (log.actualDurationMinutes <= 0) missingData.add('实际时长');
    if (log.averageHeartRate <= 0) missingData.add('平均心率');
    if (log.distanceKm <= 0 && log.averagePaceSecondsPerKm <= 0) {
      missingData.add('距离或配速');
    }
    final GrowthConfidence confidence = missingData.length <= 1
        ? GrowthConfidence.high
        : missingData.length <= 2
            ? GrowthConfidence.medium
            : GrowthConfidence.low;

    final bool stimulationInsufficient = completion < 50;
    final bool safetyDecision = components.any(
      (GrowthXpComponent item) =>
          item.type == GrowthXpComponentType.safetyDecision,
    );
    final String description = safetyDecision
        ? '本次以安全决策为优先，系统不会把降级或中止误写成身体提升。'
        : stimulationInsufficient
            ? '本次完成率不足 50%，有效训练刺激不足，未计入完成 XP。'
            : '本次训练已形成可追溯成长证据，模型贡献仅表示训练刺激，不等同于生理检测变化。';

    return GrowthEvidenceEvent(
      eventId: 'training_logs:${log.id}',
      athleteProfileId: athleteProfileId,
      eventType: GrowthEventType.training,
      title: workout.trainingType.label,
      description: description,
      occurredAt: existingEvent?.occurredAt ?? log.date,
      occurredOn: occurrence.occurredOn,
      timeZoneOffsetMinutes: occurrence.timeZoneOffsetMinutes,
      timeZoneName: occurrence.timeZoneName,
      sourceTable: 'training_logs',
      sourceId: log.id,
      xpComponents: List<GrowthXpComponent>.unmodifiable(components),
      impacts: _buildImpacts(
        workout: workout,
        durationMinutes: log.actualDurationMinutes > 0
            ? log.actualDurationMinutes
            : workout.estimatedMinutes,
        rpe: log.rpe,
        completion: completion,
        usePlannedDuration: log.actualDurationMinutes <= 0,
      ),
      confidence: confidence,
      missingData: List<String>.unmodifiable(missingData),
      inputSnapshot: <String, dynamic>{
        'completionPercentage': completion,
        'actualDurationMinutes': log.actualDurationMinutes,
        'distanceKm': log.distanceKm,
        'averageHeartRate': log.averageHeartRate,
        'averagePaceSecondsPerKm': log.averagePaceSecondsPerKm,
        'rpe': log.rpe,
        'trainingType': workout.trainingType.jsonValue,
        'downgradeAccepted': log.downgradeAccepted,
        'abortedByUser': log.abortedByUser,
      },
      modelVersion: existingEvent?.modelVersion ?? currentModelVersion,
      createdAt: existingEvent?.createdAt ?? timestamp,
      updatedAt: timestamp,
    );
  }

  GrowthEvidenceEvent buildHealthEvent({
    required String athleteProfileId,
    required BodyMetric metric,
    DateTime? now,
    GrowthEvidenceEvent? existingEvent,
  }) {
    final DateTime timestamp = now ?? _clock();
    final GrowthOccurrence occurrence = existingEvent == null
        ? captureOccurrence(metric.measuredAt)
        : GrowthOccurrence(
            occurredOn: existingEvent.occurredOn,
            timeZoneOffsetMinutes: existingEvent.timeZoneOffsetMinutes,
            timeZoneName: existingEvent.timeZoneName,
          );
    return GrowthEvidenceEvent(
      eventId: 'health_snapshots:${metric.id}',
      athleteProfileId: athleteProfileId,
      eventType: GrowthEventType.health,
      title: '恢复与健康记录',
      description: '健康数据用于恢复趋势与训练调整，不单独宣称身体能力提升。',
      occurredAt: existingEvent?.occurredAt ?? metric.measuredAt,
      occurredOn: occurrence.occurredOn,
      timeZoneOffsetMinutes: occurrence.timeZoneOffsetMinutes,
      timeZoneName: occurrence.timeZoneName,
      sourceTable: 'health_snapshots',
      sourceId: metric.id,
      xpComponents: const <GrowthXpComponent>[
        GrowthXpComponent(
          type: GrowthXpComponentType.dailyHealth,
          amount: 5,
          reason: '完成健康或恢复记录',
        ),
      ],
      impacts: const <GrowthImpact>[],
      confidence: GrowthConfidence.medium,
      missingData: const <String>[],
      inputSnapshot: <String, dynamic>{
        'hrvMs': metric.hrvMs,
        'restingHeartRate': metric.restingHeartRate,
        'sleepHours': metric.sleepHours,
        'fatigueLevel': metric.fatigueLevel,
        'source': metric.source.jsonValue,
      },
      modelVersion: existingEvent?.modelVersion ?? currentModelVersion,
      createdAt: existingEvent?.createdAt ?? timestamp,
      updatedAt: timestamp,
    );
  }

  DailyXpSettlement settleDailyXp({
    required DateTime occurredOn,
    required List<GrowthEvidenceEvent> events,
  }) {
    final List<GrowthEvidenceEvent> sorted = events
        .where(
          (GrowthEvidenceEvent event) =>
              event.isActive && growthIsSameDay(event.occurredOn, occurredOn),
        )
        .toList()
      ..sort((GrowthEvidenceEvent first, GrowthEvidenceEvent second) {
        final int byTime = first.occurredAt.compareTo(second.occurredAt);
        return byTime != 0 ? byTime : first.eventId.compareTo(second.eventId);
      });
    final Map<String, int> awards = <String, int>{};
    int rawTotal = 0;
    int awardedTotal = 0;
    bool dailyHealthAwarded = false;
    bool safetyAwarded = false;

    for (final GrowthEvidenceEvent event in sorted) {
      int eventAward = 0;
      for (final GrowthXpComponent component in event.xpComponents) {
        rawTotal += component.amount;
        if (component.type == GrowthXpComponentType.dailyHealth &&
            dailyHealthAwarded) {
          continue;
        }
        if (component.type == GrowthXpComponentType.safetyDecision &&
            safetyAwarded) {
          continue;
        }
        final int available = dailyXpCap - awardedTotal;
        if (available <= 0) continue;
        final int awarded = component.amount.clamp(0, available).toInt();
        eventAward += awarded;
        awardedTotal += awarded;
        if (component.type == GrowthXpComponentType.dailyHealth &&
            awarded > 0) {
          dailyHealthAwarded = true;
        }
        if (component.type == GrowthXpComponentType.safetyDecision &&
            awarded > 0) {
          safetyAwarded = true;
        }
      }
      awards[event.eventId] = eventAward;
    }

    return DailyXpSettlement(
      occurredOn: DateTime(occurredOn.year, occurredOn.month, occurredOn.day),
      rawTotal: rawTotal,
      awardedTotal: awardedTotal,
      awardsByEventId: Map<String, int>.unmodifiable(awards),
    );
  }

  GrowthLevelProgress buildLevelProgress({
    required List<GrowthEvidenceEvent> events,
    required GrowthLevelState previous,
  }) {
    final Map<String, DateTime> dates = <String, DateTime>{
      for (final GrowthEvidenceEvent event in events)
        if (event.isActive) event.occurredOnKey: event.occurredOn,
    };
    int currentXp = 0;
    for (final DateTime date in dates.values) {
      currentXp += settleDailyXp(occurredOn: date, events: events).awardedTotal;
    }
    final int peakXp =
        currentXp > previous.peakXp ? currentXp : previous.peakXp;
    final int calculatedLevel = 1 + peakXp ~/ levelStepXp;
    final int level = calculatedLevel > previous.peakLevel
        ? calculatedLevel
        : previous.peakLevel;
    return GrowthLevelProgress(
      currentXp: currentXp,
      peakXp: peakXp,
      level: level,
      nextLevelXp: level * levelStepXp,
    );
  }

  GrowthDashboard buildDashboard({
    required List<GrowthEvidenceEvent> events,
    required GrowthLevelState levelState,
    required WorkoutDay todayWorkout,
    required List<TrainingLog> logs,
    required List<RacePlan> races,
    DateTime? now,
  }) {
    final DateTime current = now ?? _clock();
    final DateTime today = DateTime(current.year, current.month, current.day);
    final List<GrowthEvidenceEvent> active =
        events.where((GrowthEvidenceEvent event) => event.isActive).toList()
          ..sort(
            (GrowthEvidenceEvent first, GrowthEvidenceEvent second) =>
                first.occurredOn.compareTo(second.occurredOn),
          );
    final GrowthEvidenceEvent? first = active.isEmpty ? null : active.first;
    final int? growthDay = first == null
        ? null
        : _calendarDayDifference(first.occurredOn, today) + 1;
    final bool completed = logs.any(
      (TrainingLog log) =>
          log.isSessionRecord &&
          growthIsSameDay(log.date, today) &&
          log.normalizedCompletionPercentage >= 50,
    );
    final List<GrowthTask> tasks = _buildTasks(
      workout: todayWorkout,
      completed: completed,
    );
    final RacePlan? nextRace = _nextRace(races, today);
    final int completedTaskCount =
        tasks.where((GrowthTask item) => item.completed).length;
    return GrowthDashboard(
      growthDay: growthDay,
      level: buildLevelProgress(events: events, previous: levelState),
      tasks: tasks,
      impacts: _buildImpacts(
        workout: todayWorkout,
        durationMinutes: todayWorkout.estimatedMinutes,
        rpe: _plannedRpeFor(todayWorkout.trainingType),
        completion: 100,
        usePlannedDuration: true,
      ),
      completedTaskCount: completedTaskCount,
      totalTaskCount: tasks.length,
      raceCountdownLabel: nextRace == null
          ? '尚未设置比赛'
          : '${nextRace.name} · 还有 ${mathMax(0, _calendarDayDifference(today, nextRace.raceDate))} 天',
      growthStartEventId: first?.eventId,
    );
  }

  WeeklyGrowthReport buildWeeklyGrowthReport({
    required String athleteProfileId,
    required List<TrainingLog> logs,
    required List<BodyMetric> bodyMetrics,
    required List<GrowthEvidenceEvent> events,
    required Map<String, WorkoutDay> workoutsById,
    required int plannedWorkoutCount,
    required DateTime now,
    DateTime? weekStartsOn,
    WeeklyGrowthReport? existing,
    bool manualRegeneration = false,
  }) {
    final DateTime weekStart = growthWeekStart(weekStartsOn ?? now);
    final DateTime weekEnd = growthAddCalendarDays(weekStart, 6);
    final List<TrainingLog> weeklyLogs = logs
        .where(
          (TrainingLog log) =>
              log.isSessionRecord &&
              !_isBeforeDate(log.date, weekStart) &&
              !_isAfterDate(log.date, weekEnd),
        )
        .toList();
    final List<TrainingLog> effectiveLogs = weeklyLogs
        .where((TrainingLog log) => log.normalizedCompletionPercentage >= 50)
        .toList();
    final double completedUnits = weeklyLogs.fold<double>(
      0,
      (double total, TrainingLog log) =>
          total + log.normalizedCompletionPercentage / 100,
    );
    final int safePlanned = plannedWorkoutCount.clamp(1, 7).toInt();
    final double completionRate =
        (completedUnits / safePlanned).clamp(0, 1).toDouble();
    final double runningDistance = weeklyLogs.fold<double>(
      0,
      (double total, TrainingLog log) => total + log.distanceKm,
    );
    final int strengthSessions = effectiveLogs.where((TrainingLog log) {
      final TrainingType? type = workoutsById[log.workoutDayId]?.trainingType;
      return type == TrainingType.strength || type == TrainingType.hyrox;
    }).length;
    final double trainingLoad = weeklyLogs.fold<double>(
      0,
      (double total, TrainingLog log) =>
          total +
          log.actualDurationMinutes *
              log.rpe *
              log.normalizedCompletionPercentage /
              100,
    );
    final List<BodyMetric> weeklyMetrics = bodyMetrics
        .where(
          (BodyMetric metric) =>
              !_isBeforeDate(metric.measuredAt, weekStart) &&
              !_isAfterDate(metric.measuredAt, weekEnd),
        )
        .toList();
    final Map<String, double> indexDimensions = <String, double>{
      if (weeklyLogs.isNotEmpty) '完成度': completionRate * 100,
      if (weeklyLogs.any((TrainingLog log) => log.actualDurationMinutes > 0))
        '负荷': _loadScore(trainingLoad, safePlanned),
      if (weeklyMetrics.length >= 3) '恢复': _recoveryScore(weeklyMetrics),
      if (effectiveLogs.isNotEmpty)
        '专项性': _specificityScore(effectiveLogs, workoutsById),
    };
    const Map<String, double> indexWeights = <String, double>{
      '完成度': 0.35,
      '负荷': 0.25,
      '恢复': 0.25,
      '专项性': 0.15,
    };
    final double availableWeight = indexDimensions.keys.fold<double>(
      0,
      (double total, String key) => total + (indexWeights[key] ?? 0),
    );
    // 这是训练执行层的组合指标，不用于解释生理进步。
    final double? trainingExecutionIndex =
        indexDimensions.length < 2 || availableWeight <= 0
            ? null
            : indexDimensions.entries.fold<double>(
                  0,
                  (double total, MapEntry<String, double> entry) =>
                      total + entry.value * (indexWeights[entry.key] ?? 0),
                ) /
                availableWeight;
    final List<GrowthEvidenceEvent> weeklyEvidence = events
        .where(
          (GrowthEvidenceEvent event) =>
              event.isActive &&
              !_isBeforeDate(event.occurredOn, weekStart) &&
              !_isAfterDate(event.occurredOn, weekEnd),
        )
        .toList()
      ..sort(
        (GrowthEvidenceEvent first, GrowthEvidenceEvent second) =>
            second.occurredAt.compareTo(first.occurredAt),
      );
    final bool isPastWeek = growthWeekStart(now).isAfter(weekStart);
    final DateTime generatedAt = _clock();
    return WeeklyGrowthReport(
      id: existing?.id ??
          'weekly-growth:$athleteProfileId:${growthDateKey(weekStart)}',
      athleteProfileId: athleteProfileId,
      weekKey: growthDateKey(weekStart),
      weekStartsOn: weekStart,
      weekEndsOn: weekEnd,
      generatedAt: generatedAt,
      lockedAt: existing?.lockedAt ??
          (isPastWeek ? growthAddCalendarDays(weekStart, 7) : null),
      regeneratedAt: manualRegeneration ? generatedAt : existing?.regeneratedAt,
      consecutiveTrainingDays: _longestTrainingStreak(effectiveLogs),
      runningDistanceKm: runningDistance,
      strengthSessionCount: strengthSessions,
      completionRate: completionRate,
      trainingLoad: trainingLoad,
      growthIndex: trainingExecutionIndex,
      availableIndexDimensions: indexDimensions.length,
      recoverySummary: weeklyMetrics.length < 3
          ? '恢复数据不足（本周少于 3 条有效健康记录）'
          : '本周已有 ${weeklyMetrics.length} 条健康记录，可用于恢复趋势判断。',
      evidenceEventIds: weeklyEvidence
          .take(5)
          .map((GrowthEvidenceEvent event) => event.eventId)
          .toList(),
      modelVersion: existing?.modelVersion ?? currentModelVersion,
    );
  }

  List<GrowthImpact> _buildImpacts({
    required WorkoutDay workout,
    required int durationMinutes,
    required int rpe,
    required int completion,
    required bool usePlannedDuration,
  }) {
    if (workout.trainingType == TrainingType.rest || durationMinutes <= 0) {
      return const <GrowthImpact>[];
    }
    final double effectiveRpe = rpe.clamp(1, 10).toDouble();
    final double stimulus =
        (durationMinutes * effectiveRpe * (completion / 100) / 20)
            .clamp(0, 20)
            .toDouble();
    final Map<GrowthImpactDimension, double> weights =
        _impactWeightsFor(workout.trainingType);
    final String reason =
        usePlannedDuration ? '缺少实际时长，按计划时长估算' : '按实际时长、RPE 和完成率估算';
    return <GrowthImpact>[
      for (final MapEntry<GrowthImpactDimension, double> entry
          in weights.entries)
        if (entry.value > 0)
          GrowthImpact(
            dimension: entry.key,
            points: stimulus * entry.value,
            estimated: true,
            reason: reason,
          ),
    ];
  }

  Map<GrowthImpactDimension, double> _impactWeightsFor(
    TrainingType type,
  ) {
    const Map<GrowthImpactDimension, double> running =
        <GrowthImpactDimension, double>{
      GrowthImpactDimension.aerobic: 0.65,
      GrowthImpactDimension.strength: 0.10,
      GrowthImpactDimension.movementQuality: 0.05,
      GrowthImpactDimension.recovery: 0.05,
      GrowthImpactDimension.raceReadiness: 0.15,
    };
    switch (type) {
      case TrainingType.easyRun:
      case TrainingType.tempoRun:
      case TrainingType.intervalRun:
      case TrainingType.longRun:
        return running;
      case TrainingType.strength:
        return const <GrowthImpactDimension, double>{
          GrowthImpactDimension.aerobic: 0.10,
          GrowthImpactDimension.strength: 0.65,
          GrowthImpactDimension.movementQuality: 0.10,
          GrowthImpactDimension.recovery: 0.05,
          GrowthImpactDimension.raceReadiness: 0.10,
        };
      case TrainingType.hyrox:
        return const <GrowthImpactDimension, double>{
          GrowthImpactDimension.aerobic: 0.30,
          GrowthImpactDimension.strength: 0.30,
          GrowthImpactDimension.movementQuality: 0.10,
          GrowthImpactDimension.recovery: 0,
          GrowthImpactDimension.raceReadiness: 0.30,
        };
      case TrainingType.mobility:
      case TrainingType.rehab:
        return const <GrowthImpactDimension, double>{
          GrowthImpactDimension.aerobic: 0,
          GrowthImpactDimension.strength: 0.10,
          GrowthImpactDimension.movementQuality: 0.55,
          GrowthImpactDimension.recovery: 0.30,
          GrowthImpactDimension.raceReadiness: 0.05,
        };
      case TrainingType.crossTraining:
        return const <GrowthImpactDimension, double>{
          GrowthImpactDimension.aerobic: 0.35,
          GrowthImpactDimension.strength: 0.25,
          GrowthImpactDimension.movementQuality: 0.15,
          GrowthImpactDimension.recovery: 0.10,
          GrowthImpactDimension.raceReadiness: 0.15,
        };
      case TrainingType.rest:
        return const <GrowthImpactDimension, double>{};
    }
  }

  List<GrowthTask> _buildTasks({
    required WorkoutDay workout,
    required bool completed,
  }) {
    if (workout.trainingType == TrainingType.rest ||
        workout.decisionType == TrainingDecisionType.rest) {
      return <GrowthTask>[
        GrowthTask(
          id: 'planned-recovery',
          title: '按计划恢复',
          completed: completed,
          kind: 'recovery',
        ),
      ];
    }
    final List<GrowthTask> tasks = <GrowthTask>[
      GrowthTask(
        id: 'main-${workout.id}',
        title: workout.trainingType.label,
        completed: completed,
        kind: workout.trainingType.jsonValue,
      ),
    ];
    if (workout.activationSteps.isNotEmpty) {
      tasks.add(
        GrowthTask(
          id: 'activation-${workout.id}',
          title: '激活训练',
          completed: completed,
          kind: 'activation',
        ),
      );
    }
    if (workout.accessoryWork.isNotEmpty) {
      tasks.add(
        GrowthTask(
          id: 'accessory-${workout.id}',
          title: '辅助强化',
          completed: completed,
          kind: 'accessory',
        ),
      );
    }
    return tasks;
  }

  RacePlan? _nextRace(List<RacePlan> races, DateTime today) {
    final List<RacePlan> candidates = races
        .where((RacePlan race) => !_isBeforeDate(race.raceDate, today))
        .toList()
      ..sort((RacePlan first, RacePlan second) =>
          first.raceDate.compareTo(second.raceDate));
    return candidates.isEmpty ? null : candidates.first;
  }

  int _plannedRpeFor(TrainingType type) {
    return switch (type) {
      TrainingType.easyRun => 4,
      TrainingType.tempoRun => 7,
      TrainingType.intervalRun => 8,
      TrainingType.longRun => 6,
      TrainingType.strength => 7,
      TrainingType.hyrox => 8,
      TrainingType.mobility => 3,
      TrainingType.rehab => 3,
      TrainingType.rest => 0,
      TrainingType.crossTraining => 6,
    };
  }

  int _calendarDayDifference(DateTime first, DateTime second) {
    final DateTime firstUtc = DateTime.utc(first.year, first.month, first.day);
    final DateTime secondUtc =
        DateTime.utc(second.year, second.month, second.day);
    return secondUtc.difference(firstUtc).inDays;
  }

  bool _isBeforeDate(DateTime value, DateTime comparison) {
    final DateTime date = DateTime(value.year, value.month, value.day);
    final DateTime target =
        DateTime(comparison.year, comparison.month, comparison.day);
    return date.isBefore(target);
  }

  bool _isAfterDate(DateTime value, DateTime comparison) {
    final DateTime date = DateTime(value.year, value.month, value.day);
    final DateTime target =
        DateTime(comparison.year, comparison.month, comparison.day);
    return date.isAfter(target);
  }

  int mathMax(int first, int second) => first > second ? first : second;

  double _loadScore(double trainingLoad, int plannedWorkoutCount) {
    final double target = plannedWorkoutCount * 240;
    if (target <= 0) return 0;
    final double ratio = trainingLoad / target;
    return (100 - (ratio - 1).abs() * 100).clamp(0, 100).toDouble();
  }

  double _recoveryScore(List<BodyMetric> metrics) {
    final double total = metrics.fold<double>(0, (double sum, BodyMetric item) {
      final double sleep = (item.sleepHours / 8 * 100).clamp(0, 100).toDouble();
      final double hrv = (item.hrvMs / 60 * 100).clamp(0, 100).toDouble();
      final double fatigue =
          (100 - (item.fatigueLevel - 1) * 11).clamp(0, 100).toDouble();
      return sum + (sleep + hrv + fatigue) / 3;
    });
    return total / metrics.length;
  }

  double _specificityScore(
    List<TrainingLog> logs,
    Map<String, WorkoutDay> workoutsById,
  ) {
    if (logs.isEmpty) return 0;
    final int matched = logs.where((TrainingLog log) {
      final TrainingType? type = workoutsById[log.workoutDayId]?.trainingType;
      return type == TrainingType.hyrox ||
          type == TrainingType.tempoRun ||
          type == TrainingType.intervalRun ||
          type == TrainingType.strength;
    }).length;
    return matched / logs.length * 100;
  }

  int _longestTrainingStreak(List<TrainingLog> logs) {
    final List<DateTime> dates = <DateTime>{
      for (final TrainingLog log in logs)
        DateTime(log.date.year, log.date.month, log.date.day),
    }.toList()
      ..sort();
    int longest = 0;
    int current = 0;
    DateTime? previous;
    for (final DateTime date in dates) {
      if (previous == null || _calendarDayDifference(previous, date) == 1) {
        current += 1;
      } else {
        current = 1;
      }
      if (current > longest) longest = current;
      previous = date;
    }
    return longest;
  }
}
