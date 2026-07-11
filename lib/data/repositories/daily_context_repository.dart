import '../models/daily_adjustment.dart';
import '../../services/local_storage_service.dart';

abstract class DailyContextRepository {
  DailyAdjustmentContext getContext({int defaultAvailableMinutes = 45});

  DailyAdjustmentContext saveContext(DailyAdjustmentContext context);

  void clearContext();
}

class InMemoryDailyContextRepository implements DailyContextRepository {
  DailyAdjustmentContext? _context;

  @override
  DailyAdjustmentContext getContext({int defaultAvailableMinutes = 45}) {
    return _context ??
        DailyAdjustmentContext.defaults(
          availableMinutes: defaultAvailableMinutes,
        );
  }

  @override
  DailyAdjustmentContext saveContext(DailyAdjustmentContext context) {
    _context = _normalizeContext(context);
    return _context!;
  }

  @override
  void clearContext() {
    _context = null;
  }

  DailyAdjustmentContext _normalizeContext(DailyAdjustmentContext context) {
    return DailyAdjustmentContext(
      availableMinutes: context.availableMinutes.clamp(10, 180).toInt(),
      workStress: context.workStress,
      environment: context.environment,
      weather: context.weather,
      statusMessage: context.statusMessage.trim().isEmpty
          ? '尚未应用今日现实约束调整。'
          : context.statusMessage,
    );
  }
}

class PersistedDailyContextRepository implements DailyContextRepository {
  static const String storageKey = 'trainflow.daily_context.v1';

  final LocalStorageService _storageService;
  DailyAdjustmentContext? _context;

  PersistedDailyContextRepository(this._storageService) {
    _hydrate();
  }

  @override
  DailyAdjustmentContext getContext({int defaultAvailableMinutes = 45}) {
    return _context ??
        DailyAdjustmentContext.defaults(
          availableMinutes: defaultAvailableMinutes,
        );
  }

  @override
  DailyAdjustmentContext saveContext(DailyAdjustmentContext context) {
    _context = _normalizeContext(context);
    _persist();
    return _context!;
  }

  @override
  void clearContext() {
    _context = null;
    _storageService.remove(storageKey);
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final Object? contextJson = storedState['context'];
    if (contextJson is Map<String, dynamic>) {
      _context = _normalizeContext(
        DailyAdjustmentContext.fromJson(contextJson),
      );
    }
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'context': _context?.toJson(),
    });
  }

  DailyAdjustmentContext _normalizeContext(DailyAdjustmentContext context) {
    return DailyAdjustmentContext(
      availableMinutes: context.availableMinutes.clamp(10, 180).toInt(),
      workStress: context.workStress,
      environment: context.environment,
      weather: context.weather,
      statusMessage: context.statusMessage.trim().isEmpty
          ? '尚未应用今日现实约束调整。'
          : context.statusMessage,
    );
  }
}
