import 'dart:convert';

import '../local/trainmate_structured_database_gateway.dart';
import '../models/monthly_summary.dart';
import '../models/training_metrics.dart';
import 'training_metrics_repository.dart';

/// 基于 TrainMate 结构化 SQLite 边界的指标仓库。
class SQLiteTrainingMetricsRepository implements TrainingMetricsRepository {
  const SQLiteTrainingMetricsRepository(this._database);

  final TrainMateStructuredDatabaseGateway _database;

  @override
  Future<void> saveAggregate(MetricAggregate aggregate) {
    final DateTime periodStart = _localPeriodStart(aggregate.periodStart);
    return _database.saveMetricAggregateRow(<String, Object?>{
      'id': aggregate.id,
      'athlete_profile_id': aggregate.athleteProfileId,
      'metric_code': aggregate.metricCode,
      'load_method': aggregate.loadMethod?.code ?? '',
      'period_type': aggregate.period.name,
      'period_start_local': periodStart.toIso8601String(),
      'period_end_local':
          _periodEnd(periodStart, aggregate.period).toIso8601String(),
      'time_zone_name': aggregate.metadata['timeZoneName'] as String? ?? 'UTC',
      'value': aggregate.value,
      'unit': aggregate.unit,
      'sample_count': aggregate.sampleCount,
      'sample_duration_seconds': aggregate.sampleDurationSeconds,
      'coverage': aggregate.coverage,
      'status': aggregate.status.name,
      'baseline_value': aggregate.baselineValue,
      'algorithm_version': aggregate.algorithmVersion,
      'input_fingerprint': aggregate.inputFingerprint,
      'computed_at': aggregate.computedAt.toUtc().toIso8601String(),
      'invalidated_at': aggregate.invalidatedAt?.toUtc().toIso8601String(),
      'metadata_json': _canonicalJson(aggregate.metadata),
    });
  }

  @override
  Future<List<MetricAggregate>> listAggregates({
    required String athleteProfileId,
    MetricPeriod? period,
    DateTime? periodStart,
    bool includeInvalidated = false,
  }) async {
    final String? localKey = periodStart == null
        ? null
        : _localPeriodStart(periodStart).toIso8601String();
    List<Map<String, Object?>> rows = await _database.listMetricAggregateRows(
      athleteProfileId: athleteProfileId,
      periodType: period?.name,
      periodStartLocal: localKey,
      includeInvalidated: includeInvalidated,
    );
    // 兼容早期错误写成 UTC 瞬时的本地周期键；新写入统一使用无 Z 的本地日期。
    if (rows.isEmpty && periodStart != null) {
      final String legacyKey = periodStart.toUtc().toIso8601String();
      if (legacyKey != localKey) {
        rows = await _database.listMetricAggregateRows(
          athleteProfileId: athleteProfileId,
          periodType: period?.name,
          periodStartLocal: legacyKey,
          includeInvalidated: includeInvalidated,
        );
      }
    }
    return List<MetricAggregate>.unmodifiable(
      rows.map(_aggregateFromRow),
    );
  }

  @override
  Future<void> saveLineage(MetricLineage lineage) {
    return _database.saveMetricLineageRow(<String, Object?>{
      'metric_aggregate_id': lineage.metricId,
      'source_table': lineage.sourceType,
      'source_id': lineage.sourceId,
      'source_fingerprint': '',
      'relationship': lineage.relationship,
      'created_at': lineage.createdAt.toUtc().toIso8601String(),
      'invalidated_at': lineage.invalidatedAt?.toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<MetricLineage>> listLineage({required String metricId}) async {
    final List<Map<String, Object?>> rows =
        await _database.listMetricLineageRows(metricId: metricId);
    return List<MetricLineage>.unmodifiable(rows.map(_lineageFromRow));
  }

  @override
  Future<List<String>> invalidateBySource({
    required String athleteProfileId,
    required String sourceType,
    required String sourceId,
    required DateTime invalidatedAt,
  }) {
    return _database.invalidateMetricRowsBySource(
      athleteProfileId: athleteProfileId,
      sourceType: sourceType,
      sourceId: sourceId,
      invalidatedAt: invalidatedAt.toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> saveReportRevision(ReportRevision revision) async {
    final String periodKey =
        _localPeriodStart(revision.periodStart).toIso8601String();
    List<Map<String, Object?>> existingRows =
        await _database.listReportRevisionRows(
      athleteProfileId: revision.athleteProfileId,
      reportType: revision.period.name,
      periodKey: periodKey,
    );
    final String legacyPeriodKey =
        revision.periodStart.toUtc().toIso8601String();
    if (existingRows.isEmpty && legacyPeriodKey != periodKey) {
      existingRows = await _database.listReportRevisionRows(
        athleteProfileId: revision.athleteProfileId,
        reportType: revision.period.name,
        periodKey: legacyPeriodKey,
      );
    }
    for (final Map<String, Object?> row in existingRows) {
      final ReportRevision existing = _reportRevisionFromRow(row);
      if (existing.id == revision.id) {
        if (_sameReportRevision(existing, revision)) return;
        throw StateError('报告修订不可覆盖，请创建新的修订号。');
      }
      if (existing.revision == revision.revision) {
        throw StateError('同一周期的报告修订号已存在。');
      }
    }

    await _database.saveReportRevisionRow(<String, Object?>{
      'id': revision.id,
      'athlete_profile_id': revision.athleteProfileId,
      'report_type': revision.period.name,
      'period_key': periodKey,
      'revision_number': revision.revision,
      'input_fingerprint': _stableFingerprint(
        <String, Object?>{
          if (revision.metricSnapshots.isEmpty)
            'legacyMetricIds': revision.metricIds
          else
            'metricSnapshots': revision.metricSnapshots
                .map(_snapshotToJson)
                .toList(growable: false),
          if (revision.monthlySummarySnapshot != null)
            'monthlySummarySnapshot': revision.monthlySummarySnapshot!.toJson(),
        },
      ),
      'algorithm_version': revision.algorithmVersion,
      'content_json': _canonicalJson(<String, Object?>{
        'metricIds': revision.metricIds,
        'metricSnapshots': revision.metricSnapshots
            .map(_snapshotToJson)
            .toList(growable: false),
        if (revision.monthlySummarySnapshot != null)
          'monthlySummarySnapshot': revision.monthlySummarySnapshot!.toJson(),
        'narrative': revision.narrative,
      }),
      'created_at': revision.generatedAt.toUtc().toIso8601String(),
      'supersedes_revision_id': revision.previousRevisionId,
    });
  }

  @override
  Future<List<ReportRevision>> listReportRevisions({
    required String athleteProfileId,
    required MetricPeriod period,
    required DateTime periodStart,
  }) async {
    final String localKey = _localPeriodStart(periodStart).toIso8601String();
    List<Map<String, Object?>> rows = await _database.listReportRevisionRows(
      athleteProfileId: athleteProfileId,
      reportType: period.name,
      periodKey: localKey,
    );
    final String legacyKey = periodStart.toUtc().toIso8601String();
    if (rows.isEmpty && legacyKey != localKey) {
      rows = await _database.listReportRevisionRows(
        athleteProfileId: athleteProfileId,
        reportType: period.name,
        periodKey: legacyKey,
      );
    }
    return List<ReportRevision>.unmodifiable(
      rows.map(_reportRevisionFromRow),
    );
  }

  @override
  Future<void> saveAdjustmentProposal(AdjustmentProposal proposal) {
    return _database.saveAdjustmentProposalRow(<String, Object?>{
      'id': proposal.id,
      'athlete_profile_id': proposal.athleteProfileId,
      'trigger_metric_id': null,
      'trigger_metric_code': proposal.triggerMetricCode,
      'plan_id': proposal.planId,
      'workout_day_id': proposal.workoutDayId,
      'workout_title': proposal.workoutTitle,
      'algorithm_version': proposal.triggerAlgorithmVersion,
      'status': proposal.status.name,
      'reason': proposal.explanation,
      'before_json': _canonicalJson(<String, Object?>{
        'minutes': proposal.originalMinutes,
        'intensity': proposal.originalIntensity,
        if (proposal.workoutChanges.isNotEmpty)
          'workoutChanges': proposal.workoutChanges
              .map(
                (AdjustmentProposalWorkoutChange change) => <String, Object?>{
                  'workoutDayId': change.workoutDayId,
                  'workoutTitle': change.workoutTitle,
                  'minutes': change.originalMinutes,
                  'intensity': change.originalIntensity,
                },
              )
              .toList(growable: false),
      }),
      'proposed_json': _canonicalJson(<String, Object?>{
        'minutes': proposal.adjustedMinutes,
        'intensity': proposal.adjustedIntensity,
        if (proposal.workoutChanges.isNotEmpty)
          'workoutChanges': proposal.workoutChanges
              .map(
                (AdjustmentProposalWorkoutChange change) => <String, Object?>{
                  'workoutDayId': change.workoutDayId,
                  'workoutTitle': change.workoutTitle,
                  'minutes': change.adjustedMinutes,
                  'intensity': change.adjustedIntensity,
                },
              )
              .toList(growable: false),
      }),
      'created_at': proposal.createdAt.toUtc().toIso8601String(),
      'confirmed_at': proposal.confirmedAt?.toUtc().toIso8601String(),
      'rejected_at': proposal.rejectedAt?.toUtc().toIso8601String(),
      'undone_at': proposal.undoneAt?.toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<AdjustmentProposal>> listAdjustmentProposals({
    required String athleteProfileId,
  }) async {
    final List<Map<String, Object?>> rows =
        await _database.listAdjustmentProposalRows(
      athleteProfileId: athleteProfileId,
    );
    return List<AdjustmentProposal>.unmodifiable(
      rows.map(_proposalFromRow),
    );
  }
}

MetricAggregate _aggregateFromRow(Map<String, Object?> row) {
  return MetricAggregate(
    id: _requiredString(row, 'id', '指标 ID'),
    athleteProfileId: _requiredString(row, 'athlete_profile_id', '运动员标识'),
    metricCode: _requiredString(row, 'metric_code', '指标代码'),
    period: _enumByName(
      MetricPeriod.values,
      _requiredString(row, 'period_type', '指标周期'),
      '指标周期',
    ),
    periodStart: _requiredLocalDateTime(row, 'period_start_local', '指标周期开始时间'),
    value: (row['value'] as num?)?.toDouble(),
    unit: _requiredString(row, 'unit', '指标单位'),
    sampleCount: _requiredInt(row, 'sample_count', '指标样本数'),
    sampleDurationSeconds:
        _requiredInt(row, 'sample_duration_seconds', '指标样本时长'),
    coverage: _requiredDouble(row, 'coverage', '指标覆盖率'),
    status: _enumByName(
      MetricStatus.values,
      _requiredString(row, 'status', '指标状态'),
      '指标状态',
    ),
    algorithmVersion: _requiredString(row, 'algorithm_version', '指标算法版本'),
    inputFingerprint: _requiredString(row, 'input_fingerprint', '指标输入指纹'),
    computedAt: _requiredDateTime(row, 'computed_at', '指标计算时间'),
    loadMethod: _loadMethodFromCode(row['load_method'] as String? ?? ''),
    baselineValue: (row['baseline_value'] as num?)?.toDouble(),
    invalidatedAt: _optionalDateTime(row['invalidated_at'], '指标失效时间'),
    metadata: _decodeJsonObject(row['metadata_json'], '指标元数据'),
  );
}

MetricLineage _lineageFromRow(Map<String, Object?> row) {
  return MetricLineage(
    metricId: _requiredString(row, 'metric_aggregate_id', '血缘指标 ID'),
    sourceType: _requiredString(row, 'source_table', '血缘来源类型'),
    sourceId: _requiredString(row, 'source_id', '血缘来源 ID'),
    relationship: _requiredString(row, 'relationship', '血缘关系'),
    createdAt: _requiredDateTime(row, 'created_at', '血缘创建时间'),
    invalidatedAt: _optionalDateTime(row['invalidated_at'], '血缘失效时间'),
  );
}

ReportRevision _reportRevisionFromRow(Map<String, Object?> row) {
  final Map<String, Object?> content =
      _decodeJsonObject(row['content_json'], '报告内容');
  final List<String> metricIds = content['metricIds'] is List
      ? (content['metricIds']! as List)
          .whereType<String>()
          .toList(growable: false)
      : const <String>[];
  final List<ReportMetricSnapshot> metricSnapshots =
      _metricSnapshotsFromContent(content['metricSnapshots']);
  return ReportRevision(
    id: _requiredString(row, 'id', '报告修订 ID'),
    athleteProfileId: _requiredString(row, 'athlete_profile_id', '运动员标识'),
    period: _enumByName(
      MetricPeriod.values,
      _requiredString(row, 'report_type', '报告周期'),
      '报告周期',
    ),
    periodStart: _requiredLocalDateTime(row, 'period_key', '报告周期开始时间'),
    revision: _requiredInt(row, 'revision_number', '报告修订号'),
    generatedAt: _requiredDateTime(row, 'created_at', '报告生成时间'),
    metricIds: List<String>.unmodifiable(metricIds),
    metricSnapshots: metricSnapshots,
    narrative: content['narrative'] as String? ?? '',
    algorithmVersion: _requiredString(row, 'algorithm_version', '报告算法版本'),
    previousRevisionId: row['supersedes_revision_id'] as String?,
    monthlySummarySnapshot:
        _monthlySummaryFromContent(content['monthlySummarySnapshot']),
  );
}

MonthlySummary? _monthlySummaryFromContent(Object? raw) {
  if (raw == null) return null;
  if (raw is! Map) throw FormatException('月度总结快照格式无效。');
  return MonthlySummary.fromJson(Map<String, Object?>.from(raw));
}

AdjustmentProposal _proposalFromRow(Map<String, Object?> row) {
  final Map<String, Object?> before =
      _decodeJsonObject(row['before_json'], '调整前快照');
  final Map<String, Object?> proposed =
      _decodeJsonObject(row['proposed_json'], '调整建议快照');
  final List<AdjustmentProposalWorkoutChange> workoutChanges =
      _proposalWorkoutChanges(before, proposed);
  return AdjustmentProposal(
    id: _requiredString(row, 'id', '调整建议 ID'),
    athleteProfileId: _requiredString(row, 'athlete_profile_id', '运动员标识'),
    planId: _requiredString(row, 'plan_id', '训练计划 ID'),
    workoutDayId: row['workout_day_id'] as String?,
    workoutTitle: _requiredString(row, 'workout_title', '训练标题'),
    triggerMetricCode: _requiredString(row, 'trigger_metric_code', '触发指标代码'),
    triggerAlgorithmVersion:
        _requiredString(row, 'algorithm_version', '触发算法版本'),
    explanation: _requiredString(row, 'reason', '调整建议解释'),
    originalMinutes: _requiredInt(before, 'minutes', '原训练分钟数'),
    adjustedMinutes: _requiredInt(proposed, 'minutes', '建议训练分钟数'),
    originalIntensity: _requiredString(before, 'intensity', '原训练强度'),
    adjustedIntensity: _requiredString(proposed, 'intensity', '建议训练强度'),
    status: _enumByName(
      AdjustmentProposalStatus.values,
      _requiredString(row, 'status', '调整建议状态'),
      '调整建议状态',
    ),
    createdAt: _requiredDateTime(row, 'created_at', '调整建议创建时间'),
    workoutChanges: workoutChanges,
    confirmedAt: _optionalDateTime(row['confirmed_at'], '调整建议确认时间'),
    rejectedAt: _optionalDateTime(row['rejected_at'], '调整建议拒绝时间'),
    undoneAt: _optionalDateTime(row['undone_at'], '调整建议撤销时间'),
  );
}

List<AdjustmentProposalWorkoutChange> _proposalWorkoutChanges(
  Map<String, Object?> before,
  Map<String, Object?> proposed,
) {
  final Object? beforeRaw = before['workoutChanges'];
  final Object? proposedRaw = proposed['workoutChanges'];
  if (beforeRaw is! List || proposedRaw is! List) {
    return const <AdjustmentProposalWorkoutChange>[];
  }
  final Map<String, Map<String, Object?>> proposedById =
      <String, Map<String, Object?>>{};
  for (final Object? raw in proposedRaw) {
    if (raw is! Map) continue;
    final Map<String, Object?> value = Map<String, Object?>.from(raw);
    final String id = value['workoutDayId'] as String? ?? '';
    if (id.isNotEmpty) proposedById[id] = value;
  }
  final List<AdjustmentProposalWorkoutChange> result =
      <AdjustmentProposalWorkoutChange>[];
  for (final Object? raw in beforeRaw) {
    if (raw is! Map) continue;
    final Map<String, Object?> original = Map<String, Object?>.from(raw);
    final String id = original['workoutDayId'] as String? ?? '';
    final Map<String, Object?>? adjusted = proposedById[id];
    if (id.isEmpty || adjusted == null) continue;
    result.add(AdjustmentProposalWorkoutChange(
      workoutDayId: id,
      workoutTitle: original['workoutTitle'] as String? ?? '',
      originalMinutes: (original['minutes'] as num?)?.toInt() ?? 0,
      adjustedMinutes: (adjusted['minutes'] as num?)?.toInt() ?? 0,
      originalIntensity: original['intensity'] as String? ?? '',
      adjustedIntensity: adjusted['intensity'] as String? ?? '',
    ));
  }
  return List<AdjustmentProposalWorkoutChange>.unmodifiable(result);
}

DateTime _periodEnd(DateTime start, MetricPeriod period) {
  return switch (period) {
    MetricPeriod.day => start.add(const Duration(days: 1)),
    MetricPeriod.week => start.add(const Duration(days: 7)),
    MetricPeriod.month => DateTime(start.year, start.month + 1, 1),
    MetricPeriod.quarter => DateTime(start.year, start.month + 3, 1),
    MetricPeriod.year => DateTime(start.year + 1, 1, 1),
  };
}

DateTime _localPeriodStart(DateTime value) =>
    DateTime(value.year, value.month, value.day);

LoadMethod? _loadMethodFromCode(String code) {
  return switch (code) {
    '' => null,
    'banister_trimp' => LoadMethod.banisterTrimp,
    'session_rpe' => LoadMethod.sessionRpe,
    'duration_estimate' => LoadMethod.durationEstimate,
    _ => throw FormatException('负荷方法代码无效：$code'),
  };
}

T _enumByName<T extends Enum>(
  List<T> values,
  String name,
  String label,
) {
  for (final T value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$label无效：$name');
}

String _requiredString(
  Map<String, Object?> row,
  String key,
  String label,
) {
  final Object? value = row[key];
  if (value is! String || value.isEmpty) throw FormatException('$label缺失。');
  return value;
}

int _requiredInt(Map<String, Object?> row, String key, String label) {
  final Object? value = row[key];
  if (value is! num) throw FormatException('$label缺失。');
  return value.toInt();
}

double _requiredDouble(Map<String, Object?> row, String key, String label) {
  final Object? value = row[key];
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('$label无效。');
  }
  return value.toDouble();
}

DateTime _requiredDateTime(
  Map<String, Object?> row,
  String key,
  String label,
) {
  final DateTime? value = _optionalDateTime(row[key], label);
  if (value == null) throw FormatException('$label缺失。');
  return value;
}

DateTime _requiredLocalDateTime(
  Map<String, Object?> row,
  String key,
  String label,
) {
  final Object? raw = row[key];
  if (raw is! String) throw FormatException('$label格式无效。');
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('$label格式无效。');
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime? _optionalDateTime(Object? raw, String label) {
  if (raw == null) return null;
  if (raw is! String) throw FormatException('$label格式无效。');
  final DateTime? value = DateTime.tryParse(raw)?.toUtc();
  if (value == null) throw FormatException('$label格式无效。');
  return value;
}

Map<String, Object?> _decodeJsonObject(Object? raw, String label) {
  if (raw is! String) throw FormatException('$label缺失。');
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException();
    return Map<String, Object?>.from(decoded);
  } catch (_) {
    throw FormatException('$label格式无效。');
  }
}

bool _sameReportRevision(ReportRevision first, ReportRevision second) {
  return first.athleteProfileId == second.athleteProfileId &&
      first.period == second.period &&
      first.periodStart.toUtc() == second.periodStart.toUtc() &&
      first.revision == second.revision &&
      first.generatedAt.toUtc() == second.generatedAt.toUtc() &&
      first.narrative == second.narrative &&
      first.algorithmVersion == second.algorithmVersion &&
      first.previousRevisionId == second.previousRevisionId &&
      _sameStrings(first.metricIds, second.metricIds) &&
      _sameSnapshots(first.metricSnapshots, second.metricSnapshots) &&
      _canonicalJson(first.monthlySummarySnapshot?.toJson()) ==
          _canonicalJson(second.monthlySummarySnapshot?.toJson());
}

bool _sameStrings(List<String> first, List<String> second) {
  if (first.length != second.length) return false;
  for (int index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

bool _sameSnapshots(
  List<ReportMetricSnapshot> first,
  List<ReportMetricSnapshot> second,
) {
  if (first.length != second.length) return false;
  for (int index = 0; index < first.length; index += 1) {
    if (_canonicalJson(_snapshotToJson(first[index])) !=
        _canonicalJson(_snapshotToJson(second[index]))) {
      return false;
    }
  }
  return true;
}

List<ReportMetricSnapshot> _metricSnapshotsFromContent(Object? raw) {
  if (raw == null) return const <ReportMetricSnapshot>[];
  if (raw is! List) throw FormatException('报告指标快照格式无效。');
  final List<ReportMetricSnapshot> snapshots = <ReportMetricSnapshot>[];
  for (final Object? item in raw) {
    if (item is! Map) throw FormatException('报告指标快照格式无效。');
    snapshots.add(
      _snapshotFromJson(Map<String, Object?>.from(item)),
    );
  }
  return List<ReportMetricSnapshot>.unmodifiable(snapshots);
}

ReportMetricSnapshot _snapshotFromJson(Map<String, Object?> value) {
  final Object? metadata = value['metadata'];
  if (metadata is! Map) throw FormatException('报告指标快照元数据格式无效。');
  return ReportMetricSnapshot(
    metricId: _requiredString(value, 'metricId', '报告指标 ID'),
    metricCode: _requiredString(value, 'metricCode', '报告指标代码'),
    value: (value['value'] as num?)?.toDouble(),
    unit: _requiredString(value, 'unit', '报告指标单位'),
    sampleCount: _requiredInt(value, 'sampleCount', '报告指标样本数'),
    sampleDurationSeconds:
        _requiredInt(value, 'sampleDurationSeconds', '报告指标样本时长'),
    coverage: _requiredDouble(value, 'coverage', '报告指标覆盖率'),
    status: _enumByName(
      MetricStatus.values,
      _requiredString(value, 'status', '报告指标状态'),
      '报告指标状态',
    ),
    algorithmVersion: _requiredString(value, 'algorithmVersion', '报告指标算法版本'),
    inputFingerprint: _requiredString(value, 'inputFingerprint', '报告指标输入指纹'),
    computedAt: _requiredDateTime(value, 'computedAt', '报告指标计算时间'),
    loadMethod: _loadMethodFromCode(value['loadMethod'] as String? ?? ''),
    baselineValue: (value['baselineValue'] as num?)?.toDouble(),
    invalidatedAt: _optionalDateTime(value['invalidatedAt'], '报告指标失效时间'),
    metadata: Map<String, Object?>.unmodifiable(
      Map<String, Object?>.from(metadata),
    ),
  );
}

Map<String, Object?> _snapshotToJson(ReportMetricSnapshot snapshot) {
  return <String, Object?>{
    'metricId': snapshot.metricId,
    'metricCode': snapshot.metricCode,
    'value': snapshot.value,
    'unit': snapshot.unit,
    'sampleCount': snapshot.sampleCount,
    'sampleDurationSeconds': snapshot.sampleDurationSeconds,
    'coverage': snapshot.coverage,
    'status': snapshot.status.name,
    'algorithmVersion': snapshot.algorithmVersion,
    'inputFingerprint': snapshot.inputFingerprint,
    'computedAt': snapshot.computedAt.toUtc().toIso8601String(),
    'loadMethod': snapshot.loadMethod?.code ?? '',
    'baselineValue': snapshot.baselineValue,
    'invalidatedAt': snapshot.invalidatedAt?.toUtc().toIso8601String(),
    'metadata': snapshot.metadata,
  };
}

String _stableFingerprint(Object? value) {
  int hash = 5381;
  for (final int byte in utf8.encode(_canonicalJson(value))) {
    hash = (((hash << 5) + hash) ^ byte) & 0x7fffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalValue(value));

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final List<String> keys = value.keys.map((Object? key) => '$key').toList()
      ..sort();
    return <String, Object?>{
      for (final String key in keys) key: _canonicalValue(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map<Object?>(_canonicalValue).toList(growable: false);
  }
  return value;
}
