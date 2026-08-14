import 'dart:math' as math;

class PetEnergyInput {
  const PetEnergyInput({
    this.steps,
    this.stepGoal,
    this.standHours,
    this.standGoalHours,
    this.exerciseMinutes,
    this.exerciseGoalMinutes,
    this.activeEnergyKcal,
    this.activeEnergyGoalKcal,
    this.hasValidTraining = false,
    this.hasAcceptedRecoveryDecision = false,
  });

  final num? steps;
  final num? stepGoal;
  final num? standHours;
  final num? standGoalHours;
  final num? exerciseMinutes;
  final num? exerciseGoalMinutes;
  final num? activeEnergyKcal;
  final num? activeEnergyGoalKcal;
  final bool hasValidTraining;
  final bool hasAcceptedRecoveryDecision;
}

class PetEnergyBreakdown {
  const PetEnergyBreakdown({
    required this.stepsEnergy,
    required this.standEnergy,
    required this.exerciseEnergy,
    required this.activeEnergy,
    required this.activityTotal,
    required this.trainingEnergy,
    required this.recoveryEnergy,
    required this.total,
  });

  final int stepsEnergy;
  final int standEnergy;
  final int exerciseEnergy;
  final int activeEnergy;
  final int activityTotal;
  final int trainingEnergy;
  final int recoveryEnergy;
  final int total;

  Map<String, int> toJson() => <String, int>{
        'stepsEnergy': stepsEnergy,
        'standEnergy': standEnergy,
        'exerciseEnergy': exerciseEnergy,
        'activeEnergy': activeEnergy,
        'activityTotal': activityTotal,
        'trainingEnergy': trainingEnergy,
        'recoveryEnergy': recoveryEnergy,
        'total': total,
      };
}

/// 宠物能量计算保持为纯函数，不读取时间、仓储或状态容器。
class PetEnergyCalculator {
  const PetEnergyCalculator();

  PetEnergyBreakdown calculate(PetEnergyInput input) {
    final int stepsEnergy = _scaledEnergy(input.steps, input.stepGoal, 20);
    final int standEnergy =
        _scaledEnergy(input.standHours, input.standGoalHours, 15);
    final int exerciseEnergy = _scaledEnergy(
      input.exerciseMinutes,
      input.exerciseGoalMinutes,
      15,
    );
    final int activeEnergy = _scaledEnergy(
      input.activeEnergyKcal,
      input.activeEnergyGoalKcal,
      10,
    );
    final int activityTotal = math.min(
      60,
      stepsEnergy + standEnergy + exerciseEnergy + activeEnergy,
    );
    final int trainingEnergy = input.hasValidTraining ? 100 : 0;
    final int recoveryEnergy = input.hasValidTraining
        ? 0
        : input.hasAcceptedRecoveryDecision
            ? 60
            : 0;
    final int total = math.min(
      160,
      activityTotal + math.max(trainingEnergy, recoveryEnergy),
    );

    return PetEnergyBreakdown(
      stepsEnergy: stepsEnergy,
      standEnergy: standEnergy,
      exerciseEnergy: exerciseEnergy,
      activeEnergy: activeEnergy,
      activityTotal: activityTotal,
      trainingEnergy: trainingEnergy,
      recoveryEnergy: recoveryEnergy,
      total: total,
    );
  }
}

int _scaledEnergy(num? value, num? goal, int maximum) {
  if (value == null ||
      goal == null ||
      !value.isFinite ||
      !goal.isFinite ||
      goal <= 0) {
    return 0;
  }
  final double ratio = (value / goal).clamp(0, 1).toDouble();
  return (maximum * ratio).floor();
}
