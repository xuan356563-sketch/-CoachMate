import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_10y.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'package:trainflow_ai/data/repositories/reminder_settings_repository.dart';
import 'package:trainflow_ai/features/reminders/application/reminder_settings_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/features/profile/application/training_schedule_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  ProviderContainer createContainer(InMemoryLocalStorageService storage) {
    return ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        trainingNotificationSchedulerProvider.overrideWithValue(
          TrainingNotificationScheduler(_CountingTrainingGateway()),
        ),
      ],
    );
  }

  test('初始状态读取默认提醒设置和状态文案', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    final ReminderSettingsState state =
        container.read(reminderSettingsControllerProvider);

    expect(state.settings.enabled, isTrue);
    expect(state.settings.preferredTimeLabel, '20:30');
    expect(state.statusMessage, '已读取本地提醒设置：固定时间 20:30。');
  });

  test('切换和设置时间使用仓库返回值规范化并可恢复', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer firstContainer = createContainer(storage);

    await firstContainer
        .read(reminderSettingsControllerProvider.notifier)
        .toggleTrainingRemindersAsync();
    expect(
      firstContainer.read(reminderSettingsControllerProvider).statusMessage,
      '提醒已暂停：今日训练和周报入口仍可手动打开。',
    );

    await firstContainer
        .read(reminderSettingsControllerProvider.notifier)
        .setReminderTimeLabelAsync('  ');
    final ReminderSettingsState savedState =
        firstContainer.read(reminderSettingsControllerProvider);
    expect(savedState.settings.enabled, isFalse);
    expect(savedState.settings.preferredTimeLabel, '20:30');
    expect(
      savedState.statusMessage,
      '固定提醒时间已更新为 20:30，后续主动服务会使用这个时间。',
    );
    firstContainer.dispose();

    final ProviderContainer restoredContainer = createContainer(storage);
    addTearDown(restoredContainer.dispose);
    final ReminderSettingsState restoredState =
        restoredContainer.read(reminderSettingsControllerProvider);

    expect(restoredState.settings.enabled, isFalse);
    expect(restoredState.settings.preferredTimeLabel, '20:30');
    expect(restoredState.statusMessage, '提醒已暂停：今日训练和周报入口仍可手动打开。');
  });

  test('停用清理日程订阅，再启用只恢复一份且不重新申请权限', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final _CountingTrainingGateway gateway = _CountingTrainingGateway();
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      trainingNotificationSchedulerProvider.overrideWithValue(
        TrainingNotificationScheduler(gateway),
      ),
    ]);
    addTearDown(container.dispose);
    container.read(reminderSettingsControllerProvider);
    final ProviderSubscription<ReminderSettingsState> keepAlive =
        container.listen(reminderSettingsControllerProvider, (_, __) {});
    addTearDown(keepAlive.close);
    await _pumpEvents();

    await runtime.disable('feature.reminders');
    final int pausedLoads = gateway.loadCount;
    await container.read(trainingScheduleControllerProvider.notifier).addSlot(
          date: DateTime.now().add(const Duration(days: 5)),
          startMinute: 8 * 60,
          endMinute: 9 * 60,
        );
    await _pumpEvents();
    expect(gateway.loadCount, pausedLoads);

    await runtime.enable('feature.reminders');
    await container.pump();
    container.read(reminderSettingsControllerProvider);
    await _pumpEvents();
    expect(gateway.permissionRequestCount, 0);
    gateway.loadCount = 0;
    await container.read(trainingScheduleControllerProvider.notifier).addSlot(
          date: DateTime.now().add(const Duration(days: 6)),
          startMinute: 9 * 60,
          endMinute: 10 * 60,
        );
    await _pumpEvents();
    expect(gateway.loadCount, 1);

    await runtime.disable('feature.reminders');
    await container.pump();
    await runtime.enable('feature.reminders');
    await container.pump();
    container.read(reminderSettingsControllerProvider);
    await _pumpEvents();
    gateway.loadCount = 0;
    await container.read(trainingScheduleControllerProvider.notifier).addSlot(
          date: DateTime.now().add(const Duration(days: 7)),
          startMinute: 10 * 60,
          endMinute: 11 * 60,
        );
    await _pumpEvents();
    expect(gateway.loadCount, 1);
    expect(gateway.permissionRequestCount, 0);
  });

  test('真实取消异常使停用回滚并只恢复一份日程订阅', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final _CountingTrainingGateway gateway = _CountingTrainingGateway();
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      trainingNotificationSchedulerProvider.overrideWithValue(
        TrainingNotificationScheduler(gateway),
      ),
    ]);
    addTearDown(container.dispose);
    container.read(reminderSettingsControllerProvider);
    final ProviderSubscription<ReminderSettingsState> keepAlive =
        container.listen(reminderSettingsControllerProvider, (_, __) {});
    addTearDown(keepAlive.close);
    await _pumpEvents();

    gateway.failCancellation = true;
    await expectLater(runtime.disable('feature.reminders'), throwsStateError);
    expect(runtime.isEnabled('feature.reminders'), isTrue);

    gateway.failCancellation = false;
    await container.pump();
    container.read(reminderSettingsControllerProvider);
    await _pumpEvents();
    gateway.loadCount = 0;
    await container.read(trainingScheduleControllerProvider.notifier).addSlot(
          date: DateTime.now().add(const Duration(days: 8)),
          startMinute: 11 * 60,
          endMinute: 12 * 60,
        );
    await _pumpEvents();
    expect(gateway.loadCount, 1);
  });

  test('异步设置在flush期间保持提交锁，落盘后才允许停用', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final _BlockingFlushStorage storage = _BlockingFlushStorage();
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      trainingNotificationSchedulerProvider.overrideWithValue(
        TrainingNotificationScheduler(_CountingTrainingGateway()),
      ),
    ]);
    addTearDown(container.dispose);
    final ReminderSettingsController controller =
        container.read(reminderSettingsControllerProvider.notifier);

    final Future<void> saving = controller.setReminderTimeLabelAsync('07:30');
    await storage.started.future;
    expect(runtime.checkDisable('feature.reminders').join(), contains('正在保存'));
    await expectLater(
      runtime.disable('feature.reminders'),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('正在保存'),
        ),
      ),
    );
    expect(runtime.isEnabled('feature.reminders'), isTrue);

    storage.finish.complete();
    await saving;
    await runtime.disable('feature.reminders');
    expect(runtime.isEnabled('feature.reminders'), isFalse);
  });

  test('异步设置flush失败时恢复原设置并返回中文错误', () async {
    final _FailOnceFlushStorage storage = _FailOnceFlushStorage();
    final ProviderContainer container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      trainingNotificationSchedulerProvider.overrideWithValue(
        TrainingNotificationScheduler(_CountingTrainingGateway()),
      ),
    ]);
    addTearDown(container.dispose);
    final ReminderSettingsController controller =
        container.read(reminderSettingsControllerProvider.notifier);

    await expectLater(
      controller.setReminderTimeLabelAsync('07:30'),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('已恢复原设置'),
        ),
      ),
    );
    final ReminderSettingsState current =
        container.read(reminderSettingsControllerProvider);
    expect(current.settings.preferredTimeLabel, '20:30');
    expect(current.statusMessage, contains('已恢复原设置'));
    expect(
      PersistedReminderSettingsRepository(storage)
          .getSettings()
          .preferredTimeLabel,
      '20:30',
    );
  });
}

Future<void> _pumpEvents() async {
  for (int attempt = 0; attempt < 20; attempt += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _CountingTrainingGateway implements TrainingNotificationGateway {
  final timezone.Location location =
      timezone.getLocation('America/Los_Angeles');
  int loadCount = 0;
  int permissionRequestCount = 0;
  bool failCancellation = false;

  @override
  Future<void> cancelTrainingNotifications() async {
    if (failCancellation) throw StateError('测试取消失败');
  }

  @override
  Future<timezone.Location> loadLocalLocation() async {
    loadCount += 1;
    return location;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequestCount += 1;
    return true;
  }

  @override
  Future<void> schedule(TrainingNotificationRequest request) async {}
}

class _BlockingFlushStorage extends InMemoryLocalStorageService {
  final Completer<void> started = Completer<void>();
  final Completer<void> finish = Completer<void>();

  @override
  Future<void> flush() async {
    if (!started.isCompleted) started.complete();
    await finish.future;
  }
}

class _FailOnceFlushStorage extends InMemoryLocalStorageService {
  bool _shouldFail = true;

  @override
  Future<void> flush() async {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('测试落盘失败');
    }
  }
}
