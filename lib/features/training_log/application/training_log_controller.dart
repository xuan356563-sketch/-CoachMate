import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/training_log.dart';
import '../../../data/repositories/training_log_repository.dart';
import '../../../services/local_storage_service.dart';

final trainingLogRepositoryProvider = Provider<TrainingLogRepository>(
  (Ref ref) => PersistedTrainingLogRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

final trainingLogControllerProvider =
    NotifierProvider<TrainingLogController, List<TrainingLog>>(
  TrainingLogController.new,
);

class TrainingLogController extends Notifier<List<TrainingLog>> {
  @override
  List<TrainingLog> build() {
    bindFeatureController(ref, 'feature.training_log', 'controller', this);
    return ref.read(trainingLogRepositoryProvider).listLogs();
  }

  Future<List<TrainingLog>> save(
    TrainingLog log, {
    FeatureOperation? sourceOperation,
  }) async {
    final FeatureOperation operation = sourceOperation ??
        ref.read(featureAccessProvider).beginOperation('feature.training_log');
    final TrainingLogRepository repository =
        ref.read(trainingLogRepositoryProvider);
    final LocalStorageService storage = ref.read(localStorageServiceProvider);
    return operation.commit(() async {
      repository.saveLog(log);
      await storage.flush();
      state = repository.listLogs();
      return state;
    });
  }

  Future<void> clear() async {
    final TrainingLogRepository repository =
        ref.read(trainingLogRepositoryProvider);
    final LocalStorageService storage = ref.read(localStorageServiceProvider);
    repository.clearLogs();
    await storage.flush();
    state = repository.listLogs();
  }
}
