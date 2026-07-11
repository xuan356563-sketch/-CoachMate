import '../models/training_reminder.dart';
import '../../services/local_storage_service.dart';

abstract class ReminderSettingsRepository {
  TrainingReminderSettings getSettings();

  TrainingReminderSettings saveSettings(TrainingReminderSettings settings);

  void clearSettings();
}

class InMemoryReminderSettingsRepository implements ReminderSettingsRepository {
  static const TrainingReminderSettings defaultSettings =
      TrainingReminderSettings(
    enabled: true,
    preferredTimeLabel: '20:30',
  );

  TrainingReminderSettings _settings = defaultSettings;

  @override
  TrainingReminderSettings getSettings() {
    return _settings;
  }

  @override
  TrainingReminderSettings saveSettings(TrainingReminderSettings settings) {
    _settings = _normalizeSettings(settings);
    return _settings;
  }

  @override
  void clearSettings() {
    _settings = defaultSettings;
  }

  TrainingReminderSettings _normalizeSettings(
    TrainingReminderSettings settings,
  ) {
    final String normalizedTimeLabel = settings.preferredTimeLabel.trim();
    return TrainingReminderSettings(
      enabled: settings.enabled,
      preferredTimeLabel:
          normalizedTimeLabel.isEmpty ? '20:30' : normalizedTimeLabel,
    );
  }
}

class PersistedReminderSettingsRepository
    implements ReminderSettingsRepository {
  static const String storageKey = 'trainflow.reminder_settings.v1';

  final LocalStorageService _storageService;
  TrainingReminderSettings _settings =
      InMemoryReminderSettingsRepository.defaultSettings;

  PersistedReminderSettingsRepository(this._storageService) {
    _hydrate();
  }

  @override
  TrainingReminderSettings getSettings() {
    return _settings;
  }

  @override
  TrainingReminderSettings saveSettings(TrainingReminderSettings settings) {
    _settings = _normalizeSettings(settings);
    _persist();
    return _settings;
  }

  @override
  void clearSettings() {
    _settings = InMemoryReminderSettingsRepository.defaultSettings;
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final Object? settingsJson = storedState['settings'];
    if (settingsJson is Map<String, dynamic>) {
      _settings = _normalizeSettings(
        TrainingReminderSettings.fromJson(settingsJson),
      );
    }
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'settings': _settings.toJson(),
    });
  }

  TrainingReminderSettings _normalizeSettings(
    TrainingReminderSettings settings,
  ) {
    final String normalizedTimeLabel = settings.preferredTimeLabel.trim();
    return TrainingReminderSettings(
      enabled: settings.enabled,
      preferredTimeLabel:
          normalizedTimeLabel.isEmpty ? '20:30' : normalizedTimeLabel,
    );
  }
}
