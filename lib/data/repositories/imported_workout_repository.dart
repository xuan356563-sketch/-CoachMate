import '../models/imported_workout.dart';
import '../../services/local_storage_service.dart';

abstract class ImportedWorkoutRepository {
  List<ImportedWorkout> listWorkouts();

  ImportedWorkout saveWorkout(ImportedWorkout workout);

  bool removeRouteShape(String workoutId);

  void clearWorkouts();
}

class InMemoryImportedWorkoutRepository implements ImportedWorkoutRepository {
  final List<ImportedWorkout> _workouts = [];

  @override
  List<ImportedWorkout> listWorkouts() {
    return List<ImportedWorkout>.unmodifiable(_workouts);
  }

  @override
  ImportedWorkout saveWorkout(ImportedWorkout workout) {
    _workouts.removeWhere((ImportedWorkout item) => item.id == workout.id);
    _workouts.insert(0, workout);
    return workout;
  }

  @override
  bool removeRouteShape(String workoutId) {
    final int index =
        _workouts.indexWhere((ImportedWorkout item) => item.id == workoutId);
    if (index < 0 || !_workouts[index].hasRouteShape) return false;
    _workouts[index] = _workouts[index].withoutRouteShape();
    return true;
  }

  @override
  void clearWorkouts() {
    _workouts.clear();
  }
}

class PersistedImportedWorkoutRepository implements ImportedWorkoutRepository {
  static const String storageKey = 'trainflow.imported_workouts.v1';
  static const int _maxSavedWorkouts = 100;

  final LocalStorageService _storageService;
  final List<ImportedWorkout> _workouts = [];

  PersistedImportedWorkoutRepository(this._storageService) {
    _hydrate();
  }

  @override
  List<ImportedWorkout> listWorkouts() {
    return List<ImportedWorkout>.unmodifiable(_workouts);
  }

  @override
  ImportedWorkout saveWorkout(ImportedWorkout workout) {
    _workouts.removeWhere((ImportedWorkout item) => item.id == workout.id);
    _workouts.insert(0, workout);
    if (_workouts.length > _maxSavedWorkouts) {
      _workouts.removeRange(_maxSavedWorkouts, _workouts.length);
    }
    _persist();
    return workout;
  }

  @override
  bool removeRouteShape(String workoutId) {
    final int index =
        _workouts.indexWhere((ImportedWorkout item) => item.id == workoutId);
    if (index < 0 || !_workouts[index].hasRouteShape) return false;
    _workouts[index] = _workouts[index].withoutRouteShape();
    _persist();
    return true;
  }

  @override
  void clearWorkouts() {
    _workouts.clear();
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final List<dynamic> workoutItems =
        storedState['workouts'] as List<dynamic>? ?? const [];
    _workouts.addAll(
      workoutItems
          .whereType<Map<String, dynamic>>()
          .map(ImportedWorkout.fromJson)
          .toList(),
    );
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 2,
      'workouts':
          _workouts.map((ImportedWorkout workout) => workout.toJson()).toList(),
    });
  }
}
