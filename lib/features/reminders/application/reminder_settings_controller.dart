import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/training_reminder.dart';
import '../../../data/repositories/reminder_settings_repository.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/system_training_notification_service.dart';
import '../../profile/application/training_schedule_controller.dart';

/// 提供当前本地存储对应的提醒设置仓库。
final reminderSettingsRepositoryProvider = Provider<ReminderSettingsRepository>(
  (Ref ref) => PersistedReminderSettingsRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

/// 提供可替换的系统通知能力。
final trainingNotificationSchedulerProvider =
    Provider<TrainingNotificationScheduler>(
  (Ref ref) =>
      TrainingNotificationScheduler(SystemTrainingNotificationGateway()),
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
  /// 同步请求序号：只有最新一次同步有权写回状态，避免先发后到的旧结果
  /// 把用户刚保存的设置覆盖回去。
  int _syncGeneration = 0;

  @override
  ReminderSettingsState build() {
    final TrainingReminderSettings settings =
        ref.watch(reminderSettingsRepositoryProvider).getSettings();
    ref.listen(
      trainingScheduleControllerProvider
          .select((TrainingScheduleState value) => value.workouts),
      (_, __) {
        if (state.settings.enabled) {
          unawaited(_synchronize(state.settings));
        }
      },
    );
    if (settings.enabled) {
      unawaited(_synchronize(settings));
    }
    return ReminderSettingsState(
      settings: settings,
      statusMessage: _initialStatusMessage(settings),
    );
  }

  /// 切换提醒启用状态。
  void toggleTrainingReminders() {
    final bool enabling = !state.settings.enabled;
    final TrainingReminderSettings settings =
        ref.read(reminderSettingsRepositoryProvider).saveSettings(
              TrainingReminderSettings(
                enabled: enabling,
                preferredTimeLabel: state.settings.preferredTimeLabel,
                followSchedule: state.settings.followSchedule,
                leadMinutes: state.settings.leadMinutes,
              ),
            );
    state = ReminderSettingsState(
      settings: settings,
      statusMessage: enabling ? '正在申请系统通知权限并同步训练日程。' : '提醒已暂停：今日训练和周报入口仍可手动打开。',
    );
    unawaited(_synchronize(settings, requestPermission: enabling));
  }

  /// 设置固定提醒时间。
  void setReminderTimeLabel(String value) {
    final TrainingReminderSettings settings =
        ref.read(reminderSettingsRepositoryProvider).saveSettings(
              TrainingReminderSettings(
                enabled: state.settings.enabled,
                preferredTimeLabel: value,
                followSchedule: state.settings.followSchedule,
                leadMinutes: state.settings.leadMinutes,
              ),
            );
    state = ReminderSettingsState(
      settings: settings,
      statusMessage: '固定提醒时间已更新为 ${settings.preferredTimeLabel}，后续主动服务会使用这个时间。',
    );
    unawaited(_synchronize(settings));
  }

  /// 设置提醒是否跟随训练日程。
  void setFollowSchedule(bool value) {
    _save(
      TrainingReminderSettings(
        enabled: state.settings.enabled,
        preferredTimeLabel: state.settings.preferredTimeLabel,
        followSchedule: value,
        leadMinutes: state.settings.leadMinutes,
      ),
      value ? '提醒将跟随当天训练时间。' : '提醒将使用固定时间。',
    );
  }

  /// 设置训练开始前的提醒提前量。
  void setLeadMinutes(int value) {
    _save(
      TrainingReminderSettings(
        enabled: state.settings.enabled,
        preferredTimeLabel: state.settings.preferredTimeLabel,
        followSchedule: state.settings.followSchedule,
        leadMinutes: value,
      ),
      '将在训练开始前约 $value 分钟提醒；系统省电策略可能让通知略微延后。',
    );
  }

  void _save(TrainingReminderSettings settings, String message) {
    final TrainingReminderSettings saved =
        ref.read(reminderSettingsRepositoryProvider).saveSettings(settings);
    state = ReminderSettingsState(settings: saved, statusMessage: message);
    unawaited(_synchronize(saved));
  }

  Future<void> _synchronize(
    TrainingReminderSettings settings, {
    bool requestPermission = false,
  }) async {
    final int generation = ++_syncGeneration;
    final TrainingNotificationSyncResult result =
        await ref.read(trainingNotificationSchedulerProvider).synchronize(
              settings: settings,
              workouts: ref.read(trainingScheduleControllerProvider).workouts,
              requestPermission: requestPermission,
            );
    if (!ref.mounted || generation != _syncGeneration) return;
    // 统一以仓库里的当前设置为准，不使用发起同步时捕获的旧值。
    final ReminderSettingsRepository repository =
        ref.read(reminderSettingsRepositoryProvider);
    final TrainingReminderSettings current = repository.getSettings();
    switch (result.status) {
      case TrainingNotificationSyncStatus.disabled:
        return;
      case TrainingNotificationSyncStatus.permissionDenied:
        final TrainingReminderSettings disabled = repository.saveSettings(
          TrainingReminderSettings(
            enabled: false,
            preferredTimeLabel: current.preferredTimeLabel,
            followSchedule: current.followSchedule,
            leadMinutes: current.leadMinutes,
          ),
        );
        state = ReminderSettingsState(
          settings: disabled,
          statusMessage: '系统通知权限未开启，已关闭提醒开关；在系统设置中允许通知后可重新开启。',
        );
        return;
      case TrainingNotificationSyncStatus.scheduled:
        state = ReminderSettingsState(
          settings: current,
          statusMessage: result.scheduledCount == 0
              ? '系统提醒已开启；当前没有需要调度的未来训练。'
              : '已按本地时区安排 ${result.scheduledCount} 条系统训练提醒。',
        );
        return;
      case TrainingNotificationSyncStatus.unavailable:
        state = ReminderSettingsState(
          settings: current,
          statusMessage: '当前设备无法安排系统提醒，已排期的提醒可能已被清除；训练计划本身不受影响。',
        );
        return;
    }
  }

  String _initialStatusMessage(TrainingReminderSettings settings) {
    return settings.enabled
        ? '已读取本地提醒设置：固定时间 ${settings.preferredTimeLabel}。'
        : '提醒已暂停：今日训练和周报入口仍可手动打开。';
  }
}
