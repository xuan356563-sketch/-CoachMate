import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_reminder.dart';
import 'package:trainflow_ai/data/repositories/reminder_settings_repository.dart';

import '../../support/test_harness.dart';

void main() {
  test('提醒设置仓库会持久化 reminder_settings', () {
    final TestHarness harness = TestHarness();
    final PersistedReminderSettingsRepository repository =
        PersistedReminderSettingsRepository(harness.storageService);

    expect(repository.getSettings().enabled, isTrue);
    expect(repository.getSettings().preferredTimeLabel, '20:30');

    repository.saveSettings(
      const TrainingReminderSettings(
        enabled: false,
        preferredTimeLabel: '07:30',
      ),
    );

    final PersistedReminderSettingsRepository restoredRepository =
        PersistedReminderSettingsRepository(harness.storageService);

    expect(restoredRepository.getSettings().enabled, isFalse);
    expect(restoredRepository.getSettings().preferredTimeLabel, '07:30');

    restoredRepository.saveSettings(
      const TrainingReminderSettings(
        enabled: true,
        preferredTimeLabel: '',
      ),
    );

    final PersistedReminderSettingsRepository normalizedRepository =
        PersistedReminderSettingsRepository(harness.storageService);

    expect(normalizedRepository.getSettings().enabled, isTrue);
    expect(normalizedRepository.getSettings().preferredTimeLabel, '20:30');

    normalizedRepository.clearSettings();

    final PersistedReminderSettingsRepository clearedRepository =
        PersistedReminderSettingsRepository(harness.storageService);

    expect(clearedRepository.getSettings().enabled, isTrue);
    expect(clearedRepository.getSettings().preferredTimeLabel, '20:30');
  });
}
