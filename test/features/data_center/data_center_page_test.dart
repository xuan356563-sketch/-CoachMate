import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/data/seed/seed_body_metrics.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/data_center/data_center_page.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('没有身体基线时不显示带示例默认值的快捷保存入口', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DataCenterPage()),
      ),
    );
    await tester.pump();

    expect(find.text('10 秒快录'), findsOneWidget);
    expect(find.textContaining('不会显示或预填示例值'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存身体数据'), findsNothing);
  });

  testWidgets('数据中心保存入口写入独立控制器并同步训练投影', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    PersistedBodyMetricRepository(storage).saveMetric(
      seedBodyMetrics.first,
      reason: '测试页面基线',
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DataCenterPage()),
      ),
    );
    await tester.pump();

    final Finder saveButton = find.widgetWithText(FilledButton, '保存身体数据');
    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await tester.pump();
    await tester.pump();

    final BodyMetricState bodyState =
        container.read(bodyMetricControllerProvider);
    final TrainingMvpState trainingState = container.read(trainingMvpProvider);
    expect(bodyState.persistenceVersion, 1);
    expect(bodyState.latestMetric?.note, '数据中心 10 秒快录');
    expect(trainingState.latestBodyMetric?.note, '数据中心 10 秒快录');
    expect(trainingState.bodyMetrics.length, bodyState.metrics.length);
  });

  testWidgets('清除身体数据必须确认，取消时保留记录', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    PersistedBodyMetricRepository(storage).saveMetric(
      seedBodyMetrics.first,
      reason: '删除确认测试',
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DataCenterPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('清除身体数据'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除身体数据'));
    await tester.pumpAndSettle();

    expect(find.text('清除全部身体数据？'), findsOneWidget);
    expect(find.textContaining('不会删除 Apple 健康中的原始数据'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(container.read(bodyMetricControllerProvider).metrics, isNotEmpty);

    await tester.scrollUntilVisible(find.text('清除身体数据'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除身体数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认清除'));
    await tester.pumpAndSettle();

    expect(container.read(bodyMetricControllerProvider).metrics, isEmpty);
    expect(find.textContaining('当前记录 0 条'), findsOneWidget);
    expect(find.textContaining('导出包需重新生成'), findsOneWidget);
  });
}
