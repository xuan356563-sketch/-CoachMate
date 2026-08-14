import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/local_storage_bootstrap_coordinator.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/main.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('发布配置错误会阻断业务界面并显示中文原因', (WidgetTester tester) async {
    await tester.pumpWidget(
      const StartupConfigurationErrorApp(
        message: '生产环境必须显式配置 API 地址',
      ),
    );

    expect(find.text('发布配置错误'), findsOneWidget);
    expect(find.text('生产环境必须显式配置 API 地址'), findsOneWidget);
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
