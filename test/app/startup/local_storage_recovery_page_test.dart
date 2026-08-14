import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/startup/local_storage_recovery_page.dart';
import 'package:trainflow_ai/data/local/local_storage_bootstrap_coordinator.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('恢复页提供重试、只读信息与脱敏诊断复制', (WidgetTester tester) async {
    String? copiedDiagnostics;
    int retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalStorageRecoveryPage(
          result: _recoveryResult(),
          onRetry: () async {
            retryCount += 1;
          },
          copyDiagnostics: (String value) async {
            copiedDiagnostics = value;
          },
        ),
      ),
    );

    expect(find.text('本地数据保护模式'), findsOneWidget);
    expect(find.text('重试打开数据库'), findsOneWidget);
    expect(find.text('查看只读恢复信息'), findsOneWidget);
    expect(find.text('复制诊断信息'), findsOneWidget);

    await tester.tap(find.text('查看只读恢复信息'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不会读取陈旧设备副本'), findsOneWidget);
    expect(find.textContaining('不会自动清除或覆盖数据库'), findsOneWidget);

    await tester.tap(find.text('复制诊断信息'));
    await tester.pump();
    expect(copiedDiagnostics, contains('存储后端：readOnlyRecovery'));
    expect(copiedDiagnostics, contains('错误类型：StateError'));
    expect(copiedDiagnostics, isNot(contains('模拟敏感错误详情')));

    await tester.tap(find.text('重试打开数据库'));
    await tester.pumpAndSettle();
    expect(retryCount, 1);
  });
}

LocalStorageBootstrapResult _recoveryResult() {
  return LocalStorageBootstrapResult(
    storageService: const ReadOnlyRecoveryLocalStorageService(),
    growthEvidenceRepository: PersistedGrowthEvidenceRepository(
      InMemoryLocalStorageService(),
    ),
    trainingMetricsRepository: InMemoryTrainingMetricsRepository(),
    backend: LocalStorageBackend.readOnlyRecovery,
    fallbackReason: '数据库暂时无法打开。',
    fallbackError: StateError('模拟敏感错误详情'),
  );
}
