import '../models/meal_guide.dart';
import '../../services/local_storage_service.dart';

abstract class MealPreferenceRepository {
  MealPreference getPreference();

  MealPreference savePreference(MealPreference preference);

  void clearPreference();
}

class InMemoryMealPreferenceRepository implements MealPreferenceRepository {
  static const MealPreference defaultPreference = MealPreference(
    scenario: MealScenario.takeaway,
  );

  MealPreference _preference = defaultPreference;

  @override
  MealPreference getPreference() {
    return _preference;
  }

  @override
  MealPreference savePreference(MealPreference preference) {
    _preference = preference;
    return _preference;
  }

  @override
  void clearPreference() {
    _preference = defaultPreference;
  }
}

class PersistedMealPreferenceRepository implements MealPreferenceRepository {
  static const String storageKey = 'trainflow.meal_preference.v1';

  final LocalStorageService _storageService;
  MealPreference _preference =
      InMemoryMealPreferenceRepository.defaultPreference;

  PersistedMealPreferenceRepository(this._storageService) {
    _hydrate();
  }

  @override
  MealPreference getPreference() {
    return _preference;
  }

  @override
  MealPreference savePreference(MealPreference preference) {
    _preference = preference;
    _persist();
    return _preference;
  }

  @override
  void clearPreference() {
    _preference = InMemoryMealPreferenceRepository.defaultPreference;
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final Object? preferenceJson = storedState['preference'];
    if (preferenceJson is Map<String, dynamic>) {
      _preference = MealPreference.fromJson(preferenceJson);
    }
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'preference': _preference.toJson(),
    });
  }
}
