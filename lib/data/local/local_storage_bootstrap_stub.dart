import 'package:trainflow_ai/data/local/local_storage_bootstrap_coordinator.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

Future<LocalStorageBootstrapResult> initializeLocalStorage() async {
  final SharedPreferencesLocalStorageService legacyStorage =
      await SharedPreferencesLocalStorageService.create();
  return LocalStorageBootstrapResult(
    storageService: legacyStorage,
    growthEvidenceRepository: PersistedGrowthEvidenceRepository(legacyStorage),
    trainingMetricsRepository: InMemoryTrainingMetricsRepository(),
    petDatabaseGateway: null,
    companionDatabaseGateway: null,
    backend: LocalStorageBackend.sharedPreferences,
  );
}
