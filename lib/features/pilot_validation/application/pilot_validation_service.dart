import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/pilot_validation.dart';
import '../../../data/repositories/pilot_validation_repository.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import '../../../services/local_storage_service.dart';

final pilotValidationRepositoryProvider =
    Provider<PersistedPilotValidationRepository>(
  (Ref ref) => PersistedPilotValidationRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

final pilotValidationServiceProvider = Provider<PilotValidationService>(
  (Ref ref) {
    final PilotValidationService service = PilotValidationService(
      repository: ref.watch(pilotValidationRepositoryProvider),
      storage: ref.watch(localStorageServiceProvider),
      featureAccess: ref.watch(featureAccessProvider),
    );
    bindFeatureController(
      ref,
      PilotValidationService.featureId,
      'controller',
      service,
    );
    return service;
  },
);

/// 假设卡验收的唯一写边界；页面和测试都不能直接绕过生命周期守卫。
class PilotValidationService {
  const PilotValidationService({
    required PersistedPilotValidationRepository repository,
    required LocalStorageService storage,
    required FeatureAccess featureAccess,
  })  : _repository = repository,
        _storage = storage,
        _featureAccess = featureAccess;

  static const String featureId = 'feature.pilot_validation';

  final PersistedPilotValidationRepository _repository;
  final LocalStorageService _storage;
  final FeatureAccess _featureAccess;

  List<PilotParticipantRecord> listParticipants() =>
      _repository.listParticipants();

  Future<PilotParticipantRecord> addParticipant({
    required PilotScenario scenario,
    required DateTime startedOn,
  }) {
    return _write(() => _repository.addParticipant(
          scenario: scenario,
          startedOn: startedOn,
        ));
  }

  Future<PilotParticipantRecord> save(PilotParticipantRecord participant) =>
      _write(() => _repository.save(participant));

  Future<PilotParticipantRecord> markCheckIn(
    String participantId,
    DateTime date,
  ) =>
      _write(() => _repository.markCheckIn(participantId, date));

  Future<PilotParticipantRecord> markFeedback(
    String participantId,
    DateTime date,
  ) =>
      _write(() => _repository.markFeedback(participantId, date));

  Future<T> _write<T>(T Function() write) async {
    final FeatureOperation operation = _featureAccess.beginOperation(featureId);
    return operation.commit(() async {
      final T result = write();
      await _storage.flush();
      return result;
    });
  }
}
