import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/daily_activity_summary.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/services/pet_progression_engine.dart';

void main() {
  const PetProgressionEngine engine = PetProgressionEngine();

  test('五阶段在每个能量边界确定性切换', () {
    const List<({int energy, PetStage stage})> cases =
        <({int energy, PetStage stage})>[
      (energy: -1, stage: PetStage.patternEgg),
      (energy: 0, stage: PetStage.patternEgg),
      (energy: 149, stage: PetStage.patternEgg),
      (energy: 150, stage: PetStage.sprout),
      (energy: 899, stage: PetStage.sprout),
      (energy: 900, stage: PetStage.junior),
      (energy: 2099, stage: PetStage.junior),
      (energy: 2100, stage: PetStage.advanced),
      (energy: 3599, stage: PetStage.advanced),
      (energy: 3600, stage: PetStage.champion),
    ];

    for (final ({int energy, PetStage stage}) item in cases) {
      expect(engine.stageForEnergy(item.energy), item.stage);
    }
  });

  test('冠军后每满 100 能量增加一颗伙伴星', () {
    expect(engine.partnerStars(3599), 0);
    expect(engine.partnerStars(3600), 0);
    expect(engine.partnerStars(3699), 0);
    expect(engine.partnerStars(3700), 1);
  });

  test('心情只由今日能量和距最近记录天数确定', () {
    expect(
      engine.moodFor(todayEnergy: 80, daysSinceLastRecord: 0),
      PetMood.excited,
    );
    expect(
      engine.moodFor(todayEnergy: 30, daysSinceLastRecord: 0),
      PetMood.happy,
    );
    expect(
      engine.moodFor(todayEnergy: 1, daysSinceLastRecord: 0),
      PetMood.curious,
    );
    expect(
      engine.moodFor(todayEnergy: 0, daysSinceLastRecord: 2),
      PetMood.calm,
    );
    expect(
      engine.moodFor(todayEnergy: 0, daysSinceLastRecord: 3),
      PetMood.waiting,
    );
  });

  test('风步狐需要三个不同日期达到步数目标 80%', () {
    final PetUnlockProgress before = engine.unlockProgress(
      PetSpecies.windFox,
      PetUnlockFacts(
        activitySummaries: <DailyActivitySummary>[
          _summary('2026-07-27', steps: 80, stepGoal: 100),
          _summary('2026-07-28', steps: 90, stepGoal: 100),
        ],
      ),
    );
    final PetUnlockProgress reached = engine.unlockProgress(
      PetSpecies.windFox,
      PetUnlockFacts(
        activitySummaries: <DailyActivitySummary>[
          _summary('2026-07-27', steps: 80, stepGoal: 100),
          _summary('2026-07-28', steps: 90, stepGoal: 100),
          _summary('2026-07-29', steps: 120, stepGoal: 100),
        ],
      ),
    );

    expect(before.current, 2);
    expect(before.isUnlocked, isFalse);
    expect(reached.current, 3);
    expect(reached.isUnlocked, isTrue);
  });

  test('跃动兔需要三个不同日期运动满 30 分钟', () {
    final PetUnlockProgress progress = engine.unlockProgress(
      PetSpecies.jumpRabbit,
      PetUnlockFacts(
        activitySummaries: <DailyActivitySummary>[
          _summary('2026-07-27', exerciseMinutes: 30),
          _summary('2026-07-28', exerciseMinutes: 29),
          _summary('2026-07-29', exerciseMinutes: 45),
          _summary('2026-07-30', exerciseMinutes: 30),
        ],
      ),
    );

    expect(progress.current, 3);
    expect(progress.target, 3);
    expect(progress.isUnlocked, isTrue);
  });

  test('立稳龟需要五个不同日期站立满 10 小时', () {
    final PetUnlockProgress progress = engine.unlockProgress(
      PetSpecies.steadyTurtle,
      PetUnlockFacts(
        activitySummaries: <DailyActivitySummary>[
          for (int day = 27; day <= 31; day += 1)
            _summary('2026-07-$day', standHours: 10),
        ],
      ),
    );

    expect(progress.current, 5);
    expect(progress.isUnlocked, isTrue);
  });

  test('燃能龙需要三个不同日期达到活动能量目标 80%', () {
    final PetUnlockProgress progress = engine.unlockProgress(
      PetSpecies.energyDragon,
      PetUnlockFacts(
        activitySummaries: <DailyActivitySummary>[
          _summary(
            '2026-07-27',
            activeEnergyKcal: 240,
            activeEnergyGoalKcal: 300,
          ),
          _summary(
            '2026-07-28',
            activeEnergyKcal: 300,
            activeEnergyGoalKcal: 300,
          ),
          _summary(
            '2026-07-29',
            activeEnergyKcal: 360,
            activeEnergyGoalKcal: 300,
          ),
        ],
      ),
    );

    expect(progress.current, 3);
    expect(progress.isUnlocked, isTrue);
  });

  test('力练熊按有效训练次数累计到三次', () {
    final PetUnlockProgress progress = engine.unlockProgress(
      PetSpecies.strengthBear,
      const PetUnlockFacts(
        validTrainingCountsByDate: <String, int>{
          '2026-07-27': 2,
          '2026-07-28': 1,
        },
      ),
    );

    expect(progress.current, 3);
    expect(progress.isUnlocked, isTrue);
  });

  test('袋小满要求同一自然周四项各四天达 60% 且有两次训练或恢复', () {
    final List<DailyActivitySummary> balancedDays = <DailyActivitySummary>[
      for (int day = 27; day <= 30; day += 1)
        _summary(
          '2026-07-$day',
          steps: 60,
          stepGoal: 100,
          activeEnergyKcal: 60,
          activeEnergyGoalKcal: 100,
          exerciseMinutes: 60,
          exerciseGoalMinutes: 100,
          standHours: 6,
          standGoalHours: 10,
        ),
    ];
    final PetUnlockProgress reached = engine.unlockProgress(
      PetSpecies.balanceRaccoon,
      PetUnlockFacts(
        activitySummaries: balancedDays,
        validTrainingCountsByDate: const <String, int>{
          '2026-07-27': 1,
        },
        acceptedRecoveryCountsByDate: const <String, int>{
          '2026-07-29': 1,
        },
      ),
    );
    final PetUnlockProgress splitAcrossWeeks = engine.unlockProgress(
      PetSpecies.balanceRaccoon,
      PetUnlockFacts(
        activitySummaries: <DailyActivitySummary>[
          balancedDays[0],
          balancedDays[1],
          _balancedSummary('2026-08-03'),
          _balancedSummary('2026-08-04'),
        ],
        validTrainingCountsByDate: const <String, int>{
          '2026-07-27': 1,
          '2026-08-03': 1,
        },
      ),
    );

    expect(reached.target, 18);
    expect(reached.current, 18);
    expect(reached.isUnlocked, isTrue);
    expect(splitAcrossWeeks.isUnlocked, isFalse);
  });
}

DailyActivitySummary _balancedSummary(String localDate) => _summary(
      localDate,
      steps: 60,
      stepGoal: 100,
      activeEnergyKcal: 60,
      activeEnergyGoalKcal: 100,
      exerciseMinutes: 60,
      exerciseGoalMinutes: 100,
      standHours: 6,
      standGoalHours: 10,
    );

DailyActivitySummary _summary(
  String localDate, {
  int? steps,
  int? stepGoal,
  double? activeEnergyKcal,
  double? activeEnergyGoalKcal,
  int? exerciseMinutes,
  int? exerciseGoalMinutes,
  int? standHours,
  int? standGoalHours,
}) {
  return DailyActivitySummary(
    athleteProfileId: 'athlete-1',
    localDate: localDate,
    timeZoneName: 'America/Los_Angeles',
    timeZoneOffsetMinutes: -420,
    steps: steps,
    stepGoal: stepGoal,
    activeEnergyKcal: activeEnergyKcal,
    activeEnergyGoalKcal: activeEnergyGoalKcal,
    exerciseMinutes: exerciseMinutes,
    exerciseGoalMinutes: exerciseGoalMinutes,
    standHours: standHours,
    standGoalHours: standGoalHours,
    syncedAt: DateTime.utc(2026, 8, 1),
  );
}
