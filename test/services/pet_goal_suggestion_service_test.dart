import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/daily_activity_summary.dart';
import 'package:trainflow_ai/services/pet_goal_suggestion_service.dart';

void main() {
  const PetGoalSuggestionService service = PetGoalSuggestionService();

  test('只有 13 个有效自然日时不生成目标建议', () {
    final List<DailyActivitySummary> summaries =
        List<DailyActivitySummary>.generate(
      13,
      (int index) => _summary(
        day: index + 1,
        steps: 5000 + index * 100,
        standHours: 8,
        exerciseMinutes: 25,
        activeEnergyKcal: 280,
      ),
    );

    expect(service.suggest(summaries), isNull);
  });

  test('14 个有效自然日按四项实际值的中位数生成建议', () {
    const List<int> steps = <int>[
      1000,
      2000,
      3000,
      4000,
      5000,
      5500,
      6000,
      6000,
      6500,
      7000,
      8000,
      9000,
      10000,
      11000,
    ];
    const List<int> standHours = <int>[
      2,
      3,
      4,
      5,
      6,
      8,
      10,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
    ];
    const List<int> exerciseMinutes = <int>[
      5,
      10,
      15,
      20,
      25,
      28,
      30,
      30,
      35,
      40,
      45,
      50,
      55,
      60,
    ];
    const List<double> activeEnergy = <double>[
      100,
      150,
      200,
      220,
      250,
      280,
      300,
      300,
      330,
      350,
      380,
      400,
      450,
      500,
    ];
    final List<DailyActivitySummary> summaries =
        List<DailyActivitySummary>.generate(
      14,
      (int index) => _summary(
        day: index + 1,
        steps: steps[index],
        standHours: standHours[index],
        exerciseMinutes: exerciseMinutes[index],
        activeEnergyKcal: activeEnergy[index],
      ),
    );

    final PetActivityGoals? suggestion = service.suggest(summaries);

    expect(suggestion, isNotNull);
    expect(suggestion!.stepGoal, 6000);
    expect(suggestion.standGoalHours, 10);
    expect(suggestion.exerciseGoalMinutes, 30);
    expect(suggestion.activeEnergyGoalKcal, 300);
  });
}

DailyActivitySummary _summary({
  required int day,
  required int steps,
  required int standHours,
  required int exerciseMinutes,
  required double activeEnergyKcal,
}) {
  return DailyActivitySummary(
    athleteProfileId: 'athlete-a',
    localDate: '2026-07-${day.toString().padLeft(2, '0')}',
    timeZoneName: 'Asia/Shanghai',
    timeZoneOffsetMinutes: 480,
    steps: steps,
    stepGoal: 6000,
    activeEnergyKcal: activeEnergyKcal,
    activeEnergyGoalKcal: 300,
    exerciseMinutes: exerciseMinutes,
    exerciseGoalMinutes: 30,
    standHours: standHours,
    standGoalHours: 10,
    fieldSources: const <DailyActivityField, ActivityFieldSource>{
      DailyActivityField.steps: ActivityFieldSource.healthKit,
      DailyActivityField.activeEnergyKcal: ActivityFieldSource.healthKit,
      DailyActivityField.exerciseMinutes: ActivityFieldSource.healthKit,
      DailyActivityField.standHours: ActivityFieldSource.healthKit,
    },
    syncedAt: DateTime.utc(2026, 7, day, 12),
  );
}
