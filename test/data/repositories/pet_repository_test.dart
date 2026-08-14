import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/data/repositories/pet_repository.dart';
import 'package:trainflow_ai/services/pet_energy_calculator.dart';

void main() {
  late _MemoryPetGateway gateway;
  late PetRepository repository;

  setUp(() {
    gateway = _MemoryPetGateway();
    repository = PetRepository(gateway);
  });

  test('伙伴累计能量只汇总 recipient_pet_id 并推导阶段、星级和心情', () async {
    gateway
      ..profiles['athlete-a'] = _profileRow(
        athleteProfileId: 'athlete-a',
        activePetId: 'pet-a',
      )
      ..collection.addAll(<Map<String, Object?>>[
        _collectionRow(
          petId: 'pet-a',
          athleteProfileId: 'athlete-a',
          species: PetSpecies.balanceRaccoon,
        ),
        _collectionRow(
          petId: 'pet-b',
          athleteProfileId: 'athlete-a',
          species: PetSpecies.windFox,
        ),
      ])
      ..energy.addAll(<Map<String, Object?>>[
        _energyRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-07-26',
          recipientPetId: 'pet-a',
          awardedTotal: 160,
        ),
        _energyRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-07-27',
          recipientPetId: 'pet-a',
          awardedTotal: 160,
        ),
        _energyRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-07-28',
          recipientPetId: 'pet-a',
          awardedTotal: 160,
        ),
        _energyRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-07-29',
          recipientPetId: 'pet-a',
          awardedTotal: 160,
        ),
        _energyRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-07-30',
          recipientPetId: 'pet-a',
          awardedTotal: 160,
        ),
        _energyRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-07-31',
          recipientPetId: 'pet-a',
          awardedTotal: 100,
        ),
        _energyRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-08-01',
          recipientPetId: 'pet-a',
          awardedTotal: 50,
        ),
        _energyRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-08-01',
          recipientPetId: 'pet-b',
          awardedTotal: 160,
        ),
      ]);

    final PetCompanion? companion = await repository.loadCompanionState(
      athleteProfileId: 'athlete-a',
      localDate: '2026-08-01',
    );

    expect(companion?.id, 'pet-a');
    expect(companion?.totalEnergy, 950);
    expect(companion?.stage, PetStage.junior);
    expect(companion?.partnerStars, 0);
    expect(companion?.mood, PetMood.happy);
    expect(
        gateway.collection
            .singleWhere(
              (Map<String, Object?> row) => row['pet_id'] == 'pet-a',
            )
            .keys,
        isNot(contains('stage_id')));
  });

  test('能量账本行与模型往返保留来源快照和 UTC 时间', () async {
    gateway.energy.add(
      _energyRow(
        athleteProfileId: 'athlete-a',
        localDate: '2026-08-01',
        recipientPetId: 'pet-a',
        awardedTotal: 40,
        sourceSnapshot: const <String, Object?>{
          'activity': <String, Object?>{'steps': 6000},
        },
      ),
    );

    final List<PetDailyEnergy> values = await repository.listDailyEnergy(
      athleteProfileId: 'athlete-a',
    );

    expect(values, hasLength(1));
    expect(values.single.sourceSnapshot['activity'], <String, Object?>{
      'steps': 6000,
    });
    expect(values.single.settledAt, DateTime.utc(2026, 8, 1, 1));
    expect(values.single.awardedTotal, 40);
  });

  test('健康删除预览只统计四项活动能量，不包含训练和恢复奖励', () async {
    gateway.energy.addAll(<Map<String, Object?>>[
      _energyRow(
        athleteProfileId: 'athlete-a',
        localDate: '2026-08-01',
        recipientPetId: 'pet-a',
        awardedTotal: 140,
        stepsEnergy: 20,
        standEnergy: 10,
        exerciseEnergy: 5,
        activeEnergy: 5,
        trainingEnergy: 100,
      ),
      _energyRow(
        athleteProfileId: 'athlete-a',
        localDate: '2026-08-02',
        recipientPetId: 'pet-a',
        awardedTotal: 60,
        recoveryEnergy: 60,
      ),
      _energyRow(
        athleteProfileId: 'athlete-a',
        localDate: '2026-08-03',
        recipientPetId: 'pet-b',
        awardedTotal: 15,
        stepsEnergy: 15,
      ),
      _energyRow(
        athleteProfileId: 'athlete-b',
        localDate: '2026-08-01',
        recipientPetId: 'pet-c',
        awardedTotal: 20,
        stepsEnergy: 20,
      ),
    ]);

    final PetHealthDeletionImpact impact =
        await repository.previewHealthDeletionImpact('athlete-a');

    expect(impact.affectedDateCount, 2);
    expect(impact.removedHealthEnergy, 55);
    expect(
      impact.affectedLocalDates,
      <String>['2026-08-01', '2026-08-03'],
    );
  });

  test('首蛋、解锁和切换通过仓储后可从模型状态读取', () async {
    await repository.chooseFirstEgg(
      PetFirstEggWrite(
        companion: _petWrite(
          petId: 'pet-a',
          species: PetSpecies.balanceRaccoon,
        ),
        selectedShellId: 'shell-a',
      ),
    );
    await repository.unlockSpecies(
      _petWrite(petId: 'pet-b', species: PetSpecies.windFox),
    );
    await repository.switchActivePet(
      athleteProfileId: 'athlete-a',
      petId: 'pet-b',
      updatedAt: DateTime.utc(2026, 8, 2),
    );

    final PetProfile? profile = await repository.loadProfile('athlete-a');
    final PetCompanion? active = await repository.loadCompanionState(
      athleteProfileId: 'athlete-a',
      localDate: '2026-08-02',
    );

    expect(profile?.activePetId, 'pet-b');
    expect(profile?.firstEggSpecies, PetSpecies.balanceRaccoon);
    expect(profile?.selectedShellId, 'shell-a');
    expect(active?.species, PetSpecies.windFox);
  });

  test('结算结果通过仓储返回且不改变网关确定的接收者', () async {
    gateway.nextSettlementResult = const PetSettlementResult(
      recipientPetId: 'locked-pet',
      calculatedTotal: 90,
      awardedTotal: 120,
      awardedDelta: 30,
      didLockRecipient: false,
    );

    final PetSettlementResult result = await repository.settleDay(
      PetSettlementWrite(
        summary: null,
        athleteProfileId: 'athlete-a',
        localDate: '2026-08-01',
        activePetId: 'new-active-pet',
        breakdown: const PetEnergyBreakdown(
          stepsEnergy: 20,
          standEnergy: 10,
          exerciseEnergy: 10,
          activeEnergy: 10,
          activityTotal: 50,
          trainingEnergy: 40,
          recoveryEnergy: 0,
          total: 90,
        ),
        sourceSnapshot: const <String, Object?>{'activity': true},
        modelVersion: 1,
        settledAt: DateTime.utc(2026, 8, 1, 1),
      ),
    );

    expect(result.recipientPetId, 'locked-pet');
    expect(result.awardedDelta, 30);
  });
}

PetCollectionWrite _petWrite({
  required String petId,
  required PetSpecies species,
}) {
  return PetCollectionWrite(
    petId: petId,
    athleteProfileId: 'athlete-a',
    species: species,
    nickname: '训练伙伴',
    unlockedAt: DateTime.utc(2026, 8, 1),
    bornAt: DateTime.utc(2026, 8, 1),
    createdAt: DateTime.utc(2026, 8, 1),
    updatedAt: DateTime.utc(2026, 8, 1),
  );
}

Map<String, Object?> _profileRow({
  required String athleteProfileId,
  required String activePetId,
  PetSpecies firstEggSpecies = PetSpecies.balanceRaccoon,
  String? selectedShellId,
}) {
  return <String, Object?>{
    'athlete_profile_id': athleteProfileId,
    'active_pet_id': activePetId,
    'first_egg_species_id': firstEggSpecies.id,
    'selected_shell_id': selectedShellId,
    'created_at': '2026-08-01T00:00:00.000Z',
    'updated_at': '2026-08-01T00:00:00.000Z',
  };
}

Map<String, Object?> _collectionRow({
  required String petId,
  required String athleteProfileId,
  required PetSpecies species,
}) {
  return <String, Object?>{
    'pet_id': petId,
    'athlete_profile_id': athleteProfileId,
    'species_id': species.id,
    'nickname': '训练伙伴',
    'unlocked_at': '2026-08-01T00:00:00.000Z',
    'born_at': '2026-08-01T00:00:00.000Z',
    'selected_accessory_id': null,
    'selected_badge_id': null,
    'created_at': '2026-08-01T00:00:00.000Z',
    'updated_at': '2026-08-01T00:00:00.000Z',
  };
}

Map<String, Object?> _energyRow({
  required String athleteProfileId,
  required String localDate,
  required String recipientPetId,
  required int awardedTotal,
  int stepsEnergy = 0,
  int standEnergy = 0,
  int exerciseEnergy = 0,
  int activeEnergy = 0,
  int trainingEnergy = 0,
  int recoveryEnergy = 0,
  Map<String, Object?> sourceSnapshot = const <String, Object?>{},
}) {
  return <String, Object?>{
    'athlete_profile_id': athleteProfileId,
    'local_date': localDate,
    'recipient_pet_id': recipientPetId,
    'steps_energy': stepsEnergy,
    'stand_energy': standEnergy,
    'exercise_energy': exerciseEnergy,
    'active_energy': activeEnergy,
    'training_energy': trainingEnergy,
    'recovery_energy': recoveryEnergy,
    'calculated_total': awardedTotal,
    'awarded_total': awardedTotal,
    'source_snapshot_json': jsonEncode(sourceSnapshot),
    'model_version': 1,
    'settled_at': '2026-08-01T01:00:00.000Z',
    'updated_at': '2026-08-01T01:00:00.000Z',
  };
}

class _MemoryPetGateway implements PetDatabaseGateway {
  final Map<String, Map<String, Object?>> profiles =
      <String, Map<String, Object?>>{};
  final List<Map<String, Object?>> collection = <Map<String, Object?>>[];
  final List<Map<String, Object?>> energy = <Map<String, Object?>>[];
  PetSettlementResult? nextSettlementResult;

  @override
  Future<void> chooseFirstEgg(PetFirstEggWrite write) async {
    collection.add(_rowFromWrite(write.companion));
    profiles[write.companion.athleteProfileId] = _profileRow(
      athleteProfileId: write.companion.athleteProfileId,
      activePetId: write.companion.petId,
      firstEggSpecies: write.companion.species,
      selectedShellId: write.selectedShellId,
    );
  }

  @override
  Future<void> insertUnlockedPet(PetCollectionWrite write) async {
    collection.add(_rowFromWrite(write));
  }

  @override
  Future<List<Map<String, Object?>>> listPetCollectionRows(
    String athleteProfileId,
  ) async {
    return collection
        .where(
          (Map<String, Object?> row) =>
              row['athlete_profile_id'] == athleteProfileId,
        )
        .map(Map<String, Object?>.from)
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, Object?>>> listPetDailyEnergyRows({
    required String athleteProfileId,
    String? recipientPetId,
  }) async {
    final List<Map<String, Object?>> result = energy
        .where(
          (Map<String, Object?> row) =>
              row['athlete_profile_id'] == athleteProfileId &&
              (recipientPetId == null ||
                  row['recipient_pet_id'] == recipientPetId),
        )
        .map(Map<String, Object?>.from)
        .toList();
    result.sort(
      (Map<String, Object?> left, Map<String, Object?> right) =>
          '${right['local_date']}'.compareTo('${left['local_date']}'),
    );
    return result;
  }

  @override
  Future<Map<String, Object?>?> readPetProfileRow(
    String athleteProfileId,
  ) async {
    final Map<String, Object?>? row = profiles[athleteProfileId];
    return row == null ? null : Map<String, Object?>.from(row);
  }

  @override
  Future<PetSettlementResult> settleDay(PetSettlementWrite write) async {
    return nextSettlementResult ??
        PetSettlementResult(
          recipientPetId: write.activePetId,
          calculatedTotal: write.breakdown.total,
          awardedTotal: write.breakdown.total,
          awardedDelta: write.breakdown.total,
          didLockRecipient: true,
        );
  }

  @override
  Future<void> switchActivePet({
    required String athleteProfileId,
    required String petId,
    required DateTime updatedAt,
  }) async {
    profiles[athleteProfileId] = <String, Object?>{
      ...profiles[athleteProfileId]!,
      'active_pet_id': petId,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _rowFromWrite(PetCollectionWrite write) {
  return <String, Object?>{
    'pet_id': write.petId,
    'athlete_profile_id': write.athleteProfileId,
    'species_id': write.species.id,
    'nickname': write.nickname,
    'unlocked_at': write.unlockedAt.toIso8601String(),
    'born_at': write.bornAt.toIso8601String(),
    'selected_accessory_id': write.selectedAccessoryId,
    'selected_badge_id': write.selectedBadgeId,
    'created_at': write.createdAt.toIso8601String(),
    'updated_at': write.updatedAt.toIso8601String(),
  };
}
