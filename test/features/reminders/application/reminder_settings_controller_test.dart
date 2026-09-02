import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_10y.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'package:trainflow_ai/features/reminders/application/reminder_settings_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';

void main() {
  ProviderContainer createContainer(InMemoryLocalStorageService storage) {
    return ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
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

  test('切换和设置时间使用仓库返回值规范化并可恢复', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer firstContainer = createContainer(storage);

    firstContainer
        .read(reminderSettingsControllerProvider.notifier)
        .toggleTrainingReminders();
    expect(
      firstContainer.read(reminderSettingsControllerProvider).statusMessage,
      '提醒已暂停：今日训练和周报入口仍可手动打开。',
    );

    firstContainer
        .read(reminderSettingsControllerProvider.notifier)
        .setReminderTimeLabel('  ');
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

  test('先发后到的同步结果不会覆盖用户最新保存的设置', () async {
    timezone_data.initializeTimeZones();
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final _GatedGateway gateway =
        _GatedGateway(timezone.getLocation('Asia/Shanghai'));
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        trainingNotificationSchedulerProvider
            .overrideWithValue(TrainingNotificationScheduler(gateway)),
      ],
    );
    addTearDown(container.dispose);

    final ReminderSettingsController controller =
        container.read(reminderSettingsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    controller.setLeadMinutes(60);
    await Future<void>.delayed(Duration.zero);
    controller.setLeadMinutes(15);
    await Future<void>.delayed(Duration.zero);

    // 初始化一次 + 两次设置修改，各自停在时区解析这一步。
    expect(gateway.gates.length, 3);

    // 让最后发起的同步先返回，再放行更早的两次。
    gateway.gates[2].complete();
    await Future<void>.delayed(Duration.zero);
    gateway.gates[1].complete();
    gateway.gates[0].complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(reminderSettingsControllerProvider).settings.leadMinutes,
      15,
    );
  });
}

/// 把时区解析卡在外部可控的闸门上，用来制造同步结果的乱序返回。
class _GatedGateway implements TrainingNotificationGateway {
  _GatedGateway(this.location);

  final timezone.Location location;
  final List<Completer<void>> gates = <Completer<void>>[];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<timezone.Location> loadLocalLocation() async {
    final Completer<void> gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return location;
  }

  @override
  Future<void> cancelTrainingNotifications() async {}

  @override
  Future<void> schedule(TrainingNotificationRequest request) async {}
}
