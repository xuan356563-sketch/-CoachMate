import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/training_reminder.dart';
import '../../../data/repositories/reminder_settings_repository.dart';
import '../../../services/local_storage_service.dart';

/// 提供当前本地存储对应的提醒设置仓库。
final reminderSettingsRepositoryProvider = Provider<ReminderSettingsRepository>(
  (Ref ref) => PersistedReminderSettingsRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

/// 管理独立的提醒设置状态。
final reminderSettingsControllerProvider =
    NotifierProvider<ReminderSettingsController, ReminderSettingsState>(
  ReminderSettingsController.new,
);

/// 提醒设置及其用户可见状态文案。
class ReminderSettingsState {
  final TrainingReminderSettings settings;
  final String statusMessage;

  const ReminderSettingsState({
    required this.settings,
    required this.statusMessage,
  });
}

/// 负责读取、保存和恢复提醒设置。
class ReminderSettingsController extends Notifier<ReminderSettingsState> {
  @override
  ReminderSettingsState build() {
    final TrainingReminderSettings settings =
        ref.watch(reminderSettingsRepositoryProvider).getSettings();
    return ReminderSettingsState(
      settings: settings,
      statusMessage: _initialStatusMessage(settings),
    );
  }

  /// 切换提醒启用状态。
  void toggleTrainingReminders() {
    final TrainingReminderSettings settings =
        ref.read(reminderSettingsRepositoryProvider).saveSettings(
              TrainingReminderSettings(
                enabled: !state.settings.enabled,
                preferredTimeLabel: state.settings.preferredTimeLabel,
              ),
            );
    state = ReminderSettingsState(
      settings: settings,
      statusMessage: settings.enabled
          ? '提醒已开启：会继续按本地编排生成下一条主动提醒。'
          : '提醒已暂停：今日训练和周报入口仍可手动打开。',
    );
  }

  /// 设置固定提醒时间。
  void setReminderTimeLabel(String value) {
    final TrainingReminderSettings settings =
        ref.read(reminderSettingsRepositoryProvider).saveSettings(
              TrainingReminderSettings(
                enabled: state.settings.enabled,
                preferredTimeLabel: value,
              ),
            );
    state = ReminderSettingsState(
      settings: settings,
      statusMessage: '固定提醒时间已更新为 ${settings.preferredTimeLabel}，后续主动服务会使用这个时间。',
    );
  }

  String _initialStatusMessage(TrainingReminderSettings settings) {
    return settings.enabled
        ? '已读取本地提醒设置：固定时间 ${settings.preferredTimeLabel}。'
        : '提醒已暂停：今日训练和周报入口仍可手动打开。';
  }
}
