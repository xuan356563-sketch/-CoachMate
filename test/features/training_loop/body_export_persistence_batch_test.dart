import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as timezone;
import 'package:trainflow_ai/data/models/body_metric_export.dart';
import 'package:trainflow_ai/data/repositories/body_metric_export_repository.dart';
import 'package:trainflow_ai/features/auth/application/account_switch_coordinator.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_export_controller.dart';
import 'package:trainflow_ai/features/data_center/data_center_page.dart';
import 'package:trainflow_ai/features/reminders/application/reminder_settings_controller.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

const _key = PersistedBodyMetricExportRepository.storageKey;

// Widget 测试没有原生通知插件；仍确认账号切换实际执行资源清理。
class _Notifications implements TrainingNotificationGateway {
  int cancellations = 0;
  @override
  Future<void> cancelTrainingNotifications() async {
    cancellations++;
  }

  @override
  Future<timezone.Location> loadLocalLocation() async => timezone.UTC;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> schedule(TrainingNotificationRequest request) async {}
}

class _Storage extends InMemoryLocalStorageService {
  bool failSync = false;
  int failures = 0;
  Completer<void>? gate;

  @override
  void saveJson(String key, Map<String, dynamic> value) {
    if (key == _key && failSync) {
      failSync = false;
      throw StateError('合成同步写入失败');
    }
    super.saveJson(key, value);
  }

  @override
  Future<void> flush() async {
    final pending = gate;
    gate = null;
    if (pending != null) await pending.future;
    if (failures > 0) {
      failures--;
      throw StateError('合成落盘失败');
    }
    await super.flush();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('确认提交仍限制五十条，同 ID 重试替换且重开读取一致', () async {
    final storage = _Storage();
    final repository = PersistedBodyMetricExportRepository(storage);
    for (var index = 0; index < 55; index++) {
      await repository.saveConfirmedRecord(BodyMetricExportRecord(
          id: 'synthetic-$index',
          format: BodyMetricExportFormat.csv,
          metricCount: 1,
          byteCount: index,
          fileName: 'synthetic.csv',
          exportedAt: DateTime(2026, 9, 19, 0, index)));
    }
    final record = repository.listRecords().first;
    await repository.saveConfirmedRecord(record);
    final restored = PersistedBodyMetricExportRepository(storage).listRecords();
    expect(restored, hasLength(50));
    expect(restored.first.id, 'synthetic-54');
    expect(restored.last.id, 'synthetic-5');
    expect(restored.map((item) => item.toJson()),
        repository.listRecords().map((item) => item.toJson()));
  });
  testWidgets('页面保存中禁用导出，失败保留预览和旧登记，重试只增加一条', (tester) async {
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    await container
        .read(bodyMetricExportControllerProvider.notifier)
        .recordJsonExport('旧合成');
    final before = storage.readJson(_key);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DataCenterPage()))));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, '导出 CSV');
    await tester.scrollUntilVisible(button, 400,
        scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    storage.gate = gate;
    storage.failures = 1;
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '导出 JSON'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '清除导出记录'))
            .onPressed,
        isNull);
    final preview = container.read(bodyMetricExportTextProvider);
    expect(preview, contains('measured_at'));
    expect(container.read(bodyMetricExportControllerProvider).records,
        hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(storage.readJson(_key), before);
    expect(container.read(bodyMetricExportTextProvider), preview);
    expect(container.read(bodyMetricExportControllerProvider).statusMessage,
        contains('已恢复原记录'));
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(container.read(bodyMetricExportControllerProvider).records,
        hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('清除对话框取消不写入，账号变化后的旧确认不能清除新登记', (tester) async {
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    final storage = _Storage();
    final notifications = _Notifications();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      trainingNotificationSchedulerProvider
          .overrideWithValue(TrainingNotificationScheduler(notifications)),
    ]);
    addTearDown(container.dispose);
    await container
        .read(bodyMetricExportControllerProvider.notifier)
        .recordJsonExport('旧合成');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DataCenterPage()))));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, '清除导出记录');
    await tester.scrollUntilVisible(button, 400,
        scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.pumpAndSettle();
    final before = storage.readJson(_key);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(storage.readJson(_key), before);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await runtime.changeAccountScope(replaceScope: () async {
      storage.clearBusinessData();
      await storage.flush();
    });
    container.read(accountSwitchCoordinatorProvider).resetInMemoryState();
    expect(notifications.cancellations, greaterThan(0));
    await container
        .read(bodyMetricExportControllerProvider.notifier)
        .recordCsvExport('新合成');
    final newDocument = storage.readJson(_key);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认清除'));
    await tester.pumpAndSettle();
    expect(storage.readJson(_key), newDocument);
    expect(find.textContaining('账户已变化'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await runtime.shutdown();
  });
  for (final clearing in [false, true]) {
    for (final syncFailure in [false, true]) {
      test('${clearing ? '清除' : '登记'} ${syncFailure ? '同步' : '异步'}失败恢复，重试只提交一次',
          () async {
        final storage = _Storage();
        final container = ProviderContainer(overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
        ]);
        addTearDown(container.dispose);
        final controller =
            container.read(bodyMetricExportControllerProvider.notifier);
        await controller.recordJsonExport('旧合成预览');
        final before = storage.readJson(_key);
        final oldRecords =
            container.read(bodyMetricExportControllerProvider).records;
        storage.failSync = syncFailure;
        storage.failures = syncFailure ? 0 : 1;
        Future<void> action() => clearing
            ? controller.clear()
            : controller.recordCsvExport('合成 CSV');
        await expectLater(Future.sync(action), throwsStateError);
        expect(storage.readJson(_key), before);
        expect(container.read(bodyMetricExportRepositoryProvider).listRecords(),
            oldRecords);
        expect(container.read(bodyMetricExportControllerProvider).records,
            oldRecords);
        expect(container.read(bodyMetricExportControllerProvider).statusMessage,
            contains('已恢复原记录'));
        expect(
            PersistedBodyMetricExportRepository(storage)
                .listRecords()
                .single
                .id,
            oldRecords.single.id);
        await action();
        expect(PersistedBodyMetricExportRepository(storage).listRecords(),
            hasLength(clearing ? 0 : 2));
      });
    }
  }

  test('首次失败不留登记文档，恢复失败后禁止继续写入', () async {
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final controller =
        container.read(bodyMetricExportControllerProvider.notifier);
    storage.failures = 1;
    await expectLater(controller.recordCsvExport('合成'), throwsStateError);
    expect(storage.readJson(_key), isNull);
    storage.failures = 2;
    await expectLater(controller.recordCsvExport('合成'), throwsStateError);
    expect(container.read(bodyMetricExportControllerProvider).statusMessage,
        contains('磁盘状态无法确认'));
    await expectLater(controller.recordCsvExport('合成'), throwsStateError);
    expect(container.read(bodyMetricExportControllerProvider).statusMessage,
        contains('恢复尚未确认'));
  });

  test('提交等待不发布事实，重复提交与清除不能交错', () async {
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final controller =
        container.read(bodyMetricExportControllerProvider.notifier);
    final gate = Completer<void>();
    storage.gate = gate;
    final saving = controller.recordCsvExport('合成');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(bodyMetricExportRepositoryProvider).listRecords(),
        isEmpty);
    expect(container.read(bodyMetricExportControllerProvider).records, isEmpty);
    await expectLater(
        Future.sync(() => controller.recordJsonExport('重复')), throwsStateError);
    await expectLater(controller.clear(), throwsStateError);
    gate.complete();
    await saving;
    expect(container.read(bodyMetricExportControllerProvider).records,
        hasLength(1));
  });

  test('提交期间阻止账号替换，重建后迟到回调不覆盖新控制器；换账号清空预览', () async {
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    final storage = _Storage();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      pluginRuntimeProvider.overrideWith((ref) => runtime),
    ]);
    addTearDown(container.dispose);
    final controller =
        container.read(bodyMetricExportControllerProvider.notifier);
    final gate = Completer<void>();
    storage.gate = gate;
    final saving = controller.recordCsvExport('旧账号合成');
    await Future<void>.delayed(Duration.zero);
    var replaced = false;
    await expectLater(runtime.changeAccountScope(replaceScope: () {
      replaced = true;
    }), throwsStateError);
    expect(replaced, isFalse);
    container.invalidate(bodyMetricExportControllerProvider);
    final next = container.read(bodyMetricExportControllerProvider);
    gate.complete();
    await saving;
    expect(container.read(bodyMetricExportControllerProvider), same(next));
    container.read(bodyMetricExportTextProvider.notifier).setValue('旧账号预览');
    container
        .read(bodyMetricExportPackageStatusProvider.notifier)
        .setValue('旧账号摘要');
    await runtime.changeAccountScope(replaceScope: () async {
      storage.clearBusinessData();
      await storage.flush();
    });
    container.read(accountSwitchCoordinatorProvider).resetInMemoryState();
    expect(container.read(bodyMetricExportControllerProvider).records, isEmpty);
    expect(container.read(bodyMetricExportTextProvider), isEmpty);
    expect(container.read(bodyMetricExportPackageStatusProvider), '导出包尚未生成。');
    await container
        .read(bodyMetricExportControllerProvider.notifier)
        .recordCsvExport('新账号');
    expect(PersistedBodyMetricExportRepository(storage).listRecords(),
        hasLength(1));
    await runtime.shutdown();
  });
}
