import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as timezone;

import 'package:trainflow_ai/data/models/training_reminder.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/reminders/application/reminder_settings_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';

void main() {
  test('提醒设置控制器同步旧训练状态和提醒列表并保留跟练会话', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        trainingNotificationSchedulerProvider.overrideWithValue(
          TrainingNotificationScheduler(_NoopTrainingNotificationGateway()),
        ),
      ],
    );
    addTearDown(container.dispose);

    final TrainingMvpController trainingController =
        container.read(trainingMvpProvider.notifier);
    trainingController.startWorkoutPlayer(workoutDayId: 'workout-week1-day2');
    await trainingController.completeWorkoutPlayerStep();
    trainingController.setKnowledgeSearchQuery('跑步');
    final TrainingMvpState sessionState = container.read(trainingMvpProvider);
    final ReminderSettingsController reminderController =
        container.read(reminderSettingsControllerProvider.notifier);

    await reminderController.setReminderTimeLabelAsync('07:30');
    await reminderController.toggleTrainingRemindersAsync();
    await Future<void>.delayed(Duration.zero);

    final TrainingMvpState state = container.read(trainingMvpProvider);
    final TrainingReminder dailyReminder = state.trainingReminders.firstWhere(
      (TrainingReminder reminder) =>
          reminder.type == TrainingReminderType.dailyPlan,
    );
    expect(state.remindersEnabled, isFalse);
    expect(state.reminderTimeLabel, '07:30');
    expect(
      state.reminderStatusMessage,
      container.read(reminderSettingsControllerProvider).statusMessage,
    );
    expect(dailyReminder.timeLabel, '07:30');
    expect(
        state.trainingReminders
            .every((TrainingReminder reminder) => !reminder.enabled),
        isTrue);
    expect(
        state.activeWorkoutPlayerDayId, sessionState.activeWorkoutPlayerDayId);
    expect(state.workoutPlayerStepIndex, sessionState.workoutPlayerStepIndex);
    expect(state.workoutPlayerEvents, sessionState.workoutPlayerEvents);
    expect(state.logs, sessionState.logs);
    expect(state.knowledgeSearchQuery, sessionState.knowledgeSearchQuery);
  });
}

class _NoopTrainingNotificationGateway implements TrainingNotificationGateway {
  @override
  Future<void> cancelTrainingNotifications() async {}

  @override
  Future<timezone.Location> loadLocalLocation() async =>
      throw UnsupportedError('测试不读取时区');

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(TrainingNotificationRequest request) async {}
}
