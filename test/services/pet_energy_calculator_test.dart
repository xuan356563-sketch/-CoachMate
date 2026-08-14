import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/services/pet_energy_calculator.dart';

void main() {
  const PetEnergyCalculator calculator = PetEnergyCalculator();

  group('四项日常活动能量', () {
    final Map<String, List<int>> expectedByMetric = <String, List<int>>{
      'steps': <int>[0, 10, 20, 20, 0, 0],
      'stand': <int>[0, 7, 15, 15, 0, 0],
      'exercise': <int>[0, 7, 15, 15, 0, 0],
      'active': <int>[0, 5, 10, 10, 0, 0],
    };
    final List<({num? value, num? goal})> cases = <({num? value, num? goal})>[
      (value: 0, goal: 100),
      (value: 50, goal: 100),
      (value: 100, goal: 100),
      (value: 150, goal: 100),
      (value: 100, goal: null),
      (value: 100, goal: 0),
    ];

    for (final String metric in expectedByMetric.keys) {
      test('$metric 覆盖 0、50%、100%、超额、缺失目标和零目标', () {
        final List<int> actual = <int>[];
        for (final ({num? value, num? goal}) item in cases) {
          final PetEnergyBreakdown result = calculator.calculate(
            _inputForMetric(metric, value: item.value, goal: item.goal),
          );
          actual.add(switch (metric) {
            'steps' => result.stepsEnergy,
            'stand' => result.standEnergy,
            'exercise' => result.exerciseEnergy,
            _ => result.activeEnergy,
          });
        }

        expect(actual, expectedByMetric[metric]);
      });
    }
  });

  test('日常活动封顶 60，训练与恢复互斥且每日总量封顶 160', () {
    const PetEnergyInput fullActivity = PetEnergyInput(
      steps: 8000,
      stepGoal: 6000,
      standHours: 12,
      standGoalHours: 10,
      exerciseMinutes: 45,
      exerciseGoalMinutes: 30,
      activeEnergyKcal: 450,
      activeEnergyGoalKcal: 300,
    );

    final PetEnergyBreakdown activity = calculator.calculate(fullActivity);
    final PetEnergyBreakdown trainingWins = calculator.calculate(
      const PetEnergyInput(
        steps: 8000,
        stepGoal: 6000,
        standHours: 12,
        standGoalHours: 10,
        exerciseMinutes: 45,
        exerciseGoalMinutes: 30,
        activeEnergyKcal: 450,
        activeEnergyGoalKcal: 300,
        hasValidTraining: true,
        hasAcceptedRecoveryDecision: true,
      ),
    );
    final PetEnergyBreakdown recovery = calculator.calculate(
      const PetEnergyInput(hasAcceptedRecoveryDecision: true),
    );

    expect(activity.activityTotal, 60);
    expect(activity.total, 60);
    expect(trainingWins.trainingEnergy, 100);
    expect(trainingWins.recoveryEnergy, 0);
    expect(trainingWins.total, 160);
    expect(recovery.trainingEnergy, 0);
    expect(recovery.recoveryEnergy, 60);
    expect(recovery.total, 60);
  });
}

PetEnergyInput _inputForMetric(
  String metric, {
  required num? value,
  required num? goal,
}) {
  return switch (metric) {
    'steps' => PetEnergyInput(steps: value, stepGoal: goal),
    'stand' => PetEnergyInput(standHours: value, standGoalHours: goal),
    'exercise' => PetEnergyInput(
        exerciseMinutes: value,
        exerciseGoalMinutes: goal,
      ),
    'active' => PetEnergyInput(
        activeEnergyKcal: value,
        activeEnergyGoalKcal: goal,
      ),
    _ => throw ArgumentError.value(metric, 'metric', '未知测试指标'),
  };
}
