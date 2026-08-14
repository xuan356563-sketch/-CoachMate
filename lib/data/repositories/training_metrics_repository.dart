import '../models/monthly_summary.dart';
import '../models/training_metrics.dart';

/// 指标、血缘、报告修订和调整建议的存储边界。
///
/// 当前实现仅用于应用层接线和单元测试；SQLite 实现由结构化存储层提供。
abstract interface class TrainingMetricsRepository {
  Future<void> saveAggregate(MetricAggregate aggregate);

  Future<List<MetricAggregate>> listAggregates({
    required String athleteProfileId,
    MetricPeriod? period,
    DateTime? periodStart,
    bool includeInvalidated = false,
  });

  Future<void> saveLineage(MetricLineage lineage);

  Future<List<MetricLineage>> listLineage({required String metricId});

  /// 失效与来源相关的指标，返回受影响指标 ID，供上层修订报告和成长证据。
  Future<List<String>> invalidateBySource({
    required String athleteProfileId,
    required String sourceType,
    required String sourceId,
    required DateTime invalidatedAt,
  });

  Future<void> saveReportRevision(ReportRevision revision);

  Future<List<ReportRevision>> listReportRevisions({
    required String athleteProfileId,
    required MetricPeriod period,
    required DateTime periodStart,
  });

  Future<void> saveAdjustmentProposal(AdjustmentProposal proposal);

  Future<List<AdjustmentProposal>> listAdjustmentProposals({
    required String athleteProfileId,
  });
}

/// 不持久化的参考实现，避免计算和页面层直接依赖 SQLite。
class InMemoryTrainingMetricsRepository implements TrainingMetricsRepository {
  final Map<String, MetricAggregate> _aggregates = <String, MetricAggregate>{};
  final Map<String, MetricLineage> _lineage = <String, MetricLineage>{};
  final Map<String, ReportRevision> _reportRevisions =
      <String, ReportRevision>{};
  final Map<String, AdjustmentProposal> _proposals =
      <String, AdjustmentProposal>{};

  @override
  Future<void> saveAggregate(MetricAggregate aggregate) async {
    _aggregates[aggregate.id] = aggregate;
  }

  @override
  Future<List<MetricAggregate>> listAggregates({
    required String athleteProfileId,
    MetricPeriod? period,
    DateTime? periodStart,
    bool includeInvalidated = false,
  }) async {
    final List<MetricAggregate> result = _aggregates.values
        .where(
          (MetricAggregate item) =>
              item.athleteProfileId == athleteProfileId &&
              (period == null || item.period == period) &&
              (periodStart == null ||
                  _sameInstant(item.periodStart, periodStart)) &&
              (includeInvalidated || item.status != MetricStatus.invalidated),
        )
        .toList()
      ..sort(_metricSort);
    return List<MetricAggregate>.unmodifiable(result);
  }

  @override
  Future<void> saveLineage(MetricLineage lineage) async {
    _lineage[_lineageKey(lineage)] = lineage;
  }

  @override
  Future<List<MetricLineage>> listLineage({required String metricId}) async {
    final List<MetricLineage> result = _lineage.values
        .where((MetricLineage item) => item.metricId == metricId)
        .toList()
      ..sort((MetricLineage first, MetricLineage second) =>
          first.createdAt.compareTo(second.createdAt));
    return List<MetricLineage>.unmodifiable(result);
  }

  @override
  Future<List<String>> invalidateBySource({
    required String athleteProfileId,
    required String sourceType,
    required String sourceId,
    required DateTime invalidatedAt,
  }) async {
    final Set<String> affectedIds = _lineage.values
        .where(
          (MetricLineage item) =>
              item.sourceType == sourceType &&
              item.sourceId == sourceId &&
              item.invalidatedAt == null,
        )
        .map((MetricLineage item) => item.metricId)
        .where(
          (String metricId) =>
              _aggregates[metricId]?.athleteProfileId == athleteProfileId,
        )
        .toSet();

    for (final String metricId in affectedIds) {
      final MetricAggregate? aggregate = _aggregates[metricId];
      if (aggregate != null) {
        _aggregates[metricId] = aggregate.copyWith(
          status: MetricStatus.invalidated,
          invalidatedAt: invalidatedAt,
        );
      }
    }
    for (final MapEntry<String, MetricLineage> entry
        in _lineage.entries.toList()) {
      final MetricLineage item = entry.value;
      if (affectedIds.contains(item.metricId) &&
          item.sourceType == sourceType &&
          item.sourceId == sourceId &&
          item.invalidatedAt == null) {
        _lineage[entry.key] = MetricLineage(
          metricId: item.metricId,
          sourceType: item.sourceType,
          sourceId: item.sourceId,
          relationship: item.relationship,
          createdAt: item.createdAt,
          invalidatedAt: invalidatedAt,
        );
      }
    }
    final List<String> result = affectedIds.toList()..sort();
    return List<String>.unmodifiable(result);
  }

  @override
  Future<void> saveReportRevision(ReportRevision revision) async {
    final ReportRevision? sameId = _reportRevisions[revision.id];
    if (sameId != null) {
      if (_sameReportRevision(sameId, revision)) return;
      throw StateError('报告修订不可覆盖，请创建新的修订号。');
    }
    final bool revisionExists = _reportRevisions.values.any(
      (ReportRevision item) =>
          item.athleteProfileId == revision.athleteProfileId &&
          item.period == revision.period &&
          _sameInstant(item.periodStart, revision.periodStart) &&
          item.revision == revision.revision,
    );
    if (revisionExists) {
      throw StateError('同一周期的报告修订号已存在。');
    }
    _reportRevisions[revision.id] = _freezeReportRevision(revision);
  }

  @override
  Future<List<ReportRevision>> listReportRevisions({
    required String athleteProfileId,
    required MetricPeriod period,
    required DateTime periodStart,
  }) async {
    final List<ReportRevision> result = _reportRevisions.values
        .where(
          (ReportRevision item) =>
              item.athleteProfileId == athleteProfileId &&
              item.period == period &&
              _sameInstant(item.periodStart, periodStart),
        )
        .toList()
      ..sort((ReportRevision first, ReportRevision second) =>
          second.revision.compareTo(first.revision));
    return List<ReportRevision>.unmodifiable(result);
  }

  @override
  Future<void> saveAdjustmentProposal(AdjustmentProposal proposal) async {
    _proposals[proposal.id] = proposal;
  }

  @override
  Future<List<AdjustmentProposal>> listAdjustmentProposals({
    required String athleteProfileId,
  }) async {
    final List<AdjustmentProposal> result = _proposals.values
        .where((AdjustmentProposal item) =>
            item.athleteProfileId == athleteProfileId)
        .toList()
      ..sort((AdjustmentProposal first, AdjustmentProposal second) =>
          second.createdAt.compareTo(first.createdAt));
    return List<AdjustmentProposal>.unmodifiable(result);
  }
}

String _lineageKey(MetricLineage item) =>
    '${item.metricId}\u0000${item.sourceType}\u0000${item.sourceId}\u0000${item.relationship}';

bool _sameInstant(DateTime first, DateTime second) =>
    first.toUtc().microsecondsSinceEpoch ==
    second.toUtc().microsecondsSinceEpoch;

int _metricSort(MetricAggregate first, MetricAggregate second) {
  final int periodOrder = second.periodStart.compareTo(first.periodStart);
  return periodOrder != 0
      ? periodOrder
      : first.metricCode.compareTo(second.metricCode);
}

bool _sameReportRevision(ReportRevision first, ReportRevision second) {
  return first.athleteProfileId == second.athleteProfileId &&
      first.period == second.period &&
      _sameInstant(first.periodStart, second.periodStart) &&
      first.revision == second.revision &&
      _sameInstant(first.generatedAt, second.generatedAt) &&
      first.narrative == second.narrative &&
      first.algorithmVersion == second.algorithmVersion &&
      first.previousRevisionId == second.previousRevisionId &&
      _sameStringList(first.metricIds, second.metricIds) &&
      _sameSnapshotList(first.metricSnapshots, second.metricSnapshots) &&
      _sameObject(
        first.monthlySummarySnapshot?.toJson(),
        second.monthlySummarySnapshot?.toJson(),
      );
}

bool _sameStringList(List<String> first, List<String> second) {
  if (first.length != second.length) return false;
  for (int index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

ReportRevision _freezeReportRevision(ReportRevision revision) {
  return ReportRevision(
    id: revision.id,
    athleteProfileId: revision.athleteProfileId,
    period: revision.period,
    periodStart: revision.periodStart,
    revision: revision.revision,
    generatedAt: revision.generatedAt,
    metricIds: List<String>.unmodifiable(revision.metricIds),
    metricSnapshots: List<ReportMetricSnapshot>.unmodifiable(
      revision.metricSnapshots.map(_freezeSnapshot),
    ),
    narrative: revision.narrative,
    algorithmVersion: revision.algorithmVersion,
    previousRevisionId: revision.previousRevisionId,
    monthlySummarySnapshot: revision.monthlySummarySnapshot == null
        ? null
        : MonthlySummary.fromJson(
            revision.monthlySummarySnapshot!.toJson(),
          ),
  );
}

ReportMetricSnapshot _freezeSnapshot(ReportMetricSnapshot snapshot) {
  return ReportMetricSnapshot(
    metricId: snapshot.metricId,
    metricCode: snapshot.metricCode,
    value: snapshot.value,
    unit: snapshot.unit,
    sampleCount: snapshot.sampleCount,
    sampleDurationSeconds: snapshot.sampleDurationSeconds,
    coverage: snapshot.coverage,
    status: snapshot.status,
    algorithmVersion: snapshot.algorithmVersion,
    inputFingerprint: snapshot.inputFingerprint,
    computedAt: snapshot.computedAt,
    loadMethod: snapshot.loadMethod,
    baselineValue: snapshot.baselineValue,
    invalidatedAt: snapshot.invalidatedAt,
    metadata: Map<String, Object?>.unmodifiable(snapshot.metadata),
  );
}

bool _sameSnapshotList(
  List<ReportMetricSnapshot> first,
  List<ReportMetricSnapshot> second,
) {
  if (first.length != second.length) return false;
  for (int index = 0; index < first.length; index += 1) {
    final ReportMetricSnapshot firstItem = first[index];
    final ReportMetricSnapshot secondItem = second[index];
    if (firstItem.metricId != secondItem.metricId ||
        firstItem.metricCode != secondItem.metricCode ||
        firstItem.value != secondItem.value ||
        firstItem.unit != secondItem.unit ||
        firstItem.sampleCount != secondItem.sampleCount ||
        firstItem.sampleDurationSeconds != secondItem.sampleDurationSeconds ||
        firstItem.coverage != secondItem.coverage ||
        firstItem.status != secondItem.status ||
        firstItem.algorithmVersion != secondItem.algorithmVersion ||
        firstItem.inputFingerprint != secondItem.inputFingerprint ||
        !_sameInstant(firstItem.computedAt, secondItem.computedAt) ||
        firstItem.loadMethod != secondItem.loadMethod ||
        firstItem.baselineValue != secondItem.baselineValue ||
        !_sameOptionalInstant(
          firstItem.invalidatedAt,
          secondItem.invalidatedAt,
        ) ||
        !_sameObject(firstItem.metadata, secondItem.metadata)) {
      return false;
    }
  }
  return true;
}

bool _sameOptionalInstant(DateTime? first, DateTime? second) {
  if (first == null || second == null) return first == second;
  return _sameInstant(first, second);
}

bool _sameObject(Object? first, Object? second) {
  if (first is Map && second is Map) {
    if (first.length != second.length) return false;
    for (final Object? key in first.keys) {
      if (!second.containsKey(key) || !_sameObject(first[key], second[key])) {
        return false;
      }
    }
    return true;
  }
  if (first is List && second is List) {
    if (first.length != second.length) return false;
    for (int index = 0; index < first.length; index += 1) {
      if (!_sameObject(first[index], second[index])) return false;
    }
    return true;
  }
  return first == second;
}
