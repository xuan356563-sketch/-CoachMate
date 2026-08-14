import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainflow_ai/app/startup/local_storage_recovery_page.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/core/config/api_config.dart';
import 'package:trainflow_ai/data/local/local_storage_bootstrap.dart';
import 'package:trainflow_ai/data/local/local_storage_bootstrap_coordinator.dart';
import 'package:trainflow_ai/data/local/rhythm_database_gateway.dart';
import 'package:trainflow_ai/features/growth/application/growth_evidence_controller.dart';
import 'package:trainflow_ai/features/growth/application/training_metrics_provider.dart';
import 'package:trainflow_ai/features/companion/application/companion_database_provider.dart';
import 'package:trainflow_ai/features/pet/application/daily_activity_sync_controller.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/features/cloud_sync/application/cloud_sync_controller.dart';
import 'package:trainflow_ai/features/rhythm/application/body_rhythm_controller.dart';
import 'package:trainflow_ai/services/local_report_generation_coordinator.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/training_metrics_pipeline.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Release 启动前即校验 API 配置，避免 TestFlight 包静默回退到 localhost。
  try {
    ApiConfig.baseUrl;
  } on StateError catch (error) {
    runApp(StartupConfigurationErrorApp(message: error.message.toString()));
    return;
  }
  final LocalStorageBootstrapResult storageBootstrap =
      await initializeLocalStorage();

  runApp(TrainFlowBootstrapApp(initialResult: storageBootstrap));
}

class StartupConfigurationErrorApp extends StatelessWidget {
  const StartupConfigurationErrorApp({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    '发布配置错误',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TrainFlowBootstrapApp extends StatefulWidget {
  const TrainFlowBootstrapApp({
    super.key,
    required this.initialResult,
    this.retryBootstrap = initializeLocalStorage,
  });

  final LocalStorageBootstrapResult initialResult;
  final Future<LocalStorageBootstrapResult> Function() retryBootstrap;

  @override
  State<TrainFlowBootstrapApp> createState() => _TrainFlowBootstrapAppState();
}

class _TrainFlowBootstrapAppState extends State<TrainFlowBootstrapApp> {
  late LocalStorageBootstrapResult _result = widget.initialResult;

  Future<void> _retryBootstrap() async {
    final LocalStorageBootstrapResult next = await widget.retryBootstrap();
    if (!mounted) return;
    setState(() => _result = next);
  }

  @override
  Widget build(BuildContext context) {
    if (_result.backend == LocalStorageBackend.readOnlyRecovery) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: LocalStorageRecoveryPage(
          result: _result,
          onRetry: _retryBootstrap,
        ),
      );
    }

    return ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          _result.storageService,
        ),
        growthEvidenceRepositoryProvider.overrideWithValue(
          _result.growthEvidenceRepository,
        ),
        trainingMetricsRepositoryProvider.overrideWithValue(
          _result.trainingMetricsRepository,
        ),
        healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(
          _result.structuredDatabaseGateway,
        ),
        petDatabaseGatewayProvider.overrideWithValue(
          _result.petDatabaseGateway,
        ),
        companionDatabaseGatewayProvider.overrideWithValue(
          _result.companionDatabaseGateway,
        ),
        coachDatabaseGatewayProvider.overrideWithValue(
          _result.coachDatabaseGateway,
        ),
        cloudSyncLocalStoreProvider.overrideWithValue(
          _result.cloudSyncLocalStore,
        ),
        rhythmDatabaseGatewayProvider.overrideWithValue(
          _result.structuredDatabaseGateway is RhythmDatabaseGateway
              ? _result.structuredDatabaseGateway as RhythmDatabaseGateway
              : null,
        ),
        healthSyncMetricsPipelineProvider.overrideWith((Ref ref) {
          final structured = _result.structuredDatabaseGateway;
          if (structured == null) return null;
          return TrainingMetricsPipeline(
            database: structured,
            repository: ref.watch(trainingMetricsRepositoryProvider),
            healthDataGateway: ref.watch(healthDataGatewayProvider),
          );
        }),
      ],
      child: const _TrainFlowStartup(),
    );
  }
}

/// 应用启动即尝试排空已落到 Swift 队列的健康批次。
///
/// 失败会保留批次并由健康控制器暴露中文可重试状态，不阻断应用其他功能。
class _TrainFlowStartup extends ConsumerStatefulWidget {
  const _TrainFlowStartup();

  @override
  ConsumerState<_TrainFlowStartup> createState() => _TrainFlowStartupState();
}

class _TrainFlowStartupState extends ConsumerState<_TrainFlowStartup> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_initializeHealthSync);
  }

  Future<void> _initializeHealthSync() async {
    try {
      await ref.read(healthSyncControllerProvider.future);
      await LocalReportGenerationCoordinator(
        repository: ref.read(trainingMetricsRepositoryProvider),
        metricsPipeline: ref.read(healthSyncMetricsPipelineProvider),
        monthlySummaryLoader: ref.read(monthlySummaryLoaderProvider),
      ).ensureRecentlyClosedPeriods(
        athleteProfileId: ref.read(healthSyncAthleteIdProvider),
      );
    } catch (_) {
      // Provider 保留错误状态；启动壳不能因健康同步或报告补算失败阻断训练功能。
    }
  }

  @override
  Widget build(BuildContext context) => const TrainFlowApp();
}
