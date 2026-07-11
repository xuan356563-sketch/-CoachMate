import '../models/formal_ai_plan.dart';
import '../../services/local_storage_service.dart';

abstract class FormalAiPlanRepository {
  FormalAiPlan? getPlan();

  bool isUnlocked();

  FormalAiPlan savePlan(FormalAiPlan plan);

  void clearPlan();
}

class InMemoryFormalAiPlanRepository implements FormalAiPlanRepository {
  FormalAiPlan? _plan;
  bool _unlocked = false;

  @override
  FormalAiPlan? getPlan() {
    return _plan;
  }

  @override
  bool isUnlocked() {
    return _unlocked;
  }

  @override
  FormalAiPlan savePlan(FormalAiPlan plan) {
    _plan = plan;
    _unlocked = true;
    return plan;
  }

  @override
  void clearPlan() {
    _plan = null;
    _unlocked = false;
  }
}

class PersistedFormalAiPlanRepository implements FormalAiPlanRepository {
  static const String storageKey = 'trainflow.formal_ai_plan.v1';

  final LocalStorageService _storageService;
  FormalAiPlan? _plan;
  bool _unlocked = false;

  PersistedFormalAiPlanRepository(this._storageService) {
    _hydrate();
  }

  @override
  FormalAiPlan? getPlan() {
    return _plan;
  }

  @override
  bool isUnlocked() {
    return _unlocked;
  }

  @override
  FormalAiPlan savePlan(FormalAiPlan plan) {
    _plan = plan;
    _unlocked = true;
    _persist();
    return plan;
  }

  @override
  void clearPlan() {
    _plan = null;
    _unlocked = false;
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final Object? planJson = storedState['plan'];
    if (planJson is Map<String, dynamic>) {
      _plan = FormalAiPlan.fromJson(planJson);
      _unlocked = storedState.containsKey('unlocked')
          ? storedState['unlocked'] == true
          : true;
    } else {
      _unlocked = false;
    }
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'unlocked': _unlocked,
      'plan': _plan?.toJson(),
    });
  }
}
