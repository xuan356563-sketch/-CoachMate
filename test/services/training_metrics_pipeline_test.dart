import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/trainmate_structured_database_gateway.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway_contract.dart';
import 'package:trainflow_ai/services/training_metrics_engine.dart';
import 'package:trainflow_ai/services/training_metrics_pipeline.dart';

void main() {
  const String athleteId = 'athlete-a';

  group('训练指标流水线', () {
    test('HealthKit `.running` 未确认上下文时不猜测为公路跑', () async {
      final DateTime start = DateTime.utc(2026, 7, 15, 8);
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..workoutRows['workout-unconfirmed'] = _workoutRow(
          workoutId: 'workout-unconfirmed',
          externalUuid: 'healthkit-workout-unconfirmed',
          start: start,
          durationSeconds: 1800,
        )
        ..workoutRows['workout-unconfirmed']!['source_kind'] = 'healthKit'
        ..workoutRows['workout-unconfirmed']!['run_context'] = 'unspecified';
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: InMemoryTrainingMetricsRepository(),
        healthDataGateway: const _FakeHealthDataGateway(
          workoutDetails: <String, Map<String, Object?>>{},
        ),
        clock: () => DateTime.utc(2026, 7, 15, 9),
      );

      await pipeline.analyzeWorkout(
        athleteProfileId: athleteId,
        workoutId: 'workout-unconfirmed',
      );

      final Map<String, Object?> result = _decodeObject(
        database.savedAnalysisRows.single['result_json'],
      );
      expect(result['discipline'], WorkoutDiscipline.other.name);
    });

    test('55% 心率覆盖且生理性别未知时不生成 Banister TRIMP，也不持久化原始采样', () async {
      final DateTime start = DateTime.utc(2026, 7, 15, 8);
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..workoutRows['workout-a'] = _workoutRow(
          workoutId: 'workout-a',
          externalUuid: 'healthkit-workout-a',
          start: start,
          durationSeconds: 100,
        );
      final List<Map<String, Object?>> heartRateSamples =
          <Map<String, Object?>>[
        for (int second = 0; second <= 55; second += 5)
          <String, Object?>{
            'startTime': start.add(Duration(seconds: second)).toIso8601String(),
            'value': 140 + second / 55,
          },
      ];
      final _FakeHealthDataGateway healthGateway = _FakeHealthDataGateway(
        workoutDetails: <String, Map<String, Object?>>{
          'healthkit-workout-a': <String, Object?>{
            'heartRateSamples': heartRateSamples,
            'routes': <Map<String, Object?>>[
              <String, Object?>{
                'locations': <Map<String, Object?>>[
                  <String, Object?>{
                    'timestamp': start.toIso8601String(),
                    'latitude': 31.2304,
                    'longitude': 121.4737,
                    'horizontalAccuracy': 5,
                    'altitude': 8,
                    'verticalAccuracy': 5,
                  },
                  <String, Object?>{
                    'timestamp': start
                        .add(const Duration(seconds: 100))
                        .toIso8601String(),
                    'latitude': 31.2305,
                    'longitude': 121.4737,
                    'horizontalAccuracy': 5,
                    'altitude': 9,
                    'verticalAccuracy': 5,
                  },
                ],
              },
            ],
          },
        },
      );
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: InMemoryTrainingMetricsRepository(),
        healthDataGateway: healthGateway,
        clock: () => DateTime.utc(2026, 7, 15, 9),
      );

      final WorkoutAnalysisOutcome outcome = await pipeline.analyzeWorkout(
        athleteProfileId: athleteId,
        workoutId: 'workout-a',
      );

      expect(
        outcome.loads.any(
          (TrainingLoadValue item) => item.method == LoadMethod.banisterTrimp,
        ),
        isFalse,
      );
      expect(outcome.loads.single.method, LoadMethod.durationEstimate);
      expect(database.savedAnalysisRows, hasLength(1));
      expect(database.routeAvailableAnalysisIds, <String>['workout-a']);

      final Map<String, Object?> saved = database.savedAnalysisRows.single;
      final Map<String, Object?> quality = _decodeObject(saved['quality_json']);
      expect(quality['heartRateCoverage'], closeTo(0.55, 0.000001));
      expect(database.workoutRows['workout-a']!['heart_rate_sample_count'], 12);
      expect(
        database.workoutRows['workout-a']!['heart_rate_coverage'],
        closeTo(0.55, 0.000001),
      );
      expect(database.workoutRows['workout-a']!['average_heart_rate'],
          isA<double>());
      expect(database.workoutRows['workout-a']!['maximum_heart_rate'],
          isA<double>());

      final String resultJson = saved['result_json']! as String;
      final Map<String, Object?> result = _decodeObject(resultJson);
      expect(result, isNot(contains('heartRateSamples')));
      expect(result, isNot(contains('routes')));
      expect(resultJson, isNot(contains('locations')));
      expect(resultJson, isNot(contains('latitude')));
      expect(resultJson, isNot(contains('longitude')));
      expect(resultJson, isNot(contains('31.2304')));
      expect(resultJson, isNot(contains('121.4737')));
    });

    test('单训练详情明确返回空心率时会清空事实摘要而不保留陈旧值', () async {
      final DateTime start = DateTime.utc(2026, 7, 15, 8);
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..workoutRows['workout-heart-rate-deleted'] = _workoutRow(
          workoutId: 'workout-heart-rate-deleted',
          externalUuid: 'healthkit-heart-rate-deleted',
          start: start,
          durationSeconds: 1800,
        )
        ..workoutRows['workout-heart-rate-deleted']![
            'heart_rate_sample_count'] = 120
        ..workoutRows['workout-heart-rate-deleted']!['heart_rate_coverage'] =
            0.8
        ..workoutRows['workout-heart-rate-deleted']!['maximum_heart_rate'] =
            175.0;
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: InMemoryTrainingMetricsRepository(),
        healthDataGateway: const _FakeHealthDataGateway(
          workoutDetails: <String, Map<String, Object?>>{
            'healthkit-heart-rate-deleted': <String, Object?>{
              'heartRateSamples': <Object?>[],
              'routes': <Object?>[],
            },
          },
        ),
        clock: () => DateTime.utc(2026, 7, 15, 9),
      );

      await pipeline.analyzeWorkout(
        athleteProfileId: athleteId,
        workoutId: 'workout-heart-rate-deleted',
      );

      final Map<String, Object?> row =
          database.workoutRows['workout-heart-rate-deleted']!;
      expect(row['heart_rate_sample_count'], 0);
      expect(row['heart_rate_coverage'], 0);
      expect(row['average_heart_rate'], isNull);
      expect(row['maximum_heart_rate'], isNull);
    });

    test('显式最大心率、生理性别和训练前最近有效静息心率可生成 Banister TRIMP', () async {
      final DateTime start = DateTime.utc(2026, 7, 15, 8);
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..profileRows[athleteId] = <String, Object?>{
          'id': athleteId,
          'biological_sex': 'male',
          'payload_json': jsonEncode(<String, Object?>{
            'maxHeartRate': 190,
          }),
        }
        ..workoutRows['workout-banister'] = _workoutRow(
          workoutId: 'workout-banister',
          externalUuid: 'healthkit-workout-banister',
          start: start,
          durationSeconds: 100,
        )
        ..observationRows.addAll(<Map<String, Object?>>[
          <String, Object?>{
            'athlete_profile_id': athleteId,
            'observation_kind': 'HKQuantityTypeIdentifierRestingHeartRate',
            'observed_at_utc':
                start.subtract(const Duration(days: 2)).toIso8601String(),
            'value': 55,
          },
          <String, Object?>{
            'athlete_profile_id': athleteId,
            'observation_kind': 'HKQuantityTypeIdentifierRestingHeartRate',
            'observed_at_utc':
                start.subtract(const Duration(days: 1)).toIso8601String(),
            'value': 58,
          },
          <String, Object?>{
            'athlete_profile_id': athleteId,
            'observation_kind': 'HKQuantityTypeIdentifierRestingHeartRate',
            'observed_at_utc':
                start.subtract(const Duration(hours: 12)).toIso8601String(),
            'value': 300,
          },
        ]);
      final _FakeHealthDataGateway healthGateway = _FakeHealthDataGateway(
        workoutDetails: <String, Map<String, Object?>>{
          'healthkit-workout-banister': <String, Object?>{
            'heartRateSamples': <Map<String, Object?>>[
              for (int second = 0; second <= 100; second += 5)
                <String, Object?>{
                  'startTime':
                      start.add(Duration(seconds: second)).toIso8601String(),
                  'value': 150,
                },
            ],
          },
        },
      );
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: InMemoryTrainingMetricsRepository(),
        healthDataGateway: healthGateway,
        clock: () => DateTime.utc(2026, 7, 15, 9),
      );

      final WorkoutAnalysisOutcome outcome = await pipeline.analyzeWorkout(
        athleteProfileId: athleteId,
        workoutId: 'workout-banister',
      );

      final TrainingLoadValue load = outcome.loads.single;
      final double reserve = (150 - 58) / (190 - 58);
      final double expected =
          (100 / 60) * reserve * 0.64 * math.exp(1.92 * reserve);
      expect(load.method, LoadMethod.banisterTrimp);
      expect(load.value, closeTo(expected, 0.000001));
      expect(load.durationMinutes, closeTo(100 / 60, 0.000001));
      expect(load.estimated, isFalse);
      expect(load.coverage, 1);
      expect(load.reason, contains('HRmax'));
    });

    test('达到大样本门槛时原始采样处理运行在后台 isolate', () async {
      final DateTime start = DateTime.utc(2026, 7, 15, 8);
      final int sampleCount = TrainingMetricsPipeline.rawSampleIsolateThreshold;
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..workoutRows['workout-large-samples'] = _workoutRow(
          workoutId: 'workout-large-samples',
          externalUuid: 'healthkit-workout-large-samples',
          start: start,
          durationSeconds: sampleCount,
        );
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: InMemoryTrainingMetricsRepository(),
        healthDataGateway: _FakeHealthDataGateway(
          workoutDetails: <String, Map<String, Object?>>{
            'healthkit-workout-large-samples': <String, Object?>{
              'heartRateSamples': <Map<String, Object?>>[
                for (int second = 0; second < sampleCount; second += 1)
                  <String, Object?>{
                    'startTime':
                        start.add(Duration(seconds: second)).toIso8601String(),
                    'value': 140,
                  },
              ],
            },
          },
        ),
        clock: () => DateTime.utc(2026, 7, 15, 9),
      );

      await pipeline.analyzeWorkout(
        athleteProfileId: athleteId,
        workoutId: 'workout-large-samples',
      );

      final Map<String, Object?> quality =
          _decodeObject(database.savedAnalysisRows.single['quality_json']);
      expect(quality['processingMode'], 'backgroundIsolate');
      expect(quality['rawHeartRateSampleCount'], sampleCount);
    });

    test('同步与后台 isolate 对同等连续信号生成一致的五分钟稳态分段', () async {
      final DateTime start = DateTime.utc(2026, 7, 15, 8);
      final List<int> sampleSeconds = <int>[
        for (int second = 600; second <= 1800; second += 10) second,
      ];
      final List<double> latitudeMeters = <double>[
        for (int index = 0; index < sampleSeconds.length; index += 1)
          index * 30,
      ];
      final Map<String, Object?> inlineDetails = _workoutDetailsForGps(
        start: start,
        sampleSeconds: sampleSeconds,
        latitudeMeters: latitudeMeters,
        heartRateEndSecond: 1800,
      );
      final Map<String, Object?> isolateDetails = <String, Object?>{
        'heartRateSamples': <Map<String, Object?>>[
          for (int second = 600; second <= 1800; second += 1)
            <String, Object?>{
              'startTime':
                  start.add(Duration(seconds: second)).toIso8601String(),
              'value': 145,
            },
        ],
        'routes': inlineDetails['routes']!,
      };
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..workoutRows['workout-inline-steady'] = _workoutRow(
          workoutId: 'workout-inline-steady',
          externalUuid: 'healthkit-inline-steady',
          start: start,
          durationSeconds: 1800,
        )
        ..workoutRows['workout-isolate-steady'] = _workoutRow(
          workoutId: 'workout-isolate-steady',
          externalUuid: 'healthkit-isolate-steady',
          start: start,
          durationSeconds: 1800,
        );
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: InMemoryTrainingMetricsRepository(),
        healthDataGateway: _FakeHealthDataGateway(
          workoutDetails: <String, Map<String, Object?>>{
            'healthkit-inline-steady': inlineDetails,
            'healthkit-isolate-steady': isolateDetails,
          },
        ),
        clock: () => DateTime.utc(2026, 7, 15, 10),
      );

      final WorkoutAnalysisOutcome inline = await pipeline.analyzeWorkout(
        athleteProfileId: athleteId,
        workoutId: 'workout-inline-steady',
      );
      final WorkoutAnalysisOutcome isolated = await pipeline.analyzeWorkout(
        athleteProfileId: athleteId,
        workoutId: 'workout-isolate-steady',
      );

      expect(inline.steadySegments, hasLength(4));
      expect(isolated.steadySegments, hasLength(4));
      for (int index = 0; index < 4; index += 1) {
        final SteadyPaceSegment first = inline.steadySegments[index];
        final SteadyPaceSegment second = isolated.steadySegments[index];
        expect(second.occurredAt, first.occurredAt);
        expect(second.durationSeconds, first.durationSeconds);
        expect(second.paceSecondsPerKm, closeTo(first.paceSecondsPerKm, 1e-9));
        expect(second.averageHeartRate, closeTo(first.averageHeartRate, 1e-9));
        expect(second.heartRateCoverage, first.heartRateCoverage);
      }
      expect(
        _decodeObject(
            database.savedAnalysisRows.first['quality_json'])['processingMode'],
        'inline',
      );
      expect(
        _decodeObject(
            database.savedAnalysisRows.last['quality_json'])['processingMode'],
        'backgroundIsolate',
      );
    });

    test('HealthKit 明细瞬时读取异常会向上抛出且不保存降级分析', () async {
      final DateTime start = DateTime.utc(2026, 7, 15, 8);
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..workoutRows['workout-transient-error'] = _workoutRow(
          workoutId: 'workout-transient-error',
          externalUuid: 'healthkit-workout-transient-error',
          start: start,
          durationSeconds: 3600,
        );
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: InMemoryTrainingMetricsRepository(),
        healthDataGateway: const _ThrowingHealthDataGateway(),
      );

      await expectLater(
        pipeline.analyzeWorkout(
          athleteProfileId: athleteId,
          workoutId: 'workout-transient-error',
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            '中文错误',
            contains('HealthKit 明细暂时不可读'),
          ),
        ),
      );
      expect(database.savedAnalysisRows, isEmpty);
    });

    test('周内只有 18 分钟有效稳态段时保持 accumulating，并明确还需 120 秒', () async {
      final DateTime periodStart = DateTime(2026, 7, 13);
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..analysisRows.addAll(<Map<String, Object?>>[
          _analysisRow(
            workoutId: 'history-a',
            occurredOn: DateTime(2026, 6, 15),
            steadyDurationSeconds: 600,
          ),
          _analysisRow(
            workoutId: 'history-b',
            occurredOn: DateTime(2026, 6, 22),
            steadyDurationSeconds: 600,
          ),
          _analysisRow(
            workoutId: 'history-c',
            occurredOn: DateTime(2026, 7, 6),
            steadyDurationSeconds: 600,
          ),
          _analysisRow(
            workoutId: 'current-18-minutes',
            occurredOn: DateTime(2026, 7, 15),
            steadyDurationSeconds: 18 * 60,
          ),
        ]);
      final InMemoryTrainingMetricsRepository repository =
          InMemoryTrainingMetricsRepository();
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: repository,
        healthDataGateway: const _UnsupportedHealthDataGateway(),
        clock: () => DateTime.utc(2026, 7, 20),
      );

      await pipeline.aggregatePeriod(
        athleteProfileId: athleteId,
        period: MetricPeriod.week,
        periodStart: periodStart,
      );

      final List<MetricAggregate> metrics = await repository.listAggregates(
        athleteProfileId: athleteId,
        period: MetricPeriod.week,
        periodStart: periodStart,
      );
      final MetricAggregate samePace = metrics.singleWhere(
        (MetricAggregate item) => item.metricCode == 'same_pace_heart_rate',
      );
      expect(samePace.status, MetricStatus.accumulating);
      expect(samePace.value, isNull);
      expect(samePace.sampleDurationSeconds, 18 * 60);
      expect(samePace.metadata['remainingDurationSeconds'], 120);
      expect(samePace.metadata['reason'], '有效稳态段不足 20 分钟。');
    });

    test('周聚合落库单次训练内的有氧解耦、产品阈值和输入血缘', () async {
      final DateTime periodStart = DateTime(2026, 7, 13);
      final DateTime currentAt = DateTime.utc(2026, 7, 15, 8);
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..analysisRows.addAll(<Map<String, Object?>>[
          _analysisRow(
            workoutId: 'history-a',
            occurredOn: DateTime(2026, 6, 15),
            steadyDurationSeconds: 600,
          ),
          _analysisRow(
            workoutId: 'history-b',
            occurredOn: DateTime(2026, 6, 22),
            steadyDurationSeconds: 600,
          ),
          _analysisRow(
            workoutId: 'history-c',
            occurredOn: DateTime(2026, 7, 6),
            steadyDurationSeconds: 600,
          ),
          _analysisRow(
            workoutId: 'current-decoupling',
            occurredOn: DateTime(2026, 7, 15),
            steadyDurationSeconds: 1200,
            steadySegments: <Map<String, Object?>>[
              for (int index = 0; index < 4; index += 1)
                <String, Object?>{
                  'sourceWorkoutId': 'current-decoupling',
                  'occurredAt': currentAt
                      .add(Duration(minutes: index * 5))
                      .toIso8601String(),
                  'durationSeconds': 300,
                  'paceSecondsPerKm': 360,
                  'grade': 0,
                  'paceCoefficientOfVariation': 0.02,
                  'averageHeartRate': index < 2 ? 140 : 147,
                  'heartRateCoverage': 0.9,
                  'warmupExcluded': true,
                  'isAerobic': true,
                },
            ],
          ),
        ]);
      final InMemoryTrainingMetricsRepository repository =
          InMemoryTrainingMetricsRepository();
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: repository,
        healthDataGateway: const _UnsupportedHealthDataGateway(),
        clock: () => DateTime.utc(2026, 7, 20),
      );

      await pipeline.aggregatePeriod(
        athleteProfileId: athleteId,
        period: MetricPeriod.week,
        periodStart: periodStart,
      );

      final List<MetricAggregate> metrics = await repository.listAggregates(
        athleteProfileId: athleteId,
        period: MetricPeriod.week,
        periodStart: periodStart,
      );
      final MetricAggregate decoupling = metrics.singleWhere(
        (MetricAggregate item) => item.metricCode == 'aerobic_decoupling',
      );
      expect(decoupling.status, MetricStatus.ready);
      expect(decoupling.value, closeTo(100 * (1 - 140 / 147), 0.000001));
      expect(decoupling.sampleDurationSeconds, 1200);
      expect(
        decoupling.algorithmVersion,
        TrainingMetricsEngine.aerobicDecouplingAlgorithmVersion,
      );
      expect(
          decoupling.metadata['interpretationThresholdPercent'], <num>[5, 10]);
      expect(
        decoupling.metadata['interpretation'],
        'product_threshold_not_physiological',
      );
      expect(decoupling.metadata['comparableWorkoutCount'], 1);
      final List<MetricLineage> lineage =
          await repository.listLineage(metricId: decoupling.id);
      expect(lineage, hasLength(1));
      expect(lineage.single.sourceId, 'current-decoupling');
    });

    test('同一训练存在多条分析时只使用当前算法最新完成结果', () async {
      final DateTime periodStart = DateTime(2026, 7, 13);
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..analysisRows.addAll(<Map<String, Object?>>[
          _analysisRow(
            workoutId: 'history-a',
            occurredOn: DateTime(2026, 6, 15),
            steadyDurationSeconds: 600,
          ),
          _analysisRow(
            workoutId: 'history-b',
            occurredOn: DateTime(2026, 6, 22),
            steadyDurationSeconds: 600,
          ),
          _analysisRow(
            workoutId: 'history-c',
            occurredOn: DateTime(2026, 7, 6),
            steadyDurationSeconds: 600,
          ),
          _analysisRow(
            rowId: 'analysis-duplicate-older',
            workoutId: 'duplicate-workout',
            occurredOn: DateTime(2026, 7, 15),
            steadyDurationSeconds: 20 * 60,
            loadValue: 20,
            completedAt: DateTime.utc(2026, 7, 15, 9),
          ),
          _analysisRow(
            rowId: 'analysis-duplicate-current-latest',
            workoutId: 'duplicate-workout',
            occurredOn: DateTime(2026, 7, 15),
            steadyDurationSeconds: 18 * 60,
            loadValue: 18,
            completedAt: DateTime.utc(2026, 7, 15, 10),
          ),
          _analysisRow(
            rowId: 'analysis-duplicate-legacy-latest',
            workoutId: 'duplicate-workout',
            occurredOn: DateTime(2026, 7, 15),
            steadyDurationSeconds: 40 * 60,
            loadValue: 40,
            algorithmVersion: 'trainmate-workout-analysis-legacy',
            completedAt: DateTime.utc(2026, 7, 15, 11),
          ),
        ]);
      final InMemoryTrainingMetricsRepository repository =
          InMemoryTrainingMetricsRepository();
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: repository,
        healthDataGateway: const _UnsupportedHealthDataGateway(),
        clock: () => DateTime.utc(2026, 7, 20),
      );

      await pipeline.aggregatePeriod(
        athleteProfileId: athleteId,
        period: MetricPeriod.week,
        periodStart: periodStart,
      );

      final List<MetricAggregate> metrics = await repository.listAggregates(
        athleteProfileId: athleteId,
        period: MetricPeriod.week,
        periodStart: periodStart,
      );
      final MetricAggregate samePace = metrics.singleWhere(
        (MetricAggregate item) => item.metricCode == 'same_pace_heart_rate',
      );
      final MetricAggregate acwr = metrics.singleWhere(
        (MetricAggregate item) => item.metricCode.startsWith('acwr'),
      );
      expect(samePace.status, MetricStatus.accumulating);
      expect(samePace.sampleDurationSeconds, 18 * 60);
      expect(samePace.metadata['remainingDurationSeconds'], 120);
      expect(acwr.sampleCount, 1);
      expect(
        await repository.listLineage(metricId: samePace.id),
        hasLength(1),
      );
    });

    test('只有前台同步覆盖证明包含完整 28 天窗口时才计算 ACWR', () async {
      final DateTime periodStart = DateTime(2026, 7, 13);
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..anchorRows['$athleteId|coverage:foreground.workout|1'] =
            <String, Object?>{
          'anchor_payload': jsonEncode(<String, Object?>{
            'start': DateTime.utc(2026, 6, 19).toIso8601String(),
            'end': DateTime.utc(2026, 7, 20).toIso8601String(),
          }),
        }
        ..analysisRows.addAll(<Map<String, Object?>>[
          for (int index = 0; index < 28; index += 1)
            _analysisRow(
              workoutId: 'load-$index',
              occurredOn: DateTime(2026, 6, 22).add(Duration(days: index)),
              steadyDurationSeconds: 0,
              loadValue: index >= 21 ? 300 : 50,
            ),
        ]);
      final InMemoryTrainingMetricsRepository repository =
          InMemoryTrainingMetricsRepository();
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: repository,
        healthDataGateway: const _UnsupportedHealthDataGateway(),
        clock: () => DateTime.utc(2026, 7, 20),
      );

      await pipeline.aggregatePeriod(
        athleteProfileId: athleteId,
        period: MetricPeriod.week,
        periodStart: periodStart,
      );

      final List<MetricAggregate> metrics = await repository.listAggregates(
        athleteProfileId: athleteId,
        period: MetricPeriod.week,
        periodStart: periodStart,
      );
      final MetricAggregate acwr = metrics.singleWhere(
        (MetricAggregate item) => item.metricCode.startsWith('acwr'),
      );
      expect(acwr.status, MetricStatus.ready);
      expect(acwr.metadata['windowCoverageVerified'], isTrue);
      expect(acwr.value, isNotNull);
    });

    test('超过 30 秒的 GPS 断点不会把两个不足四分钟的区段合并为稳态段', () async {
      final DateTime start = DateTime.utc(2026, 7, 15, 8);
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..workoutRows['workout-gps-break'] = _workoutRow(
          workoutId: 'workout-gps-break',
          externalUuid: 'healthkit-workout-gps-break',
          start: start,
          durationSeconds: 20 * 60,
        );
      final List<int> sampleSeconds = <int>[
        for (int second = 600; second <= 830; second += 10) second,
        for (int second = 870; second <= 1100; second += 10) second,
      ];
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: InMemoryTrainingMetricsRepository(),
        healthDataGateway: _FakeHealthDataGateway(
          workoutDetails: <String, Map<String, Object?>>{
            'healthkit-workout-gps-break': _workoutDetailsForGps(
              start: start,
              sampleSeconds: sampleSeconds,
              latitudeMeters: <double>[
                for (int index = 0; index < sampleSeconds.length; index += 1)
                  index * 30,
              ],
              heartRateEndSecond: 1100,
            ),
          },
        ),
        clock: () => DateTime.utc(2026, 7, 15, 10),
      );

      final WorkoutAnalysisOutcome outcome = await pipeline.analyzeWorkout(
        athleteProfileId: athleteId,
        workoutId: 'workout-gps-break',
      );

      expect(outcome.steadySegments, isEmpty);
    });

    test('20 秒 GPS 缺失不计入稳态时长，也不把跨缺口位移计入配速', () async {
      final DateTime start = DateTime.utc(2026, 7, 15, 8);
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..workoutRows['workout-gps-missing'] = _workoutRow(
          workoutId: 'workout-gps-missing',
          externalUuid: 'healthkit-workout-gps-missing',
          start: start,
          durationSeconds: 15 * 60,
        );
      final List<int> sampleSeconds = <int>[
        for (int second = 600; second <= 720; second += 10) second,
        for (int second = 740; second <= 860; second += 10) second,
      ];
      final List<double> latitudeMeters = <double>[
        for (int index = 0; index <= 12; index += 1) index * 30,
        for (int index = 0; index <= 12; index += 1) 450 + index * 30,
      ];
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: InMemoryTrainingMetricsRepository(),
        healthDataGateway: _FakeHealthDataGateway(
          workoutDetails: <String, Map<String, Object?>>{
            'healthkit-workout-gps-missing': _workoutDetailsForGps(
              start: start,
              sampleSeconds: sampleSeconds,
              latitudeMeters: latitudeMeters,
              heartRateEndSecond: 860,
            ),
          },
        ),
        clock: () => DateTime.utc(2026, 7, 15, 10),
      );

      final WorkoutAnalysisOutcome outcome = await pipeline.analyzeWorkout(
        athleteProfileId: athleteId,
        workoutId: 'workout-gps-missing',
      );

      expect(outcome.steadySegments, hasLength(1));
      final SteadyPaceSegment segment = outcome.steadySegments.single;
      expect(segment.durationSeconds, 240);
      expect(segment.paceSecondsPerKm, closeTo(333.33, 1));
    });

    test('已提交健康批次会分析受影响训练，并刷新对应周和月聚合', () async {
      final DateTime start = DateTime.utc(2026, 7, 15, 8);
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..workoutRows['workout-batch'] = _workoutRow(
          workoutId: 'workout-batch',
          externalUuid: 'healthkit-workout-batch',
          start: start,
          durationSeconds: 3600,
        );
      final InMemoryTrainingMetricsRepository repository =
          InMemoryTrainingMetricsRepository();
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: repository,
        healthDataGateway: const _UnsupportedHealthDataGateway(),
        clock: () => DateTime.utc(2026, 7, 15, 10),
      );
      final HealthSyncBatch batch = HealthSyncBatch(
        batchId: 'batch-a',
        athleteId: athleteId,
        objectType: 'workout',
        queryVersion: 1,
        upserts: const <Map<String, Object?>>[
          <String, Object?>{
            'kind': 'workout',
            'uuid': 'healthkit-workout-batch',
            'sourceBundleId': 'com.apple.health',
          },
        ],
        deletedExternalIds: const <String>[],
        nextAnchor: 'anchor-a',
        createdAt: DateTime.utc(2026, 7, 15, 9),
        requiresAcknowledgement: true,
      );

      await pipeline.processCommittedHealthBatch(
        batch,
        const HealthSyncApplyResult(
          batchId: 'batch-a',
          upsertCount: 1,
          deletedCount: 0,
          invalidatedSourceIds: <String>[],
        ),
      );

      expect(database.savedAnalysisRows, hasLength(1));
      expect(database.analysisListCalls, 2);
      expect(database.observationListCalls, 1);
      final List<MetricAggregate> metrics = await repository.listAggregates(
        athleteProfileId: athleteId,
      );
      expect(
          metrics
              .any((MetricAggregate item) => item.period == MetricPeriod.week),
          isTrue);
      expect(
        metrics
            .any((MetricAggregate item) => item.period == MetricPeriod.month),
        isTrue,
      );
    });

    test('删除历史离散健康样本会按原本本地日期刷新历史周和月', () async {
      final InMemoryTrainingMetricsRepository repository =
          InMemoryTrainingMetricsRepository();
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: _FakeStructuredGateway(),
        repository: repository,
        healthDataGateway: const _UnsupportedHealthDataGateway(),
        clock: () => DateTime.utc(2026, 7, 15),
      );
      final HealthBatchMetricsResult result =
          await pipeline.processCommittedHealthBatch(
        HealthSyncBatch(
          batchId: 'delete-old-observation',
          athleteId: athleteId,
          objectType: 'HKQuantityTypeIdentifierBodyMass',
          queryVersion: 1,
          upserts: const <Map<String, Object?>>[],
          deletedExternalIds: const <String>['old-body-mass'],
          nextAnchor: 'anchor-old-observation',
          createdAt: DateTime.utc(2026, 7, 15),
          requiresAcknowledgement: true,
        ),
        const HealthSyncApplyResult(
          batchId: 'delete-old-observation',
          upsertCount: 0,
          deletedCount: 1,
          invalidatedSourceIds: <String>['observation-old'],
          invalidatedSources: <StructuredSourceReference>[
            StructuredSourceReference(
              'health_observations',
              'observation-old',
              localDate: '2026-05-06',
              timeZoneName: 'Asia/Shanghai',
            ),
          ],
        ),
      );

      expect(
        result.affectedPeriods,
        contains(
          MetricPeriodWindow(
            period: MetricPeriod.month,
            periodStart: DateTime(2026, 5),
          ),
        ),
      );
      expect(
        result.affectedPeriods,
        isNot(
          contains(
            MetricPeriodWindow(
              period: MetricPeriod.month,
              periodStart: DateTime(2026, 7),
            ),
          ),
        ),
      );
    });

    test('身体 7 日均线按事实 local_date 分日而不是按 UTC 日期分日', () async {
      final _FakeStructuredGateway database = _FakeStructuredGateway();
      for (int day = 1; day <= 3; day += 1) {
        database.observationRows.add(<String, Object?>{
          'id': 'weight-$day',
          'athlete_profile_id': athleteId,
          'observation_kind': 'HKQuantityTypeIdentifierBodyMass',
          'observed_at_utc':
              DateTime.utc(2026, 7, day - 1, 16).toIso8601String(),
          'local_date': '2026-07-${day.toString().padLeft(2, '0')}',
          'time_zone_name': 'Asia/Shanghai',
          'value': 70 + day,
          'updated_at': DateTime.utc(2026, 7, day).toIso8601String(),
        });
      }
      final InMemoryTrainingMetricsRepository repository =
          InMemoryTrainingMetricsRepository();
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: repository,
        healthDataGateway: const _UnsupportedHealthDataGateway(),
        clock: () => DateTime.utc(2026, 7, 3, 12),
      );

      final List<MetricAggregate> metrics = await pipeline.aggregatePeriod(
        athleteProfileId: athleteId,
        period: MetricPeriod.month,
        periodStart: DateTime(2026, 7),
      );

      final MetricAggregate weight = metrics.singleWhere(
        (MetricAggregate item) => item.metricCode == 'body_weight_7d',
      );
      expect(weight.status, MetricStatus.ready);
      expect(weight.value, 72);
      expect(weight.metadata['validDayCount'], 3);
      expect(weight.metadata['timeZoneName'], 'Asia/Shanghai');
    });

    test('VO2max 只生成月度观察值，并按最新有效日取日中位数', () async {
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..observationRows.addAll(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'vo2-old',
            'athlete_profile_id': athleteId,
            'observation_kind': 'HKQuantityTypeIdentifierVO2Max',
            'observed_at_utc': '2026-07-02T01:00:00.000Z',
            'local_date': '2026-07-02',
            'time_zone_name': 'Asia/Shanghai',
            'value': 43.0,
            'updated_at': '2026-07-02T01:00:00.000Z',
          },
          <String, Object?>{
            'id': 'vo2-latest-a',
            'athlete_profile_id': athleteId,
            'observation_kind': 'HKQuantityTypeIdentifierVO2Max',
            'observed_at_utc': '2026-07-14T01:00:00.000Z',
            'local_date': '2026-07-14',
            'time_zone_name': 'Asia/Shanghai',
            'value': 44.0,
            'updated_at': '2026-07-14T01:00:00.000Z',
          },
          <String, Object?>{
            'id': 'vo2-latest-b',
            'athlete_profile_id': athleteId,
            'observation_kind': 'HKQuantityTypeIdentifierVO2Max',
            'observed_at_utc': '2026-07-14T02:00:00.000Z',
            'local_date': '2026-07-14',
            'time_zone_name': 'Asia/Shanghai',
            'value': 46.0,
            'updated_at': '2026-07-14T02:00:00.000Z',
          },
        ]);
      final InMemoryTrainingMetricsRepository repository =
          InMemoryTrainingMetricsRepository();
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: repository,
        healthDataGateway: const _UnsupportedHealthDataGateway(),
        clock: () => DateTime.utc(2026, 7, 15, 12),
      );

      final List<MetricAggregate> metrics = await pipeline.aggregatePeriod(
        athleteProfileId: athleteId,
        period: MetricPeriod.month,
        periodStart: DateTime(2026, 7),
      );

      final MetricAggregate vo2 = metrics.singleWhere(
        (MetricAggregate item) => item.metricCode == 'vo2max_monthly',
      );
      expect(vo2.status, MetricStatus.ready);
      expect(vo2.value, 45);
      expect(vo2.metadata['aggregation'], 'latest_daily_median');
      expect(vo2.metadata['interpretation'], 'observation_only');
      expect(vo2.metadata['visibleSurface'], 'monthly_or_explicit');
      final List<MetricLineage> lineage =
          await repository.listLineage(metricId: vo2.id);
      expect(lineage, hasLength(3));
    });

    test('力量只按用户主项和相近重量区间生成 e1RM 与进步解释', () async {
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..analysisRows.addAll(<Map<String, Object?>>[
          _analysisRow(
            workoutId: 'strength-history',
            occurredOn: DateTime(2026, 7, 6),
            steadyDurationSeconds: 3600,
            steadySegments: const <Map<String, Object?>>[],
            discipline: WorkoutDiscipline.strength,
          ),
          _analysisRow(
            workoutId: 'strength-current',
            occurredOn: DateTime(2026, 7, 14),
            steadyDurationSeconds: 3600,
            steadySegments: const <Map<String, Object?>>[],
            discipline: WorkoutDiscipline.strength,
          ),
        ])
        ..strengthSetRows.addAll(<Map<String, Object?>>[
          _strengthSetRow(
            id: 'set-history',
            workoutId: 'strength-history',
            localDate: '2026-07-06',
            weightKg: 100,
            repetitions: 5,
            rpe: 8,
          ),
          _strengthSetRow(
            id: 'set-current',
            workoutId: 'strength-current',
            localDate: '2026-07-14',
            weightKg: 102.5,
            repetitions: 5,
            rpe: 7,
          ),
          _strengthSetRow(
            id: 'set-other-exercise',
            workoutId: 'strength-current',
            localDate: '2026-07-14',
            weightKg: 200,
            repetitions: 5,
            rpe: 7,
            exerciseKey: 'deadlift',
            exerciseName: '硬拉',
          ),
        ])
        ..primaryExerciseRows.add(<String, Object?>{
          'athlete_profile_id': athleteId,
          'exercise_key': 'squat',
          'display_name': '深蹲',
          'is_active': 1,
        });
      final InMemoryTrainingMetricsRepository repository =
          InMemoryTrainingMetricsRepository();
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: repository,
        healthDataGateway: const _UnsupportedHealthDataGateway(),
        clock: () => DateTime(2026, 7, 15, 12),
      );

      final List<MetricAggregate> metrics = await pipeline.aggregatePeriod(
        athleteProfileId: athleteId,
        period: MetricPeriod.week,
        periodStart: DateTime(2026, 7, 13),
      );

      final MetricAggregate e1Rm = metrics.singleWhere(
        (MetricAggregate item) => item.metricCode == 'strength_e1rm',
      );
      final MetricAggregate progress = metrics.singleWhere(
        (MetricAggregate item) => item.metricCode == 'strength_progress',
      );
      expect(e1Rm.status, MetricStatus.ready);
      expect(e1Rm.value, closeTo(119.583333, 0.0001));
      expect(e1Rm.metadata['exerciseName'], '深蹲');
      expect(e1Rm.metadata['volumeUsedForProgressConclusion'], isFalse);
      expect(progress.status, MetricStatus.ready);
      expect(progress.value, closeTo(2.5, 0.0001));
      expect(progress.metadata['weightBandLowerKg'], closeTo(97.375, 0.0001));
      expect(progress.metadata['weightBandUpperKg'], closeTo(107.625, 0.0001));
      expect(progress.metadata['displayValue'], contains('同重量区间'));
      expect(progress.metadata['displayValue'], contains('RPE 7.0'));
      final List<MetricLineage> lineage =
          await repository.listLineage(metricId: progress.id);
      expect(
        lineage.any((MetricLineage item) =>
            item.sourceType == 'athlete_primary_exercises' &&
            item.sourceId == '$athleteId:squat'),
        isTrue,
      );
      expect(
        metrics.where(
            (MetricAggregate item) => item.metadata['exerciseName'] == '硬拉'),
        isEmpty,
      );
    });

    test('羽毛球 v1 只汇总训练次数、分口径负荷和场上时长', () async {
      final _FakeStructuredGateway database = _FakeStructuredGateway()
        ..analysisRows.add(
          _analysisRow(
            workoutId: 'badminton-current',
            occurredOn: DateTime(2026, 7, 14),
            steadyDurationSeconds: 3600,
            steadySegments: const <Map<String, Object?>>[],
            loadValue: 30,
            discipline: WorkoutDiscipline.badminton,
          ),
        );
      final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
        database: database,
        repository: InMemoryTrainingMetricsRepository(),
        healthDataGateway: const _UnsupportedHealthDataGateway(),
        clock: () => DateTime(2026, 7, 15, 12),
      );

      final List<MetricAggregate> metrics = await pipeline.aggregatePeriod(
        athleteProfileId: athleteId,
        period: MetricPeriod.week,
        periodStart: DateTime(2026, 7, 13),
      );
      final MetricAggregate badminton = metrics.singleWhere(
        (MetricAggregate item) => item.metricCode == 'badminton_consistency',
      );

      expect(badminton.status, MetricStatus.ready);
      expect(badminton.value, 1);
      expect(badminton.metadata['courtDurationMinutes'], 60);
      expect(
        (badminton.metadata['loadByMethod'] as Map)['duration_estimate'],
        30,
      );
      expect(
        badminton.metadata['interpretation'],
        'descriptive_not_skill_progress',
      );
      expect(badminton.metadata['displayValue'], isNot(contains('技术进步')));
    });
  });
}

Map<String, Object?> _workoutRow({
  required String workoutId,
  required String externalUuid,
  required DateTime start,
  required int durationSeconds,
}) {
  return <String, Object?>{
    'id': workoutId,
    'athlete_profile_id': 'athlete-a',
    'external_uuid': externalUuid,
    'source_bundle_id': 'com.apple.health',
    'discipline': 'roadRun',
    'run_context': 'road',
    'started_at_utc': start.toUtc().toIso8601String(),
    'ended_at_utc':
        start.add(Duration(seconds: durationSeconds)).toUtc().toIso8601String(),
    'local_date': '2026-07-15',
    'time_zone_name': 'Asia/Shanghai',
    'active_duration_seconds': durationSeconds,
    'elapsed_duration_seconds': durationSeconds,
    'average_heart_rate': 145,
    'heart_rate_coverage': 0.55,
    'payload_json': jsonEncode(<String, Object?>{'isAerobic': true}),
    'updated_at': DateTime.utc(2026, 7, 15, 9).toIso8601String(),
    'source_deleted_at': null,
  };
}

Map<String, Object?> _analysisRow({
  String? rowId,
  required String workoutId,
  required DateTime occurredOn,
  required int steadyDurationSeconds,
  List<Map<String, Object?>>? steadySegments,
  double? loadValue,
  String algorithmVersion = TrainingMetricsPipeline.workoutAlgorithmVersion,
  DateTime? completedAt,
  WorkoutDiscipline discipline = WorkoutDiscipline.roadRun,
}) {
  final DateTime occurredAt = DateTime(
    occurredOn.year,
    occurredOn.month,
    occurredOn.day,
    8,
  );
  return <String, Object?>{
    'id': rowId ?? 'analysis-$workoutId',
    'athlete_profile_id': 'athlete-a',
    'workout_id': workoutId,
    'algorithm_version': algorithmVersion,
    'input_fingerprint': 'fingerprint-$workoutId',
    'status': 'completed',
    'result_json': jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'workoutId': workoutId,
      'occurredOn': _dateKey(occurredOn),
      'timeZoneName': 'Asia/Shanghai',
      'discipline': discipline.name,
      'durationSeconds': steadyDurationSeconds,
      'loads': loadValue == null
          ? const <Object?>[]
          : <Map<String, Object?>>[
              <String, Object?>{
                'method': LoadMethod.durationEstimate.code,
                'value': loadValue,
                'durationMinutes': steadyDurationSeconds / 60,
                'estimated': true,
                'coverage': 0,
                'reason': '测试负荷',
              },
            ],
      'steadySegments': steadySegments ??
          <Map<String, Object?>>[
            <String, Object?>{
              'sourceWorkoutId': workoutId,
              'occurredAt': occurredAt.toUtc().toIso8601String(),
              'durationSeconds': steadyDurationSeconds,
              'paceSecondsPerKm': 360,
              'grade': 0,
              'paceCoefficientOfVariation': 0.02,
              'averageHeartRate': 145,
              'heartRateCoverage': 0.9,
              'warmupExcluded': true,
              'isAerobic': true,
            },
          ],
      'vam': const <String, Object?>{
        'status': 'accumulating',
        'metersPerHour': null,
        'label': '本周无有效爬升段',
      },
      'deviceBestSegment': null,
    }),
    'started_at': occurredAt.toUtc().toIso8601String(),
    'completed_at': (completedAt ?? occurredAt).toUtc().toIso8601String(),
    'invalidated_at': null,
  };
}

Map<String, Object?> _strengthSetRow({
  required String id,
  required String workoutId,
  required String localDate,
  required double weightKg,
  required double repetitions,
  double? rpe,
  String exerciseKey = 'squat',
  String exerciseName = '深蹲',
}) {
  return <String, Object?>{
    'id': id,
    'athlete_profile_id': 'athlete-a',
    'workout_id': workoutId,
    'exercise_key': exerciseKey,
    'exercise_name': exerciseName,
    'set_index': 1,
    'repetitions': repetitions,
    'weight_kg': weightKg,
    'rpe': rpe,
    'local_date': localDate,
  };
}

Map<String, Object?> _workoutDetailsForGps({
  required DateTime start,
  required List<int> sampleSeconds,
  required List<double> latitudeMeters,
  required int heartRateEndSecond,
}) {
  assert(sampleSeconds.length == latitudeMeters.length);
  const double metersPerLatitudeDegree = 111195;
  return <String, Object?>{
    'heartRateSamples': <Map<String, Object?>>[
      for (int second = 600; second <= heartRateEndSecond; second += 10)
        <String, Object?>{
          'startTime': start.add(Duration(seconds: second)).toIso8601String(),
          'value': 145,
        },
    ],
    'routes': <Map<String, Object?>>[
      <String, Object?>{
        'locations': <Map<String, Object?>>[
          for (int index = 0; index < sampleSeconds.length; index += 1)
            <String, Object?>{
              'timestamp': start
                  .add(Duration(seconds: sampleSeconds[index]))
                  .toIso8601String(),
              'latitude': latitudeMeters[index] / metersPerLatitudeDegree,
              'longitude': 0,
              'horizontalAccuracy': 5,
              'altitude': 0,
              'verticalAccuracy': 5,
            },
        ],
      },
    ],
  };
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

Map<String, Object?> _decodeObject(Object? value) {
  final Object? decoded = value is String ? jsonDecode(value) : value;
  return Map<String, Object?>.from(decoded! as Map);
}

class _FakeStructuredGateway implements TrainMateStructuredDatabaseGateway {
  final Map<String, Map<String, Object?>> profileRows =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> workoutRows =
      <String, Map<String, Object?>>{};
  final List<Map<String, Object?>> observationRows = <Map<String, Object?>>[];
  final List<Map<String, Object?>> strengthSetRows = <Map<String, Object?>>[];
  final List<Map<String, Object?>> primaryExerciseRows =
      <Map<String, Object?>>[];
  final List<Map<String, Object?>> analysisRows = <Map<String, Object?>>[];
  final List<Map<String, Object?>> savedAnalysisRows = <Map<String, Object?>>[];
  final List<String> routeAvailableAnalysisIds = <String>[];
  final Map<String, Map<String, Object?>> anchorRows =
      <String, Map<String, Object?>>{};
  int analysisListCalls = 0;
  int observationListCalls = 0;

  @override
  Future<Map<String, Object?>?> readAthleteProfileRow(
    String athleteProfileId,
  ) async {
    final Map<String, Object?>? row = profileRows[athleteProfileId];
    return row == null ? null : Map<String, Object?>.from(row);
  }

  @override
  Future<Map<String, Object?>?> readHealthSyncAnchor({
    required String athleteId,
    required String objectType,
    required int queryVersion,
  }) async {
    final Map<String, Object?>? row =
        anchorRows['$athleteId|$objectType|$queryVersion'];
    return row == null ? null : Map<String, Object?>.from(row);
  }

  @override
  Future<Map<String, Object?>?> readWorkoutFactRow({
    required String athleteProfileId,
    required String workoutId,
  }) async {
    final Map<String, Object?>? row = workoutRows[workoutId];
    return row == null ? null : Map<String, Object?>.from(row);
  }

  @override
  Future<Map<String, Object?>?> findWorkoutFactRowByExternalId({
    required String athleteProfileId,
    required String sourceBundleId,
    required String externalUuid,
  }) async {
    for (final Map<String, Object?> row in workoutRows.values) {
      if (row['athlete_profile_id'] == athleteProfileId &&
          row['source_bundle_id'] == sourceBundleId &&
          row['external_uuid'] == externalUuid) {
        return Map<String, Object?>.from(row);
      }
    }
    return null;
  }

  @override
  Future<void> saveWorkoutAnalysisRunRow(
    Map<String, Object?> row, {
    bool markRouteAvailable = false,
  }) async {
    final Map<String, Object?> copied = Map<String, Object?>.from(row);
    savedAnalysisRows.add(copied);
    final Object? rawSummary = copied['workout_summary'];
    if (rawSummary is Map) {
      final Map<String, Object?> summary =
          Map<String, Object?>.from(rawSummary);
      workoutRows[row['workout_id']]?.addAll(<String, Object?>{
        'average_heart_rate': summary['averageHeartRate'],
        'maximum_heart_rate': summary['maximumHeartRate'],
        'heart_rate_sample_count': summary['heartRateSampleCount'],
        'heart_rate_coverage': summary['heartRateCoverage'],
      });
    }
    if (markRouteAvailable) {
      routeAvailableAnalysisIds.add(row['workout_id']! as String);
    }
    analysisRows.removeWhere(
      (Map<String, Object?> existing) => existing['id'] == copied['id'],
    );
    analysisRows.add(copied);
  }

  @override
  Future<List<Map<String, Object?>>> listWorkoutAnalysisRunRows({
    required String athleteProfileId,
    required String workoutStartedAtOrAfter,
    required String workoutStartedBefore,
  }) async {
    analysisListCalls += 1;
    return analysisRows
        .where(
          (Map<String, Object?> row) =>
              row['athlete_profile_id'] == athleteProfileId &&
              row['invalidated_at'] == null,
        )
        .map(Map<String, Object?>.from)
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, Object?>>> listHealthObservationFactRows({
    required String athleteProfileId,
    required String observedAtOrAfter,
    required String observedBefore,
  }) async {
    observationListCalls += 1;
    final DateTime start = DateTime.parse(observedAtOrAfter);
    final DateTime end = DateTime.parse(observedBefore);
    return observationRows
        .where((Map<String, Object?> row) {
          final DateTime? observedAt =
              DateTime.tryParse(row['observed_at_utc'] as String? ?? '');
          return row['athlete_profile_id'] == athleteProfileId &&
              observedAt != null &&
              !observedAt.isBefore(start) &&
              observedAt.isBefore(end);
        })
        .map(Map<String, Object?>.from)
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, Object?>>> listStrengthSetRows({
    required String athleteProfileId,
    required String localDateOnOrAfter,
    required String localDateBefore,
  }) async {
    return strengthSetRows
        .where((Map<String, Object?> row) =>
            row['athlete_profile_id'] == athleteProfileId &&
            (row['local_date'] as String).compareTo(localDateOnOrAfter) >= 0 &&
            (row['local_date'] as String).compareTo(localDateBefore) < 0)
        .map(Map<String, Object?>.from)
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, Object?>>> listAthletePrimaryExerciseRows({
    required String athleteProfileId,
  }) async {
    return primaryExerciseRows
        .where((Map<String, Object?> row) =>
            row['athlete_profile_id'] == athleteProfileId)
        .map(Map<String, Object?>.from)
        .toList(growable: false);
  }

  @override
  Future<void> setAthletePrimaryExercise({
    required String athleteProfileId,
    required String exerciseKey,
    required String displayName,
    required bool isActive,
    required DateTime updatedAt,
  }) async {
    primaryExerciseRows.removeWhere((Map<String, Object?> row) =>
        row['athlete_profile_id'] == athleteProfileId &&
        row['exercise_key'] == exerciseKey);
    primaryExerciseRows.add(<String, Object?>{
      'athlete_profile_id': athleteProfileId,
      'exercise_key': exerciseKey,
      'display_name': displayName,
      'is_active': isActive ? 1 : 0,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试未实现的结构化网关调用。');
}

class _FakeHealthDataGateway extends HealthDataGateway {
  const _FakeHealthDataGateway({required this.workoutDetails});

  final Map<String, Map<String, Object?>> workoutDetails;

  @override
  bool get isSupported => true;

  @override
  Future<Map<String, Object?>?> fetchWorkoutDetails(String workoutUuid) async {
    final Map<String, Object?>? details = workoutDetails[workoutUuid];
    return details == null ? null : Map<String, Object?>.from(details);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试未实现的健康数据网关调用。');
}

class _UnsupportedHealthDataGateway extends HealthDataGateway {
  const _UnsupportedHealthDataGateway();

  @override
  bool get isSupported => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试未实现的健康数据网关调用。');
}

class _ThrowingHealthDataGateway extends HealthDataGateway {
  const _ThrowingHealthDataGateway();

  @override
  bool get isSupported => true;

  @override
  Future<Map<String, Object?>?> fetchWorkoutDetails(String workoutUuid) {
    throw StateError('HealthKit 明细暂时不可读');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试未实现的健康数据网关调用。');
}
