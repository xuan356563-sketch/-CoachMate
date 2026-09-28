import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as timezone;
import 'package:trainflow_ai/data/models/daily_check_in_record.dart';
import 'package:trainflow_ai/data/repositories/daily_check_in_repository.dart';
import 'package:trainflow_ai/features/auth/application/account_switch_coordinator.dart';
import 'package:trainflow_ai/features/daily_check_in/daily_check_in_page.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';
import 'package:trainflow_ai/features/reminders/application/reminder_settings_controller.dart';

const _key = PersistedDailyCheckInRepository.storageKey;

void _seed(_Storage storage, int days) {
  final repository = PersistedDailyCheckInRepository(storage);
  final today = DateTime.now();
  for (var i = days; i > 0; i--) {
    final date = DateTime(today.year, today.month, today.day - i);
    repository.record(
        localDate: date,
        confirmedAt: date,
        source: DailyCheckInSource.prefilled);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final sync in [true, false]) {
    for (final kind in [
      DailyContinuityKind.standard,
      DailyContinuityKind.plannedRest,
      DailyContinuityKind.safetyPause
    ]) {
      test('${kind.name} ${sync ? '同步' : '异步'}失败恢复原签到和里程碑，重试只计一次', () async {
        final storage = _Storage();
        _seed(storage, 6);
        final container = ProviderContainer(overrides: [
          localStorageServiceProvider.overrideWithValue(storage)
        ]);
        addTearDown(container.dispose);
        final controller =
            container.read(bodyMetricControllerProvider.notifier);
        final before = storage.readJson(_key);
        Future<void> save() => kind == DailyContinuityKind.standard
            ? controller.recordTiredDailyCheckIn()
            : controller.recordContinuityDay(kind);
        storage.failSync = sync;
        storage.failFlushes = sync ? 0 : 1;
        await expectLater(save(), throwsStateError);
        expect(storage.readJson(_key), before);
        expect(
            container
                .read(dailyCheckInRepositoryProvider)
                .getSnapshot()
                .records,
            hasLength(6));
        final failed = container.read(bodyMetricControllerProvider);
        expect(failed.checkInStreak.totalCheckInDays, 6);
        expect(failed.checkInCelebrations, isEmpty);
        expect(failed.dailyCheckInStatusMessage, contains('已恢复原记录'));
        await save();
        expect(
            container
                .read(bodyMetricControllerProvider)
                .checkInStreak
                .totalCheckInDays,
            7);
        expect(
            container
                .read(bodyMetricControllerProvider)
                .checkInCelebrations
                .single
                .id,
            'growth_days_7');
        final saved = storage.readJson(_key);
        await save();
        expect(storage.readJson(_key), saved);
        expect(PersistedDailyCheckInRepository(storage).getSnapshot().records,
            hasLength(7));
        expect(container.read(bodyMetricControllerProvider).metrics, isEmpty);
      });
    }
  }

  test('首次签到失败不留文档，恢复失败后禁止继续写入', () async {
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    storage.failFlushes = 1;
    await expectLater(controller.recordTiredDailyCheckIn(), throwsStateError);
    expect(storage.readJson(_key), isNull);
    storage.failFlushes = 2;
    await expectLater(controller.recordTiredDailyCheckIn(), throwsStateError);
    expect(
        container.read(bodyMetricControllerProvider).dailyCheckInStatusMessage,
        contains('磁盘状态无法确认'));
    await expectLater(controller.recordTiredDailyCheckIn(), throwsStateError);
    expect(
        container
            .read(bodyMetricControllerProvider)
            .checkInStreak
            .totalCheckInDays,
        0);
  });

  test('收取里程碑等待落盘，失败保留未读回执并能重试', () async {
    final storage = _Storage();
    _seed(storage, 7);
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    final before = storage.readJson(_key);
    storage.failFlushes = 1;
    await expectLater(controller.markCheckInCelebrationSeen('growth_days_7'),
        throwsStateError);
    expect(storage.readJson(_key), before);
    expect(
        container
            .read(dailyCheckInRepositoryProvider)
            .getSnapshot()
            .unseenCelebrations,
        hasLength(1));
    expect(container.read(bodyMetricControllerProvider).checkInCelebrations,
        hasLength(1));
    await controller.markCheckInCelebrationSeen('growth_days_7');
    expect(container.read(bodyMetricControllerProvider).checkInCelebrations,
        isEmpty);
    expect(
        PersistedDailyCheckInRepository(storage)
            .getSnapshot()
            .unseenCelebrations,
        isEmpty);
    final saved = storage.readJson(_key);
    await controller.markCheckInCelebrationSeen('growth_days_7');
    expect(storage.readJson(_key), saved);
  });

  test('保存期间不发布签到事实，不影响身体数据、计划或日志', () async {
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final before = container.read(trainingMvpProvider);
    await Future<void>.delayed(Duration.zero);
    storage.gate = Completer<void>();
    final saving = container
        .read(bodyMetricControllerProvider.notifier)
        .recordContinuityDay(DailyContinuityKind.plannedRest);
    try {
      await Future<void>.delayed(Duration.zero);
      expect(
          container
              .read(bodyMetricControllerProvider)
              .checkInStreak
              .totalCheckInDays,
          0);
      expect(
          container.read(dailyCheckInRepositoryProvider).getSnapshot().records,
          isEmpty);
    } finally {
      storage.gate!.complete();
      await saving;
    }
    final after = container.read(trainingMvpProvider);
    expect(after.activePlan.toJson(), before.activePlan.toJson());
    expect(after.logs, before.logs);
    expect(after.bodyMetrics, before.bodyMetrics);
    expect(after.readinessScore, before.readinessScore);
  });

  test('签到保存阻止交错操作、停用与换账号，重建后迟到结果不发布', () async {
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
    final saving = controller.recordTiredDailyCheckIn();
    try {
      await Future<void>.delayed(Duration.zero);
      await expectLater(
          controller
              .recordTiredDailyCheckIn()
              .timeout(const Duration(milliseconds: 100)),
          throwsStateError);
      await expectLater(controller.markCheckInCelebrationSeen('growth_days_7'),
          throwsStateError);
      await expectLater(controller.importCsv('date'), throwsStateError);
      await expectLater(controller.confirmPendingMetric(), throwsStateError);
      await expectLater(controller.clear(), throwsStateError);
      await expectLater(
          runtime.disable('feature.daily_check_in'), throwsStateError);
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
    } finally {
      if (!storage.gate!.isCompleted) storage.gate!.complete();
      await saving;
    }
    await runtime.changeAccountScope(replaceScope: () async {
      storage.clearBusinessData();
      await storage.flush();
    });
    container.read(accountSwitchCoordinatorProvider).resetInMemoryState();
    expect(
        container
            .read(bodyMetricControllerProvider)
            .checkInStreak
            .totalCheckInDays,
        0);
    await runtime.disable('feature.daily_check_in');
    await expectLater(controller.recordTiredDailyCheckIn(), throwsStateError);
    await runtime.enable('feature.daily_check_in');
    await container
        .read(bodyMetricControllerProvider.notifier)
        .recordTiredDailyCheckIn();
    expect(
        container
            .read(bodyMetricControllerProvider)
            .checkInStreak
            .totalCheckInDays,
        1);
  });

  testWidgets('偏累按钮保存时禁用，失败不进入后续调整说明且允许重试', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DailyCheckInPage()))));
    await tester.pumpAndSettle();
    final before =
        container.read(trainingMvpProvider).dailyAdjustmentStatusMessage;
    final button = find.widgetWithText(OutlinedButton, '今天偏累，建议轻松版');
    await tester.scrollUntilVisible(button, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    storage.gate = Completer<void>();
    storage.failFlushes = 1;
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    storage.gate!.complete();
    await tester.pumpAndSettle();
    expect(
        container
            .read(bodyMetricControllerProvider)
            .checkInStreak
            .totalCheckInDays,
        0);
    expect(container.read(trainingMvpProvider).dailyAdjustmentStatusMessage,
        before);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
        container
            .read(bodyMetricControllerProvider)
            .checkInStreak
            .totalCheckInDays,
        1);
    expect(container.read(trainingMvpProvider).dailyAdjustmentStatusMessage,
        contains('未生成身体指标'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('签到已保存但调整说明失败时明确区分结果，重试不重复计数', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DailyCheckInPage()))));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, '今天偏累，建议轻松版');
    await tester.scrollUntilVisible(button, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    storage.failContext = true;
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
        container
            .read(bodyMetricControllerProvider)
            .checkInStreak
            .totalCheckInDays,
        1);
    expect(find.textContaining('签到已保存，偏累说明未更新'), findsOneWidget);
    final saved = storage.readJson(_key);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(storage.readJson(_key), saved);
    expect(container.read(trainingMvpProvider).dailyAdjustmentStatusMessage,
        contains('未生成身体指标'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('恢复确认可取消，弹窗期间换账号后旧确认不写新账号', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DailyCheckInPage()))));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, '按计划恢复');
    await tester.scrollUntilVisible(button, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(storage.readJson(_key), isNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await runtime.changeAccountScope(replaceScope: () async {
      storage.clearBusinessData();
      await storage.flush();
    });
    container.read(accountSwitchCoordinatorProvider).resetInMemoryState();
    expect(notifications.cancellations, greaterThan(0));
    await tester.pump();
    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();
    expect(storage.readJson(_key), isNull);
    expect(
        container
            .read(bodyMetricControllerProvider)
            .checkInStreak
            .totalCheckInDays,
        0);
    expect(find.textContaining('本次操作结果已失效'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// 组件测试没有原生通知平台，保留账号切换时真实清理调用的断言。
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
  Completer<void>? gate;
  int failFlushes = 0;
  bool failSync = false;
  bool failContext = false;
  @override
  void saveJson(String key, Map<String, dynamic> value) {
    if (key == 'trainflow.daily_context.v1' && failContext) {
      failContext = false;
      throw StateError('合成调整说明写入失败');
    }
    if (key == _key && failSync) {
      failSync = false;
      throw StateError('合成签到同步写入失败');
    }
    super.saveJson(key, value);
  }

  @override
  Future<void> flush() async {
    await gate?.future;
    if (failFlushes > 0) {
      failFlushes--;
      throw StateError('合成签到磁盘写入失败');
    }
  }
}
