import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/local/sqflite_pet_database_gateway.dart';
import 'package:trainflow_ai/data/models/daily_activity_summary.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/services/pet_energy_calculator.dart';

void main() {
  group('宠物数据库网关', () {
    test('首次首蛋在同一事务中创建图鉴、档案并设为出战宠物', () async {
      final _MemoryPetDatabaseAdapter adapter = _MemoryPetDatabaseAdapter();
      final PetDatabaseGateway gateway = SqflitePetDatabaseGateway(adapter);

      await gateway.chooseFirstEgg(
        PetFirstEggWrite(
          companion: _pet(
            petId: 'pet-a',
            athleteProfileId: 'athlete-a',
            species: PetSpecies.balanceRaccoon,
          ),
          selectedShellId: 'shell-peach',
        ),
      );

      final Map<String, Object?>? profile =
          await gateway.readPetProfileRow('athlete-a');
      final List<Map<String, Object?>> collection =
          await gateway.listPetCollectionRows('athlete-a');
      expect(collection, hasLength(1));
      expect(collection.single['pet_id'], 'pet-a');
      expect(profile?['active_pet_id'], 'pet-a');
      expect(profile?['first_egg_species_id'], PetSpecies.balanceRaccoon.id);
      expect(profile?['selected_shell_id'], 'shell-peach');
      expect(adapter.transactionCount, 1);
    });

    test('重复选择首蛋会被拒绝且不会新增图鉴行', () async {
      final _MemoryPetDatabaseAdapter adapter = _MemoryPetDatabaseAdapter();
      final PetDatabaseGateway gateway = SqflitePetDatabaseGateway(adapter);
      await gateway.chooseFirstEgg(
        PetFirstEggWrite(
          companion: _pet(
            petId: 'pet-a',
            athleteProfileId: 'athlete-a',
            species: PetSpecies.balanceRaccoon,
          ),
        ),
      );

      await expectLater(
        gateway.chooseFirstEgg(
          PetFirstEggWrite(
            companion: _pet(
              petId: 'pet-b',
              athleteProfileId: 'athlete-a',
              species: PetSpecies.windFox,
            ),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('首蛋'),
          ),
        ),
      );

      expect(await gateway.listPetCollectionRows('athlete-a'), hasLength(1));
      expect(
        (await gateway.readPetProfileRow('athlete-a'))?['active_pet_id'],
        'pet-a',
      );
    });

    test('同一账号不能重复解锁相同物种', () async {
      final _MemoryPetDatabaseAdapter adapter = _MemoryPetDatabaseAdapter();
      final PetDatabaseGateway gateway = SqflitePetDatabaseGateway(adapter);
      await gateway.chooseFirstEgg(
        PetFirstEggWrite(
          companion: _pet(
            petId: 'pet-a',
            athleteProfileId: 'athlete-a',
            species: PetSpecies.balanceRaccoon,
          ),
        ),
      );

      await expectLater(
        gateway.insertUnlockedPet(
          _pet(
            petId: 'pet-b',
            athleteProfileId: 'athlete-a',
            species: PetSpecies.balanceRaccoon,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('物种'),
          ),
        ),
      );
      expect(await gateway.listPetCollectionRows('athlete-a'), hasLength(1));
    });

    test('每日活动摘要行可幂等写入并按自然日倒序读取', () async {
      final _MemoryPetDatabaseAdapter adapter = _MemoryPetDatabaseAdapter();
      final PetDatabaseGateway gateway = SqflitePetDatabaseGateway(adapter);
      await gateway.upsertDailyActivitySummaryRow(<String, Object?>{
        'athlete_profile_id': 'athlete-a',
        'local_date': '2026-08-01',
        'time_zone_name': 'Asia/Shanghai',
        'time_zone_offset_minutes': 480,
        'steps': null,
        'step_goal': 6000,
        'active_energy_kcal': null,
        'active_energy_goal_kcal': null,
        'exercise_minutes': null,
        'exercise_goal_minutes': 30,
        'stand_hours': null,
        'stand_goal_hours': 10,
        'field_sources_json': '{"steps":"unavailable"}',
        'synced_at': '2026-08-01T01:00:00.000Z',
        'updated_at': '2026-08-01T01:00:00.000Z',
      });
      await gateway.upsertDailyActivitySummaryRow(<String, Object?>{
        'athlete_profile_id': 'athlete-a',
        'local_date': '2026-08-02',
        'time_zone_name': 'Asia/Shanghai',
        'time_zone_offset_minutes': 480,
        'steps': 7200,
        'step_goal': 6000,
        'active_energy_kcal': 320.5,
        'active_energy_goal_kcal': 300.0,
        'exercise_minutes': 35,
        'exercise_goal_minutes': 30,
        'stand_hours': 11,
        'stand_goal_hours': 10,
        'field_sources_json': '{"steps":"health_kit"}',
        'synced_at': '2026-08-02T01:00:00.000Z',
        'updated_at': '2026-08-02T01:00:00.000Z',
      });
      await gateway.upsertDailyActivitySummaryRow(<String, Object?>{
        'athlete_profile_id': 'athlete-a',
        'local_date': '2026-08-01',
        'time_zone_name': 'Asia/Shanghai',
        'time_zone_offset_minutes': 480,
        'steps': 6100,
        'step_goal': 6000,
        'active_energy_kcal': null,
        'active_energy_goal_kcal': null,
        'exercise_minutes': null,
        'exercise_goal_minutes': 30,
        'stand_hours': null,
        'stand_goal_hours': 10,
        'field_sources_json': '{"steps":"manual_override"}',
        'synced_at': '2026-08-01T02:00:00.000Z',
        'updated_at': '2026-08-01T02:00:00.000Z',
      });

      final List<Map<String, Object?>> rows =
          await gateway.listDailyActivitySummaryRows('athlete-a');

      expect(
        rows.map((Map<String, Object?> row) => row['local_date']).toList(),
        <String>['2026-08-02', '2026-08-01'],
      );
      expect(rows.last['steps'], 6100);
      expect(rows.last['active_energy_kcal'], isNull);
    });

    test('零能量只保存活动摘要，不创建账本也不锁定接收者', () async {
      final _GatewayFixture fixture = await _readyFixture();

      final PetSettlementResult result = await fixture.gateway.settleDay(
        _settlement(
          summary: _summary(
            athleteProfileId: 'athlete-a',
            localDate: '2026-08-01',
          ),
          activePetId: 'pet-a',
          breakdown: _energy(0),
        ),
      );

      expect(result.recipientPetId, isNull);
      expect(result.awardedDelta, 0);
      expect(result.didLockRecipient, isFalse);
      expect(
        await fixture.gateway.readDailyActivitySummaryRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-08-01',
        ),
        isNotNull,
      );
      expect(
        await fixture.gateway.readPetDailyEnergyRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-08-01',
        ),
        isNull,
      );
    });

    test('首次正能量创建账本并锁定当前出战宠物', () async {
      final _GatewayFixture fixture = await _readyFixture();

      final PetSettlementResult result = await fixture.gateway.settleDay(
        _settlement(
          summary: _summary(
            athleteProfileId: 'athlete-a',
            localDate: '2026-08-01',
          ),
          activePetId: 'pet-a',
          breakdown: _energy(40),
        ),
      );

      expect(result.recipientPetId, 'pet-a');
      expect(result.calculatedTotal, 40);
      expect(result.awardedTotal, 40);
      expect(result.awardedDelta, 40);
      expect(result.didLockRecipient, isTrue);
      final Map<String, Object?>? row =
          await fixture.gateway.readPetDailyEnergyRow(
        athleteProfileId: 'athlete-a',
        localDate: '2026-08-01',
      );
      expect(row?['recipient_pet_id'], 'pet-a');
      expect(row?['awarded_total'], 40);
    });

    test('同日切换不转移接收者，重复同步为零差额，上调只补差额', () async {
      final _GatewayFixture fixture = await _readyFixture(
        includeSecondPet: true,
      );
      final DailyActivitySummary summary = _summary(
        athleteProfileId: 'athlete-a',
        localDate: '2026-08-01',
      );
      await fixture.gateway.settleDay(
        _settlement(
          summary: summary,
          activePetId: 'pet-a',
          breakdown: _energy(40),
        ),
      );
      await fixture.gateway.switchActivePet(
        athleteProfileId: 'athlete-a',
        petId: 'pet-b',
        updatedAt: DateTime.utc(2026, 8, 1, 11),
      );

      final PetSettlementResult repeated = await fixture.gateway.settleDay(
        _settlement(
          summary: summary,
          activePetId: 'pet-b',
          breakdown: _energy(40),
        ),
      );
      final PetSettlementResult increased = await fixture.gateway.settleDay(
        _settlement(
          summary: summary,
          activePetId: 'pet-b',
          breakdown: _energy(90),
        ),
      );
      final PetSettlementResult decreased = await fixture.gateway.settleDay(
        _settlement(
          summary: summary,
          activePetId: 'pet-b',
          breakdown: _energy(20),
        ),
      );

      expect(repeated.recipientPetId, 'pet-a');
      expect(repeated.awardedDelta, 0);
      expect(increased.recipientPetId, 'pet-a');
      expect(increased.awardedTotal, 90);
      expect(increased.awardedDelta, 50);
      expect(decreased.recipientPetId, 'pet-a');
      expect(decreased.calculatedTotal, 20);
      expect(decreased.awardedTotal, 90);
      expect(decreased.awardedDelta, 0);
    });

    test('明确删除健康数据时允许降低已发放总量但不返回负差额', () async {
      final _GatewayFixture fixture = await _readyFixture();
      final DailyActivitySummary summary = _summary(
        athleteProfileId: 'athlete-a',
        localDate: '2026-08-01',
      );
      await fixture.gateway.settleDay(
        _settlement(
          summary: summary,
          activePetId: 'pet-a',
          breakdown: _energy(90),
        ),
      );

      final PetSettlementResult result = await fixture.gateway.settleDay(
        _settlement(
          summary: summary,
          activePetId: 'pet-a',
          breakdown: _energy(20),
          mode: PetSettlementMode.explicitHealthDeletion,
        ),
      );

      expect(result.calculatedTotal, 20);
      expect(result.awardedTotal, 20);
      expect(result.awardedDelta, 0);
    });

    test('无活动摘要的训练日必须提供账号和自然日并可正常结算', () async {
      final _GatewayFixture fixture = await _readyFixture();

      final PetSettlementResult result = await fixture.gateway.settleDay(
        PetSettlementWrite(
          summary: null,
          athleteProfileId: 'athlete-a',
          localDate: '2026-08-01',
          activePetId: 'pet-a',
          breakdown: _energy(100),
          sourceSnapshot: const <String, Object?>{'training': true},
          modelVersion: 1,
          settledAt: DateTime.utc(2026, 8, 1, 10),
        ),
      );

      expect(result.awardedDelta, 100);
      expect(result.recipientPetId, 'pet-a');
    });

    test('来源快照递归排序且拒绝原始健康点位、音频或位置轨迹', () async {
      final _GatewayFixture fixture = await _readyFixture();
      await fixture.gateway.settleDay(
        _settlement(
          summary: _summary(
            athleteProfileId: 'athlete-a',
            localDate: '2026-08-01',
          ),
          activePetId: 'pet-a',
          breakdown: _energy(40),
          sourceSnapshot: const <String, Object?>{
            'zeta': 1,
            'alpha': <String, Object?>{'z': 2, 'a': 1},
          },
        ),
      );
      final Map<String, Object?> row =
          (await fixture.gateway.readPetDailyEnergyRow(
        athleteProfileId: 'athlete-a',
        localDate: '2026-08-01',
      ))!;
      expect(
        row['source_snapshot_json'],
        '{"alpha":{"a":1,"z":2},"zeta":1}',
      );
      expect(
        jsonDecode(row['source_snapshot_json']! as String),
        <String, Object?>{
          'alpha': <String, Object?>{'a': 1, 'z': 2},
          'zeta': 1,
        },
      );

      await expectLater(
        fixture.gateway.settleDay(
          _settlement(
            summary: _summary(
              athleteProfileId: 'athlete-a',
              localDate: '2026-08-02',
            ),
            activePetId: 'pet-a',
            breakdown: _energy(40),
            sourceSnapshot: const <String, Object?>{
              'healthRate': <String, Object?>{
                'rawSamples': <int>[70, 72],
              },
            },
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('原始'),
          ),
        ),
      );
    });

    test('事务第二次写入失败时活动摘要与能量账本全部回滚', () async {
      final _GatewayFixture fixture = await _readyFixture();
      fixture.adapter
        ..resetWriteCounter()
        ..failOnWriteNumber = 2;

      await expectLater(
        fixture.gateway.settleDay(
          _settlement(
            summary: _summary(
              athleteProfileId: 'athlete-a',
              localDate: '2026-08-01',
            ),
            activePetId: 'pet-a',
            breakdown: _energy(40),
          ),
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        await fixture.gateway.readDailyActivitySummaryRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-08-01',
        ),
        isNull,
      );
      expect(
        await fixture.gateway.readPetDailyEnergyRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-08-01',
        ),
        isNull,
      );
    });

    test('相同自然日按账号隔离，不能把其他账号宠物设为接收者', () async {
      final _MemoryPetDatabaseAdapter adapter = _MemoryPetDatabaseAdapter();
      final PetDatabaseGateway gateway = SqflitePetDatabaseGateway(adapter);
      await gateway.chooseFirstEgg(
        PetFirstEggWrite(
          companion: _pet(
            petId: 'pet-a',
            athleteProfileId: 'athlete-a',
            species: PetSpecies.balanceRaccoon,
          ),
        ),
      );
      await gateway.chooseFirstEgg(
        PetFirstEggWrite(
          companion: _pet(
            petId: 'pet-b',
            athleteProfileId: 'athlete-b',
            species: PetSpecies.balanceRaccoon,
          ),
        ),
      );
      await gateway.settleDay(
        _settlement(
          summary: _summary(
            athleteProfileId: 'athlete-a',
            localDate: '2026-08-01',
          ),
          activePetId: 'pet-a',
          breakdown: _energy(40),
        ),
      );
      await gateway.settleDay(
        _settlement(
          summary: _summary(
            athleteProfileId: 'athlete-b',
            localDate: '2026-08-01',
          ),
          activePetId: 'pet-b',
          breakdown: _energy(70),
        ),
      );

      expect(
        (await gateway.readPetDailyEnergyRow(
          athleteProfileId: 'athlete-a',
          localDate: '2026-08-01',
        ))?['awarded_total'],
        40,
      );
      expect(
        (await gateway.readPetDailyEnergyRow(
          athleteProfileId: 'athlete-b',
          localDate: '2026-08-01',
        ))?['awarded_total'],
        70,
      );
      expect(
        await gateway.listPetDailyEnergyRows(
          athleteProfileId: 'athlete-a',
          recipientPetId: 'pet-a',
        ),
        hasLength(1),
      );
      await expectLater(
        gateway.settleDay(
          _settlement(
            summary: _summary(
              athleteProfileId: 'athlete-a',
              localDate: '2026-08-02',
            ),
            activePetId: 'pet-b',
            breakdown: _energy(10),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('当前账号'),
          ),
        ),
      );
    });
  });
}

Future<_GatewayFixture> _readyFixture({bool includeSecondPet = false}) async {
  final _MemoryPetDatabaseAdapter adapter = _MemoryPetDatabaseAdapter();
  final PetDatabaseGateway gateway = SqflitePetDatabaseGateway(adapter);
  await gateway.chooseFirstEgg(
    PetFirstEggWrite(
      companion: _pet(
        petId: 'pet-a',
        athleteProfileId: 'athlete-a',
        species: PetSpecies.balanceRaccoon,
      ),
    ),
  );
  if (includeSecondPet) {
    await gateway.insertUnlockedPet(
      _pet(
        petId: 'pet-b',
        athleteProfileId: 'athlete-a',
        species: PetSpecies.windFox,
      ),
    );
  }
  return _GatewayFixture(adapter: adapter, gateway: gateway);
}

PetCollectionWrite _pet({
  required String petId,
  required String athleteProfileId,
  required PetSpecies species,
}) {
  return PetCollectionWrite(
    petId: petId,
    athleteProfileId: athleteProfileId,
    species: species,
    nickname: '小伙伴',
    unlockedAt: DateTime.utc(2026, 8, 1, 8),
    bornAt: DateTime.utc(2026, 8, 1, 8),
    createdAt: DateTime.utc(2026, 8, 1, 8),
    updatedAt: DateTime.utc(2026, 8, 1, 8),
  );
}

DailyActivitySummary _summary({
  required String athleteProfileId,
  required String localDate,
}) {
  return DailyActivitySummary(
    athleteProfileId: athleteProfileId,
    localDate: localDate,
    timeZoneName: 'Asia/Shanghai',
    timeZoneOffsetMinutes: 480,
    steps: 6000,
    stepGoal: 6000,
    fieldSources: const <DailyActivityField, ActivityFieldSource>{
      DailyActivityField.steps: ActivityFieldSource.healthKit,
      DailyActivityField.stepGoal: ActivityFieldSource.derivedGoal,
    },
    syncedAt: DateTime.utc(2026, 8, 1, 9),
  );
}

PetSettlementWrite _settlement({
  required DailyActivitySummary summary,
  required String activePetId,
  required PetEnergyBreakdown breakdown,
  Map<String, Object?> sourceSnapshot = const <String, Object?>{
    'activity': true,
  },
  PetSettlementMode mode = PetSettlementMode.normalSync,
}) {
  return PetSettlementWrite(
    summary: summary,
    activePetId: activePetId,
    breakdown: breakdown,
    sourceSnapshot: sourceSnapshot,
    modelVersion: 1,
    settledAt: DateTime.utc(2026, 8, 1, 10),
    mode: mode,
  );
}

PetEnergyBreakdown _energy(int total) {
  return PetEnergyBreakdown(
    stepsEnergy: total.clamp(0, 20),
    standEnergy: 0,
    exerciseEnergy: 0,
    activeEnergy: 0,
    activityTotal: total.clamp(0, 60),
    trainingEnergy: total > 60 ? total - 60 : 0,
    recoveryEnergy: 0,
    total: total,
  );
}

class _GatewayFixture {
  const _GatewayFixture({required this.adapter, required this.gateway});

  final _MemoryPetDatabaseAdapter adapter;
  final PetDatabaseGateway gateway;
}

class _MemoryPetDatabaseAdapter implements PetDatabaseAdapter {
  Map<PetDatabaseTable, List<Map<String, Object?>>> _rows =
      <PetDatabaseTable, List<Map<String, Object?>>>{
    for (final PetDatabaseTable table in PetDatabaseTable.values)
      table: <Map<String, Object?>>[],
  };

  int transactionCount = 0;
  int writeCount = 0;
  int? failOnWriteNumber;

  void resetWriteCounter() {
    writeCount = 0;
  }

  @override
  Future<void> insertRow(
    PetDatabaseTable table,
    Map<String, Object?> row,
  ) async {
    _beforeWrite();
    _rows[table]!.add(Map<String, Object?>.from(row));
  }

  @override
  Future<List<Map<String, Object?>>> readRows(
    PetDatabaseTable table, {
    Map<String, Object?> where = const <String, Object?>{},
    String? orderByColumn,
    bool descending = false,
    int? limit,
  }) async {
    final List<Map<String, Object?>> matches = _rows[table]!
        .where((Map<String, Object?> row) => _matches(row, where))
        .map(Map<String, Object?>.from)
        .toList();
    if (orderByColumn != null) {
      matches.sort((Map<String, Object?> left, Map<String, Object?> right) {
        final int result =
            '${left[orderByColumn]}'.compareTo('${right[orderByColumn]}');
        return descending ? -result : result;
      });
    }
    if (limit != null && matches.length > limit) {
      return matches.take(limit).toList(growable: false);
    }
    return matches;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(PetDatabaseRowExecutor transaction) action,
  ) async {
    transactionCount += 1;
    final Map<PetDatabaseTable, List<Map<String, Object?>>> working =
        <PetDatabaseTable, List<Map<String, Object?>>>{
      for (final MapEntry<PetDatabaseTable, List<Map<String, Object?>>> entry
          in _rows.entries)
        entry.key:
            entry.value.map(Map<String, Object?>.from).toList(growable: true),
    };
    final _MemoryPetDatabaseAdapter transactionAdapter =
        _MemoryPetDatabaseAdapter()
          .._rows = working
          ..writeCount = writeCount
          ..failOnWriteNumber = failOnWriteNumber;
    try {
      final T result = await action(transactionAdapter);
      _rows = transactionAdapter._rows;
      writeCount = transactionAdapter.writeCount;
      return result;
    } catch (_) {
      writeCount = transactionAdapter.writeCount;
      rethrow;
    }
  }

  @override
  Future<int> updateRows(
    PetDatabaseTable table,
    Map<String, Object?> values, {
    required Map<String, Object?> where,
  }) async {
    _beforeWrite();
    int count = 0;
    for (final Map<String, Object?> row in _rows[table]!) {
      if (!_matches(row, where)) continue;
      row.addAll(values);
      count += 1;
    }
    return count;
  }

  void _beforeWrite() {
    writeCount += 1;
    if (writeCount == failOnWriteNumber) {
      throw StateError('模拟事务中途写入失败');
    }
  }
}

bool _matches(
  Map<String, Object?> row,
  Map<String, Object?> conditions,
) {
  for (final MapEntry<String, Object?> condition in conditions.entries) {
    if (row[condition.key] != condition.value) return false;
  }
  return true;
}
