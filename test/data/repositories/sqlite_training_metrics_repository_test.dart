import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/local/trainmate_structured_database_gateway.dart';
import 'package:trainflow_ai/data/models/monthly_summary.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/repositories/sqlite_training_metrics_repository.dart';

void main() {
  late _MemoryMetricsGateway gateway;
  late SQLiteTrainingMetricsRepository repository;

  setUp(() {
    gateway = _MemoryMetricsGateway();
    repository = SQLiteTrainingMetricsRepository(gateway);
  });

  test('指标与血缘可完整往返并隔离运动员', () async {
    await repository.saveAggregate(_aggregate());
    await repository.saveAggregate(
      _aggregate(id: 'metric-b', athleteProfileId: 'athlete-b'),
    );
    await repository.saveLineage(
      MetricLineage(
        metricId: 'metric-a',
        sourceType: 'workouts',
        sourceId: 'workout-a',
        relationship: 'input',
        createdAt: DateTime.utc(2026, 7, 15, 12),
      ),
    );

    final List<MetricAggregate> metrics = await repository.listAggregates(
      athleteProfileId: 'athlete-a',
      period: MetricPeriod.week,
      periodStart: DateTime.utc(2026, 7, 13),
    );
    final List<MetricLineage> lineage =
        await repository.listLineage(metricId: 'metric-a');

    expect(metrics, hasLength(1));
    expect(metrics.single.metadata['timeZoneName'], 'Asia/Shanghai');
    expect(
      gateway.metrics['metric-a']!['period_start_local'],
      '2026-07-13T00:00:00.000',
    );
    expect(
      gateway.metrics['metric-a']!['period_end_local'],
      '2026-07-20T00:00:00.000',
    );
    expect(lineage, hasLength(1));
    expect(lineage.single.relationship, 'input');
  });

  test('同一报告修订不能被不同内容覆盖', () async {
    await repository.saveReportRevision(_revision(narrative: '原始周报'));

    await expectLater(
      repository.saveReportRevision(_revision(narrative: '被覆盖的周报')),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          '中文错误',
          contains('不可覆盖'),
        ),
      ),
    );

    final List<ReportRevision> revisions = await repository.listReportRevisions(
      athleteProfileId: 'athlete-a',
      period: MetricPeriod.week,
      periodStart: DateTime.utc(2026, 7, 13),
    );
    expect(revisions, hasLength(1));
    expect(revisions.single.narrative, '原始周报');
    expect(revisions.single.metricSnapshots.single.value, 0.8);
    expect(
      revisions.single.metricSnapshots.single.inputFingerprint,
      'snapshot-input-0.8',
    );
  });

  test('报告输入指纹包含指标快照内容而不只依赖指标 ID', () async {
    await repository.saveReportRevision(_revision(narrative: '第一版周报'));
    await repository.saveReportRevision(
      _revision(
        id: 'report-b',
        revision: 2,
        narrative: '第二版周报',
        snapshotValue: 0.9,
        previousRevisionId: 'report-a',
      ),
    );

    expect(
      gateway.reports['report-a']!['input_fingerprint'],
      isNot(gateway.reports['report-b']!['input_fingerprint']),
    );
  });

  test('月度总结快照可完整往返，且旧报告缺少该字段时保持兼容', () async {
    await repository.saveReportRevision(
      _revision(
        narrative: '月报',
        period: MetricPeriod.month,
        periodStart: DateTime(2026, 6),
        monthlySummarySnapshot: _monthlySummary(),
      ),
    );

    final ReportRevision restored = (await repository.listReportRevisions(
      athleteProfileId: 'athlete-a',
      period: MetricPeriod.month,
      periodStart: DateTime(2026, 6),
    ))
        .single;

    expect(restored.monthlySummarySnapshot?.inputFingerprint, 'summary-a');
    expect(
      restored.monthlySummarySnapshot?.bodyChanges.single.label,
      '体重',
    );
  });

  test('旧报告 JSON 没有指标快照时仍可读取', () async {
    gateway.reports['legacy-report'] = <String, Object?>{
      'id': 'legacy-report',
      'athlete_profile_id': 'athlete-a',
      'report_type': 'week',
      'period_key': DateTime.utc(2026, 7, 13).toIso8601String(),
      'revision_number': 1,
      'input_fingerprint': 'legacy-input',
      'algorithm_version': 'narrative-v1',
      'content_json': '{"metricIds":["metric-a"],"narrative":"旧版报告"}',
      'created_at': DateTime.utc(2026, 7, 15, 12).toIso8601String(),
      'supersedes_revision_id': null,
    };

    final List<ReportRevision> revisions = await repository.listReportRevisions(
      athleteProfileId: 'athlete-a',
      period: MetricPeriod.week,
      periodStart: DateTime.utc(2026, 7, 13),
    );

    expect(revisions.single.narrative, '旧版报告');
    expect(revisions.single.metricIds, <String>['metric-a']);
    expect(revisions.single.metricSnapshots, isEmpty);
  });

  test('按来源失效时同时更新指标和血缘', () async {
    await repository.saveAggregate(_aggregate());
    await repository.saveLineage(
      MetricLineage(
        metricId: 'metric-a',
        sourceType: 'workouts',
        sourceId: 'workout-a',
        relationship: 'input',
        createdAt: DateTime.utc(2026, 7, 15, 12),
      ),
    );
    final DateTime invalidatedAt = DateTime.utc(2026, 7, 16, 1);

    final List<String> affected = await repository.invalidateBySource(
      athleteProfileId: 'athlete-a',
      sourceType: 'workouts',
      sourceId: 'workout-a',
      invalidatedAt: invalidatedAt,
    );

    expect(affected, <String>['metric-a']);
    final List<MetricAggregate> metrics = await repository.listAggregates(
      athleteProfileId: 'athlete-a',
      includeInvalidated: true,
    );
    final List<MetricLineage> lineage =
        await repository.listLineage(metricId: 'metric-a');
    expect(metrics.single.status, MetricStatus.invalidated);
    expect(metrics.single.invalidatedAt, invalidatedAt);
    expect(lineage.single.invalidatedAt, invalidatedAt);
  });

  test('调整建议可按 ID 更新确认状态并保持账号隔离', () async {
    await repository.saveAdjustmentProposal(_proposal());
    await repository.saveAdjustmentProposal(
      _proposal().copyWith(
        status: AdjustmentProposalStatus.confirmed,
        confirmedAt: DateTime.utc(2026, 7, 16),
      ),
    );
    await repository.saveAdjustmentProposal(
      _proposal(id: 'proposal-b', athleteProfileId: 'athlete-b'),
    );

    final List<AdjustmentProposal> values =
        await repository.listAdjustmentProposals(
      athleteProfileId: 'athlete-a',
    );

    expect(values, hasLength(1));
    expect(values.single.status, AdjustmentProposalStatus.confirmed);
    expect(values.single.confirmedAt, DateTime.utc(2026, 7, 16));
  });

  test('周总量建议的训练日快照可完整往返结构化仓库', () async {
    await repository.saveAdjustmentProposal(
      _proposal(
        id: 'proposal-weekly',
        workoutDayId: null,
        workoutChanges: const <AdjustmentProposalWorkoutChange>[
          AdjustmentProposalWorkoutChange(
            workoutDayId: 'day-a',
            workoutTitle: '轻松跑',
            originalMinutes: 40,
            adjustedMinutes: 36,
            originalIntensity: 'RPE 4',
            adjustedIntensity: 'RPE 4',
          ),
          AdjustmentProposalWorkoutChange(
            workoutDayId: 'day-b',
            workoutTitle: '力量训练',
            originalMinutes: 60,
            adjustedMinutes: 54,
            originalIntensity: 'RPE 6',
            adjustedIntensity: 'RPE 6',
          ),
        ],
      ),
    );

    final AdjustmentProposal restored =
        (await repository.listAdjustmentProposals(
      athleteProfileId: 'athlete-a',
    ))
            .single;

    expect(restored.workoutDayId, isNull);
    expect(restored.workoutChanges, hasLength(2));
    expect(restored.workoutChanges.last.adjustedMinutes, 54);
  });
}

MetricAggregate _aggregate({
  String id = 'metric-a',
  String athleteProfileId = 'athlete-a',
}) {
  return MetricAggregate(
    id: id,
    athleteProfileId: athleteProfileId,
    metricCode: 'weekly_consistency',
    period: MetricPeriod.week,
    periodStart: DateTime.utc(2026, 7, 13),
    value: 0.8,
    unit: 'ratio',
    sampleCount: 4,
    sampleDurationSeconds: 7200,
    coverage: 0.9,
    status: MetricStatus.ready,
    algorithmVersion: 'consistency-v1',
    inputFingerprint: 'input-a',
    computedAt: DateTime.utc(2026, 7, 15, 12),
    metadata: const <String, Object?>{
      'timeZoneName': 'Asia/Shanghai',
      'explanation': '测试指标',
    },
  );
}

ReportRevision _revision({
  String id = 'report-a',
  int revision = 1,
  required String narrative,
  double snapshotValue = 0.8,
  String? previousRevisionId,
  MetricPeriod period = MetricPeriod.week,
  DateTime? periodStart,
  MonthlySummary? monthlySummarySnapshot,
}) {
  return ReportRevision(
    id: id,
    athleteProfileId: 'athlete-a',
    period: period,
    periodStart: periodStart ?? DateTime.utc(2026, 7, 13),
    revision: revision,
    generatedAt: DateTime.utc(2026, 7, 15, 12),
    metricIds: const <String>['metric-a'],
    metricSnapshots: <ReportMetricSnapshot>[
      ReportMetricSnapshot(
        metricId: 'metric-a',
        metricCode: 'weekly_consistency',
        value: snapshotValue,
        unit: 'ratio',
        sampleCount: 4,
        sampleDurationSeconds: 7200,
        coverage: 0.9,
        status: MetricStatus.ready,
        algorithmVersion: 'consistency-v1',
        inputFingerprint: 'snapshot-input-$snapshotValue',
        computedAt: DateTime.utc(2026, 7, 15, 11),
        baselineValue: 0.7,
        metadata: const <String, Object?>{'explanation': '测试指标'},
      ),
    ],
    narrative: narrative,
    algorithmVersion: 'narrative-v1',
    previousRevisionId: previousRevisionId,
    monthlySummarySnapshot: monthlySummarySnapshot,
  );
}

MonthlySummary _monthlySummary() {
  final MonthlyMetricChange weight = MonthlyMetricChange(
    code: 'weight',
    label: '体重',
    unit: 'kg',
    state: MonthlyChangeState.mixed,
    directionIsNeutral: true,
    currentValue: 69,
    previousValue: 70,
    firstWindowValue: 70,
    lastWindowValue: 69,
    monthOverMonthDelta: -1,
    withinMonthDelta: -1,
    validDayCount: 6,
    reason: '仅描述数值变化，不判断好坏。',
  );
  return MonthlySummary(
    monthStart: DateTime(2026, 6),
    previousMonthStart: DateTime(2026, 5),
    inputFingerprint: 'summary-a',
    dimensions: <MonthlyDimensionSummary>[
      MonthlyDimensionSummary(
        dimension: MonthlySummaryDimension.recovery,
        state: MonthlyChangeState.stable,
        metrics: <MonthlyMetricChange>[weight],
      ),
    ],
    bodyChanges: <MonthlyMetricChange>[weight],
  );
}

AdjustmentProposal _proposal({
  String id = 'proposal-a',
  String athleteProfileId = 'athlete-a',
  String? workoutDayId = 'day-a',
  List<AdjustmentProposalWorkoutChange> workoutChanges =
      const <AdjustmentProposalWorkoutChange>[],
}) {
  return AdjustmentProposal(
    id: id,
    athleteProfileId: athleteProfileId,
    planId: 'plan-a',
    workoutDayId: workoutDayId,
    workoutTitle: '间歇跑',
    triggerMetricCode: 'acwr.session_rpe',
    triggerAlgorithmVersion: 'acwr-v1',
    explanation: '仅生成待确认建议。',
    originalMinutes: 60,
    adjustedMinutes: 60,
    originalIntensity: '高强度',
    adjustedIntensity: '降低一级',
    status: AdjustmentProposalStatus.proposed,
    createdAt: DateTime.utc(2026, 7, 15),
    workoutChanges: workoutChanges,
  );
}

class _MemoryMetricsGateway implements TrainMateStructuredDatabaseGateway {
  final Map<String, Map<String, Object?>> metrics =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> lineage =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> reports =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> proposals =
      <String, Map<String, Object?>>{};

  @override
  Future<void> saveMetricAggregateRow(Map<String, Object?> row) async {
    metrics[row['id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<List<Map<String, Object?>>> listMetricAggregateRows({
    required String athleteProfileId,
    String? periodType,
    String? periodStartLocal,
    required bool includeInvalidated,
  }) async {
    return metrics.values
        .where((Map<String, Object?> row) =>
            row['athlete_profile_id'] == athleteProfileId &&
            (periodType == null || row['period_type'] == periodType) &&
            (periodStartLocal == null ||
                row['period_start_local'] == periodStartLocal) &&
            (includeInvalidated || row['status'] != 'invalidated'))
        .map(Map<String, Object?>.from)
        .toList();
  }

  @override
  Future<void> saveMetricLineageRow(Map<String, Object?> row) async {
    final String key =
        '${row['metric_aggregate_id']}|${row['source_table']}|${row['source_id']}|${row['relationship']}';
    lineage[key] = Map<String, Object?>.from(row);
  }

  @override
  Future<List<Map<String, Object?>>> listMetricLineageRows({
    required String metricId,
  }) async {
    return lineage.values
        .where((Map<String, Object?> row) =>
            row['metric_aggregate_id'] == metricId)
        .map(Map<String, Object?>.from)
        .toList();
  }

  @override
  Future<List<String>> invalidateMetricRowsBySource({
    required String athleteProfileId,
    required String sourceType,
    required String sourceId,
    required String invalidatedAt,
  }) async {
    final Set<String> ids = lineage.values
        .where((Map<String, Object?> row) =>
            row['source_table'] == sourceType &&
            row['source_id'] == sourceId &&
            row['invalidated_at'] == null)
        .map(
            (Map<String, Object?> row) => row['metric_aggregate_id']! as String)
        .where((String id) =>
            metrics[id]?['athlete_profile_id'] == athleteProfileId)
        .toSet();
    for (final String id in ids) {
      metrics[id]!
        ..['status'] = 'invalidated'
        ..['invalidated_at'] = invalidatedAt;
    }
    for (final Map<String, Object?> row in lineage.values) {
      if (ids.contains(row['metric_aggregate_id']) &&
          row['source_table'] == sourceType &&
          row['source_id'] == sourceId) {
        row['invalidated_at'] = invalidatedAt;
      }
    }
    return ids.toList()..sort();
  }

  @override
  Future<void> saveReportRevisionRow(Map<String, Object?> row) async {
    reports[row['id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<List<Map<String, Object?>>> listReportRevisionRows({
    required String athleteProfileId,
    required String reportType,
    required String periodKey,
  }) async {
    return reports.values
        .where((Map<String, Object?> row) =>
            row['athlete_profile_id'] == athleteProfileId &&
            row['report_type'] == reportType &&
            row['period_key'] == periodKey)
        .map(Map<String, Object?>.from)
        .toList();
  }

  @override
  Future<void> saveAdjustmentProposalRow(Map<String, Object?> row) async {
    proposals[row['id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<List<Map<String, Object?>>> listAdjustmentProposalRows({
    required String athleteProfileId,
  }) async {
    return proposals.values
        .where((Map<String, Object?> row) =>
            row['athlete_profile_id'] == athleteProfileId)
        .map(Map<String, Object?>.from)
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
