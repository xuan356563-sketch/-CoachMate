import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/features/data_center/data_center_page.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

Map<String, dynamic> _record() => {
      'id': 'synthetic-boundary',
      'measuredAt': DateTime.now().toIso8601String(),
      'source': 'manual',
      'weightKg': 70.0,
      'restingHeartRate': 60,
      'hrvMs': 50,
      'sleepHours': 7.0,
      'fatigueLevel': 3,
    };

Future<(ProviderContainer, InMemoryLocalStorageService)> _page(
    WidgetTester tester, Map<String, dynamic> json,
    {double scale = 1}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = InMemoryLocalStorageService();
  PersistedBodyMetricRepository(storage).saveMetric(BodyMetric.fromJson(json));
  final container = ProviderContainer(
      overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: const Scaffold(body: DataCenterPage()))));
  await tester.pumpAndSettle();
  return (container, storage);
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final field in [
    'weightKg',
    'restingHeartRate',
    'hrvMs',
    'sleepHours',
    'fatigueLevel'
  ]) {
    testWidgets('旧记录缺少 $field 时不能把兼容默认值作为快录预填', (tester) async {
      final json = _record()..remove(field);
      final (container, storage) = await _page(tester, json);
      final before = storage.readJson('trainflow.body_metrics.v1');
      final plan = container.read(trainingMvpProvider).activePlan.toJson();
      await tester.scrollUntilVisible(find.text('10 秒快录'), 400,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('无法安全预填'), findsOneWidget);
      expect(find.text('保存身体数据'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(storage.readJson('trainflow.body_metrics.v1'), before);
      expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
      expect(container.read(trainingMvpProvider).activePlan.toJson(), plan);
    });
  }

  for (final change in <Map<String, dynamic>>[
    {
      'recordedFields': ['weightKg']
    },
    {'source': 'unknown'},
    {'sleepHours': 0},
    {'fatigueLevel': -1},
  ]) {
    testWidgets('无效或继承字段不开放快录：$change', (tester) async {
      await _page(tester, {..._record(), ...change}, scale: 1.5);
      await tester.scrollUntilVisible(find.text('10 秒快录'), 400,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('无法安全预填'), findsOneWidget);
      expect(find.text('保存身体数据'), findsNothing);
    });
  }

  for (final values in [
    [58.0, 42, 20, 3.5, 0],
    [95.0, 90, 100, 10.0, 10],
  ]) {
    testWidgets('超出原控件范围的实际记录保留数值：$values', (tester) async {
      final (container, storage) = await _page(tester, {
        ..._record(),
        'weightKg': values[0],
        'restingHeartRate': values[1].toInt(),
        'hrvMs': values[2].toInt(),
        'sleepHours': values[3],
        'fatigueLevel': values[4].toInt(),
      });
      final before = storage.readJson('trainflow.body_metrics.v1');
      expect(tester.takeException(), isNull);
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders.map((s) => s.value), values);
      for (final slider in sliders) {
        expect(slider.value, inInclusiveRange(slider.min, slider.max));
      }
      expect(container.read(bodyMetricWeightProvider), values[0]);
      expect(storage.readJson('trainflow.body_metrics.v1'), before);
      expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
      final plan = container.read(trainingMvpProvider).activePlan.toJson();
      await tester.scrollUntilVisible(find.text('保存身体数据'), 400,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存身体数据'));
      await tester.pumpAndSettle();
      expect(
          container.read(bodyMetricControllerProvider).pendingMetric, isNull);
      final saved = PersistedBodyMetricRepository(storage).listMetrics().first;
      expect(saved.id, isNot('synthetic-boundary'));
      expect(storage.readJson('trainflow.body_metrics.v1'), isNot(before));
      expect(storage.readJson('trainflow.daily_check_ins.v1'), isNotNull);
      expect([
        saved.weightKg,
        saved.restingHeartRate,
        saved.hrvMs,
        saved.sleepHours,
        saved.fatigueLevel
      ], values);
      expect(container.read(trainingMvpProvider).activePlan.toJson(), plan);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('补全字段后恢复快录，缺失期间不保存控件默认值', (tester) async {
    final (container, storage) =
        await _page(tester, _record()..remove('sleepHours'));
    expect(find.text('保存身体数据'), findsNothing);
    final before = storage.readJson('trainflow.body_metrics.v1');
    final controller = container.read(bodyMetricControllerProvider.notifier);
    controller
        .recognizeSnapshotText('体重 70 体脂率 18 静息心率 60 HRV 50 睡眠 6 疲劳 3 酸痛 2');
    await tester.pumpAndSettle();
    expect(storage.readJson('trainflow.body_metrics.v1'), before);
    await controller.confirmPendingMetric();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widgetList<Slider>(find.byType(Slider)).map((s) => s.value),
        [70, 60, 50, 6, 3]);
    expect(find.text('保存身体数据'), findsOneWidget);
    expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
  });
}
