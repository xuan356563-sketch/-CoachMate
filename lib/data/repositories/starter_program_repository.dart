import '../models/starter_program.dart';
import '../seed/seed_starter_programs.dart';
import '../../services/local_storage_service.dart';

abstract class StarterProgramRepository {
  List<StarterProgramDay> listDays();

  StarterProgramDay findDay(StarterProgramGoal goal, int dayIndex);

  StarterProgramProgress getProgress();

  StarterProgramProgress saveProgress(StarterProgramProgress progress);

  void clearProgress();
}

class InMemoryStarterProgramRepository implements StarterProgramRepository {
  static const StarterProgramProgress defaultProgress = StarterProgramProgress(
    goal: StarterProgramGoal.habit,
    dayIndex: 1,
    streak: 0,
    rescueMode: false,
    statusMessage: '第 1 天目标：低到不可能失败。',
  );

  final List<StarterProgramDay> _days;
  StarterProgramProgress _progress = defaultProgress;

  InMemoryStarterProgramRepository({List<StarterProgramDay>? initialDays})
      : _days = List<StarterProgramDay>.from(
          initialDays ?? seedStarterProgramDays,
        );

  @override
  List<StarterProgramDay> listDays() {
    return List<StarterProgramDay>.unmodifiable(_days);
  }

  @override
  StarterProgramDay findDay(StarterProgramGoal goal, int dayIndex) {
    for (final StarterProgramDay day in _days) {
      if (day.goal == goal && day.dayIndex == dayIndex) {
        return day;
      }
    }
    return _days.first;
  }

  @override
  StarterProgramProgress getProgress() {
    return _progress;
  }

  @override
  StarterProgramProgress saveProgress(StarterProgramProgress progress) {
    _progress = _normalizeProgress(progress);
    return _progress;
  }

  @override
  void clearProgress() {
    _progress = defaultProgress;
  }

  StarterProgramProgress _normalizeProgress(StarterProgramProgress progress) {
    return StarterProgramProgress(
      goal: progress.goal,
      dayIndex: progress.dayIndex.clamp(1, 30).toInt(),
      streak: progress.streak.clamp(0, 30).toInt(),
      rescueMode: progress.rescueMode,
      statusMessage: progress.statusMessage,
    );
  }
}

class PersistedStarterProgramRepository
    extends InMemoryStarterProgramRepository {
  static const String storageKey = 'trainflow.starter_progress.v1';

  final LocalStorageService _storageService;
  StarterProgramProgress _persistedProgress =
      InMemoryStarterProgramRepository.defaultProgress;

  PersistedStarterProgramRepository({
    required LocalStorageService storageService,
    super.initialDays,
  }) : _storageService = storageService {
    _hydrate();
  }

  @override
  StarterProgramProgress getProgress() {
    return _persistedProgress;
  }

  @override
  StarterProgramProgress saveProgress(StarterProgramProgress progress) {
    _persistedProgress = super.saveProgress(progress);
    _persist();
    return _persistedProgress;
  }

  @override
  void clearProgress() {
    _persistedProgress = InMemoryStarterProgramRepository.defaultProgress;
    super.clearProgress();
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final Object? progressJson = storedState['progress'];
    if (progressJson is Map<String, dynamic>) {
      _persistedProgress = super.saveProgress(
        StarterProgramProgress.fromJson(progressJson),
      );
    }
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'progress': _persistedProgress.toJson(),
    });
  }
}
