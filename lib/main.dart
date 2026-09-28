import 'plugins/application/plugin_runtime.dart';
import 'plugins/application/plugin_runtime_provider.dart';
import 'plugins/application/feature_controller_binding.dart';
import 'plugins/settings/plugin_settings_controller.dart';
import 'plugins/assembly/built_in_distribution.dart';
import 'plugins/core/plugin_core.dart';
import 'features/training_plan/application/four_week_plan_controller.dart';
import 'features/profile/application/training_schedule_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainflow_ai/app/startup/local_storage_recovery_page.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/core/config/api_config.dart';
import 'package:trainflow_ai/data/local/local_storage_bootstrap.dart';
import 'package:trainflow_ai/data/local/local_storage_bootstrap_coordinator.dart';
import 'package:trainflow_ai/data/local/rhythm_database_gateway.dart';
import 'package:trainflow_ai/features/growth/application/growth_evidence_controller.dart';
import 'package:trainflow_ai/features/growth/application/local_training_fact_sync.dart';
import 'package:trainflow_ai/features/growth/application/training_metrics_provider.dart';
import 'package:trainflow_ai/features/companion/application/companion_database_provider.dart';
import 'package:trainflow_ai/features/pet/application/daily_activity_sync_controller.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/features/cloud_sync/application/cloud_sync_controller.dart';
import 'package:trainflow_ai/features/rhythm/application/body_rhythm_controller.dart';
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
    this.title = '发布配置错误',
  });

  final String message;
  final String title;

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
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
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
    this.pluginFactory = builtInDistribution,
  });

  final LocalStorageBootstrapResult initialResult;
  final Future<LocalStorageBootstrapResult> Function() retryBootstrap;
  final List<TrainMatePlugin> Function() pluginFactory;

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
        pluginRuntimeProvider.overrideWith((ref) {
          final runtime =
              PluginRuntime(PluginRegistry(plugins: widget.pluginFactory()));
          registerPersistedSportLocks(
              runtime, () => ref.read(localStorageServiceProvider));
          return runtime;
        }),
        sportCapabilityDirectoryProvider.overrideWith(
            (ref) => ref.watch(pluginRuntimeProvider).sportDirectory),
        planPluginSourceResolverProvider.overrideWith(
            (ref) => ref.watch(pluginRuntimeProvider).resolvePlanSources),
        planPluginSourceDecoratorProvider.overrideWith(
            (ref) => ref.watch(pluginRuntimeProvider).decoratePlanSources),
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
          final TrainingMetricsPipeline pipeline = TrainingMetricsPipeline(
            database: structured,
            repository: ref.watch(trainingMetricsRepositoryProvider),
            healthDataGateway: ref.watch(healthDataGatewayProvider),
          );
          bindFeatureController(
            ref,
            'feature.growth',
            'metricsPipeline',
            pipeline,
          );
          return pipeline;
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
  bool _pluginsReady = false;
  String? _pluginError;
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_initializePlugins);
  }

  Future<void> _initializePlugins() async {
    try {
      final PluginRuntime runtime = ref.read(pluginRuntimeProvider);
      final PluginSettingsController settings =
          ref.read(pluginSettingsControllerProvider);
      final result = await runtime.initialize(
        enabledIds: settings.desiredEnabledIds(),
      );
      if (!mounted) return;
      if (result.hasRequiredFailures) {
        setState(() => _pluginError = '必需能力初始化失败，暂时无法进入训练。请重启应用重试；不要删除本地数据。');
        return;
      }
      if (ref.read(featureAccessProvider).isWritable('feature.training_plan')) {
        await ref
            .read(fourWeekPlanControllerProvider.notifier)
            .initializeDefaultPlan();
        await ref
            .read(trainingScheduleControllerProvider.notifier)
            .initializeSchedule();
      }
      setState(() => _pluginsReady = true);
      await _initializeHealthSync();
    } catch (_) {
      if (mounted) setState(() => _pluginError = '功能装配失败，请重启应用恢复。原有训练数据已保留。');
    }
  }

  Future<void> _initializeHealthSync() async {
    try {
      final featureAccess = ref.read(featureAccessProvider);
      if (featureAccess.isWritable('feature.activity_import')) {
        await ref.read(healthSyncControllerProvider.future);
        await ref
            .read(healthSyncControllerProvider.notifier)
            .initializeBackgroundDrain();
      }
      if (featureAccess.isWritable('feature.growth')) {
        await ref.read(localTrainingFactSyncProvider.future);
      }
      if (featureAccess.isWritable('feature.weekly_report')) {
        await ref
            .read(localReportGenerationCoordinatorProvider)
            .ensureRecentlyClosedPeriods(
              athleteProfileId: ref.read(healthSyncAthleteIdProvider),
            );
      }
    } catch (_) {
      // Provider 保留错误状态；启动壳不能因健康同步或报告补算失败阻断训练功能。
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pluginError != null) {
      return StartupConfigurationErrorApp(
          message: _pluginError!, title: '功能初始化失败');
    }
    if (!_pluginsReady) {
      return const MaterialApp(
          home: Scaffold(body: Center(child: Text('正在准备运动与功能…'))));
    }
    return const TrainFlowApp();
  }
}
