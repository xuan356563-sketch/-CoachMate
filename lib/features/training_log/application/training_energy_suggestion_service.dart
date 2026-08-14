import '../../../data/models/training_log.dart';

class TrainingEnergySuggestion {
  const TrainingEnergySuggestion({
    required this.workoutId,
    required this.energyKcal,
  });

  final String workoutId;
  final double energyKcal;
}

class TrainingEnergySuggestionService {
  const TrainingEnergySuggestionService();

  TrainingEnergySuggestion? select({
    required List<Map<String, Object?>> rows,
    required TrainingActivityType activityType,
    required DateTime localDate,
    required DateTime expectedStart,
    required int expectedDurationMinutes,
  }) {
    final String localDateKey = _dateKey(localDate);
    final List<_ScoredEnergySuggestion> candidates = rows
        .where((Map<String, Object?> row) => row['source_kind'] == 'healthKit')
        .where((Map<String, Object?> row) => row['local_date'] == localDateKey)
        .where(
          (Map<String, Object?> row) => _isCompatible(
            activityType,
            row['discipline'] as String?,
          ),
        )
        .map(
          (Map<String, Object?> row) => _score(
            row,
            expectedStart: expectedStart,
            expectedDurationMinutes: expectedDurationMinutes,
          ),
        )
        .whereType<_ScoredEnergySuggestion>()
        .toList(growable: false)
      ..sort(
        (_ScoredEnergySuggestion first, _ScoredEnergySuggestion second) =>
            first.score.compareTo(second.score),
      );
    if (candidates.isEmpty) return null;
    if (candidates.length > 1 && candidates[0].score == candidates[1].score) {
      return null;
    }
    return candidates.first.suggestion;
  }

  _ScoredEnergySuggestion? _score(
    Map<String, Object?> row, {
    required DateTime expectedStart,
    required int expectedDurationMinutes,
  }) {
    final String workoutId = (row['id'] as String? ?? '').trim();
    final DateTime? startedAt =
        DateTime.tryParse(row['started_at_utc'] as String? ?? '');
    final int? durationSeconds =
        (row['elapsed_duration_seconds'] as num?)?.toInt();
    final double? energyKcal = (row['energy_kcal'] as num?)?.toDouble();
    if (workoutId.isEmpty ||
        startedAt == null ||
        durationSeconds == null ||
        durationSeconds <= 0 ||
        energyKcal == null ||
        !energyKcal.isFinite ||
        energyKcal <= 0 ||
        energyKcal > 5000) {
      return null;
    }
    final int startDifference =
        startedAt.difference(expectedStart).inMinutes.abs();
    final int durationDifference =
        (durationSeconds ~/ 60 - expectedDurationMinutes).abs();
    if (startDifference > 180 || durationDifference > 120) return null;
    return _ScoredEnergySuggestion(
      suggestion: TrainingEnergySuggestion(
        workoutId: workoutId,
        energyKcal: energyKcal,
      ),
      score: startDifference + durationDifference,
    );
  }
}

class _ScoredEnergySuggestion {
  const _ScoredEnergySuggestion({
    required this.suggestion,
    required this.score,
  });

  final TrainingEnergySuggestion suggestion;
  final int score;
}

bool _isCompatible(TrainingActivityType activityType, String? discipline) {
  final String normalized = discipline?.trim() ?? '';
  if (normalized.isEmpty || activityType == TrainingActivityType.custom) {
    return false;
  }
  final Set<String> compatible = switch (activityType) {
    TrainingActivityType.running => <String>{'running', 'roadRun', 'trailRun'},
    TrainingActivityType.fastWalking => <String>{'walking', 'roadRun'},
    TrainingActivityType.hiking => <String>{'hiking', 'trailRun'},
    TrainingActivityType.strength => <String>{'strength'},
    _ => <String>{activityType.jsonValue},
  };
  return compatible.contains(normalized);
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
