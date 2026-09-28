import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/local_storage_bootstrap_coordinator.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/main.dart';
import 'package:trainflow_ai/plugins/settings/plugin_settings.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('必需插件初始化失败时生产启动壳不挂载可写业务', (tester) async {
    final storage = InMemoryLocalStorageService();
    await tester.pumpWidget(TrainFlowBootstrapApp(
      initialResult: LocalStorageBootstrapResult(
        storageService: storage,
        growthEvidenceRepository: PersistedGrowthEvidenceRepository(storage),
        trainingMetricsRepository: InMemoryTrainingMetricsRepository(),
        backend: LocalStorageBackend.sharedPreferences,
      ),
      pluginFactory: () =>
          builtInDistribution(replacements: {'core.storage': _FailedCore()}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('功能初始化失败'), findsOneWidget);
    expect(find.textContaining('不要删除本地数据'), findsOneWidget);
    expect(find.text('开始跟练'), findsNothing);
  });
  testWidgets('发布配置错误会阻断业务界面并显示中文原因', (WidgetTester tester) async {
    await tester.pumpWidget(
      const StartupConfigurationErrorApp(
        message: '生产环境必须显式配置 API 地址',
      ),
    );

    expect(find.text('发布配置错误'), findsOneWidget);
    expect(find.text('生产环境必须显式配置 API 地址'), findsOneWidget);
  });

  testWidgets('生产启动先读账号域设置，不启动已关闭的后台功能', (WidgetTester tester) async {
    final storage = InMemoryLocalStorageService()
      ..saveJson(pluginSettingsStorageKey, <String, dynamic>{
        'version': 1,
        'enabledOverrides': <String, bool>{'feature.motion_check': false},
      });
    final _TrackingPlugin tracking = _TrackingPlugin(
      builtInDistribution()
          .singleWhere(
            (TrainMatePlugin plugin) =>
                plugin.descriptor.id == 'feature.motion_check',
          )
          .descriptor,
    );

    await tester.pumpWidget(TrainFlowBootstrapApp(
      initialResult: LocalStorageBootstrapResult(
        storageService: storage,
        growthEvidenceRepository: PersistedGrowthEvidenceRepository(storage),
        trainingMetricsRepository: InMemoryTrainingMetricsRepository(),
        backend: LocalStorageBackend.sharedPreferences,
      ),
      pluginFactory: () => builtInDistribution(
        replacements: <String, TrainMatePlugin>{
          'feature.motion_check': tracking,
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(tracking.initializeCount, 0);
    expect(find.text('功能初始化失败'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('只读恢复状态重试后会刷新保护原因', (WidgetTester tester) async {
    await tester.pumpWidget(
      TrainFlowBootstrapApp(
        initialResult: _recoveryResult('第一次打开失败'),
        retryBootstrap: () async => _recoveryResult('重试后仍无法安全打开'),
      ),
    );

    expect(find.text('第一次打开失败'), findsOneWidget);

    await tester.tap(find.text('重试打开数据库'));
    await tester.pumpAndSettle();

    expect(find.text('第一次打开失败'), findsNothing);
    expect(find.text('重试后仍无法安全打开'), findsOneWidget);
  });
}

LocalStorageBootstrapResult _recoveryResult(String reason) {
  return LocalStorageBootstrapResult(
    storageService: const ReadOnlyRecoveryLocalStorageService(),
    growthEvidenceRepository: PersistedGrowthEvidenceRepository(
      InMemoryLocalStorageService(),
    ),
    trainingMetricsRepository: InMemoryTrainingMetricsRepository(),
    backend: LocalStorageBackend.readOnlyRecovery,
    fallbackReason: reason,
    fallbackError: StateError('测试错误'),
  );
}

class _FailedCore extends TrainMatePlugin {
  @override
  final descriptor = PluginDescriptor(
      id: 'core.storage',
      type: PluginType.core,
      version: '1.0.0',
      name: '测试存储',
      description: '测试必需故障',
      isRequired: true);
  @override
  Future<void> initialize(PluginContext context) async =>
      throw StateError('测试存储故障');
}

class _TrackingPlugin extends TrainMatePlugin {
  _TrackingPlugin(this.descriptor);

  @override
  final PluginDescriptor descriptor;

  int initializeCount = 0;

  @override
  Future<void> initialize(PluginContext context) async {
    initializeCount++;
  }
}
