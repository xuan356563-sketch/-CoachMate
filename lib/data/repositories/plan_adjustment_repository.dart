import '../models/plan_adjustment.dart';
import '../../services/local_storage_service.dart';

abstract class PlanAdjustmentRepository {
  List<PlanAdjustment> listAdjustments();

  PlanAdjustment saveAdjustment(PlanAdjustment adjustment);
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
    _adjustments.removeWhere(
      (PlanAdjustment item) => item.id == adjustment.id,
    );
    _adjustments.add(adjustment);
    _sortAdjustments();
    if (_adjustments.length > _maxSavedAdjustments) {
      _adjustments.removeRange(_maxSavedAdjustments, _adjustments.length);
    }
    _persist();
    return adjustment;
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
