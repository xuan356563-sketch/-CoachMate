import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/self_use_acceptance.dart';
import '../../../data/repositories/self_use_acceptance_repository.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import '../../../services/local_storage_service.dart';

final selfUseAcceptanceRepositoryProvider =
    Provider<SelfUseAcceptanceRepository>(
  (Ref ref) => PersistedSelfUseAcceptanceRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

final selfUseAcceptanceServiceProvider = Provider<SelfUseAcceptanceService>(
  (Ref ref) {
    final SelfUseAcceptanceService service = SelfUseAcceptanceService(
      repository: ref.watch(selfUseAcceptanceRepositoryProvider),
      storage: ref.watch(localStorageServiceProvider),
      featureAccess: ref.watch(featureAccessProvider),
    );
    bindFeatureController(
      ref,
      SelfUseAcceptanceService.featureId,
      'controller',
      service,
    );
    return service;
  },
);

/// 14 天自用验收的唯一写边界；清空是用户数据删除权例外。
class SelfUseAcceptanceService {
  const SelfUseAcceptanceService({
    required SelfUseAcceptanceRepository repository,
    required LocalStorageService storage,
    required FeatureAccess featureAccess,
  })  : _repository = repository,
        _storage = storage,
        _featureAccess = featureAccess;

  static const String featureId = 'feature.self_use_acceptance';

  final SelfUseAcceptanceRepository _repository;
  final LocalStorageService _storage;
  final FeatureAccess _featureAccess;

  SelfUseAcceptanceRecord getRecord() => _repository.getRecord();

  Future<SelfUseAcceptanceRecord> start(DateTime startedAt) =>
      _write(() => _repository.start(startedAt));

  Future<SelfUseAcceptanceRecord> updateDay(SelfUseAcceptanceDay day) =>
      _write(() => _repository.updateDay(day));

  Future<void> clear() async {
    _repository.clear();
    await _storage.flush();
  }

  Future<T> _write<T>(T Function() write) async {
    final FeatureOperation operation = _featureAccess.beginOperation(featureId);
    final SelfUseAcceptanceRecord previous = _repository.getRecord();
    return operation.commit(() async {
      try {
        final T result = write();
        await _storage.flush();
        return result;
      } catch (_) {
        _restore(previous);
        try {
          await _storage.flush();
        } catch (_) {
          throw StateError('自用验收记录保存失败，恢复落盘也失败；内存仍显示原记录，请不要关闭应用并重试。');
        }
        throw StateError('自用验收记录保存失败，已恢复原记录，请重试。');
      }
    });
  }

  void _restore(SelfUseAcceptanceRecord record) {
    _repository.clear();
    if (!record.isStarted) return;
    _repository.start(record.startedAt!);
    for (final SelfUseAcceptanceDay day in record.days) {
      _repository.updateDay(day);
    }
  }
}
