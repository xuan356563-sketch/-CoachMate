import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/reminders/application/reminder_settings_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

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
}
