import '../models/plan_adjustment.dart';
import '../../services/local_storage_service.dart';

abstract class PlanAdjustmentRepository {
  List<PlanAdjustment> listAdjustments();

  PlanAdjustment saveAdjustment(PlanAdjustment adjustment);

  /// 在一次持久化写入中保存同一建议产生的整组训练日差异。
  List<PlanAdjustment> saveAdjustmentsAtomically(
    List<PlanAdjustment> adjustments,
  );

  /// 删除由健康指标建议产生的调整，保留用户手动调整。
  int clearHealthDerivedAdjustments();
}

class PersistedPlanAdjustmentRepository implements PlanAdjustmentRepository {
  static const String storageKey = 'trainflow.plan_adjustments.v1';
  static const int _maxSavedAdjustments = 120;

  final LocalStorageService _storageService;
  final List<PlanAdjustment> _adjustments = [];

  PersistedPlanAdjustmentRepository(this._storageService) {
    _hydrate();
  }

  @override
  List<PlanAdjustment> listAdjustments() {
    _sortAdjustments();
    return List<PlanAdjustment>.unmodifiable(_adjustments);
  }

  @override
  PlanAdjustment saveAdjustment(PlanAdjustment adjustment) {
    saveAdjustmentsAtomically(<PlanAdjustment>[adjustment]);
    return adjustment;
  }

  @override
  List<PlanAdjustment> saveAdjustmentsAtomically(
    List<PlanAdjustment> adjustments,
  ) {
    if (adjustments.isEmpty) return const <PlanAdjustment>[];
    final List<PlanAdjustment> before = List<PlanAdjustment>.from(_adjustments);
    try {
      final Set<String> ids =
          adjustments.map((PlanAdjustment item) => item.id).toSet();
      _adjustments.removeWhere(
        (PlanAdjustment item) => ids.contains(item.id),
      );
      _adjustments.addAll(adjustments);
      _sortAdjustments();
      if (_adjustments.length > _maxSavedAdjustments) {
        _adjustments.removeRange(_maxSavedAdjustments, _adjustments.length);
      }
      _persist();
    } catch (_) {
      _adjustments
        ..clear()
        ..addAll(before);
      rethrow;
    }
    return List<PlanAdjustment>.unmodifiable(adjustments);
  }

  @override
  int clearHealthDerivedAdjustments() {
    final int before = _adjustments.length;
    _adjustments.removeWhere(
      (PlanAdjustment item) => item.sourceProposalId != null,
    );
    final int removed = before - _adjustments.length;
    if (removed > 0) _persist();
    return removed;
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final List<dynamic> adjustmentItems =
        storedState['adjustments'] as List<dynamic>? ?? const [];
    _adjustments.addAll(
      adjustmentItems
          .whereType<Map<String, dynamic>>()
          .map(PlanAdjustment.fromJson)
          .toList(),
    );
    _sortAdjustments();
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'adjustments': _adjustments
          .map((PlanAdjustment adjustment) => adjustment.toJson())
          .toList(),
    });
  }

  void _sortAdjustments() {
    _adjustments.sort(
      (PlanAdjustment a, PlanAdjustment b) =>
          b.adjustedAt.compareTo(a.adjustedAt),
    );
  }
}
