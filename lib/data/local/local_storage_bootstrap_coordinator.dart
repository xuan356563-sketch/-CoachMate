import 'package:trainflow_ai/data/local/database_local_storage_service.dart';
import 'package:trainflow_ai/data/local/companion_database_gateway.dart';
import 'package:trainflow_ai/data/local/coach_database_gateway.dart';
import 'package:trainflow_ai/data/local/legacy_storage_migrator.dart';
import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/local/sqflite_trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/local/trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/local/trainflow_database_schema.dart';
import 'package:trainflow_ai/data/local/trainmate_structured_database_gateway.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/data/repositories/sqlite_training_metrics_repository.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/features/cloud_sync/data/cloud_sync_local_store.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

enum LocalStorageBackend {
  sqlite,
  sharedPreferences,
  readOnlyRecovery,
}

class LocalStorageBootstrapResult {
  const LocalStorageBootstrapResult({
    required this.storageService,
    required this.growthEvidenceRepository,
    required this.trainingMetricsRepository,
    required this.backend,
    this.structuredDatabaseGateway,
    this.petDatabaseGateway,
    this.companionDatabaseGateway,
    this.coachDatabaseGateway,
    this.cloudSyncLocalStore,
    this.migrationResult,
    this.fallbackReason,
    this.fallbackError,
    this.fallbackStackTrace,
  });

  final LocalStorageService storageService;
  final GrowthEvidenceRepository growthEvidenceRepository;
  final TrainingMetricsRepository trainingMetricsRepository;
  final TrainMateStructuredDatabaseGateway? structuredDatabaseGateway;
  final PetDatabaseGateway? petDatabaseGateway;
  final CompanionDatabaseGateway? companionDatabaseGateway;
  final CoachDatabaseGateway? coachDatabaseGateway;
  final CloudSyncLocalStore? cloudSyncLocalStore;
  final LocalStorageBackend backend;
  final LegacyMigrationResult? migrationResult;
  final String? fallbackReason;
  final Object? fallbackError;
  final StackTrace? fallbackStackTrace;
}

class LocalStorageBootstrapCoordinator {
  LocalStorageBootstrapCoordinator({
    required this.legacyStorage,
    required this.openDatabase,
    required Iterable<String> storageKeys,
    this.onWriteError,
    this.protectExistingDatabaseOnFailure = false,
    DateTime Function()? clock,
  })  : storageKeys = Set<String>.unmodifiable(storageKeys),
        _clock = clock;

  final LocalStorageService legacyStorage;
  final Future<TrainFlowDatabaseGateway> Function() openDatabase;
  final Set<String> storageKeys;
  final DatabaseWriteErrorHandler? onWriteError;
  final bool protectExistingDatabaseOnFailure;
  final DateTime Function()? _clock;

  static const String cutoverMarkerKey = 'trainflow.sqlite_cutover.v1';

  Future<LocalStorageBootstrapResult> initialize() async {
    TrainFlowDatabaseGateway? database;
    bool databaseBecamePrimary = false;
    try {
      database = await openDatabase();
      final LegacyMigrationResult migrationResult = await LegacyStorageMigrator(
        legacyStorage: legacyStorage,
        database: database,
        storageKeys: storageKeys,
        clock: _clock,
      ).migrate();
      final DatabaseLocalStorageService storageService =
          await DatabaseLocalStorageService.create(
        database,
        onWriteError: onWriteError,
      );
      databaseBecamePrimary = true;
      legacyStorage.saveJson(cutoverMarkerKey, <String, dynamic>{
        'schemaVersion': TrainFlowDatabaseSchema.version,
        'completed': true,
        'completedAt': (_clock ?? DateTime.now)().toUtc().toIso8601String(),
      });
      await legacyStorage.flush();
      final GrowthDatabaseGateway? growthDatabase =
          database is GrowthDatabaseGateway
              ? database as GrowthDatabaseGateway
              : null;
      final TrainMateStructuredDatabaseGateway? structuredDatabase =
          database is TrainMateStructuredDatabaseGateway
              ? database as TrainMateStructuredDatabaseGateway
              : null;
      final PetDatabaseGateway? petDatabase = database
              is PetDatabaseGatewayProvider
          ? (database as PetDatabaseGatewayProvider).createPetDatabaseGateway()
          : null;
      final CompanionDatabaseGateway? companionDatabase =
          database is CompanionDatabaseGatewayProvider
              ? (database as CompanionDatabaseGatewayProvider)
                  .createCompanionDatabaseGateway()
              : null;
      final CoachDatabaseGateway? coachDatabase =
          database is CoachDatabaseGatewayProvider
              ? (database as CoachDatabaseGatewayProvider)
                  .createCoachDatabaseGateway()
              : null;
      final CloudSyncLocalStore? cloudSyncLocalStore =
          database is SqfliteTrainFlowDatabaseGateway
              ? database.createCloudSyncLocalStore()
              : null;
      return LocalStorageBootstrapResult(
        storageService: storageService,
        growthEvidenceRepository: growthDatabase != null
            ? SqliteGrowthEvidenceRepository(growthDatabase)
            : PersistedGrowthEvidenceRepository(storageService),
        trainingMetricsRepository: structuredDatabase != null
            ? SQLiteTrainingMetricsRepository(structuredDatabase)
            : InMemoryTrainingMetricsRepository(),
        structuredDatabaseGateway: structuredDatabase,
        petDatabaseGateway: petDatabase,
        companionDatabaseGateway: companionDatabase,
        coachDatabaseGateway: coachDatabase,
        cloudSyncLocalStore: cloudSyncLocalStore,
        backend: LocalStorageBackend.sqlite,
        migrationResult: migrationResult,
      );
    } catch (error, stackTrace) {
      if (database != null) {
        try {
          await database.close();
        } catch (_) {
          // 回退路径不能被关闭数据库时的次要错误打断。
        }
      }
      final bool hasCutover =
          legacyStorage.readJson(cutoverMarkerKey)?['completed'] == true;
      if (hasCutover ||
          protectExistingDatabaseOnFailure ||
          databaseBecamePrimary) {
        const ReadOnlyRecoveryLocalStorageService recoveryStorage =
            ReadOnlyRecoveryLocalStorageService();
        return LocalStorageBootstrapResult(
          storageService: recoveryStorage,
          growthEvidenceRepository: PersistedGrowthEvidenceRepository(
            InMemoryLocalStorageService(),
          ),
          trainingMetricsRepository: InMemoryTrainingMetricsRepository(),
          petDatabaseGateway: null,
          companionDatabaseGateway: null,
          coachDatabaseGateway: null,
          backend: LocalStorageBackend.readOnlyRecovery,
          fallbackReason: '本地数据库暂时无法安全打开。'
              '为保护训练数据，已进入只读恢复状态，'
              '未读取陈旧设备副本。',
          fallbackError: error,
          fallbackStackTrace: stackTrace,
        );
      }
      return LocalStorageBootstrapResult(
        storageService: legacyStorage,
        growthEvidenceRepository:
            PersistedGrowthEvidenceRepository(legacyStorage),
        trainingMetricsRepository: InMemoryTrainingMetricsRepository(),
        petDatabaseGateway: null,
        companionDatabaseGateway: null,
        coachDatabaseGateway: null,
        backend: LocalStorageBackend.sharedPreferences,
        fallbackReason: 'SQLite 初始化或迁移失败，已继续使用原设备存储',
        fallbackError: error,
        fallbackStackTrace: stackTrace,
      );
    }
  }
}
