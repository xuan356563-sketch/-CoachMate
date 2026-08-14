import 'dart:convert';
import 'dart:math' as math;

import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/services/pet_progression_engine.dart';

class PetHealthDeletionImpact {
  PetHealthDeletionImpact({
    required this.affectedDateCount,
    required this.removedHealthEnergy,
    required List<String> affectedLocalDates,
  }) : affectedLocalDates = List<String>.unmodifiable(affectedLocalDates);

  final int affectedDateCount;
  final int removedHealthEnergy;
  final List<String> affectedLocalDates;
}

class PetRepository {
  const PetRepository(
    this._database, {
    PetProgressionEngine progressionEngine = const PetProgressionEngine(),
  }) : _progressionEngine = progressionEngine;

  final PetDatabaseGateway _database;
  final PetProgressionEngine _progressionEngine;

  Future<PetProfile?> loadProfile(String athleteProfileId) async {
    final Map<String, Object?>? row =
        await _database.readPetProfileRow(athleteProfileId);
    return row == null ? null : _profileFromRow(row);
  }

  Future<PetCompanion?> loadCompanionState({
    required String athleteProfileId,
    required String localDate,
    String? petId,
  }) async {
    final PetProfile? profile = await loadProfile(athleteProfileId);
    final String? resolvedPetId = petId ?? profile?.activePetId;
    if (resolvedPetId == null) return null;

    final List<Map<String, Object?>> collection =
        await _database.listPetCollectionRows(athleteProfileId);
    Map<String, Object?>? petRow;
    for (final Map<String, Object?> row in collection) {
      if (row['pet_id'] == resolvedPetId) {
        petRow = row;
        break;
      }
    }
    if (petRow == null) return null;

    final List<PetDailyEnergy> ledger = await listDailyEnergy(
      athleteProfileId: athleteProfileId,
      recipientPetId: resolvedPetId,
    );
    final int totalEnergy = ledger.fold<int>(
      0,
      (int total, PetDailyEnergy item) => total + item.awardedTotal,
    );
    final int todayEnergy = ledger
        .where((PetDailyEnergy item) => item.localDate == localDate)
        .fold<int>(
          0,
          (int total, PetDailyEnergy item) => total + item.awardedTotal,
        );
    final int daysSinceLastRecord = _daysSinceLastRecord(
      ledger,
      localDate,
    );

    return _companionFromRow(
      petRow,
      totalEnergy: totalEnergy,
      stage: _progressionEngine.stageForEnergy(totalEnergy),
      partnerStars: _progressionEngine.partnerStars(totalEnergy),
      mood: _progressionEngine.moodFor(
        todayEnergy: todayEnergy,
        daysSinceLastRecord: daysSinceLastRecord,
      ),
    );
  }

  Future<List<PetDailyEnergy>> listDailyEnergy({
    required String athleteProfileId,
    String? recipientPetId,
  }) async {
    final List<Map<String, Object?>> rows =
        await _database.listPetDailyEnergyRows(
      athleteProfileId: athleteProfileId,
      recipientPetId: recipientPetId,
    );
    return List<PetDailyEnergy>.unmodifiable(rows.map(_dailyEnergyFromRow));
  }

  Future<PetHealthDeletionImpact> previewHealthDeletionImpact(
    String athleteProfileId,
  ) async {
    final List<Map<String, Object?>> rows =
        await _database.listPetDailyEnergyRows(
      athleteProfileId: athleteProfileId,
    );
    final Set<String> dates = <String>{};
    int removedHealthEnergy = 0;
    for (final Map<String, Object?> row in rows) {
      final int healthEnergy = _rowInt(row, 'steps_energy') +
          _rowInt(row, 'stand_energy') +
          _rowInt(row, 'exercise_energy') +
          _rowInt(row, 'active_energy');
      if (healthEnergy <= 0) continue;
      dates.add(_requiredString(row, 'local_date', '本地日期'));
      removedHealthEnergy += healthEnergy;
    }
    final List<String> affectedLocalDates = dates.toList()..sort();
    return PetHealthDeletionImpact(
      affectedDateCount: affectedLocalDates.length,
      removedHealthEnergy: removedHealthEnergy,
      affectedLocalDates: affectedLocalDates,
    );
  }

  Future<void> chooseFirstEgg(PetFirstEggWrite write) {
    return _database.chooseFirstEgg(write);
  }

  Future<void> unlockSpecies(PetCollectionWrite write) {
    return _database.insertUnlockedPet(write);
  }

  Future<void> switchActivePet({
    required String athleteProfileId,
    required String petId,
    required DateTime updatedAt,
  }) {
    return _database.switchActivePet(
      athleteProfileId: athleteProfileId,
      petId: petId,
      updatedAt: updatedAt,
    );
  }

  Future<PetSettlementResult> settleDay(PetSettlementWrite write) {
    return _database.settleDay(write);
  }
}

PetProfile _profileFromRow(Map<String, Object?> row) {
  return PetProfile(
    athleteProfileId: _requiredString(
      row,
      'athlete_profile_id',
      '运动员账号',
    ),
    activePetId: row['active_pet_id'] as String?,
    firstEggSpecies: PetSpecies.tryFromId(row['first_egg_species_id']),
    selectedShellId: row['selected_shell_id'] as String?,
    createdAt: _requiredDateTime(row, 'created_at', '宠物档案创建时间'),
    updatedAt: _requiredDateTime(row, 'updated_at', '宠物档案更新时间'),
  );
}

PetCompanion _companionFromRow(
  Map<String, Object?> row, {
  required int totalEnergy,
  required PetStage stage,
  required int partnerStars,
  required PetMood mood,
}) {
  final PetSpecies? species = PetSpecies.tryFromId(row['species_id']);
  if (species == null) throw const FormatException('宠物物种无效');
  return PetCompanion(
    id: _requiredString(row, 'pet_id', '宠物编号'),
    athleteProfileId: _requiredString(
      row,
      'athlete_profile_id',
      '运动员账号',
    ),
    species: species,
    nickname: _requiredString(row, 'nickname', '宠物昵称'),
    unlockedAt: _requiredDateTime(row, 'unlocked_at', '宠物解锁时间'),
    bornAt: _requiredDateTime(row, 'born_at', '宠物出生时间'),
    selectedAccessoryId: row['selected_accessory_id'] as String?,
    selectedBadgeId: row['selected_badge_id'] as String?,
    createdAt: _requiredDateTime(row, 'created_at', '宠物创建时间'),
    updatedAt: _requiredDateTime(row, 'updated_at', '宠物更新时间'),
    totalEnergy: totalEnergy,
    stage: stage,
    partnerStars: partnerStars,
    mood: mood,
  );
}

PetDailyEnergy _dailyEnergyFromRow(Map<String, Object?> row) {
  return PetDailyEnergy(
    athleteProfileId: _requiredString(
      row,
      'athlete_profile_id',
      '运动员账号',
    ),
    localDate: _requiredString(row, 'local_date', '本地日期'),
    recipientPetId: _requiredString(
      row,
      'recipient_pet_id',
      '能量接收宠物',
    ),
    stepsEnergy: _rowInt(row, 'steps_energy'),
    standEnergy: _rowInt(row, 'stand_energy'),
    exerciseEnergy: _rowInt(row, 'exercise_energy'),
    activeEnergy: _rowInt(row, 'active_energy'),
    trainingEnergy: _rowInt(row, 'training_energy'),
    recoveryEnergy: _rowInt(row, 'recovery_energy'),
    calculatedTotal: _rowInt(row, 'calculated_total'),
    awardedTotal: _rowInt(row, 'awarded_total'),
    sourceSnapshot: _decodeJsonObject(
      row['source_snapshot_json'],
      '宠物能量来源快照',
    ),
    modelVersion: _rowInt(row, 'model_version'),
    settledAt: _requiredDateTime(row, 'settled_at', '宠物结算时间'),
    updatedAt: _requiredDateTime(row, 'updated_at', '宠物账本更新时间'),
  );
}

int _daysSinceLastRecord(
  List<PetDailyEnergy> ledger,
  String localDate,
) {
  final DateTime? reference = DateTime.tryParse(localDate);
  if (reference == null) {
    throw const FormatException('本地日期必须使用 yyyy-MM-dd 格式');
  }
  DateTime? latest;
  for (final PetDailyEnergy item in ledger) {
    final DateTime? date = DateTime.tryParse(item.localDate);
    if (date == null || date.isAfter(reference)) continue;
    if (latest == null || date.isAfter(latest)) latest = date;
  }
  return latest == null
      ? 999
      : math.max(0, reference.difference(latest).inDays);
}

Map<String, Object?> _decodeJsonObject(Object? value, String label) {
  try {
    final Object? decoded = jsonDecode(value as String? ?? '');
    if (decoded is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in decoded.entries)
          if (entry.key is String) entry.key! as String: entry.value,
      };
    }
  } catch (_) {
    // 统一在下方抛出稳定的中文格式错误。
  }
  throw FormatException('$label不是有效的 JSON 对象');
}

String _requiredString(
  Map<String, Object?> row,
  String key,
  String label,
) {
  final String value = row[key] as String? ?? '';
  if (value.trim().isEmpty) throw FormatException('$label不能为空');
  return value;
}

int _rowInt(Map<String, Object?> row, String key) {
  return (row[key] as num?)?.toInt() ?? 0;
}

DateTime _requiredDateTime(
  Map<String, Object?> row,
  String key,
  String label,
) {
  final DateTime? value = DateTime.tryParse(row[key] as String? ?? '');
  if (value == null) throw FormatException('$label无效');
  return value.toUtc();
}
