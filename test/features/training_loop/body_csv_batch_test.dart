import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/features/auth/application/account_switch_coordinator.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/data_center/data_center_page.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

const _key = 'trainflow.body_metrics.v1';
const _header = 'date,weight,body_fat,resting_hr,hrv,sleep,fatigue,soreness';
const _initial = '$_header\n2026-09-16,70,18,60,50,7,3,2';
const _batch =
    '$_header\n2026-09-16,71,18,60,50,7,3,2\n2026-09-17,72,18,60,50,7,3,2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final syncFailure in [true, false]) {
    test('${syncFailure ? '同步' : '异步'}多行导入失败恢复全部原记录，重试不留下额外修订', () async {
      final storage = _Storage();
      final container = ProviderContainer(overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);
      final controller = container.read(bodyMetricControllerProvider.notifier);
      await controller.importCsv(_initial);
      controller
          .recognizeSnapshotText('体重 73 体脂率 18 静息心率 60 HRV 50 睡眠 7 疲劳 3 酸痛 2');
      final before = container.read(bodyMetricControllerProvider);
      final document = storage.readJson(_key);
      storage.failSync = syncFailure;
      storage.failFlushes = syncFailure ? 0 : 1;
      await expectLater(controller.importCsv(_batch), throwsStateError);
      final failed = container.read(bodyMetricControllerProvider);
      expect(storage.readJson(_key), document);
      expect(
          container
              .read(bodyMetricRepositoryProvider)
              .listMetrics()
              .single
              .weightKg,
          70);
      expect(failed.metrics, before.metrics);
      expect(failed.revisions, before.revisions);
      expect(failed.pendingMetric, same(before.pendingMetric));
      expect(failed.persistenceVersion, before.persistenceVersion);
      expect(failed.importResults, before.importResults);
      expect(failed.importStatusMessage, contains('已恢复原记录'));
      await controller.importCsv(_batch);
      final saved = container.read(bodyMetricControllerProvider);
      expect(saved.metrics.map((e) => e.weightKg), [72, 71]);
      expect(saved.revisions, hasLength(1));
      expect(saved.persistenceVersion, before.persistenceVersion + 1);
      expect(saved.importResults, hasLength(2));
      final reopened = PersistedBodyMetricRepository(storage);
      expect(reopened.listMetrics().map((e) => e.weightKg), [72, 71]);
      expect(reopened.listRevisions(), hasLength(1));
    });
  }

  test('首次整批失败不留文档；恢复失败锁住仓储并给出中文原因', () async {
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    storage.failFlushes = 1;
    await expectLater(controller.importCsv(_batch), throwsStateError);
    expect(storage.readJson(_key), isNull);
    expect(container.read(bodyMetricControllerProvider).metrics, isEmpty);
    storage.failFlushes = 2;
    await expectLater(controller.importCsv(_batch), throwsStateError);
    expect(container.read(bodyMetricControllerProvider).importStatusMessage,
        contains('磁盘状态无法确认'));
    await expectLater(controller.importCsv(_batch), throwsStateError);
    expect(container.read(bodyMetricControllerProvider).importStatusMessage,
        contains('恢复尚未确认'));
  });

  test('导入等待期间原事实不发布，失败不影响计划、日志或成长', () async {
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final before = container.read(trainingMvpProvider);
    await Future<void>.delayed(Duration.zero);
    storage.gate = Completer<void>();
    storage.failFlushes = 1;
    final saving =
        container.read(bodyMetricControllerProvider.notifier).importCsv(_batch);
    final failure = expectLater(saving, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(bodyMetricRepositoryProvider).listMetrics(), isEmpty);
    expect(container.read(trainingMvpProvider).bodyMetrics, isEmpty);
    storage.gate!.complete();
    await failure;
    final after = container.read(trainingMvpProvider);
    expect(after.bodyMetrics, isEmpty);
    expect(after.readinessScore, before.readinessScore);
    expect(after.achievementRecordFor('body_data_first'), isNull);
    expect(after.activePlan.toJson(), before.activePlan.toJson());
    expect(after.logs, before.logs);
  });

  test('提交期间阻止交错写入、停用和换账号，重建后迟到结果不发布', () async {
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
    storage.gate = Completer<void>();
    final saving = controller.importCsv(_batch);
    await Future<void>.delayed(Duration.zero);
    await expectLater(
        Future.sync(() => controller.importCsv(_batch)), throwsStateError);
    expect(() => controller.recognizeSnapshotText('体重 70'), throwsStateError);
    await expectLater(controller.confirmPendingMetric(), throwsStateError);
    await expectLater(controller.clear(), throwsStateError);
    await expectLater(
        Future.sync(() => controller.confirmDailyCheckInSameAsYesterday()),
        throwsStateError);
    await expectLater(
        Future.sync(() => controller.saveManualMetric(
            weightKg: 70,
            restingHeartRate: 60,
            hrvMs: 50,
            sleepHours: 7,
            fatigueLevel: 3)),
        throwsStateError);
    await expectLater(runtime.disable('feature.data_center'), throwsStateError);
    var replaced = false;
    await expectLater(runtime.changeAccountScope(replaceScope: () {
      replaced = true;
    }), throwsStateError);
    expect(replaced, isFalse);
    container.invalidate(bodyMetricControllerProvider);
    final next = container.read(bodyMetricControllerProvider);
    storage.gate!.complete();
    await saving;
    expect(container.read(bodyMetricControllerProvider), same(next));
    await runtime.changeAccountScope(replaceScope: () async {
      storage.clearBusinessData();
      await storage.flush();
    });
    container.read(accountSwitchCoordinatorProvider).resetInMemoryState();
    expect(container.read(bodyMetricControllerProvider).metrics, isEmpty);
    await runtime.disable('feature.data_center');
    await expectLater(
        Future.sync(() => controller.importCsv(_batch)), throwsStateError);
    await runtime.enable('feature.data_center');
    await container
        .read(bodyMetricControllerProvider.notifier)
        .importCsv(_batch);
    expect(container.read(bodyMetricControllerProvider).metrics, hasLength(2));
  });

  testWidgets('导入按钮等待时禁用，失败后保留 CSV 并允许重试', (tester) async {
    tester.view.physicalSize = const Size(800, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DataCenterPage()))));
    await tester.pumpAndSettle();
    final input = find.widgetWithText(TextFormField, '身体数据 CSV');
    await tester.enterText(input, _batch);
    final button = find.widgetWithText(FilledButton, '导入身体数据 CSV');
    await tester.scrollUntilVisible(button, 500,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    storage.gate = Completer<void>();
    storage.failFlushes = 1;
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    storage.gate!.complete();
    await tester.pumpAndSettle();
    expect(container.read(bodyMetricCsvImportTextProvider), _batch);
    expect(container.read(bodyMetricControllerProvider).importStatusMessage,
        contains('已恢复原记录'));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(container.read(bodyMetricControllerProvider).metrics, hasLength(2));
    expect(container.read(bodyMetricControllerProvider).revisions, isEmpty);
    expect(tester.takeException(), isNull);
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
