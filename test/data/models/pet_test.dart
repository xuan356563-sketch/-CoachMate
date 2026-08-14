import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/pet.dart';

void main() {
  test('六种宠物使用稳定 ID，衡衡狸固定为 balance_raccoon', () {
    expect(
      PetSpecies.values.map((PetSpecies species) => species.id).toList(),
      <String>[
        'wind_fox',
        'jump_rabbit',
        'steady_turtle',
        'energy_dragon',
        'strength_bear',
        'balance_raccoon',
      ],
    );
    expect(PetSpecies.balanceRaccoon.id, 'balance_raccoon');
  });

  test('未知旧枚举值采用保守降级且不误认成其他物种', () {
    expect(PetSpecies.tryFromId('legacy_pet'), isNull);
    expect(PetStage.fromId('legacy_stage'), PetStage.patternEgg);
    expect(PetMood.fromId('legacy_mood'), PetMood.waiting);
  });

  test('宠物档案与伙伴 JSON 往返保留 UTC 时间和派生状态', () {
    final PetProfile profile = PetProfile(
      athleteProfileId: 'athlete-1',
      activePetId: 'pet-1',
      firstEggSpecies: PetSpecies.balanceRaccoon,
      selectedShellId: 'shell-default',
      createdAt: DateTime.parse('2026-08-01T08:00:00+08:00'),
      updatedAt: DateTime.parse('2026-08-01T09:00:00+08:00'),
    );
    final PetCompanion companion = PetCompanion(
      id: 'pet-1',
      athleteProfileId: 'athlete-1',
      species: PetSpecies.balanceRaccoon,
      nickname: '衡衡',
      unlockedAt: DateTime.parse('2026-08-01T08:00:00+08:00'),
      bornAt: DateTime.parse('2026-08-01T08:05:00+08:00'),
      selectedAccessoryId: 'headband-1',
      selectedBadgeId: null,
      createdAt: DateTime.parse('2026-08-01T08:00:00+08:00'),
      updatedAt: DateTime.parse('2026-08-01T09:00:00+08:00'),
      totalEnergy: 3700,
      stage: PetStage.champion,
      partnerStars: 1,
      mood: PetMood.happy,
    );

    final PetProfile restoredProfile = PetProfile.fromJson(profile.toJson());
    final PetCompanion restoredCompanion =
        PetCompanion.fromJson(companion.toJson());

    expect(restoredProfile.toJson(), profile.toJson());
    expect(restoredCompanion.toJson(), companion.toJson());
    expect(restoredProfile.createdAt.isUtc, isTrue);
    expect(restoredCompanion.bornAt.isUtc, isTrue);
  });

  test('每日能量账本 JSON 往返保留本地日期、来源快照与结算值', () {
    final PetDailyEnergy energy = PetDailyEnergy(
      athleteProfileId: 'athlete-1',
      localDate: '2026-08-01',
      recipientPetId: 'pet-1',
      stepsEnergy: 20,
      standEnergy: 15,
      exerciseEnergy: 15,
      activeEnergy: 10,
      trainingEnergy: 100,
      recoveryEnergy: 0,
      calculatedTotal: 160,
      awardedTotal: 160,
      sourceSnapshot: const <String, Object?>{
        'steps': 8000,
        'hasValidTraining': true,
      },
      modelVersion: 1,
      settledAt: DateTime.parse('2026-08-01T12:00:00+08:00'),
      updatedAt: DateTime.parse('2026-08-01T12:05:00+08:00'),
    );

    final PetDailyEnergy restored = PetDailyEnergy.fromJson(energy.toJson());

    expect(restored.toJson(), energy.toJson());
    expect(restored.localDate, '2026-08-01');
    expect(restored.settledAt.isUtc, isTrue);
    expect(restored.awardedTotal, 160);
  });

  test('每日能量账本拒绝非 yyyy-MM-dd 本地日期', () {
    expect(
      () => PetDailyEnergy.fromJson(<String, Object?>{
        'localDate': '2026/08/01',
        'settledAt': '2026-08-01T00:00:00.000Z',
        'updatedAt': '2026-08-01T00:00:00.000Z',
      }),
      throwsFormatException,
    );
  });

  test('结算结果和解锁进度暴露稳定的消费端行为', () {
    const PetSettlementResult settlement = PetSettlementResult(
      recipientPetId: 'pet-1',
      calculatedTotal: 90,
      awardedTotal: 100,
      awardedDelta: 10,
      didLockRecipient: true,
    );
    const PetUnlockProgress progress = PetUnlockProgress(
      species: PetSpecies.balanceRaccoon,
      current: 3,
      target: 4,
      isUnlocked: false,
    );

    expect(settlement.awardedDelta, 10);
    expect(settlement.didLockRecipient, isTrue);
    expect(progress.fraction, 0.75);
  });
}
