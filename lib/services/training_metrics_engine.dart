import 'dart:math' as math;

import '../data/models/training_metrics.dart';

/// TrainMate L1/L2/L3 的纯 Dart 计算入口，不读取存储也不修改训练计划。
class TrainingMetricsEngine {
  static const String completionAlgorithmVersion = 'trainmate-l1-completion-v1';
  static const String loadAlgorithmVersion = 'trainmate-l1-load-v1';
  static const String acwrAlgorithmVersion = 'trainmate-l1-acwr-v1';
  static const String samplingAlgorithmVersion = 'trainmate-sampling-v1';
  static const String aerobicDecouplingAlgorithmVersion =
      'trainmate-l2-aerobic-decoupling-v1';
  static const List<double> aerobicDecouplingInterpretationThresholds =
      <double>[5, 10];

  ScheduledWorkoutResult evaluateCompletion({
    required PlannedWorkoutTarget? plan,
    required CompletedWorkoutFact? workout,
    required DateTime now,
  }) {
    if (plan == null) {
      return ScheduledWorkoutResult(
        planItemId: null,
        workoutId: workout?.workoutId,
        status: WorkoutCompletionStatus.notPlanned,
        completionRatio: null,
        evaluatedAt: now,
        algorithmVersion: completionAlgorithmVersion,
        reason: '没有可匹配的计划训练项。',
      );
    }
    if (plan.cancelled) {
      return ScheduledWorkoutResult(
        planItemId: plan.planItemId,
        workoutId: workout?.workoutId,
        status: WorkoutCompletionStatus.cancelled,
        completionRatio: null,
        evaluatedAt: now,
        algorithmVersion: completionAlgorithmVersion,
        reason: '该计划训练项已取消，不计入周一致性分母。',
      );
    }

    final CompletionTargetKind? targetKind = plan.primaryTargetKind ??
        (plan.targets.length == 1 ? plan.targets.keys.single : null);
    if (targetKind == null) {
      return ScheduledWorkoutResult(
        planItemId: plan.planItemId,
        workoutId: workout?.workoutId,
        status: WorkoutCompletionStatus.needsReview,
        completionRatio: null,
        evaluatedAt: now,
        algorithmVersion: completionAlgorithmVersion,
        reason: '计划包含多个目标但未声明主目标，需要人工核对。',
      );
    }
    final double target = plan.targets[targetKind] ?? 0;
    if (target <= 0) {
      return ScheduledWorkoutResult(
        planItemId: plan.planItemId,
        workoutId: workout?.workoutId,
        status: WorkoutCompletionStatus.needsReview,
        completionRatio: null,
        evaluatedAt: now,
        algorithmVersion: completionAlgorithmVersion,
        reason: '计划主目标缺失或无效，需要人工核对。',
      );
    }
    if (workout == null) {
      final bool planDayHasEnded = _dateOnly(now).isAfter(
        _dateOnly(plan.rescheduledTo ?? plan.scheduledAt),
      );
      return ScheduledWorkoutResult(
        planItemId: plan.planItemId,
        workoutId: null,
        status: planDayHasEnded
            ? WorkoutCompletionStatus.missed
            : WorkoutCompletionStatus.pending,
        completionRatio: planDayHasEnded ? 0 : null,
        evaluatedAt: now,
        algorithmVersion: completionAlgorithmVersion,
        reason: planDayHasEnded ? '计划日已结束且没有训练记录。' : '计划日尚未结束，等待训练记录。',
      );
    }
    if (workout.discipline != plan.discipline ||
        (workout.planItemId != null && workout.planItemId != plan.planItemId)) {
      return ScheduledWorkoutResult(
        planItemId: plan.planItemId,
        workoutId: workout.workoutId,
        status: WorkoutCompletionStatus.needsReview,
        completionRatio: null,
        evaluatedAt: now,
        algorithmVersion: completionAlgorithmVersion,
        reason: '训练项目或明确计划关联不一致，需要人工核对。',
      );
    }
    final double actual = workout.actualValues[targetKind] ?? 0;
    final double ratio = (actual / target).clamp(0, double.infinity).toDouble();
    final WorkoutCompletionStatus status = ratio >= 0.9
        ? WorkoutCompletionStatus.completed
        : ratio >= 0.5
            ? WorkoutCompletionStatus.partial
            : WorkoutCompletionStatus.missed;
    return ScheduledWorkoutResult(
      planItemId: plan.planItemId,
      workoutId: workout.workoutId,
      status: status,
      completionRatio: ratio,
      evaluatedAt: now,
      algorithmVersion: completionAlgorithmVersion,
      reason: '按主目标 ${targetKind.name} 计算，实际完成 ${(ratio * 100).round()}%。',
    );
  }

  WeeklyConsistencyResult calculateWeeklyConsistency(
    List<ScheduledWorkoutResult> results,
  ) {
    final List<ScheduledWorkoutResult> planned = results
        .where(
          (ScheduledWorkoutResult item) =>
              item.effectiveStatus != WorkoutCompletionStatus.cancelled &&
              item.effectiveStatus != WorkoutCompletionStatus.notPlanned,
        )
        .toList();
    if (planned.isEmpty) {
      return const WeeklyConsistencyResult(
        status: MetricStatus.unavailable,
        value: null,
        completedCount: 0,
        denominator: 0,
        reason: '本周暂无可计算计划。',
      );
    }
    if (planned.any(
      (ScheduledWorkoutResult item) =>
          item.effectiveStatus == WorkoutCompletionStatus.pending ||
          item.effectiveStatus == WorkoutCompletionStatus.needsReview,
    )) {
      return WeeklyConsistencyResult(
        status: MetricStatus.accumulating,
        value: null,
        completedCount: planned
            .where((ScheduledWorkoutResult item) =>
                item.effectiveStatus == WorkoutCompletionStatus.completed)
            .length,
        denominator: planned.length,
        reason: '本周仍有待完成或待核对训练项。',
      );
    }
    final int completed = planned
        .where((ScheduledWorkoutResult item) =>
            item.effectiveStatus == WorkoutCompletionStatus.completed)
        .length;
    return WeeklyConsistencyResult(
      status: MetricStatus.ready,
      value: completed / planned.length,
      completedCount: completed,
      denominator: planned.length,
      reason: '仅 completed 计入分子，取消项不进入分母。',
    );
  }

  List<TrainingLoadValue> calculateLoadSeries({
    required TrainingLoadInput input,
  }) {
    if (input.durationMinutes <= 0) return const <TrainingLoadValue>[];
    final List<TrainingLoadValue> result = <TrainingLoadValue>[];
    final double? averageHeartRate = input.averageHeartRate;
    final double? restingHeartRate = input.restingHeartRate;
    final double? maxHeartRate = input.maxHeartRate;
    final bool validSex = input.biologicalSex == BiologicalSex.male ||
        input.biologicalSex == BiologicalSex.female;
    final bool validHeartRate = averageHeartRate != null &&
        restingHeartRate != null &&
        maxHeartRate != null &&
        maxHeartRate > restingHeartRate &&
        averageHeartRate > restingHeartRate;
    if (validSex && validHeartRate && input.heartRateCoverage >= 0.6) {
      final double heartRateReserve = ((averageHeartRate - restingHeartRate) /
              (maxHeartRate - restingHeartRate))
          .clamp(0, 1)
          .toDouble();
      final bool male = input.biologicalSex == BiologicalSex.male;
      final double k1 = male ? 0.64 : 0.86;
      final double k2 = male ? 1.92 : 1.67;
      result.add(
        TrainingLoadValue(
          workoutId: input.workoutId,
          occurredOn: input.occurredOn,
          method: LoadMethod.banisterTrimp,
          value: input.durationMinutes *
              heartRateReserve *
              k1 *
              math.exp(k2 * heartRateReserve),
          durationMinutes: input.durationMinutes,
          estimated: false,
          coverage: input.heartRateCoverage.clamp(0, 1).toDouble(),
          reason: '使用有效生理性别、HRmax、HRrest 和平均心率计算。',
        ),
      );
    }

    final double? rpe = input.rpe;
    if (rpe != null && rpe >= 1 && rpe <= 10) {
      result.add(
        TrainingLoadValue(
          workoutId: input.workoutId,
          occurredOn: input.occurredOn,
          method: LoadMethod.sessionRpe,
          value: input.durationMinutes * rpe,
          durationMinutes: input.durationMinutes,
          estimated: false,
          coverage: 1,
          reason: '按实际训练时长与用户 RPE 计算。',
        ),
      );
    }
    if (result.isEmpty) {
      result.add(
        TrainingLoadValue(
          workoutId: input.workoutId,
          occurredOn: input.occurredOn,
          method: LoadMethod.durationEstimate,
          value: input.durationMinutes * _durationLoadFactor(input.discipline),
          durationMinutes: input.durationMinutes,
          estimated: true,
          coverage: 0,
          reason: '缺少可用心率和 RPE，按时长与项目系数估算。',
        ),
      );
    }
    return List<TrainingLoadValue>.unmodifiable(result);
  }

  AcwrResult calculateAcwr({
    required List<TrainingLoadValue> values,
    required DateTime asOf,
    bool hasComplete28DayWindow = false,
  }) {
    if (!hasComplete28DayWindow) {
      return const AcwrResult(
        status: MetricStatus.accumulating,
        method: null,
        ratio: null,
        acuteTotal: 0,
        chronicTotal: 0,
        coverage: 0,
        reason: '尚未完成 28 天训练数据同步覆盖，不能计算 ACWR。',
      );
    }
    final DateTime windowStart =
        _dateOnly(asOf).subtract(const Duration(days: 27));
    final DateTime acuteStart =
        _dateOnly(asOf).subtract(const Duration(days: 6));
    for (final LoadMethod method in const <LoadMethod>[
      LoadMethod.banisterTrimp,
      LoadMethod.sessionRpe,
      LoadMethod.durationEstimate,
    ]) {
      final List<TrainingLoadValue> series = values
          .where((TrainingLoadValue item) =>
              item.method == method &&
              !_dateOnly(item.occurredOn).isBefore(windowStart) &&
              !_dateOnly(item.occurredOn).isAfter(_dateOnly(asOf)))
          .toList();
      if (series.isEmpty) continue;
      final double total = series.fold<double>(
        0,
        (double sum, TrainingLoadValue item) => sum + item.value,
      );
      final double acute = series
          .where((TrainingLoadValue item) =>
              !_dateOnly(item.occurredOn).isBefore(acuteStart))
          .fold<double>(
            0,
            (double sum, TrainingLoadValue item) => sum + item.value,
          );
      final double coverage =
          method == LoadMethod.banisterTrimp ? _weightedCoverage(series) : 1;
      if (method == LoadMethod.banisterTrimp && coverage < 0.8) continue;
      final double denominator = total / 28 * 7;
      if (denominator <= 0) continue;
      return AcwrResult(
        status: MetricStatus.ready,
        method: method,
        ratio: acute / denominator,
        acuteTotal: acute,
        chronicTotal: total,
        coverage: coverage,
        reason: '使用完整 28 天的 ${method.code} 单一序列计算，未混入其他负荷口径。',
      );
    }
    return const AcwrResult(
      status: MetricStatus.accumulating,
      method: null,
      ratio: null,
      acuteTotal: 0,
      chronicTotal: 0,
      coverage: 0,
      reason: '尚未形成完整、同口径的 28 天负荷序列。',
    );
  }

  AdjustmentProposal? buildAcwrProposal({
    required AcwrResult result,
    required String athleteProfileId,
    required String planId,
    required String? workoutDayId,
    required String workoutTitle,
    required int originalMinutes,
    required String originalIntensity,
    required bool hasHighIntensityWorkout,
    DateTime? now,
  }) {
    final double? ratio = result.ratio;
    final LoadMethod? method = result.method;
    if (result.status != MetricStatus.ready ||
        ratio == null ||
        ratio <= 1.5 ||
        method == null) {
      return null;
    }
    final DateTime createdAt = now ?? DateTime.now();
    return AdjustmentProposal(
      id: 'adjustment-proposal-$planId-${createdAt.microsecondsSinceEpoch}',
      athleteProfileId: athleteProfileId,
      planId: planId,
      workoutDayId: workoutDayId,
      workoutTitle: workoutTitle,
      triggerMetricCode: 'acwr.${method.code}',
      triggerAlgorithmVersion: acwrAlgorithmVersion,
      explanation: hasHighIntensityWorkout
          ? '同口径 28 天负荷信号偏高，建议把一项高强度训练降低一级；确认前计划不会改变。'
          : '同口径 28 天负荷信号偏高，建议将下周目标时长降低 10%；确认前计划不会改变。',
      originalMinutes: originalMinutes,
      adjustedMinutes: hasHighIntensityWorkout
          ? originalMinutes
          : (originalMinutes * 0.9).round(),
      originalIntensity: originalIntensity,
      adjustedIntensity: hasHighIntensityWorkout ? '降低一级' : originalIntensity,
      status: AdjustmentProposalStatus.proposed,
      createdAt: createdAt,
    );
  }

  HeartRateProcessingResult processHeartRateSamples({
    required List<HeartRateSample> samples,
    required DateTime start,
    required DateTime end,
  }) {
    final List<HeartRateSample> sorted = List<HeartRateSample>.from(samples)
      ..sort((HeartRateSample first, HeartRateSample second) =>
          first.timestamp.compareTo(second.timestamp));
    final List<HeartRateSample> valid = <HeartRateSample>[];
    int rejected = 0;
    for (final HeartRateSample sample in sorted) {
      if (sample.timestamp.isBefore(start) ||
          sample.timestamp.isAfter(end) ||
          sample.bpm < 30 ||
          sample.bpm > 220) {
        rejected += 1;
        continue;
      }
      if (valid.isNotEmpty) {
        final double seconds =
            sample.timestamp.difference(valid.last.timestamp).inMilliseconds /
                1000;
        if (seconds <= 0 ||
            (sample.bpm - valid.last.bpm).abs() / seconds > 10) {
          rejected += 1;
          continue;
        }
      }
      valid.add(sample);
    }

    final List<HeartRateGridPoint> points = <HeartRateGridPoint>[];
    final int totalSeconds = math.max(0, end.difference(start).inSeconds);
    int segmentIndex = 0;
    int rightIndex = 0;
    for (int second = 0; second <= totalSeconds; second += 1) {
      final DateTime timestamp = start.add(Duration(seconds: second));
      while (rightIndex < valid.length &&
          valid[rightIndex].timestamp.isBefore(timestamp)) {
        rightIndex += 1;
      }
      final HeartRateSample? right =
          rightIndex < valid.length ? valid[rightIndex] : null;
      final HeartRateSample? left =
          rightIndex > 0 ? valid[rightIndex - 1] : null;
      if (right != null && right.timestamp == timestamp) {
        if (left != null &&
            right.timestamp.difference(left.timestamp).inSeconds > 30) {
          segmentIndex += 1;
        }
        points.add(
          HeartRateGridPoint(
            timestamp: timestamp,
            bpm: right.bpm,
            interpolated: false,
            segmentIndex: segmentIndex,
          ),
        );
        continue;
      }
      if (left != null && right != null) {
        final int gap = right.timestamp.difference(left.timestamp).inSeconds;
        if (gap <= 10 && gap > 0) {
          final double elapsed =
              timestamp.difference(left.timestamp).inMilliseconds / 1000;
          final double ratio = elapsed / gap;
          points.add(
            HeartRateGridPoint(
              timestamp: timestamp,
              bpm: left.bpm + (right.bpm - left.bpm) * ratio,
              interpolated: true,
              segmentIndex: segmentIndex,
            ),
          );
          continue;
        }
      }
      points.add(
        HeartRateGridPoint(
          timestamp: timestamp,
          bpm: null,
          interpolated: false,
          segmentIndex: segmentIndex,
        ),
      );
    }
    double supportedSeconds = 0;
    for (int index = 1; index < valid.length; index += 1) {
      final int gap = valid[index]
          .timestamp
          .difference(valid[index - 1].timestamp)
          .inSeconds;
      if (gap > 0 && gap <= 10) supportedSeconds += gap;
    }
    return HeartRateProcessingResult(
      points: List<HeartRateGridPoint>.unmodifiable(points),
      rawSampleCount: valid.length,
      rejectedSampleCount: rejected,
      rawCoverage: totalSeconds == 0
          ? (valid.isEmpty ? 0 : 1)
          : (supportedSeconds / totalSeconds).clamp(0, 1).toDouble(),
    );
  }

  List<GpsSample> filterGpsSamples(List<GpsSample> samples) {
    final List<GpsSample> sorted = List<GpsSample>.from(samples)
      ..sort((GpsSample first, GpsSample second) =>
          first.timestamp.compareTo(second.timestamp));
    final List<GpsSample> valid = <GpsSample>[];
    for (final GpsSample sample in sorted) {
      if (sample.horizontalAccuracyMeters <= 0 ||
          sample.horizontalAccuracyMeters > 20) {
        continue;
      }
      if (valid.isNotEmpty) {
        final double seconds =
            sample.timestamp.difference(valid.last.timestamp).inMilliseconds /
                1000;
        if (seconds <= 0) continue;
        final double speed = _haversineMeters(valid.last, sample) / seconds;
        if (speed > 12.5) continue;
      }
      valid.add(sample);
    }
    return List<GpsSample>.unmodifiable(valid);
  }

  GapResult calculateTrainMateGap({
    required double speedMetersPerSecond,
    required double grade,
  }) {
    final double clampedGrade = grade.clamp(-0.10, 0.25).toDouble();
    final double cost =
        1 + 2.9 * clampedGrade + 15.2 * clampedGrade * clampedGrade;
    return GapResult(
      equivalentSpeedMetersPerSecond: math.max(0, speedMetersPerSecond) * cost,
      clampedGrade: clampedGrade,
    );
  }

  VamResult calculateVam({
    required double grade,
    required double elevationGainMeters,
    required Duration duration,
  }) {
    if (grade <= 0.08 || duration.inSeconds < 180 || elevationGainMeters <= 0) {
      return const VamResult(
        status: MetricStatus.accumulating,
        metersPerHour: null,
        label: '本周无有效爬升段',
      );
    }
    return VamResult(
      status: MetricStatus.ready,
      metersPerHour: elevationGainMeters / duration.inSeconds * 3600,
      label: '设备记录有效爬升段',
    );
  }

  PaceReferenceBand buildPaceReferenceBand({
    required List<PaceObservation> observations,
    required DateTime now,
    PaceReferenceBand? existing,
  }) {
    if (existing != null &&
        existing.status == MetricStatus.ready &&
        now.isBefore(existing.expiresAt)) {
      return existing;
    }
    final DateTime windowStart = now.subtract(const Duration(days: 56));
    final List<PaceObservation> valid = observations
        .where((PaceObservation item) =>
            item.isAerobic &&
            !item.occurredAt.isBefore(windowStart) &&
            !item.occurredAt.isAfter(now) &&
            item.paceSecondsPerKm > 0 &&
            item.durationSeconds > 0)
        .toList();
    final Set<String> workoutIds = valid
        .map((PaceObservation item) => item.sourceWorkoutId)
        .where((String item) => item.isNotEmpty)
        .toSet();
    if (workoutIds.length < 3) {
      return PaceReferenceBand(
        status: MetricStatus.accumulating,
        centerSecondsPerKm: null,
        lowerSecondsPerKm: null,
        upperSecondsPerKm: null,
        frozenAt: now,
        expiresAt: now,
        version: 'pace-band-v1-pending',
        sampleCount: workoutIds.length,
        remainingSamples: 3 - workoutIds.length,
      );
    }
    final Map<int, int> durationByBin = <int, int>{};
    for (final PaceObservation item in valid) {
      final int bin = (item.paceSecondsPerKm / 15).floor();
      durationByBin[bin] = (durationByBin[bin] ?? 0) + item.durationSeconds;
    }
    final int winningBin = durationByBin.entries
        .reduce(
          (MapEntry<int, int> first, MapEntry<int, int> second) =>
              first.value >= second.value ? first : second,
        )
        .key;
    final double center = winningBin * 15 + 7.5;
    return PaceReferenceBand(
      status: MetricStatus.ready,
      centerSecondsPerKm: center,
      lowerSecondsPerKm: center * 0.97,
      upperSecondsPerKm: center * 1.03,
      frozenAt: now,
      expiresAt: now.add(const Duration(days: 28)),
      version: 'pace-band-v1-${_dateKey(now)}',
      sampleCount: workoutIds.length,
      remainingSamples: 0,
    );
  }

  L2MetricResult calculateSamePaceHeartRate({
    required List<SteadyPaceSegment> segments,
    required PaceReferenceBand band,
  }) {
    if (band.status != MetricStatus.ready) {
      return const L2MetricResult(
        status: MetricStatus.accumulating,
        value: null,
        unit: 'bpm',
        validDurationSeconds: 0,
        remainingDurationSeconds: 1200,
        reason: '参考配速带尚未建立。',
      );
    }
    final List<SteadyPaceSegment> valid = segments
        .where((SteadyPaceSegment item) =>
            item.warmupExcluded &&
            item.durationSeconds >= 240 &&
            item.grade.abs() < 0.01 &&
            item.paceCoefficientOfVariation < 0.05 &&
            band.contains(item.paceSecondsPerKm) &&
            item.heartRateCoverage >= 0.6 &&
            item.averageHeartRate >= 30 &&
            item.averageHeartRate <= 220)
        .toList();
    final int duration = valid.fold<int>(
      0,
      (int total, SteadyPaceSegment item) => total + item.durationSeconds,
    );
    if (duration < 1200) {
      return L2MetricResult(
        status: MetricStatus.accumulating,
        value: null,
        unit: 'bpm',
        validDurationSeconds: duration,
        remainingDurationSeconds: 1200 - duration,
        reason: '有效稳态段不足 20 分钟。',
      );
    }
    final double weighted = valid.fold<double>(
      0,
      (double total, SteadyPaceSegment item) =>
          total + item.averageHeartRate * item.durationSeconds,
    );
    return L2MetricResult(
      status: MetricStatus.ready,
      value: weighted / duration,
      unit: 'bpm',
      validDurationSeconds: duration,
      remainingDurationSeconds: 0,
      reason: '按参考配速带内稳态段时长加权计算。',
    );
  }

  L2MetricResult calculateRunningEfficiencyFactor({
    required List<SteadyPaceSegment> segments,
  }) {
    final List<SteadyPaceSegment> valid = segments
        .where((SteadyPaceSegment item) =>
            item.warmupExcluded &&
            item.durationSeconds >= 240 &&
            item.grade.abs() < 0.01 &&
            item.paceCoefficientOfVariation < 0.05 &&
            item.paceSecondsPerKm > 0 &&
            item.heartRateCoverage >= 0.6 &&
            item.averageHeartRate >= 30 &&
            item.averageHeartRate <= 220)
        .toList();
    final int duration = valid.fold<int>(
      0,
      (int total, SteadyPaceSegment item) => total + item.durationSeconds,
    );
    if (duration < 1200) {
      return L2MetricResult(
        status: MetricStatus.accumulating,
        value: null,
        unit: '(m/s)/bpm',
        validDurationSeconds: duration,
        remainingDurationSeconds: 1200 - duration,
        reason: '有效平路稳态段不足 20 分钟，或原始心率覆盖率低于 60%。',
      );
    }
    final double weighted = valid.fold<double>(
      0,
      (double total, SteadyPaceSegment item) =>
          total +
          (1000 / item.paceSecondsPerKm / item.averageHeartRate) *
              item.durationSeconds,
    );
    return L2MetricResult(
      status: MetricStatus.ready,
      value: weighted / duration,
      unit: '(m/s)/bpm',
      validDurationSeconds: duration,
      remainingDurationSeconds: 0,
      reason: '仅使用原始心率覆盖率不低于 60% 的有效平路稳态段计算。',
    );
  }

  AerobicDecouplingResult calculateAerobicDecoupling({
    required List<SteadyPaceSegment> segments,
  }) {
    final List<SteadyPaceSegment> valid = segments
        .where(_isValidAerobicDecouplingSegment)
        .toList(growable: false);
    final int totalValidDuration = valid.fold<int>(
      0,
      (int total, SteadyPaceSegment item) => total + item.durationSeconds,
    );
    final Map<String, List<SteadyPaceSegment>> byWorkout =
        <String, List<SteadyPaceSegment>>{};
    for (final SteadyPaceSegment segment in valid) {
      byWorkout
          .putIfAbsent(segment.sourceWorkoutId, () => <SteadyPaceSegment>[])
          .add(segment);
    }

    final List<AerobicDecouplingWorkoutResult> workoutResults =
        <AerobicDecouplingWorkoutResult>[];
    int bestWorkoutDuration = 0;
    for (final MapEntry<String, List<SteadyPaceSegment>> entry
        in byWorkout.entries) {
      final List<SteadyPaceSegment> workoutSegments = entry.value
        ..sort(
          (SteadyPaceSegment first, SteadyPaceSegment second) =>
              first.occurredAt.compareTo(second.occurredAt),
        );
      final int duration = workoutSegments.fold<int>(
        0,
        (int total, SteadyPaceSegment item) => total + item.durationSeconds,
      );
      bestWorkoutDuration = math.max(bestWorkoutDuration, duration);
      // 只有一个汇总段时已经丢失前后半段变化，不能反推两个相同的半段。
      if (duration < 1200 || workoutSegments.length < 2) continue;
      final AerobicDecouplingWorkoutResult? result =
          _calculateWorkoutAerobicDecoupling(
        sourceWorkoutId: entry.key,
        segments: workoutSegments,
      );
      if (result != null) workoutResults.add(result);
    }

    if (workoutResults.isEmpty) {
      final double coverage = totalValidDuration <= 0
          ? 0
          : valid.fold<double>(
                0,
                (double total, SteadyPaceSegment item) =>
                    total + item.heartRateCoverage * item.durationSeconds,
              ) /
              totalValidDuration;
      final int remaining = math.max(0, 1200 - bestWorkoutDuration);
      return AerobicDecouplingResult(
        status: MetricStatus.accumulating,
        value: null,
        validDurationSeconds: totalValidDuration,
        comparableDurationSeconds: 0,
        remainingDurationSeconds: remaining,
        validSegmentCount: valid.length,
        heartRateCoverage: coverage,
        reason: totalValidDuration < 1200
            ? '单次训练有效稳态段不足 20 分钟，还需 ${(remaining / 60).ceil()} 分钟。'
            : remaining > 0
                ? '有效稳态段分散在多次训练中；还需单次训练积累 ${(remaining / 60).ceil()} 分钟，不能跨训练拼接前后半段。'
                : '有效稳态时长已达到门槛，但缺少可区分的前后半段，继续积累分段数据。',
        workouts: const <AerobicDecouplingWorkoutResult>[],
      );
    }

    final int comparableDuration = workoutResults.fold<int>(
      0,
      (int total, AerobicDecouplingWorkoutResult item) =>
          total + item.validDurationSeconds,
    );
    final double weightedValue = workoutResults.fold<double>(
          0,
          (double total, AerobicDecouplingWorkoutResult item) =>
              total + item.decouplingPercent * item.validDurationSeconds,
        ) /
        comparableDuration;
    final double weightedCoverage = workoutResults.fold<double>(
          0,
          (double total, AerobicDecouplingWorkoutResult item) =>
              total + item.heartRateCoverage * item.validDurationSeconds,
        ) /
        comparableDuration;
    return AerobicDecouplingResult(
      status: MetricStatus.ready,
      value: weightedValue,
      validDurationSeconds: totalValidDuration,
      comparableDurationSeconds: comparableDuration,
      remainingDurationSeconds: 0,
      validSegmentCount: valid.length,
      heartRateCoverage: weightedCoverage,
      reason: '先在每次训练内比较前后半段 EF，再按有效时长汇总；该值仅用于产品训练解释，不作为生理结论。',
      workouts: List<AerobicDecouplingWorkoutResult>.unmodifiable(
        workoutResults,
      ),
    );
  }

  SevenDayBodyAverageResult calculateSevenDayBodyAverage({
    required List<BodyObservation> observations,
    required DateTime asOf,
  }) {
    final DateTime end = _dateOnly(asOf);
    final DateTime start = end.subtract(const Duration(days: 6));
    final Map<DateTime, List<double>> byDay = <DateTime, List<double>>{};
    for (final BodyObservation item in observations) {
      final DateTime day = _dateOnly(item.measuredAt);
      if (day.isBefore(start) || day.isAfter(end) || item.value <= 0) continue;
      byDay.putIfAbsent(day, () => <double>[]).add(item.value);
    }
    final Map<DateTime, double> medians = <DateTime, double>{};
    for (final MapEntry<DateTime, List<double>> entry in byDay.entries) {
      final List<double> values = List<double>.from(entry.value)..sort();
      final int middle = values.length ~/ 2;
      medians[entry.key] = values.length.isOdd
          ? values[middle]
          : (values[middle - 1] + values[middle]) / 2;
    }
    if (medians.length < 3) {
      return SevenDayBodyAverageResult(
        status: MetricStatus.accumulating,
        average: null,
        dailyMedians: Map<DateTime, double>.unmodifiable(medians),
        validDayCount: medians.length,
        remainingDays: 3 - medians.length,
      );
    }
    final double average = medians.values
            .fold<double>(0, (double sum, double item) => sum + item) /
        medians.length;
    return SevenDayBodyAverageResult(
      status: MetricStatus.ready,
      average: average,
      dailyMedians: Map<DateTime, double>.unmodifiable(medians),
      validDayCount: medians.length,
      remainingDays: 0,
    );
  }

  DeviceBestSegment buildDeviceBestSegment({
    required String sourceId,
    required double distanceMeters,
    required int durationSeconds,
    bool userConfirmedOfficialRace = false,
  }) {
    return DeviceBestSegment(
      sourceId: sourceId,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      isOfficialRaceResult: userConfirmedOfficialRace,
    );
  }

  double _durationLoadFactor(WorkoutDiscipline discipline) {
    return switch (discipline) {
      WorkoutDiscipline.strength => 0.5,
      WorkoutDiscipline.badminton => 0.8,
      WorkoutDiscipline.trailRun => 1.1,
      WorkoutDiscipline.hyrox => 1.2,
      WorkoutDiscipline.roadRun => 1,
      WorkoutDiscipline.other => 0.75,
    };
  }

  bool _isValidAerobicDecouplingSegment(SteadyPaceSegment item) =>
      item.isAerobic &&
      item.warmupExcluded &&
      item.durationSeconds >= 240 &&
      item.grade.abs() < 0.01 &&
      item.paceCoefficientOfVariation < 0.05 &&
      item.paceSecondsPerKm > 0 &&
      item.heartRateCoverage >= 0.6 &&
      item.averageHeartRate >= 30 &&
      item.averageHeartRate <= 220;

  AerobicDecouplingWorkoutResult? _calculateWorkoutAerobicDecoupling({
    required String sourceWorkoutId,
    required List<SteadyPaceSegment> segments,
  }) {
    final int totalDuration = segments.fold<int>(
      0,
      (int total, SteadyPaceSegment item) => total + item.durationSeconds,
    );
    if (totalDuration < 1200) return null;
    final double halfDuration = totalDuration / 2;
    double elapsed = 0;
    double firstWeightedEfficiency = 0;
    double firstSupportedSeconds = 0;
    double secondWeightedEfficiency = 0;
    double secondSupportedSeconds = 0;
    double coverageWeightedSeconds = 0;
    for (final SteadyPaceSegment segment in segments) {
      final double segmentStart = elapsed;
      final double segmentEnd = elapsed + segment.durationSeconds;
      final double efficiency =
          (1000 / segment.paceSecondsPerKm) / segment.averageHeartRate;
      final double firstOverlap =
          math.max(0, math.min(segmentEnd, halfDuration) - segmentStart);
      final double secondOverlap =
          math.max(0, segmentEnd - math.max(segmentStart, halfDuration));
      firstWeightedEfficiency += efficiency * firstOverlap;
      firstSupportedSeconds += firstOverlap;
      secondWeightedEfficiency += efficiency * secondOverlap;
      secondSupportedSeconds += secondOverlap;
      coverageWeightedSeconds +=
          segment.heartRateCoverage * segment.durationSeconds;
      elapsed = segmentEnd;
    }
    if (firstSupportedSeconds <= 0 || secondSupportedSeconds <= 0) return null;
    final double firstEfficiency =
        firstWeightedEfficiency / firstSupportedSeconds;
    final double secondEfficiency =
        secondWeightedEfficiency / secondSupportedSeconds;
    if (firstEfficiency <= 0 || secondEfficiency <= 0) return null;
    return AerobicDecouplingWorkoutResult(
      sourceWorkoutId: sourceWorkoutId,
      firstHalfEfficiencyFactor: firstEfficiency,
      secondHalfEfficiencyFactor: secondEfficiency,
      decouplingPercent:
          (firstEfficiency - secondEfficiency) / firstEfficiency * 100,
      validDurationSeconds: totalDuration,
      heartRateCoverage: coverageWeightedSeconds / totalDuration,
    );
  }

  double _weightedCoverage(List<TrainingLoadValue> values) {
    final double total = values.fold<double>(
      0,
      (double sum, TrainingLoadValue item) =>
          sum + math.max(0, item.durationMinutes),
    );
    if (total <= 0) return 0;
    return values.fold<double>(
          0,
          (double sum, TrainingLoadValue item) =>
              sum +
              math.max(0, item.durationMinutes) * item.coverage.clamp(0, 1),
        ) /
        total;
  }

  double _haversineMeters(GpsSample first, GpsSample second) {
    const double earthRadiusMeters = 6371000;
    final double firstLatitude = first.latitude * math.pi / 180;
    final double secondLatitude = second.latitude * math.pi / 180;
    final double latitudeDelta =
        (second.latitude - first.latitude) * math.pi / 180;
    final double longitudeDelta =
        (second.longitude - first.longitude) * math.pi / 180;
    final double value =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
            math.cos(firstLatitude) *
                math.cos(secondLatitude) *
                math.sin(longitudeDelta / 2) *
                math.sin(longitudeDelta / 2);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(value), math.sqrt(1 - value));
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
