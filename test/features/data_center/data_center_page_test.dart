import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/data_center/data_center_page.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('数据中心保存入口写入独立控制器并同步训练投影', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
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

    final Finder saveButton =
        find.widgetWithText(FilledButton, '保存身体数据');
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
}
