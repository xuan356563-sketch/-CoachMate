import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/data_center/data_center_page.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('样例只读查看，不预填、不覆盖输入、不产生指标或训练变化', (tester) async {
    tester.view.physicalSize = const Size(800, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = _Storage();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DataCenterPage()))));
    await tester.pumpAndSettle();
    expect(container.read(bodyMetricSnapshotTextProvider), isEmpty);
    expect(container.read(bodyMetricCsvImportTextProvider), isEmpty);
    final before = container.read(trainingMvpProvider);
    final pending = container.read(bodyMetricControllerProvider).pendingMetric;
    container
        .read(bodyMetricSnapshotTextProvider.notifier)
        .setValue('尚未完成的本人记录');
    container
        .read(bodyMetricCsvImportTextProvider.notifier)
        .setValue('date,weight_kg');
    await tester.pump();
    final input = find.widgetWithText(TextFormField, '身体数据 CSV');
    await tester.ensureVisible(input);
    await tester.tap(input);
    await tester.enterText(input, 'date,weight');
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);
    tester.testTextInput.enterText('date,weight_kg');
    await tester.pump();
    storage.writes = 0;
    for (final title in ['查看截图文字样例', '查看 CSV 格式样例']) {
      final button = find.widgetWithText(OutlinedButton, title);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining('仅供查看格式'), findsOneWidget);
      expect(find.text('确认写入截图识别数据'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, '关闭'));
      await tester.pumpAndSettle();
    }
    expect(container.read(bodyMetricSnapshotTextProvider), '尚未完成的本人记录');
    expect(container.read(bodyMetricCsvImportTextProvider), 'date,weight_kg');
    expect(container.read(bodyMetricControllerProvider).pendingMetric, pending);
    expect(container.read(bodyMetricControllerProvider).metrics, isEmpty);
    final after = container.read(trainingMvpProvider);
    expect(after.activePlan.toJson(), before.activePlan.toJson());
    expect(after.logs, before.logs);
    expect(after.readinessScore, before.readinessScore);
    expect(after.achievementRecords, before.achievementRecords);
    expect(storage.writes, 0);
  });
}

class _Storage extends InMemoryLocalStorageService {
  int writes = 0;
  @override
  void saveJson(String key, Map<String, dynamic> value) {
    writes++;
    super.saveJson(key, value);
  }
}
