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
    return ref.read(trainingLogRepositoryProvider).listLogs();
  }

  List<TrainingLog> save(TrainingLog log) {
    final TrainingLogRepository repository =
        ref.read(trainingLogRepositoryProvider);
    repository.saveLog(log);
    state = repository.listLogs();
    return state;
  }

  void clear() {
    final TrainingLogRepository repository =
        ref.read(trainingLogRepositoryProvider);
    repository.clearLogs();
    state = repository.listLogs();
  }
}
