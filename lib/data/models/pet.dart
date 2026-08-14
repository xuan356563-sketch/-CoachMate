enum PetSpecies {
  windFox('wind_fox'),
  jumpRabbit('jump_rabbit'),
  steadyTurtle('steady_turtle'),
  energyDragon('energy_dragon'),
  strengthBear('strength_bear'),
  balanceRaccoon('balance_raccoon');

  const PetSpecies(this.id);

  final String id;

  static PetSpecies? tryFromId(Object? value) {
    for (final PetSpecies species in PetSpecies.values) {
      if (species.id == value) return species;
    }
    return null;
  }
}

enum PetStage {
  patternEgg('pattern_egg'),
  sprout('sprout'),
  junior('junior'),
  advanced('advanced'),
  champion('champion');

  const PetStage(this.id);

  final String id;

  static PetStage fromId(Object? value) {
    return PetStage.values.firstWhere(
      (PetStage stage) => stage.id == value,
      orElse: () => PetStage.patternEgg,
    );
  }
}

enum PetMood {
  excited('excited'),
  happy('happy'),
  curious('curious'),
  calm('calm'),
  waiting('waiting');

  const PetMood(this.id);

  final String id;

  static PetMood fromId(Object? value) {
    return PetMood.values.firstWhere(
      (PetMood mood) => mood.id == value,
      orElse: () => PetMood.waiting,
    );
  }
}

class PetProfile {
  PetProfile({
    required this.athleteProfileId,
    required this.activePetId,
    required this.firstEggSpecies,
    required this.selectedShellId,
    required DateTime createdAt,
    required DateTime updatedAt,
  })  : createdAt = createdAt.toUtc(),
        updatedAt = updatedAt.toUtc();

  factory PetProfile.fromJson(Map<String, dynamic> json) => PetProfile(
        athleteProfileId: json['athleteProfileId'] as String? ?? '',
        activePetId: json['activePetId'] as String?,
        firstEggSpecies: PetSpecies.tryFromId(json['firstEggSpeciesId']),
        selectedShellId: json['selectedShellId'] as String?,
        createdAt: _requiredUtcDateTime(json['createdAt'], '创建时间'),
        updatedAt: _requiredUtcDateTime(json['updatedAt'], '更新时间'),
      );

  final String athleteProfileId;
  final String? activePetId;
  final PetSpecies? firstEggSpecies;
  final String? selectedShellId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'athleteProfileId': athleteProfileId,
        'activePetId': activePetId,
        'firstEggSpeciesId': firstEggSpecies?.id,
        'selectedShellId': selectedShellId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class PetCompanion {
  PetCompanion({
    required this.id,
    required this.athleteProfileId,
    required this.species,
    required this.nickname,
    required DateTime unlockedAt,
    required DateTime bornAt,
    required this.selectedAccessoryId,
    required this.selectedBadgeId,
    required DateTime createdAt,
    required DateTime updatedAt,
    required int totalEnergy,
    required this.stage,
    required int partnerStars,
    required this.mood,
  })  : unlockedAt = unlockedAt.toUtc(),
        bornAt = bornAt.toUtc(),
        createdAt = createdAt.toUtc(),
        updatedAt = updatedAt.toUtc(),
        totalEnergy = _nonNegativeInt(totalEnergy),
        partnerStars = _nonNegativeInt(partnerStars);

  factory PetCompanion.fromJson(Map<String, dynamic> json) {
    final PetSpecies? species = PetSpecies.tryFromId(json['speciesId']);
    if (species == null) {
      throw const FormatException('宠物物种无效');
    }
    return PetCompanion(
      id: json['id'] as String? ?? '',
      athleteProfileId: json['athleteProfileId'] as String? ?? '',
      species: species,
      nickname: json['nickname'] as String? ?? '',
      unlockedAt: _requiredUtcDateTime(json['unlockedAt'], '解锁时间'),
      bornAt: _requiredUtcDateTime(json['bornAt'], '出生时间'),
      selectedAccessoryId: json['selectedAccessoryId'] as String?,
      selectedBadgeId: json['selectedBadgeId'] as String?,
      createdAt: _requiredUtcDateTime(json['createdAt'], '创建时间'),
      updatedAt: _requiredUtcDateTime(json['updatedAt'], '更新时间'),
      totalEnergy: (json['totalEnergy'] as num?)?.toInt() ?? 0,
      stage: PetStage.fromId(json['stageId']),
      partnerStars: (json['partnerStars'] as num?)?.toInt() ?? 0,
      mood: PetMood.fromId(json['moodId']),
    );
  }

  final String id;
  final String athleteProfileId;
  final PetSpecies species;
  final String nickname;
  final DateTime unlockedAt;
  final DateTime bornAt;
  final String? selectedAccessoryId;
  final String? selectedBadgeId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int totalEnergy;
  final PetStage stage;
  final int partnerStars;
  final PetMood mood;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'athleteProfileId': athleteProfileId,
        'speciesId': species.id,
        'nickname': nickname,
        'unlockedAt': unlockedAt.toIso8601String(),
        'bornAt': bornAt.toIso8601String(),
        'selectedAccessoryId': selectedAccessoryId,
        'selectedBadgeId': selectedBadgeId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'totalEnergy': totalEnergy,
        'stageId': stage.id,
        'partnerStars': partnerStars,
        'moodId': mood.id,
      };
}

class PetDailyEnergy {
  PetDailyEnergy({
    required this.athleteProfileId,
    required String localDate,
    required this.recipientPetId,
    required int stepsEnergy,
    required int standEnergy,
    required int exerciseEnergy,
    required int activeEnergy,
    required int trainingEnergy,
    required int recoveryEnergy,
    required int calculatedTotal,
    required int awardedTotal,
    required Map<String, Object?> sourceSnapshot,
    required this.modelVersion,
    required DateTime settledAt,
    required DateTime updatedAt,
  })  : localDate = _validatedLocalDate(localDate),
        stepsEnergy = _nonNegativeInt(stepsEnergy),
        standEnergy = _nonNegativeInt(standEnergy),
        exerciseEnergy = _nonNegativeInt(exerciseEnergy),
        activeEnergy = _nonNegativeInt(activeEnergy),
        trainingEnergy = _nonNegativeInt(trainingEnergy),
        recoveryEnergy = _nonNegativeInt(recoveryEnergy),
        calculatedTotal = calculatedTotal.clamp(0, 160),
        awardedTotal = awardedTotal.clamp(0, 160),
        sourceSnapshot = Map<String, Object?>.unmodifiable(sourceSnapshot),
        settledAt = settledAt.toUtc(),
        updatedAt = updatedAt.toUtc();

  factory PetDailyEnergy.fromJson(Map<String, dynamic> json) => PetDailyEnergy(
        athleteProfileId: json['athleteProfileId'] as String? ?? '',
        localDate: json['localDate'] as String? ?? '',
        recipientPetId: json['recipientPetId'] as String? ?? '',
        stepsEnergy: (json['stepsEnergy'] as num?)?.toInt() ?? 0,
        standEnergy: (json['standEnergy'] as num?)?.toInt() ?? 0,
        exerciseEnergy: (json['exerciseEnergy'] as num?)?.toInt() ?? 0,
        activeEnergy: (json['activeEnergy'] as num?)?.toInt() ?? 0,
        trainingEnergy: (json['trainingEnergy'] as num?)?.toInt() ?? 0,
        recoveryEnergy: (json['recoveryEnergy'] as num?)?.toInt() ?? 0,
        calculatedTotal: (json['calculatedTotal'] as num?)?.toInt() ?? 0,
        awardedTotal: (json['awardedTotal'] as num?)?.toInt() ?? 0,
        sourceSnapshot: _objectMap(json['sourceSnapshot']),
        modelVersion: (json['modelVersion'] as num?)?.toInt() ?? 1,
        settledAt: _requiredUtcDateTime(json['settledAt'], '结算时间'),
        updatedAt: _requiredUtcDateTime(json['updatedAt'], '更新时间'),
      );

  final String athleteProfileId;
  final String localDate;
  final String recipientPetId;
  final int stepsEnergy;
  final int standEnergy;
  final int exerciseEnergy;
  final int activeEnergy;
  final int trainingEnergy;
  final int recoveryEnergy;
  final int calculatedTotal;
  final int awardedTotal;
  final Map<String, Object?> sourceSnapshot;
  final int modelVersion;
  final DateTime settledAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'athleteProfileId': athleteProfileId,
        'localDate': localDate,
        'recipientPetId': recipientPetId,
        'stepsEnergy': stepsEnergy,
        'standEnergy': standEnergy,
        'exerciseEnergy': exerciseEnergy,
        'activeEnergy': activeEnergy,
        'trainingEnergy': trainingEnergy,
        'recoveryEnergy': recoveryEnergy,
        'calculatedTotal': calculatedTotal,
        'awardedTotal': awardedTotal,
        'sourceSnapshot': sourceSnapshot,
        'modelVersion': modelVersion,
        'settledAt': settledAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class PetSettlementResult {
  const PetSettlementResult({
    required this.recipientPetId,
    required this.calculatedTotal,
    required this.awardedTotal,
    required this.awardedDelta,
    required this.didLockRecipient,
  });

  final String? recipientPetId;
  final int calculatedTotal;
  final int awardedTotal;
  final int awardedDelta;
  final bool didLockRecipient;
}

class PetUnlockProgress {
  const PetUnlockProgress({
    required this.species,
    required this.current,
    required this.target,
    required this.isUnlocked,
  });

  final PetSpecies species;
  final int current;
  final int target;
  final bool isUnlocked;

  double get fraction {
    if (target <= 0 || isUnlocked) return 1;
    return (current / target).clamp(0, 1).toDouble();
  }
}

int _nonNegativeInt(int value) => value < 0 ? 0 : value;

String _validatedLocalDate(String value) {
  final RegExpMatch? match =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw const FormatException('本地日期必须使用 yyyy-MM-dd 格式');
  }
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null ||
      parsed.year.toString().padLeft(4, '0') != match.group(1) ||
      parsed.month.toString().padLeft(2, '0') != match.group(2) ||
      parsed.day.toString().padLeft(2, '0') != match.group(3)) {
    throw const FormatException('本地日期不是有效的自然日');
  }
  return value;
}

DateTime _requiredUtcDateTime(Object? value, String fieldLabel) {
  final DateTime? parsed = value is DateTime
      ? value
      : DateTime.tryParse(value is String ? value : '');
  if (parsed == null) {
    throw FormatException('$fieldLabel 无效');
  }
  return parsed.toUtc();
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in value.entries)
      if (entry.key is String) entry.key! as String: entry.value,
  };
}
