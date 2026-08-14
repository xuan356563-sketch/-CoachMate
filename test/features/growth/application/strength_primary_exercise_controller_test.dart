import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/local/trainmate_structured_database_gateway.dart';
import 'package:trainflow_ai/data/models/health_snapshot.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/features/growth/application/strength_primary_exercise_controller.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway_contract.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/services/training_metrics_pipeline.dart';

void main() {
  test('主项候选按动作去重，并保留用户已激活选择', () async {
    final _PrimaryExerciseGateway database = _PrimaryExerciseGateway()
      ..strengthRows.addAll(<Map<String, Object?>>[
        _setRow(id: 'set-1', exerciseKey: 'squat', exerciseName: '深蹲'),
        _setRow(id: 'set-2', exerciseKey: 'squat', exerciseName: '深蹲'),
        _setRow(id: 'set-3', exerciseKey: 'deadlift', exerciseName: '硬拉'),
      ])
      ..primaryRows.add(<String, Object?>{
        'athlete_profile_id': 'athlete-a',
        'exercise_key': 'deadlift',
        'display_name': '硬拉',
        'is_active': 1,
      });
    final ProviderContainer container = ProviderContainer(
      overrides: [
        healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(database),
      ],
    );
    addTearDown(container.dispose);

    final List<StrengthExerciseOption> values = await container.read(
      strengthExerciseOptionsProvider('athlete-a').future,
    );

    expect(values, hasLength(2));
    expect(values.first.exerciseKey, 'deadlift');
    expect(values.first.isActive, isTrue);
    expect(
      values
          .singleWhere(
              (StrengthExerciseOption item) => item.exerciseKey == 'squat')
          .recordedSetCount,
      2,
    );
  });

  test('保存主项会失效旧配置血缘并重算当前周', () async {
    final _PrimaryExerciseGateway database = _PrimaryExerciseGateway();
    final InMemoryTrainingMetricsRepository repository =
        InMemoryTrainingMetricsRepository();
    final DateTime now = DateTime(2026, 7, 15, 12);
    final MetricAggregate oldMetric = _strengthMetric(now);
    await repository.saveAggregate(oldMetric);
    await repository.saveLineage(MetricLineage(
      metricId: oldMetric.id,
      sourceType: 'athlete_primary_exercises',
      sourceId: 'athlete-a:squat',
      relationship: 'configuration',
      createdAt: now,
    ));
    final _RecordingMetricsPipeline pipeline = _RecordingMetricsPipeline(
      database: database,
      repository: repository,
    );
    final StrengthPrimaryExerciseService service =
        StrengthPrimaryExerciseService(
      database: database,
      repository: repository,
      metricsPipeline: pipeline,
      clock: () => now,
    );

    await service.setActive(
      athleteProfileId: 'athlete-a',
      exerciseKey: 'squat',
      displayName: '深蹲',
      isActive: false,
    );

    expect(database.primaryRows.single['is_active'], 0);
    expect(pipeline.periodStarts, <DateTime>[DateTime(2026, 7, 13)]);
    final List<MetricAggregate> metrics = await repository.listAggregates(
      athleteProfileId: 'athlete-a',
      includeInvalidated: true,
    );
    expect(metrics.single.status, MetricStatus.invalidated);
  });

  test('主项已保存但重算失败时明确保留失效状态', () async {
    final _PrimaryExerciseGateway database = _PrimaryExerciseGateway();
    final InMemoryTrainingMetricsRepository repository =
        InMemoryTrainingMetricsRepository();
    final _RecordingMetricsPipeline pipeline = _RecordingMetricsPipeline(
      database: database,
      repository: repository,
      aggregateError: StateError('测试重算失败'),
    );
    final StrengthPrimaryExerciseService service =
        StrengthPrimaryExerciseService(
      database: database,
      repository: repository,
      metricsPipeline: pipeline,
      clock: () => DateTime(2026, 7, 15, 12),
    );

    await expectLater(
      service.setActive(
        athleteProfileId: 'athlete-a',
        exerciseKey: 'squat',
        displayName: '深蹲',
        isActive: true,
      ),
      throwsA(
        isA<StrengthPrimaryExerciseRecalculationException>().having(
          (StrengthPrimaryExerciseRecalculationException error) =>
              error.message,
          '中文错误',
          contains('主项已保存'),
        ),
      ),
    );
    expect(database.primaryRows.single['is_active'], 1);
  });
}

class _PrimaryExerciseGateway implements TrainMateStructuredDatabaseGateway {
  final List<Map<String, Object?>> strengthRows = <Map<String, Object?>>[];
  final List<Map<String, Object?>> primaryRows = <Map<String, Object?>>[];

  @override
  Future<List<Map<String, Object?>>> listStrengthSetRows({
    required String athleteProfileId,
    required String localDateOnOrAfter,
    required String localDateBefore,
  }) async {
    return strengthRows
        .where((Map<String, Object?> row) =>
            row['athlete_profile_id'] == athleteProfileId)
        .map(Map<String, Object?>.from)
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, Object?>>> listAthletePrimaryExerciseRows({
    required String athleteProfileId,
  }) async {
    return primaryRows
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
    primaryRows.removeWhere((Map<String, Object?> row) =>
        row['athlete_profile_id'] == athleteProfileId &&
        row['exercise_key'] == exerciseKey);
    primaryRows.add(<String, Object?>{
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

class _RecordingMetricsPipeline extends TrainingMetricsPipeline {
  _RecordingMetricsPipeline({
    required super.database,
    required super.repository,
    this.aggregateError,
  }) : super(
          healthDataGateway: const _UnsupportedGateway(),
        );

  final Object? aggregateError;
  final List<DateTime> periodStarts = <DateTime>[];

  @override
  Future<List<MetricAggregate>> aggregatePeriod({
    required String athleteProfileId,
    required MetricPeriod period,
    required DateTime periodStart,
  }) async {
    if (aggregateError case final Object error) throw error;
    periodStarts.add(periodStart);
    return const <MetricAggregate>[];
  }
}

class _UnsupportedGateway extends HealthDataGateway {
  const _UnsupportedGateway();

  @override
  bool get isSupported => false;

  @override
  Future<HealthAuthorizationResult> requestAuthorization({
    required HealthPermissionStage stage,
    required String athleteId,
  }) async =>
      HealthAuthorizationResult(
        stage: stage,
        requestCompleted: false,
        state: HealthAuthorizationState.unavailable,
      );

  @override
  Future<HealthForegroundSyncResult> fetchForeground({
    required HealthPermissionStage stage,
    required String athleteId,
    required DateTime start,
    required DateTime end,
  }) async =>
      const HealthForegroundSyncResult(
        snapshots: <HealthSnapshot>[],
        batches: <HealthSyncBatch>[],
      );

  @override
  Future<List<HealthSyncBatch>> drainPendingBatches({int limit = 20}) async =>
      const <HealthSyncBatch>[];

  @override
  Future<void> acknowledgeBatch(String batchId) async {}

  @override
  Future<void> clearPendingBatches({required String athleteId}) async {}
}

Map<String, Object?> _setRow({
  required String id,
  required String exerciseKey,
  required String exerciseName,
}) =>
    <String, Object?>{
      'id': id,
      'athlete_profile_id': 'athlete-a',
      'workout_id': 'workout-$id',
      'exercise_key': exerciseKey,
      'exercise_name': exerciseName,
      'local_date': '2026-07-15',
    };

MetricAggregate _strengthMetric(DateTime computedAt) => MetricAggregate(
      id: 'metric-strength-old',
      athleteProfileId: 'athlete-a',
      metricCode: 'strength_e1rm',
      period: MetricPeriod.week,
      periodStart: DateTime(2026, 7, 13),
      value: 100,
      unit: 'kg',
      sampleCount: 1,
      sampleDurationSeconds: 0,
      coverage: 1,
      status: MetricStatus.ready,
      algorithmVersion: 'test-v1',
      inputFingerprint: 'test-input',
      computedAt: computedAt,
    );
