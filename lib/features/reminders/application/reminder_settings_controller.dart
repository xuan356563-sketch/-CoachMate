import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/training_reminder.dart';
import '../../../data/models/training_schedule.dart';
import '../../../data/repositories/reminder_settings_repository.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/system_training_notification_service.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
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
  static const String _featureId = 'feature.reminders';
  late ReminderSettingsRepository _repository;
  late TrainingNotificationScheduler _scheduler;
  ProviderSubscription<List<ScheduledWorkout>>? _scheduleSubscription;
  int _synchronizationEpoch = 0;
  bool _resumeWithoutBuildSync = false;

  @override
  ReminderSettingsState build() {
    _scheduleSubscription = null;
    final bool resumeWithoutBuildSync = _resumeWithoutBuildSync;
    _resumeWithoutBuildSync = false;
    _repository = ref.watch(reminderSettingsRepositoryProvider);
    _scheduler = ref.watch(trainingNotificationSchedulerProvider);
    final TrainingReminderSettings settings = _repository.getSettings();
    bindFeatureController(
      ref,
      _featureId,
      'controller',
      this,
      cleanup: _pauseResources,
      onRestore: _restoreResourcesAfterRollback,
    );
    ref.listen<bool>(featureEnabledProvider(_featureId), (_, bool enabled) {
      if (!enabled) return;
      _resumeWithoutBuildSync = true;
      ref.invalidateSelf();
    });
    if (ref.read(featureAccessProvider).isWritable(_featureId)) {
      _startScheduleSubscription();
      if (settings.enabled) {
        if (resumeWithoutBuildSync) {
          unawaited(Future<void>.delayed(Duration.zero, _restoreResources));
        } else {
          unawaited(_synchronize(settings));
        }
      }
    }
    return ReminderSettingsState(
      settings: settings,
      statusMessage: _initialStatusMessage(settings),
    );
  }

  /// 切换提醒启用状态。
  void toggleTrainingReminders() {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    unawaited(_toggleTrainingReminders(operation));
  }

  /// 等待设置落盘和系统通知同步完成，供生产交互入口使用。
  Future<void> toggleTrainingRemindersAsync() {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    return _toggleTrainingReminders(operation);
  }

  Future<void> _toggleTrainingReminders(FeatureOperation operation) async {
    _synchronizationEpoch++;
    final bool enabling = !state.settings.enabled;
    final TrainingReminderSettings settings = await _commitSettings(
      operation,
      TrainingReminderSettings(
        enabled: enabling,
        preferredTimeLabel: state.settings.preferredTimeLabel,
        followSchedule: state.settings.followSchedule,
        leadMinutes: state.settings.leadMinutes,
      ),
      enabling ? '正在申请系统通知权限并同步训练日程。' : '提醒已暂停：今日训练和周报入口仍可手动打开。',
    );
    if (!ref.mounted) return;
    await _synchronize(
      settings,
      requestPermission: enabling,
      operation: operation,
    );
  }

  /// 设置固定提醒时间。
  void setReminderTimeLabel(String value) {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    unawaited(_save(
      TrainingReminderSettings(
        enabled: state.settings.enabled,
        preferredTimeLabel: value,
        followSchedule: state.settings.followSchedule,
        leadMinutes: state.settings.leadMinutes,
      ),
      '固定提醒时间已更新，后续主动服务会使用这个时间。',
      operation,
    ));
  }

  /// 等待固定提醒时间落盘和系统通知同步完成。
  Future<void> setReminderTimeLabelAsync(String value) {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    return _save(
      TrainingReminderSettings(
        enabled: state.settings.enabled,
        preferredTimeLabel: value,
        followSchedule: state.settings.followSchedule,
        leadMinutes: state.settings.leadMinutes,
      ),
      '固定提醒时间已更新，后续主动服务会使用这个时间。',
      operation,
    );
  }

  /// 设置提醒是否跟随训练日程。
  void setFollowSchedule(bool value) {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    unawaited(_save(
      TrainingReminderSettings(
        enabled: state.settings.enabled,
        preferredTimeLabel: state.settings.preferredTimeLabel,
        followSchedule: value,
        leadMinutes: state.settings.leadMinutes,
      ),
      value ? '提醒将跟随当天训练时间。' : '提醒将使用固定时间。',
      operation,
    ));
  }

  /// 等待跟随日程设置落盘和系统通知同步完成。
  Future<void> setFollowScheduleAsync(bool value) {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    return _save(
      TrainingReminderSettings(
        enabled: state.settings.enabled,
        preferredTimeLabel: state.settings.preferredTimeLabel,
        followSchedule: value,
        leadMinutes: state.settings.leadMinutes,
      ),
      value ? '提醒将跟随当天训练时间。' : '提醒将使用固定时间。',
      operation,
    );
  }

  /// 设置训练开始前的提醒提前量。
  void setLeadMinutes(int value) {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    unawaited(_save(
      TrainingReminderSettings(
        enabled: state.settings.enabled,
        preferredTimeLabel: state.settings.preferredTimeLabel,
        followSchedule: state.settings.followSchedule,
        leadMinutes: value,
      ),
      '将在训练开始前 $value 分钟提醒。',
      operation,
    ));
  }

  /// 等待提前量设置落盘和系统通知同步完成。
  Future<void> setLeadMinutesAsync(int value) {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    return _save(
      TrainingReminderSettings(
        enabled: state.settings.enabled,
        preferredTimeLabel: state.settings.preferredTimeLabel,
        followSchedule: state.settings.followSchedule,
        leadMinutes: value,
      ),
      '将在训练开始前 $value 分钟提醒。',
      operation,
    );
  }

  Future<void> _save(
    TrainingReminderSettings settings,
    String message,
    FeatureOperation operation,
  ) async {
    _synchronizationEpoch++;
    final TrainingReminderSettings saved = await _commitSettings(
      operation,
      settings,
      message,
    );
    if (!ref.mounted) return;
    await _synchronize(saved, operation: operation);
  }

  Future<TrainingReminderSettings> _commitSettings(
    FeatureOperation operation,
    TrainingReminderSettings settings,
    String message,
  ) {
    final ReminderSettingsState previous = state;
    return operation.commit(() async {
      try {
        final TrainingReminderSettings saved =
            _repository.saveSettings(settings);
        state = ReminderSettingsState(
          settings: saved,
          statusMessage: message.contains('固定提醒时间')
              ? '固定提醒时间已更新为 ${saved.preferredTimeLabel}，后续主动服务会使用这个时间。'
              : message,
        );
        await ref.read(localStorageServiceProvider).flush();
        return saved;
      } catch (_) {
        _repository.saveSettings(previous.settings);
        state = ReminderSettingsState(
          settings: previous.settings,
          statusMessage: '提醒设置保存失败，已恢复原设置，请重试。',
        );
        try {
          await ref.read(localStorageServiceProvider).flush();
        } catch (_) {
          throw StateError('提醒设置保存失败，恢复落盘也失败；已保留原设置，请重试。');
        }
        throw StateError('提醒设置保存失败，已恢复原设置，请重试。');
      }
    });
  }

  Future<void> _synchronize(
    TrainingReminderSettings settings, {
    bool requestPermission = false,
    FeatureOperation? operation,
  }) async {
    final FeatureOperation activeOperation =
        operation ?? ref.read(featureAccessProvider).beginOperation(_featureId);
    final int epoch = ++_synchronizationEpoch;
    bool isActive() {
      if (epoch != _synchronizationEpoch) return false;
      try {
        activeOperation.checkActive();
        return true;
      } on StateError {
        return false;
      }
    }

    final TrainingNotificationSyncResult result = await _scheduler.synchronize(
      settings: settings,
      workouts: ref.read(trainingScheduleControllerProvider).workouts,
      requestPermission: requestPermission,
      isActive: isActive,
    );
    if (!ref.mounted ||
        !isActive() ||
        state.settings.enabled != settings.enabled) {
      return;
    }
    switch (result.status) {
      case TrainingNotificationSyncStatus.disabled:
        return;
      case TrainingNotificationSyncStatus.permissionDenied:
        await activeOperation.commit(() async {
          final TrainingReminderSettings disabled = _repository.saveSettings(
            TrainingReminderSettings(
              enabled: false,
              preferredTimeLabel: settings.preferredTimeLabel,
              followSchedule: settings.followSchedule,
              leadMinutes: settings.leadMinutes,
            ),
          );
          await ref.read(localStorageServiceProvider).flush();
          state = ReminderSettingsState(
            settings: disabled,
            statusMessage: '系统通知权限未开启，已保留设置并回退为应用内提醒。',
          );
        });
        return;
      case TrainingNotificationSyncStatus.scheduled:
        state = ReminderSettingsState(
          settings: settings,
          statusMessage: result.scheduledCount == 0
              ? '系统提醒已开启；当前没有需要调度的未来训练。'
              : '已按本地时区安排 ${result.scheduledCount} 条系统训练提醒。',
        );
        return;
      case TrainingNotificationSyncStatus.unavailable:
        state = ReminderSettingsState(
          settings: settings,
          statusMessage: '系统提醒暂不可用，已回退为应用内提醒，不影响训练计划。',
        );
        return;
    }
  }

  String _initialStatusMessage(TrainingReminderSettings settings) {
    return settings.enabled
        ? '已读取本地提醒设置：固定时间 ${settings.preferredTimeLabel}。'
        : '提醒已暂停：今日训练和周报入口仍可手动打开。';
  }

  void _startScheduleSubscription() {
    if (_scheduleSubscription != null) return;
    _scheduleSubscription = ref.listen<List<ScheduledWorkout>>(
      trainingScheduleControllerProvider
          .select((TrainingScheduleState value) => value.workouts),
      (_, __) {
        if (state.settings.enabled &&
            ref.read(featureAccessProvider).isWritable(_featureId)) {
          unawaited(_synchronize(state.settings));
        }
      },
    );
  }

  Future<void> _pauseResources() async {
    _synchronizationEpoch++;
    _scheduleSubscription?.close();
    _scheduleSubscription = null;
    await _scheduler.cancel();
  }

  Future<void> _restoreResources() async {
    if (!ref.mounted ||
        !ref.read(featureAccessProvider).isWritable(_featureId)) {
      return;
    }
    final TrainingReminderSettings settings = _repository.getSettings();
    if (settings.enabled) await _synchronize(settings);
  }

  Future<void> _restoreResourcesAfterRollback() async {
    if (!ref.mounted ||
        !ref.read(featureAccessProvider).isEnabled(_featureId)) {
      return;
    }
    _resumeWithoutBuildSync = true;
    ref.invalidateSelf();
  }
}
