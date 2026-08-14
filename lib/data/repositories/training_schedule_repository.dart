import '../../services/local_storage_service.dart';
import '../models/training_schedule.dart';

class TrainingScheduleRepository {
  static const String availabilityStorageKey =
      'trainflow.training_availability.v1';
  static const String scheduleStorageKey = 'trainflow.training_schedule.v1';

  final LocalStorageService _storage;

  const TrainingScheduleRepository(this._storage);

  List<TrainingAvailabilitySlot> listAvailability() {
    final Map<String, dynamic>? json =
        _storage.readJson(availabilityStorageKey);
    return (json?['slots'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(TrainingAvailabilitySlot.fromJson)
        .toList();
  }

  void saveAvailability(List<TrainingAvailabilitySlot> slots) {
    _storage.saveJson(availabilityStorageKey, {
      'schemaVersion': 1,
      'slots':
          slots.map((TrainingAvailabilitySlot item) => item.toJson()).toList(),
    });
  }

  List<ScheduledWorkout> listSchedule() {
    final Map<String, dynamic>? json = _storage.readJson(scheduleStorageKey);
    return (json?['workouts'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ScheduledWorkout.fromJson)
        .toList();
  }

  void saveSchedule(List<ScheduledWorkout> workouts) {
    _storage.saveJson(scheduleStorageKey, {
      'schemaVersion': 1,
      'workouts':
          workouts.map((ScheduledWorkout item) => item.toJson()).toList(),
    });
  }
}
