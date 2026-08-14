import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/services/training_metrics_engine.dart';

void main() {
  final TrainingMetricsEngine engine = TrainingMetricsEngine();

  group('L1 训练完成度', () {
    final DateTime scheduledAt = DateTime(2026, 7, 15, 8);

    PlannedWorkoutTarget plan({
      CompletionTargetKind? primary = CompletionTargetKind.duration,
      Map<CompletionTargetKind, double>? targets,
      bool cancelled = false,
    }) {
      return PlannedWorkoutTarget(
        planItemId: 'plan-item-1',
        scheduledAt: scheduledAt,
        discipline: WorkoutDiscipline.roadRun,
        targets: targets ??
            const <CompletionTargetKind, double>{
              CompletionTargetKind.duration: 60,
            },
        primaryTargetKind: primary,
        cancelled: cancelled,
      );
    }

    CompletedWorkoutFact workout(double actualMinutes) {
      return CompletedWorkoutFact(
        workoutId: 'workout-1',
        planItemId: 'plan-item-1',
        occurredAt: scheduledAt.add(const Duration(hours: 1)),
        discipline: WorkoutDiscipline.roadRun,
        actualValues: <CompletionTargetKind, double>{
          CompletionTargetKind.duration: actualMinutes,
        },
      );
    }

    test('50% 与 90% 边界分别判定为部分完成和完成', () {
      expect(
        engine
            .evaluateCompletion(
              plan: plan(),
              workout: workout(30),
              now: scheduledAt,
            )
            .status,
        WorkoutCompletionStatus.partial,
      );
      expect(
        engine
            .evaluateCompletion(
              plan: plan(),
              workout: workout(54),
              now: scheduledAt,
            )
            .status,
        WorkoutCompletionStatus.completed,
      );
    });

    test('计划日尚未结束且无记录时保持 pending', () {
      final ScheduledWorkoutResult result = engine.evaluateCompletion(
        plan: plan(),
        workout: null,
        now: DateTime(2026, 7, 15, 18),
      );
      expect(result.status, WorkoutCompletionStatus.pending);
    });

    test('旧计划含多个目标且缺少主目标时进入 needsReview', () {
      final ScheduledWorkoutResult result = engine.evaluateCompletion(
        plan: plan(
          primary: null,
          targets: const <CompletionTargetKind, double>{
            CompletionTargetKind.duration: 60,
            CompletionTargetKind.distance: 10000,
          },
        ),
        workout: workout(60),
        now: scheduledAt,
      );
      expect(result.status, WorkoutCompletionStatus.needsReview);
    });

    test('无计划周明确不可计算而不是 0% 或 100%', () {
      final WeeklyConsistencyResult result =
          engine.calculateWeeklyConsistency(const <ScheduledWorkoutResult>[]);
      expect(result.status, MetricStatus.unavailable);
      expect(result.value, isNull);
      expect(result.denominator, 0);
    });
  });

  group('L1 多口径负荷与 ACWR', () {
    TrainingLoadInput input({
      BiologicalSex sex = BiologicalSex.unknown,
      double coverage = 0.55,
      double? rpe,
      DateTime? occurredOn,
    }) {
      return TrainingLoadInput(
        workoutId: 'workout-load',
        occurredOn: occurredOn ?? DateTime(2026, 7, 15),
        discipline: WorkoutDiscipline.roadRun,
        durationMinutes: 60,
        rpe: rpe,
        averageHeartRate: 150,
        restingHeartRate: 55,
        maxHeartRate: 190,
        heartRateCoverage: coverage,
        biologicalSex: sex,
      );
    }

    test('未知生理性别或 55% 覆盖率都不计算 Banister TRIMP', () {
      final List<TrainingLoadValue> unknownSex =
          engine.calculateLoadSeries(input: input(coverage: 0.9));
      final List<TrainingLoadValue> lowCoverage = engine.calculateLoadSeries(
        input: input(sex: BiologicalSex.female),
      );
      expect(
        unknownSex.any((TrainingLoadValue item) =>
            item.method == LoadMethod.banisterTrimp),
        isFalse,
      );
      expect(
        lowCoverage.any((TrainingLoadValue item) =>
            item.method == LoadMethod.banisterTrimp),
        isFalse,
      );
    });

    test('有 RPE 生成独立 session-RPE，无 RPE 使用时长估算', () {
      final List<TrainingLoadValue> withRpe =
          engine.calculateLoadSeries(input: input(rpe: 6));
      final List<TrainingLoadValue> withoutRpe =
          engine.calculateLoadSeries(input: input());
      expect(
        withRpe
            .singleWhere(
              (TrainingLoadValue item) => item.method == LoadMethod.sessionRpe,
            )
            .value,
        360,
      );
      expect(withoutRpe, hasLength(1));
      expect(withoutRpe.single.method, LoadMethod.durationEstimate);
      expect(withoutRpe.single.estimated, isTrue);
    });

    test('28 天只用同一种方法计算 ACWR，高于 1.5 只生成待确认建议', () {
      final DateTime asOf = DateTime(2026, 7, 28);
      final List<TrainingLoadValue> values = <TrainingLoadValue>[
        for (int index = 0; index < 28; index += 1)
          TrainingLoadValue(
            workoutId: 'load-$index',
            occurredOn: asOf.subtract(Duration(days: 27 - index)),
            method: LoadMethod.sessionRpe,
            value: index >= 21 ? 300 : 50,
            durationMinutes: 60,
            estimated: false,
            coverage: 1,
            reason: '测试负荷',
          ),
        TrainingLoadValue(
          workoutId: 'duration-noise',
          occurredOn: asOf,
          method: LoadMethod.durationEstimate,
          value: 10000,
          durationMinutes: 60,
          estimated: true,
          coverage: 0,
          reason: '不应混算',
        ),
      ];

      final AcwrResult result = engine.calculateAcwr(
        values: values,
        asOf: asOf,
        hasComplete28DayWindow: true,
      );
      expect(result.status, MetricStatus.ready);
      expect(result.method, LoadMethod.sessionRpe);
      expect(result.ratio, greaterThan(1.5));

      final AdjustmentProposal? proposal = engine.buildAcwrProposal(
        result: result,
        athleteProfileId: 'athlete-1',
        planId: 'plan-1',
        workoutDayId: 'day-1',
        workoutTitle: '间歇跑',
        originalMinutes: 60,
        originalIntensity: '高强度',
        hasHighIntensityWorkout: true,
      );
      expect(proposal, isNotNull);
      expect(proposal!.status, AdjustmentProposalStatus.proposed);
      expect(proposal.triggerMetricCode, contains('session_rpe'));
      expect(proposal.adjustedIntensity, '降低一级');
    });

    test('完整同步窗口内的无训练日按零负荷处理，不强制第一天必须有训练', () {
      final DateTime asOf = DateTime(2026, 7, 28);
      final AcwrResult result = engine.calculateAcwr(
        values: <TrainingLoadValue>[
          for (final int daysAgo in <int>[20, 10, 2])
            TrainingLoadValue(
              workoutId: 'sparse-$daysAgo',
              occurredOn: asOf.subtract(Duration(days: daysAgo)),
              method: LoadMethod.sessionRpe,
              value: daysAgo == 2 ? 300 : 100,
              durationMinutes: 60,
              estimated: false,
              coverage: 1,
              reason: '测试负荷',
            ),
        ],
        asOf: asOf,
        hasComplete28DayWindow: true,
      );

      expect(result.status, MetricStatus.ready);
      expect(result.method, LoadMethod.sessionRpe);
      expect(result.coverage, 1);
    });

    test('同负荷值但时长不同时，TRIMP 覆盖率按训练时长加权', () {
      final DateTime asOf = DateTime(2026, 7, 28);
      final List<TrainingLoadValue> values = <TrainingLoadValue>[
        for (int index = 0; index < 28; index += 1)
          TrainingLoadValue(
            workoutId: 'trimp-$index',
            occurredOn: asOf.subtract(Duration(days: 27 - index)),
            method: LoadMethod.banisterTrimp,
            value: 100,
            durationMinutes: index == 0 ? 90 : 10,
            estimated: false,
            coverage: index == 0 ? 0 : 1,
            reason: '相同负荷值，不同训练时长',
          ),
        for (int index = 0; index < 28; index += 1)
          TrainingLoadValue(
            workoutId: 'rpe-$index',
            occurredOn: asOf.subtract(Duration(days: 27 - index)),
            method: LoadMethod.sessionRpe,
            value: 50,
            durationMinutes: 10,
            estimated: false,
            coverage: 1,
            reason: '可用的 session-RPE 备选序列',
          ),
      ];

      final AcwrResult result = engine.calculateAcwr(
        values: values,
        asOf: asOf,
        hasComplete28DayWindow: true,
      );

      // TRIMP 的时长覆盖率为 270 / 360 = 75%，应降级使用
      // 完整的 session-RPE，而不是按相同负荷值算出 27 / 28。
      expect(result.status, MetricStatus.ready);
      expect(result.method, LoadMethod.sessionRpe);
      expect(result.coverage, 1);
    });

    test('未证明完整同步覆盖时，即使有 28 天记录也保持数据积累中', () {
      final DateTime asOf = DateTime(2026, 7, 28);
      final List<TrainingLoadValue> values = <TrainingLoadValue>[
        for (int index = 0; index < 28; index += 1)
          TrainingLoadValue(
            workoutId: 'load-$index',
            occurredOn: asOf.subtract(Duration(days: 27 - index)),
            method: LoadMethod.sessionRpe,
            value: 100,
            durationMinutes: 30,
            estimated: false,
            coverage: 1,
            reason: '测试负荷',
          ),
      ];

      final AcwrResult result = engine.calculateAcwr(
        values: values,
        asOf: asOf,
      );

      expect(result.status, MetricStatus.accumulating);
      expect(result.ratio, isNull);
      expect(result.reason, contains('同步覆盖'));
    });
  });

  group('采样处理与越野指标', () {
    test('10 秒缺口允许插值，30 秒不切段，超过 30 秒才切段', () {
      final DateTime start = DateTime(2026, 7, 15, 8);
      final HeartRateProcessingResult tenSeconds =
          engine.processHeartRateSamples(
        samples: <HeartRateSample>[
          HeartRateSample(timestamp: start, bpm: 100),
          HeartRateSample(
            timestamp: start.add(const Duration(seconds: 10)),
            bpm: 110,
          ),
        ],
        start: start,
        end: start.add(const Duration(seconds: 10)),
      );
      expect(tenSeconds.points[5].bpm, 105);
      expect(tenSeconds.points[5].interpolated, isTrue);
      expect(tenSeconds.rawSampleCount, 2);
      expect(tenSeconds.rawCoverage, 1);

      final HeartRateProcessingResult thirtySeconds =
          engine.processHeartRateSamples(
        samples: <HeartRateSample>[
          HeartRateSample(timestamp: start, bpm: 100),
          HeartRateSample(
            timestamp: start.add(const Duration(seconds: 30)),
            bpm: 105,
          ),
        ],
        start: start,
        end: start.add(const Duration(seconds: 30)),
      );
      expect(thirtySeconds.points[15].bpm, isNull);
      expect(thirtySeconds.points.last.segmentIndex, 0);

      final HeartRateProcessingResult thirtyOneSeconds =
          engine.processHeartRateSamples(
        samples: <HeartRateSample>[
          HeartRateSample(timestamp: start, bpm: 100),
          HeartRateSample(
            timestamp: start.add(const Duration(seconds: 31)),
            bpm: 105,
          ),
        ],
        start: start,
        end: start.add(const Duration(seconds: 31)),
      );
      expect(thirtyOneSeconds.points.last.segmentIndex, 1);
      expect(thirtyOneSeconds.rawCoverage, 0);
    });

    test('剔除异常心率、低精度 GPS 和不可能跑速', () {
      final DateTime start = DateTime(2026, 7, 15, 8);
      final HeartRateProcessingResult heartRate =
          engine.processHeartRateSamples(
        samples: <HeartRateSample>[
          HeartRateSample(timestamp: start, bpm: 100),
          HeartRateSample(
            timestamp: start.add(const Duration(seconds: 1)),
            bpm: 150,
          ),
          HeartRateSample(
            timestamp: start.add(const Duration(seconds: 2)),
            bpm: 20,
          ),
          HeartRateSample(
            timestamp: start.add(const Duration(seconds: 2)),
            bpm: 105,
          ),
        ],
        start: start,
        end: start.add(const Duration(seconds: 2)),
      );
      expect(heartRate.rawSampleCount, 2);
      expect(heartRate.rejectedSampleCount, 2);

      final List<GpsSample> gps = engine.filterGpsSamples(<GpsSample>[
        GpsSample(
          timestamp: start,
          latitude: 0,
          longitude: 0,
          horizontalAccuracyMeters: 5,
        ),
        GpsSample(
          timestamp: start.add(const Duration(seconds: 1)),
          latitude: 0.001,
          longitude: 0,
          horizontalAccuracyMeters: 5,
        ),
        GpsSample(
          timestamp: start.add(const Duration(seconds: 5)),
          latitude: 0,
          longitude: 0.00005,
          horizontalAccuracyMeters: 25,
        ),
        GpsSample(
          timestamp: start.add(const Duration(seconds: 10)),
          latitude: 0,
          longitude: 0.0001,
          horizontalAccuracyMeters: 5,
        ),
      ]);
      expect(gps, hasLength(2));
      expect(gps.last.timestamp, start.add(const Duration(seconds: 10)));
    });

    test('TrainMate GAP v1 保持实验标记，VAM 只接受有效爬升段', () {
      final GapResult gap = engine.calculateTrainMateGap(
        speedMetersPerSecond: 3,
        grade: -0.20,
      );
      expect(GapResult.modelName, 'TrainMate GAP v1');
      expect(GapResult.experimental, isTrue);
      expect(gap.clampedGrade, -0.10);

      expect(
        engine
            .calculateVam(
              grade: 0.08,
              elevationGainMeters: 30,
              duration: const Duration(minutes: 3),
            )
            .label,
        '本周无有效爬升段',
      );
      final VamResult valid = engine.calculateVam(
        grade: 0.09,
        elevationGainMeters: 30,
        duration: const Duration(minutes: 3),
      );
      expect(valid.status, MetricStatus.ready);
      expect(valid.metersPerHour, 600);
    });
  });

  group('L2 配速带与最低样本', () {
    test('少于三次训练时积累，建立后冻结四周', () {
      final DateTime now = DateTime(2026, 7, 15);
      PaceObservation observation(
        int day,
        double pace, {
        String? workoutId,
      }) =>
          PaceObservation(
            sourceWorkoutId: workoutId ?? 'workout-$day',
            occurredAt: now.subtract(Duration(days: day)),
            paceSecondsPerKm: pace,
            durationSeconds: 1800,
            isAerobic: true,
          );
      final PaceReferenceBand pending = engine.buildPaceReferenceBand(
        observations: <PaceObservation>[
          observation(1, 360),
          observation(3, 365),
        ],
        now: now,
      );
      expect(pending.status, MetricStatus.accumulating);
      expect(pending.remainingSamples, 1);

      final PaceReferenceBand ready = engine.buildPaceReferenceBand(
        observations: <PaceObservation>[
          observation(1, 360),
          observation(3, 365),
          observation(5, 362),
        ],
        now: now,
      );
      expect(ready.status, MetricStatus.ready);
      final PaceReferenceBand frozen = engine.buildPaceReferenceBand(
        observations: <PaceObservation>[observation(1, 500)],
        now: now.add(const Duration(days: 7)),
        existing: ready,
      );
      expect(identical(frozen, ready), isTrue);
    });

    test('八周三次门槛按训练来源去重，不把同一训练多个分段重复计数', () {
      final DateTime now = DateTime(2026, 7, 15);
      final List<PaceObservation> sameWorkout = <PaceObservation>[
        for (int index = 0; index < 3; index += 1)
          PaceObservation(
            sourceWorkoutId: 'workout-1',
            occurredAt: now.subtract(Duration(minutes: index)),
            paceSecondsPerKm: 360 + index.toDouble(),
            durationSeconds: 600,
            isAerobic: true,
          ),
      ];

      final PaceReferenceBand result = engine.buildPaceReferenceBand(
        observations: sameWorkout,
        now: now,
      );

      expect(result.status, MetricStatus.accumulating);
      expect(result.sampleCount, 1);
      expect(result.remainingSamples, 2);
    });

    test('同配速心率不足 20 分钟时明确剩余时长', () {
      final DateTime now = DateTime(2026, 7, 15);
      final PaceReferenceBand band = PaceReferenceBand(
        status: MetricStatus.ready,
        centerSecondsPerKm: 360,
        lowerSecondsPerKm: 349.2,
        upperSecondsPerKm: 370.8,
        frozenAt: now,
        expiresAt: now.add(const Duration(days: 28)),
        version: 'pace-band-v1-test',
        sampleCount: 3,
        remainingSamples: 0,
      );
      final SteadyPaceSegment sixMinutes = SteadyPaceSegment(
        sourceWorkoutId: 'workout-steady',
        occurredAt: DateTime(2026, 7, 15),
        paceSecondsPerKm: 360,
        averageHeartRate: 145,
        heartRateCoverage: 0.9,
        durationSeconds: 360,
        grade: 0,
        paceCoefficientOfVariation: 0.02,
        warmupExcluded: true,
        isAerobic: true,
      );
      final L2MetricResult pending = engine.calculateSamePaceHeartRate(
        segments: <SteadyPaceSegment>[
          sixMinutes,
          sixMinutes,
          sixMinutes,
        ],
        band: band,
      );
      expect(pending.status, MetricStatus.accumulating);
      expect(pending.remainingDurationSeconds, 120);

      final L2MetricResult ready = engine.calculateSamePaceHeartRate(
        segments: <SteadyPaceSegment>[
          sixMinutes,
          sixMinutes,
          sixMinutes,
          sixMinutes,
        ],
        band: band,
      );
      expect(ready.status, MetricStatus.ready);
      expect(ready.value, 145);
    });

    test('55% 原始心率覆盖不进入同配速心率和跑步 EF', () {
      final DateTime now = DateTime(2026, 7, 15);
      final PaceReferenceBand band = PaceReferenceBand(
        status: MetricStatus.ready,
        centerSecondsPerKm: 360,
        lowerSecondsPerKm: 349.2,
        upperSecondsPerKm: 370.8,
        frozenAt: now,
        expiresAt: now.add(const Duration(days: 28)),
        version: 'pace-band-v1-test',
        sampleCount: 3,
        remainingSamples: 0,
      );
      final SteadyPaceSegment lowCoverage = SteadyPaceSegment(
        sourceWorkoutId: 'workout-low-coverage',
        occurredAt: DateTime(2026, 7, 15),
        paceSecondsPerKm: 360,
        averageHeartRate: 145,
        heartRateCoverage: 0.55,
        durationSeconds: 1200,
        grade: 0,
        paceCoefficientOfVariation: 0.02,
        warmupExcluded: true,
        isAerobic: true,
      );

      final L2MetricResult samePace = engine.calculateSamePaceHeartRate(
        segments: <SteadyPaceSegment>[lowCoverage],
        band: band,
      );
      final L2MetricResult efficiency = engine.calculateRunningEfficiencyFactor(
        segments: <SteadyPaceSegment>[lowCoverage],
      );

      expect(samePace.status, MetricStatus.accumulating);
      expect(samePace.validDurationSeconds, 0);
      expect(efficiency.status, MetricStatus.accumulating);
      expect(efficiency.validDurationSeconds, 0);
    });

    test('有氧解耦只在同一次训练内比较前后半段 EF', () {
      final DateTime startedAt = DateTime(2026, 7, 15, 8);
      SteadyPaceSegment segment(int index, double heartRate) =>
          SteadyPaceSegment(
            sourceWorkoutId: 'workout-decoupling',
            occurredAt: startedAt.add(Duration(minutes: index * 5)),
            paceSecondsPerKm: 360,
            averageHeartRate: heartRate,
            heartRateCoverage: 0.9,
            durationSeconds: 300,
            grade: 0,
            paceCoefficientOfVariation: 0.02,
            warmupExcluded: true,
            isAerobic: true,
          );

      final AerobicDecouplingResult result = engine.calculateAerobicDecoupling(
        segments: <SteadyPaceSegment>[
          segment(0, 140),
          segment(1, 140),
          segment(2, 147),
          segment(3, 147),
        ],
      );

      expect(result.status, MetricStatus.ready);
      expect(result.value, closeTo(100 * (1 - 140 / 147), 0.000001));
      expect(result.workouts, hasLength(1));
      expect(result.workouts.single.validDurationSeconds, 1200);
      expect(result.reason, contains('不作为生理结论'));
    });

    test('18 分钟有氧稳态保持 accumulating 并明确还差 2 分钟', () {
      final DateTime startedAt = DateTime(2026, 7, 15, 8);
      final AerobicDecouplingResult result = engine.calculateAerobicDecoupling(
        segments: <SteadyPaceSegment>[
          for (int index = 0; index < 3; index += 1)
            SteadyPaceSegment(
              sourceWorkoutId: 'workout-18-minutes',
              occurredAt: startedAt.add(Duration(minutes: index * 6)),
              paceSecondsPerKm: 360,
              averageHeartRate: 145,
              heartRateCoverage: 0.9,
              durationSeconds: 360,
              grade: 0,
              paceCoefficientOfVariation: 0.02,
              warmupExcluded: true,
              isAerobic: true,
            ),
        ],
      );

      expect(result.status, MetricStatus.accumulating);
      expect(result.validDurationSeconds, 18 * 60);
      expect(result.remainingDurationSeconds, 120);
      expect(result.reason, contains('还需 2 分钟'));
    });

    test('两次各 12 分钟训练不能拼接成一次有氧解耦', () {
      final DateTime startedAt = DateTime(2026, 7, 15, 8);
      final AerobicDecouplingResult result = engine.calculateAerobicDecoupling(
        segments: <SteadyPaceSegment>[
          for (final String workoutId in <String>['workout-a', 'workout-b'])
            for (int index = 0; index < 2; index += 1)
              SteadyPaceSegment(
                sourceWorkoutId: workoutId,
                occurredAt: startedAt.add(Duration(minutes: index * 6)),
                paceSecondsPerKm: 360,
                averageHeartRate: 145,
                heartRateCoverage: 0.9,
                durationSeconds: 360,
                grade: 0,
                paceCoefficientOfVariation: 0.02,
                warmupExcluded: true,
                isAerobic: true,
              ),
        ],
      );

      expect(result.status, MetricStatus.accumulating);
      expect(result.validDurationSeconds, 24 * 60);
      expect(result.remainingDurationSeconds, 8 * 60);
      expect(result.reason, contains('不能跨训练拼接'));
    });

    test('非有氧、非平路、不稳定或低心率覆盖段均不进入有氧解耦', () {
      final DateTime startedAt = DateTime(2026, 7, 15, 8);
      SteadyPaceSegment invalid({
        bool isAerobic = true,
        double grade = 0,
        double paceVariation = 0.02,
        double coverage = 0.9,
      }) =>
          SteadyPaceSegment(
            sourceWorkoutId: 'workout-invalid',
            occurredAt: startedAt,
            paceSecondsPerKm: 360,
            averageHeartRate: 145,
            heartRateCoverage: coverage,
            durationSeconds: 1200,
            grade: grade,
            paceCoefficientOfVariation: paceVariation,
            warmupExcluded: true,
            isAerobic: isAerobic,
          );

      final AerobicDecouplingResult result = engine.calculateAerobicDecoupling(
        segments: <SteadyPaceSegment>[
          invalid(isAerobic: false),
          invalid(grade: 0.02),
          invalid(paceVariation: 0.06),
          invalid(coverage: 0.55),
        ],
      );

      expect(result.status, MetricStatus.accumulating);
      expect(result.validDurationSeconds, 0);
      expect(result.remainingDurationSeconds, 1200);
    });
  });

  group('L3 身体均线与里程碑命名', () {
    test('先取每日中位数，至少三个有效日才计算七日均线', () {
      final DateTime asOf = DateTime(2026, 7, 15);
      final SevenDayBodyAverageResult pending =
          engine.calculateSevenDayBodyAverage(
        observations: <BodyObservation>[
          BodyObservation(measuredAt: asOf, value: 70),
          BodyObservation(
            measuredAt: asOf.subtract(const Duration(days: 1)),
            value: 69,
          ),
        ],
        asOf: asOf,
      );
      expect(pending.status, MetricStatus.accumulating);
      expect(pending.remainingDays, 1);

      final SevenDayBodyAverageResult ready =
          engine.calculateSevenDayBodyAverage(
        observations: <BodyObservation>[
          BodyObservation(measuredAt: asOf, value: 70),
          BodyObservation(
            measuredAt: asOf.add(const Duration(hours: 8)),
            value: 72,
          ),
          BodyObservation(
            measuredAt: asOf.subtract(const Duration(days: 1)),
            value: 69,
          ),
          BodyObservation(
            measuredAt: asOf.subtract(const Duration(days: 2)),
            value: 68,
          ),
        ],
        asOf: asOf,
      );
      expect(ready.status, MetricStatus.ready);
      expect(ready.dailyMedians[asOf], 71);
      expect(ready.average, closeTo(69.3333, 0.001));
    });

    test('未经比赛确认的扫描结果只称设备记录最佳分段', () {
      final DeviceBestSegment segment = engine.buildDeviceBestSegment(
        sourceId: 'route-1',
        distanceMeters: 5000,
        durationSeconds: 1200,
      );
      expect(segment.displayName, '设备记录最佳分段');
      expect(segment.displayName, isNot(contains('PB')));
    });
  });
}
