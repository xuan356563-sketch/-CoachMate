import 'package:trainflow_ai/data/models/daily_activity_summary.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/services/pet_energy_calculator.dart';

enum PetSettlementMode {
  normalSync,
  explicitHealthDeletion,
}

/// 一只待写入本地图鉴的宠物。
class PetCollectionWrite {
  PetCollectionWrite({
    required this.petId,
    required this.athleteProfileId,
    required this.species,
    required this.nickname,
    required DateTime unlockedAt,
    required DateTime bornAt,
    this.selectedAccessoryId,
    this.selectedBadgeId,
    required DateTime createdAt,
    required DateTime updatedAt,
  })  : unlockedAt = unlockedAt.toUtc(),
        bornAt = bornAt.toUtc(),
        createdAt = createdAt.toUtc(),
        updatedAt = updatedAt.toUtc();

  final String petId;
  final String athleteProfileId;
  final PetSpecies species;
  final String nickname;
  final DateTime unlockedAt;
  final DateTime bornAt;
  final String? selectedAccessoryId;
  final String? selectedBadgeId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// 首次选蛋需要作为一个整体写入的内容。
class PetFirstEggWrite {
  const PetFirstEggWrite({
    required this.companion,
    this.selectedShellId,
  });

  final PetCollectionWrite companion;
  final String? selectedShellId;
}

/// 单个自然日的宠物能量结算请求。
///
/// 有活动摘要时，账号与自然日以摘要为准；没有摘要的训练日或恢复日
/// 必须显式提供 [athleteProfileId] 和 [localDate]。
class PetSettlementWrite {
  const PetSettlementWrite({
    required this.summary,
    this.athleteProfileId,
    this.localDate,
    required this.activePetId,
    required this.breakdown,
    required this.sourceSnapshot,
    required this.modelVersion,
    required this.settledAt,
    this.mode = PetSettlementMode.normalSync,
  });

  final DailyActivitySummary? summary;
  final String? athleteProfileId;
  final String? localDate;
  final String activePetId;
  final PetEnergyBreakdown breakdown;
  final Map<String, Object?> sourceSnapshot;
  final int modelVersion;
  final DateTime settledAt;
  final PetSettlementMode mode;
}

/// 宠物领域使用的最小数据库边界。
///
/// 只返回稳定的行快照，不向仓储或控制器暴露 sqflite `Database`。
abstract interface class PetDatabaseGateway {
  Future<Map<String, Object?>?> readPetProfileRow(
    String athleteProfileId,
  );

  Future<List<Map<String, Object?>>> listPetCollectionRows(
    String athleteProfileId,
  );

  Future<Map<String, Object?>?> readDailyActivitySummaryRow({
    required String athleteProfileId,
    required String localDate,
  });

  Future<List<Map<String, Object?>>> listDailyActivitySummaryRows(
    String athleteProfileId,
  );

  Future<void> upsertDailyActivitySummaryRow(
    Map<String, Object?> row,
  );

  Future<Map<String, Object?>?> readPetDailyEnergyRow({
    required String athleteProfileId,
    required String localDate,
  });

  Future<List<Map<String, Object?>>> listPetDailyEnergyRows({
    required String athleteProfileId,
    String? recipientPetId,
  });

  Future<void> chooseFirstEgg(PetFirstEggWrite write);

  Future<void> insertUnlockedPet(PetCollectionWrite write);

  Future<void> switchActivePet({
    required String athleteProfileId,
    required String petId,
    required DateTime updatedAt,
  });

  Future<PetSettlementResult> settleDay(PetSettlementWrite write);
}

/// 主数据库网关可选提供的宠物数据库能力。
abstract interface class PetDatabaseGatewayProvider {
  PetDatabaseGateway createPetDatabaseGateway();
}
