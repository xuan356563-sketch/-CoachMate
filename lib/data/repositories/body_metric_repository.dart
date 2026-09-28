import '../models/body_metric.dart';
import '../models/body_metric_revision.dart';
import '../seed/seed_body_metrics.dart';
import '../../services/local_storage_service.dart';
import '../../services/confirmed_local_document_write.dart';

abstract class BodyMetricRepository {
  List<BodyMetric> listMetrics();

  List<BodyMetricRevision> listRevisions();

  BodyMetric saveMetric(BodyMetric metric, {String reason = '同日记录覆盖'});

  /// 用户确认入口等待持久化；失败时保留原记录与修订。
  Future<BodyMetric> saveConfirmedMetric(BodyMetric metric,
      {String reason = '同日记录覆盖'});

  /// 一次提交全部已解析记录；落盘前不发布，失败恢复原文档。
  Future<void> saveConfirmedMetrics(List<BodyMetric> metrics,
      {String reason = '同日记录覆盖'});

  /// 仅供同一次本地联合提交使用，调用方必须提交或释放候选写锁。
  PreparedLocalDocumentWrite prepareConfirmedMetrics(List<BodyMetric> metrics,
      {String reason = '同日记录覆盖'});

  void clearMetrics();
}

class InMemoryBodyMetricRepository implements BodyMetricRepository {
  final List<BodyMetric> _metrics;
  final List<BodyMetricRevision> _revisions = [];
  bool _savingConfirmation = false;
  bool _recoveryRequired = false;

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
    _checkWritable();
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
  Future<BodyMetric> saveConfirmedMetric(BodyMetric metric,
      {String reason = '同日记录覆盖'}) async => saveMetric(metric, reason: reason);

  @override
  Future<void> saveConfirmedMetrics(List<BodyMetric> metrics,
      {String reason = '同日记录覆盖'}) async {
    for (final metric in metrics) {
      saveMetric(metric, reason: reason);
    }
  }

  @override
  PreparedLocalDocumentWrite prepareConfirmedMetrics(List<BodyMetric> metrics,
      {String reason = '同日记录覆盖'}) {
    _checkWritable();
    final candidate = InMemoryBodyMetricRepository(initialMetrics: _metrics);
    candidate._revisions.addAll(_revisions);
    for (final metric in metrics) { candidate.saveMetric(metric, reason: reason); }
    _savingConfirmation = true;
    return PreparedLocalDocumentWrite(
      key: 'trainflow.body_metrics.v1',
      document: {'schemaVersion': 1,
        'metrics': candidate._metrics.map((e) => e.toJson()).toList(),
        'revisions': candidate._revisions.map((e) => e.toJson()).toList()},
      publish: () {
        _metrics..clear()..addAll(candidate._metrics);
        _revisions..clear()..addAll(candidate._revisions);
      },
      blockRecovery: () => _recoveryRequired = true,
      release: () => _savingConfirmation = false,
    );
  }

  @override
  void clearMetrics() {
    _checkWritable();
    _metrics.clear();
    _revisions.clear();
  }

  void _checkWritable() {
    if (_recoveryRequired) {
      throw StateError('身体数据恢复尚未确认，请重启检查后再操作。');
    }
    if (_savingConfirmation) {
      throw StateError('身体数据正在保存，请稍候再操作。');
    }
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
  bool _savingConfirmation = false;
  bool _recoveryRequired = false;

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
    _checkWritable();
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
  Future<BodyMetric> saveConfirmedMetric(BodyMetric metric,
      {String reason = '同日记录覆盖'}) async {
    await saveConfirmedMetrics([metric], reason: reason);
    return metric;
  }

  @override
  Future<void> saveConfirmedMetrics(List<BodyMetric> metrics,
      {String reason = '同日记录覆盖'}) => commitLocalDocumentWrites(
        _storageService, [prepareConfirmedMetrics(metrics, reason: reason)],
        label: '身体数据');

  @override
  PreparedLocalDocumentWrite prepareConfirmedMetrics(List<BodyMetric> metrics,
      {String reason = '同日记录覆盖'}) {
    _checkWritable();
    _savingConfirmation = true;
    try {
      final staging = InMemoryLocalStorageService();
      staging.saveJson(_storageKey, {
        'schemaVersion': 1,
        'metrics': _metrics.map((e) => e.toJson()).toList(),
        'revisions': _revisions.map((e) => e.toJson()).toList(),
      });
      final candidate = PersistedBodyMetricRepository(staging);
      for (final metric in metrics) { candidate.saveMetric(metric, reason: reason); }
      return PreparedLocalDocumentWrite(
        key: _storageKey, document: staging.readJson(_storageKey)!,
        publish: () {
          _metrics..clear()..addAll(candidate.listMetrics());
          _revisions..clear()..addAll(candidate.listRevisions());
        },
        blockRecovery: () => _recoveryRequired = true,
        release: () => _savingConfirmation = false,
      );
    } catch (_) {
      _savingConfirmation = false;
      rethrow;
    }
  }

  void _checkWritable() {
    if (_recoveryRequired) {
      throw StateError('身体数据恢复尚未确认，请重启检查后再操作。');
    }
    if (_savingConfirmation) {
      throw StateError('身体数据正在保存，请等待完成后再操作。');
    }
  }

  @override
  void clearMetrics() {
    _checkWritable();
    _metrics.clear();
    _revisions.clear();
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(_storageKey);
    if (storedState == null) {
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
