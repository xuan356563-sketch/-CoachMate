import '../data/models/daily_activity_summary.dart';

/// 宠物日常活动使用的四项目标。
class PetActivityGoals {
  const PetActivityGoals({
    required this.stepGoal,
    required this.standGoalHours,
    required this.exerciseGoalMinutes,
    required this.activeEnergyGoalKcal,
  });

  final int stepGoal;
  final int standGoalHours;
  final int exerciseGoalMinutes;
  final double activeEnergyGoalKcal;
}

/// 根据最近 14 个有效自然日生成目标建议，但不负责持久化或自动应用。
class PetGoalSuggestionService {
  const PetGoalSuggestionService();

  static const PetActivityGoals defaultGoals = PetActivityGoals(
    stepGoal: 6000,
    standGoalHours: 10,
    exerciseGoalMinutes: 30,
    activeEnergyGoalKcal: 300,
  );

  PetActivityGoals? suggest(List<DailyActivitySummary> summaries) {
    final Map<String, DailyActivitySummary> latestByDate =
        <String, DailyActivitySummary>{};
    for (final DailyActivitySummary summary in summaries) {
      if (!_isValidNaturalDay(summary)) continue;
      final DailyActivitySummary? existing = latestByDate[summary.localDate];
      if (existing == null || summary.syncedAt.isAfter(existing.syncedAt)) {
        latestByDate[summary.localDate] = summary;
      }
    }
    if (latestByDate.length < 14) return null;

    final List<DailyActivitySummary> recent = latestByDate.values.toList()
      ..sort(
        (DailyActivitySummary left, DailyActivitySummary right) =>
            right.localDate.compareTo(left.localDate),
      );
    final List<DailyActivitySummary> window = recent.take(14).toList();
    return PetActivityGoals(
      stepGoal: _median(
        window.map((DailyActivitySummary item) => item.steps!.toDouble()),
      ).round(),
      standGoalHours: _median(
        window.map(
          (DailyActivitySummary item) => item.standHours!.toDouble(),
        ),
      ).round(),
      exerciseGoalMinutes: _median(
        window.map(
          (DailyActivitySummary item) => item.exerciseMinutes!.toDouble(),
        ),
      ).round(),
      activeEnergyGoalKcal: _median(
        window.map(
          (DailyActivitySummary item) => item.activeEnergyKcal!,
        ),
      ),
    );
  }
}

bool _isValidNaturalDay(DailyActivitySummary summary) {
  return summary.steps != null &&
      summary.standHours != null &&
      summary.exerciseMinutes != null &&
      summary.activeEnergyKcal?.isFinite == true &&
      summary.sourceFor(DailyActivityField.steps) !=
          ActivityFieldSource.unavailable &&
      summary.sourceFor(DailyActivityField.standHours) !=
          ActivityFieldSource.unavailable &&
      summary.sourceFor(DailyActivityField.exerciseMinutes) !=
          ActivityFieldSource.unavailable &&
      summary.sourceFor(DailyActivityField.activeEnergyKcal) !=
          ActivityFieldSource.unavailable;
}

double _median(Iterable<double> values) {
  final List<double> sorted = values.toList()..sort();
  final int middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}
