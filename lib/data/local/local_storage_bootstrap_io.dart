import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:trainflow_ai/data/local/database_local_storage_service.dart';
import 'package:trainflow_ai/data/local/local_storage_bootstrap_coordinator.dart';
import 'package:trainflow_ai/data/local/sqflite_trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/local/trainflow_database_schema.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/features/profile/application/native_healthkit_bridge.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

Future<LocalStorageBootstrapResult> initializeLocalStorage() async {
  final SharedPreferencesLocalStorageService legacyStorage =
      await SharedPreferencesLocalStorageService.create();
  final String databasePath = p.join(
    await getDatabasesPath(),
    TrainFlowDatabaseSchema.databaseName,
  );
  final bool databaseAlreadyExists = await databaseExists(databasePath);
  final LocalStorageBootstrapResult result =
      await LocalStorageBootstrapCoordinator(
    legacyStorage: legacyStorage,
    openDatabase: SqfliteTrainFlowDatabaseGateway.open,
    storageKeys: SharedPreferencesLocalStorageService.allowedKeys.where(
      (String key) => key != LocalStorageBootstrapCoordinator.cutoverMarkerKey,
    ),
    protectExistingDatabaseOnFailure: databaseAlreadyExists,
    onWriteError: (Object error, StackTrace stackTrace) {
      developer.log(
        'SQLite 写入失败，当前内存状态尚未安全落盘',
        name: 'TrainFlow.Storage',
        error: error,
        stackTrace: stackTrace,
      );
    },
  ).initialize();
  if (result.backend == LocalStorageBackend.sqlite) {
    try {
      await createNativeHealthKitBridge().protectLocalFiles(
        await _databaseProtectionPaths(databasePath),
      );
    } catch (error, stackTrace) {
      final LocalStorageService storage = result.storageService;
      if (storage is DatabaseLocalStorageService) {
        try {
          await storage.close();
        } catch (_) {
          // 文件保护失败是主错误，关闭数据库的次要错误不覆盖它。
        }
      }
      developer.log(
        '本地健康数据库文件保护失败，已进入只读恢复状态',
        name: 'TrainFlow.Storage',
        error: error,
        stackTrace: stackTrace,
      );
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
        backend: LocalStorageBackend.readOnlyRecovery,
        fallbackReason: '本地健康数据库未能完成安全保护。'
            '为防止健康数据以未保护状态写入，已进入只读恢复状态，请重启应用后重试。',
        fallbackError: error,
        fallbackStackTrace: stackTrace,
      );
    }
  }
  if (result.fallbackReason != null) {
    developer.log(
      result.fallbackReason!,
      name: 'TrainFlow.Storage',
      error: result.fallbackError,
      stackTrace: result.fallbackStackTrace,
    );
  }
  return result;
}

Future<List<String>> _databaseProtectionPaths(String databasePath) async {
  final List<String> paths = <String>[
    p.dirname(databasePath),
    databasePath,
    '$databasePath-wal',
    '$databasePath-shm',
  ];
  final Directory directory = Directory(p.dirname(databasePath));
  if (!await directory.exists()) return paths;
  final RegExp backupName = RegExp(
    '^${RegExp.escape(p.basename(databasePath))}\\.v[1-9][0-9]*\\.bak\$',
  );
  await for (final FileSystemEntity entry
      in directory.list(followLinks: false)) {
    if (entry is File && backupName.hasMatch(p.basename(entry.path))) {
      paths.add(entry.path);
    }
  }
  paths.sort();
  return List<String>.unmodifiable(paths);
}
