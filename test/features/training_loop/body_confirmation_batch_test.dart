import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

import 'package:trainflow_ai/features/auth/application/account_switch_coordinator.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/data_center/data_center_page.dart';
import 'package:trainflow_ai/features/daily_adjustment/application/daily_adjustment_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';

const _key = 'trainflow.body_metrics.v1';
const _text = '体重 70\n体脂率 18\n静息心率 60\nHRV 50\n睡眠 7\n疲劳 3\n酸痛 2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('提交期间阻止停用和换账号，销毁后迟到结果不更新新控制器', () async {
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    final storage = _Storage();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      pluginRuntimeProvider.overrideWith((ref) => runtime),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    controller.recognizeSnapshotText(_text);
    storage.gate = Completer<void>();
    final saving = controller.confirmPendingMetric();
    await Future<void>.delayed(Duration.zero);
    await expectLater(runtime.disable('feature.data_center'), throwsStateError);
    var replaced = false;
    await expectLater(runtime.changeAccountScope(replaceScope: () {
      replaced = true;
    }), throwsStateError);
    expect(replaced, isFalse);
    expect(() => controller.recognizeSnapshotText(_text), throwsStateError);
    await expectLater(
        Future.sync(() => controller.importCsv('date')), throwsStateError);
    await expectLater(controller.clear(), throwsStateError);
    storage.gate!.complete();
    await saving;
    await runtime.changeAccountScope(replaceScope: () async {
      storage.clearBusinessData();
      await storage.flush();
    });
    container.read(accountSwitchCoordinatorProvider).resetInMemoryState();
    expect(container.read(bodyMetricControllerProvider).metrics, isEmpty);
    expect(container.read(bodyMetricControllerProvider).pendingMetric, isNull);
    await runtime.disable('feature.data_center');
    await expectLater(controller.confirmPendingMetric(), throwsStateError);
    await runtime.enable('feature.data_center');
    controller.recognizeSnapshotText(_text);
    storage.gate = Completer<void>();
    final late = controller.confirmPendingMetric();
    await Future<void>.delayed(Duration.zero);
    container.invalidate(bodyMetricControllerProvider);
    final next = container.read(bodyMetricControllerProvider);
    storage.gate!.complete();
    await late;
    expect(container.read(bodyMetricControllerProvider), same(next));
    expect(next.pendingMetric, isNull);
  });

  test('未落盘的完整输入不能改变准备度、成就或有效计划', () async {
    final storage = _Storage();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final before = container.read(trainingMvpProvider);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    await container
        .read(dailyAdjustmentControllerProvider.notifier)
        .confirmTodayStatus();
    controller.recognizeSnapshotText(_text);
    storage.failFlushes = 1;
    await expectLater(controller.confirmPendingMetric(), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(trainingMvpProvider).bodyMetrics, isEmpty);
    expect(container.read(trainingMvpProvider).readinessScore, isNull);
    expect(
        container
            .read(trainingMvpProvider)
            .achievementRecordFor('body_data_first'),
        isNull);
    await controller.confirmPendingMetric();
    await Future<void>.delayed(Duration.zero);
    expect(
        container.read(trainingMvpProvider).bodyMetrics.single.sleepHours, 7);
    expect(container.read(trainingMvpProvider).activePlan.toJson(),
        before.activePlan.toJson());
    expect(container.read(trainingMvpProvider).logs, before.logs);
  });

  testWidgets('确认按钮等待时禁用，失败保留文字和预览并允许重试', (tester) async {
    tester.view.physicalSize = const Size(800, 7000);
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
    final input = find.widgetWithText(TextFormField, '截图文字');
    await tester.ensureVisible(input);
    await tester.tap(input);
    await tester.enterText(input, '体重');
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue,
        reason: '每次输入后必须保持输入连接，不能因文本变化重建控件');
    tester.testTextInput.enterText(_text);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '识别截图文字'));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, '确认写入截图识别数据');
    await tester.ensureVisible(button);
    storage.gate = Completer<void>();
    storage.failFlushes = 1;
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    storage.gate!.complete();
    await tester.pumpAndSettle();
    expect(container.read(bodyMetricSnapshotTextProvider), _text);
    expect(
        container.read(bodyMetricControllerProvider).pendingMetric, isNotNull);
    expect(find.textContaining('身体数据保存失败'), findsWidgets);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(container.read(bodyMetricControllerProvider).metrics, hasLength(1));
    expect(container.read(bodyMetricControllerProvider).pendingMetric, isNull);
    // 外部文本恢复仍需同步；演示样例现已改为独立只读查看。
    container.read(bodyMetricSnapshotTextProvider.notifier).setValue('恢复的未完成输入');
    await tester.pump();
    final field = tester.widget<TextFormField>(input);
    expect(
        field.controller!.text, container.read(bodyMetricSnapshotTextProvider));
  });

  test('完整身体记录确认等待磁盘，不提前发布指标或清除待确认内容', () async {
    final storage = _Storage();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    controller.recognizeSnapshotText(_text);
    final pending = container.read(bodyMetricControllerProvider).pendingMetric;
    storage.gate = Completer<void>();
    final saving = controller.confirmPendingMetric();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(bodyMetricControllerProvider).metrics, isEmpty);
    expect(container.read(bodyMetricControllerProvider).pendingMetric, pending);
    expect(container.read(bodyMetricRepositoryProvider).listMetrics(), isEmpty);
    await expectLater(
        Future.sync(controller.confirmPendingMetric), throwsStateError);
    storage.gate!.complete();
    await saving;
    expect(container.read(bodyMetricControllerProvider).pendingMetric, isNull);
    expect(container.read(bodyMetricControllerProvider).metrics.single.id,
        pending!.id);
    await controller.confirmPendingMetric();
    expect(container.read(bodyMetricControllerProvider).revisions, isEmpty);
  });

  for (final sync in [true, false]) {
    test('${sync ? '同步' : '异步'}保存失败保留待确认内容，原记录与修订不变且可重试', () async {
      final storage = _Storage();
      final container = ProviderContainer(overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);
      final controller = container.read(bodyMetricControllerProvider.notifier);
      controller.recognizeSnapshotText(_text);
      await controller.confirmPendingMetric();
      final before = storage.readJson(_key);
      final old =
          container.read(bodyMetricControllerProvider).metrics.single.toJson();
      controller.recognizeSnapshotText(_text.replaceFirst('70', '71'));
      final pending =
          container.read(bodyMetricControllerProvider).pendingMetric;
      storage.failSync = sync;
      storage.failFlushes = sync ? 0 : 1;
      await expectLater(controller.confirmPendingMetric(), throwsStateError);
      expect(storage.readJson(_key), before);
      expect(
          container.read(bodyMetricControllerProvider).metrics.single.toJson(),
          old);
      expect(
          container
              .read(bodyMetricRepositoryProvider)
              .listMetrics()
              .single
              .toJson(),
          old);
      expect(
          container.read(bodyMetricControllerProvider).pendingMetric, pending);
      expect(container.read(bodyMetricControllerProvider).snapshotStatusMessage,
          contains('失败'));
      await controller.confirmPendingMetric();
      expect(
          container.read(bodyMetricControllerProvider).metrics.single.weightKg,
          71);
      expect(
          container.read(bodyMetricControllerProvider).revisions, hasLength(1));
    });
  }

  test('首次确认失败不遗留文档，恢复失败明确阻止继续写入', () async {
    final storage = _Storage();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    controller.recognizeSnapshotText(_text);
    storage.failFlushes = 1;
    await expectLater(controller.confirmPendingMetric(), throwsStateError);
    expect(storage.readJson(_key), isNull);
    storage.failFlushes = 2;
    await expectLater(controller.confirmPendingMetric(), throwsStateError);
    expect(container.read(bodyMetricControllerProvider).snapshotStatusMessage,
        contains('恢复'));
    await expectLater(controller.confirmPendingMetric(), throwsStateError);
    expect(container.read(bodyMetricControllerProvider).metrics, isEmpty);
    expect(PersistedBodyMetricRepository(storage).listMetrics(), isEmpty);
  });
}

class _Storage extends InMemoryLocalStorageService {
  Completer<void>? gate;
  int failFlushes = 0;
  bool failSync = false;
  @override
  void saveJson(String key, Map<String, dynamic> value) {
    if (key == _key && failSync) {
      failSync = false;
      throw StateError('合成同步故障');
    }
    super.saveJson(key, value);
  }

  @override
  Future<void> flush() async {
    await gate?.future;
    if (failFlushes > 0) {
      failFlushes--;
      throw StateError('合成磁盘故障');
    }
  }
}
