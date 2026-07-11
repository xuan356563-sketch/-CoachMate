import '../models/body_metric.dart';
import '../models/body_metric_revision.dart';
import '../seed/seed_body_metrics.dart';
import '../../services/local_storage_service.dart';

abstract class BodyMetricRepository {
  List<BodyMetric> listMetrics();

  List<BodyMetricRevision> listRevisions();

  BodyMetric saveMetric(BodyMetric metric, {String reason = '同日记录覆盖'});

  void clearMetrics();
}

class InMemoryBodyMetricRepository implements BodyMetricRepository {
  final List<BodyMetric> _metrics;
  final List<BodyMetricRevision> _revisions = [];

  InMemoryBodyMetricRepository({List<BodyMetric>? initialMetrics})
      : _metrics = List<BodyMetric>.from(initialMetrics ?? seedBodyMetrics) {
    _sortMetrics();
  }

  @override
  List<BodyMetric> listMetrics() {
    _sortMetrics();
    return List<BodyMetric>.unmodifiable(_metrics);
  }

  @override
  List<BodyMetricRevision> listRevisions() {
    _sortRevisions();
    return List<BodyMetricRevision>.unmodifiable(_revisions);
  }

  @override
  BodyMetric saveMetric(BodyMetric metric, {String reason = '同日记录覆盖'}) {
    final List<BodyMetric> replacedMetrics = _metrics
        .where((BodyMetric item) =>
            _isSameDate(item.measuredAt, metric.measuredAt))
        .toList();
    final DateTime revisedAt = DateTime.now();
    for (final BodyMetric previousMetric in replacedMetrics) {
      _revisions.add(
        BodyMetricRevision(
          id: 'body-revision-${revisedAt.microsecondsSinceEpoch}-${previousMetric.id}',
          previousMetric: previousMetric,
          revisedMetric: metric,
          revisedAt: revisedAt,
          reason: reason,
        ),
      );
    }
    _metrics.removeWhere(
      (BodyMetric item) => _isSameDate(item.measuredAt, metric.measuredAt),
    );
    _metrics.add(metric);
    _sortMetrics();
    _sortRevisions();
    return metric;
  }

  @override
  void clearMetrics() {
    _metrics.clear();
    _revisions.clear();
  }

  void _sortMetrics() {
    _metrics.sort(
      (BodyMetric a, BodyMetric b) => b.measuredAt.compareTo(a.measuredAt),
    );
  }

  void _sortRevisions() {
    _revisions.sort(
      (BodyMetricRevision a, BodyMetricRevision b) =>
          b.revisedAt.compareTo(a.revisedAt),
    );
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class PersistedBodyMetricRepository implements BodyMetricRepository {
  static const String _storageKey = 'trainflow.body_metrics.v1';

  final LocalStorageService _storageService;
  final List<BodyMetric> _metrics;
  final List<BodyMetricRevision> _revisions;

  PersistedBodyMetricRepository(this._storageService)
      : _metrics = [],
        _revisions = [] {
    _hydrate();
  }

  @override
  List<BodyMetric> listMetrics() {
    _sortMetrics();
    return List<BodyMetric>.unmodifiable(_metrics);
  }

  @override
  List<BodyMetricRevision> listRevisions() {
    _sortRevisions();
    return List<BodyMetricRevision>.unmodifiable(_revisions);
  }

  @override
  BodyMetric saveMetric(BodyMetric metric, {String reason = '同日记录覆盖'}) {
    final List<BodyMetric> replacedMetrics = _metrics
        .where(
          (BodyMetric item) => _isSameDate(item.measuredAt, metric.measuredAt),
        )
        .toList();
    final DateTime revisedAt = DateTime.now();
    for (final BodyMetric previousMetric in replacedMetrics) {
      _revisions.add(
        BodyMetricRevision(
          id: 'body-revision-${revisedAt.microsecondsSinceEpoch}-${previousMetric.id}',
          previousMetric: previousMetric,
          revisedMetric: metric,
          revisedAt: revisedAt,
          reason: reason,
        ),
      );
    }
    _metrics.removeWhere(
      (BodyMetric item) => _isSameDate(item.measuredAt, metric.measuredAt),
    );
    _metrics.add(metric);
    _sortMetrics();
    _sortRevisions();
    _persist();
    return metric;
  }

  @override
  void clearMetrics() {
    _metrics.clear();
    _revisions.clear();
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(_storageKey);
    if (storedState == null) {
      _metrics.addAll(seedBodyMetrics);
      _sortMetrics();
      return;
    }

    final List<dynamic> metricItems =
        storedState['metrics'] as List<dynamic>? ?? const [];
    final List<dynamic> revisionItems =
        storedState['revisions'] as List<dynamic>? ?? const [];
    _metrics.addAll(
      metricItems
          .whereType<Map<String, dynamic>>()
          .map(BodyMetric.fromJson)
          .toList(),
    );
    _revisions.addAll(
      revisionItems
          .whereType<Map<String, dynamic>>()
          .map(BodyMetricRevision.fromJson)
          .toList(),
    );
    _sortMetrics();
    _sortRevisions();
  }

  void _persist() {
    _storageService.saveJson(_storageKey, {
      'schemaVersion': 1,
      'metrics': _metrics.map((BodyMetric metric) => metric.toJson()).toList(),
      'revisions': _revisions
          .map((BodyMetricRevision revision) => revision.toJson())
          .toList(),
    });
  }

  void _sortMetrics() {
    _metrics.sort(
      (BodyMetric a, BodyMetric b) => b.measuredAt.compareTo(a.measuredAt),
    );
  }

  void _sortRevisions() {
    _revisions.sort(
      (BodyMetricRevision a, BodyMetricRevision b) =>
          b.revisedAt.compareTo(a.revisedAt),
    );
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
