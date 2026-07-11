import '../models/motion_check.dart';
import '../../services/local_storage_service.dart';

abstract class MotionAnalysisRepository {
  List<MotionAnalysisResult> listResults();

  MotionAnalysisResult saveResult(MotionAnalysisResult result);

  void clearResults();
}

class InMemoryMotionAnalysisRepository implements MotionAnalysisRepository {
  final List<MotionAnalysisResult> _results = [];

  @override
  List<MotionAnalysisResult> listResults() {
    _sortResults();
    return List<MotionAnalysisResult>.unmodifiable(_results);
  }

  @override
  MotionAnalysisResult saveResult(MotionAnalysisResult result) {
    _results.removeWhere((MotionAnalysisResult item) => item.id == result.id);
    _results.insert(0, result);
    _sortResults();
    return result;
  }

  @override
  void clearResults() {
    _results.clear();
  }

  void _sortResults() {
    _results.sort(
      (MotionAnalysisResult a, MotionAnalysisResult b) =>
          b.capturedAt.compareTo(a.capturedAt),
    );
  }
}

class PersistedMotionAnalysisRepository implements MotionAnalysisRepository {
  static const String storageKey = 'trainflow.motion_analysis_results.v1';
  static const int _maxSavedResults = 50;

  final LocalStorageService _storageService;
  final List<MotionAnalysisResult> _results = [];

  PersistedMotionAnalysisRepository(this._storageService) {
    _hydrate();
  }

  @override
  List<MotionAnalysisResult> listResults() {
    _sortResults();
    return List<MotionAnalysisResult>.unmodifiable(_results);
  }

  @override
  MotionAnalysisResult saveResult(MotionAnalysisResult result) {
    _results.removeWhere((MotionAnalysisResult item) => item.id == result.id);
    _results.insert(0, result);
    _sortResults();
    if (_results.length > _maxSavedResults) {
      _results.removeRange(_maxSavedResults, _results.length);
    }
    _persist();
    return result;
  }

  @override
  void clearResults() {
    _results.clear();
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final List<dynamic> resultItems =
        storedState['results'] as List<dynamic>? ?? const [];
    _results.addAll(
      resultItems
          .whereType<Map<String, dynamic>>()
          .map(MotionAnalysisResult.fromJson)
          .toList(),
    );
    _sortResults();
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'results': _results
          .map((MotionAnalysisResult result) => result.toJson())
          .toList(),
    });
  }

  void _sortResults() {
    _results.sort(
      (MotionAnalysisResult a, MotionAnalysisResult b) =>
          b.capturedAt.compareTo(a.capturedAt),
    );
  }
}
