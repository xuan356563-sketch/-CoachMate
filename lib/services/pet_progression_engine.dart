import 'dart:math' as math;

import 'package:trainflow_ai/data/models/daily_activity_summary.dart';
import 'package:trainflow_ai/data/models/pet.dart';

class PetUnlockFacts {
  const PetUnlockFacts({
    this.activitySummaries = const <DailyActivitySummary>[],
    this.validTrainingCountsByDate = const <String, int>{},
    this.acceptedRecoveryCountsByDate = const <String, int>{},
  });

  final List<DailyActivitySummary> activitySummaries;
  final Map<String, int> validTrainingCountsByDate;
  final Map<String, int> acceptedRecoveryCountsByDate;
}

/// 根据不可变事实推导阶段、心情和解锁进度。
class PetProgressionEngine {
  const PetProgressionEngine();

  PetStage stageForEnergy(int totalEnergy) {
    final int normalized = math.max(0, totalEnergy);
    if (normalized >= 3600) return PetStage.champion;
    if (normalized >= 2100) return PetStage.advanced;
    if (normalized >= 900) return PetStage.junior;
    if (normalized >= 150) return PetStage.sprout;
    return PetStage.patternEgg;
  }

  int partnerStars(int totalEnergy) {
    return (math.max(totalEnergy - 3600, 0) / 100).floor();
  }

  PetMood moodFor({
    required int todayEnergy,
    required int daysSinceLastRecord,
  }) {
    if (todayEnergy >= 80) return PetMood.excited;
    if (todayEnergy >= 30) return PetMood.happy;
    if (todayEnergy >= 1) return PetMood.curious;
    return daysSinceLastRecord >= 3 ? PetMood.waiting : PetMood.calm;
  }

  PetUnlockProgress unlockProgress(
    PetSpecies species,
    PetUnlockFacts facts,
  ) {
    return switch (species) {
      PetSpecies.windFox => _simpleProgress(
          species,
          _matchingDates(
            facts.activitySummaries,
            (DailyActivitySummary summary) =>
                _reachesRatio(summary.steps, summary.stepGoal, 0.8),
          ),
          3,
        ),
      PetSpecies.jumpRabbit => _simpleProgress(
          species,
          _matchingDates(
            facts.activitySummaries,
            (DailyActivitySummary summary) =>
                (summary.exerciseMinutes ?? 0) >= 30,
          ),
          3,
        ),
      PetSpecies.steadyTurtle => _simpleProgress(
          species,
          _matchingDates(
            facts.activitySummaries,
            (DailyActivitySummary summary) => (summary.standHours ?? 0) >= 10,
          ),
          5,
        ),
      PetSpecies.energyDragon => _simpleProgress(
          species,
          _matchingDates(
            facts.activitySummaries,
            (DailyActivitySummary summary) => _reachesRatio(
              summary.activeEnergyKcal,
              summary.activeEnergyGoalKcal,
              0.8,
            ),
          ),
          3,
        ),
      PetSpecies.strengthBear => _simpleProgress(
          species,
          facts.validTrainingCountsByDate.values.fold<int>(
            0,
            (int total, int count) => total + math.max(0, count),
          ),
          3,
        ),
      PetSpecies.balanceRaccoon => _balanceProgress(facts),
    };
  }

  PetUnlockProgress _simpleProgress(
    PetSpecies species,
    int current,
    int target,
  ) {
    return PetUnlockProgress(
      species: species,
      current: math.min(math.max(0, current), target),
      target: target,
      isUnlocked: current >= target,
    );
  }

  int _matchingDates(
    List<DailyActivitySummary> summaries,
    bool Function(DailyActivitySummary summary) matches,
  ) {
    return summaries
        .where(matches)
        .map((DailyActivitySummary summary) => summary.localDate)
        .toSet()
        .length;
  }

  PetUnlockProgress _balanceProgress(PetUnlockFacts facts) {
    final Map<String, List<DailyActivitySummary>> summariesByWeek =
        <String, List<DailyActivitySummary>>{};
    final Set<String> weekKeys = <String>{};
    for (final DailyActivitySummary summary in facts.activitySummaries) {
      final String? key = _naturalWeekKey(summary.localDate);
      if (key == null) continue;
      weekKeys.add(key);
      summariesByWeek.putIfAbsent(key, () => <DailyActivitySummary>[]).add(
            summary,
          );
    }
    for (final String localDate in <String>{
      ...facts.validTrainingCountsByDate.keys,
      ...facts.acceptedRecoveryCountsByDate.keys,
    }) {
      final String? key = _naturalWeekKey(localDate);
      if (key != null) weekKeys.add(key);
    }

    int bestCurrent = 0;
    bool unlocked = false;
    for (final String weekKey in weekKeys) {
      final List<DailyActivitySummary> weekSummaries =
          summariesByWeek[weekKey] ?? const <DailyActivitySummary>[];
      final int stepsDays = _matchingDates(
        weekSummaries,
        (DailyActivitySummary summary) =>
            _reachesRatio(summary.steps, summary.stepGoal, 0.6),
      );
      final int standDays = _matchingDates(
        weekSummaries,
        (DailyActivitySummary summary) =>
            _reachesRatio(summary.standHours, summary.standGoalHours, 0.6),
      );
      final int exerciseDays = _matchingDates(
        weekSummaries,
        (DailyActivitySummary summary) => _reachesRatio(
          summary.exerciseMinutes,
          summary.exerciseGoalMinutes,
          0.6,
        ),
      );
      final int activeDays = _matchingDates(
        weekSummaries,
        (DailyActivitySummary summary) => _reachesRatio(
          summary.activeEnergyKcal,
          summary.activeEnergyGoalKcal,
          0.6,
        ),
      );
      final int decisions = _decisionCountForWeek(facts, weekKey);
      final int current = (math.min(stepsDays, 4) +
              math.min(standDays, 4) +
              math.min(exerciseDays, 4) +
              math.min(activeDays, 4) +
              math.min(decisions, 2))
          .toInt();
      bestCurrent = math.max(bestCurrent, current);
      unlocked = unlocked ||
          (stepsDays >= 4 &&
              standDays >= 4 &&
              exerciseDays >= 4 &&
              activeDays >= 4 &&
              decisions >= 2);
    }

    return PetUnlockProgress(
      species: PetSpecies.balanceRaccoon,
      current: bestCurrent,
      target: 18,
      isUnlocked: unlocked,
    );
  }

  int _decisionCountForWeek(PetUnlockFacts facts, String weekKey) {
    int total = 0;
    for (final MapEntry<String, int> entry
        in facts.validTrainingCountsByDate.entries) {
      if (_naturalWeekKey(entry.key) == weekKey) {
        total += math.max(0, entry.value);
      }
    }
    for (final MapEntry<String, int> entry
        in facts.acceptedRecoveryCountsByDate.entries) {
      if (_naturalWeekKey(entry.key) == weekKey) {
        total += math.max(0, entry.value);
      }
    }
    return total;
  }
}

bool _reachesRatio(num? value, num? goal, double threshold) {
  if (value == null ||
      goal == null ||
      !value.isFinite ||
      !goal.isFinite ||
      goal <= 0) {
    return false;
  }
  return value / goal >= threshold;
}

String? _naturalWeekKey(String localDate) {
  final DateTime? date = DateTime.tryParse(localDate);
  if (date == null) return null;
  final DateTime monday = date.subtract(Duration(days: date.weekday - 1));
  return '${monday.year.toString().padLeft(4, '0')}-'
      '${monday.month.toString().padLeft(2, '0')}-'
      '${monday.day.toString().padLeft(2, '0')}';
}
