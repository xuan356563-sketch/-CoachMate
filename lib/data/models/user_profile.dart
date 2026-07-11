enum Gender {
  male,
  female,
  other,
  unknown,
}

extension GenderJson on Gender {
  String get jsonValue {
    switch (this) {
      case Gender.male:
        return 'male';
      case Gender.female:
        return 'female';
      case Gender.other:
        return 'other';
      case Gender.unknown:
        return 'unknown';
    }
  }
}

Gender genderFromJson(String? value) {
  switch (value) {
    case 'male':
      return Gender.male;
    case 'female':
      return Gender.female;
    case 'other':
      return Gender.other;
    default:
      return Gender.unknown;
  }
}

enum MainSport {
  marathon,
  trailRunning,
  strength,
  hyrox,
  fatLoss,
  rehab,
  generalFitness,
}

extension MainSportJson on MainSport {
  String get jsonValue {
    switch (this) {
      case MainSport.marathon:
        return 'marathon';
      case MainSport.trailRunning:
        return 'trail_running';
      case MainSport.strength:
        return 'strength';
      case MainSport.hyrox:
        return 'hyrox';
      case MainSport.fatLoss:
        return 'fat_loss';
      case MainSport.rehab:
        return 'rehab';
      case MainSport.generalFitness:
        return 'general_fitness';
    }
  }

  String get label {
    switch (this) {
      case MainSport.marathon:
        return '马拉松';
      case MainSport.trailRunning:
        return '越野跑';
      case MainSport.strength:
        return '力量训练';
      case MainSport.hyrox:
        return 'HYROX';
      case MainSport.fatLoss:
        return '减脂';
      case MainSport.rehab:
        return '康复';
      case MainSport.generalFitness:
        return '综合健身';
    }
  }
}

MainSport mainSportFromJson(String? value) {
  switch (value) {
    case 'marathon':
      return MainSport.marathon;
    case 'trail_running':
      return MainSport.trailRunning;
    case 'strength':
      return MainSport.strength;
    case 'hyrox':
      return MainSport.hyrox;
    case 'fat_loss':
      return MainSport.fatLoss;
    case 'rehab':
      return MainSport.rehab;
    case 'general_fitness':
      return MainSport.generalFitness;
    default:
      return MainSport.generalFitness;
  }
}

enum WorkScheduleType {
  regularOffice,
  overtimeHeavy,
  shiftWork,
  freelancer,
  unknown,
}

extension WorkScheduleTypeJson on WorkScheduleType {
  String get jsonValue {
    switch (this) {
      case WorkScheduleType.regularOffice:
        return 'regular_office';
      case WorkScheduleType.overtimeHeavy:
        return 'overtime_heavy';
      case WorkScheduleType.shiftWork:
        return 'shift_work';
      case WorkScheduleType.freelancer:
        return 'freelancer';
      case WorkScheduleType.unknown:
        return 'unknown';
    }
  }

  String get label {
    switch (this) {
      case WorkScheduleType.regularOffice:
        return '规律坐班';
      case WorkScheduleType.overtimeHeavy:
        return '加班较多';
      case WorkScheduleType.shiftWork:
        return '轮班';
      case WorkScheduleType.freelancer:
        return '自由职业';
      case WorkScheduleType.unknown:
        return '暂不确定';
    }
  }
}

WorkScheduleType workScheduleTypeFromJson(String? value) {
  switch (value) {
    case 'regular_office':
      return WorkScheduleType.regularOffice;
    case 'overtime_heavy':
      return WorkScheduleType.overtimeHeavy;
    case 'shift_work':
      return WorkScheduleType.shiftWork;
    case 'freelancer':
      return WorkScheduleType.freelancer;
    default:
      return WorkScheduleType.unknown;
  }
}

enum EquipmentAccessType {
  none,
  basicHome,
  gym,
  mixed,
}

extension EquipmentAccessTypeJson on EquipmentAccessType {
  String get jsonValue {
    switch (this) {
      case EquipmentAccessType.none:
        return 'none';
      case EquipmentAccessType.basicHome:
        return 'basic_home';
      case EquipmentAccessType.gym:
        return 'gym';
      case EquipmentAccessType.mixed:
        return 'mixed';
    }
  }

  String get label {
    switch (this) {
      case EquipmentAccessType.none:
        return '基本无器械';
      case EquipmentAccessType.basicHome:
        return '基础家用器械';
      case EquipmentAccessType.gym:
        return '健身房';
      case EquipmentAccessType.mixed:
        return '家用 + 健身房';
    }
  }
}

EquipmentAccessType equipmentAccessTypeFromJson(String? value) {
  switch (value) {
    case 'none':
      return EquipmentAccessType.none;
    case 'basic_home':
      return EquipmentAccessType.basicHome;
    case 'gym':
      return EquipmentAccessType.gym;
    case 'mixed':
      return EquipmentAccessType.mixed;
    default:
      return EquipmentAccessType.gym;
  }
}

enum WorkerProfileType {
  sedentaryOffice,
  overtimeHeavy,
  shiftWork,
  highPressureKnowledge,
  standingJob,
  racePrepWorker,
  unstableDiet,
  general,
}

extension WorkerProfileTypeJson on WorkerProfileType {
  String get jsonValue {
    switch (this) {
      case WorkerProfileType.sedentaryOffice:
        return 'sedentary_office';
      case WorkerProfileType.overtimeHeavy:
        return 'overtime_heavy';
      case WorkerProfileType.shiftWork:
        return 'shift_work';
      case WorkerProfileType.highPressureKnowledge:
        return 'high_pressure_knowledge';
      case WorkerProfileType.standingJob:
        return 'standing_job';
      case WorkerProfileType.racePrepWorker:
        return 'race_prep_worker';
      case WorkerProfileType.unstableDiet:
        return 'unstable_diet';
      case WorkerProfileType.general:
        return 'general';
    }
  }

  String get label {
    switch (this) {
      case WorkerProfileType.sedentaryOffice:
        return '久坐办公室';
      case WorkerProfileType.overtimeHeavy:
        return '经常加班';
      case WorkerProfileType.shiftWork:
        return '倒班 / 熬夜';
      case WorkerProfileType.highPressureKnowledge:
        return '高压力脑力工作';
      case WorkerProfileType.standingJob:
        return '久站工作';
      case WorkerProfileType.racePrepWorker:
        return '备赛打工人';
      case WorkerProfileType.unstableDiet:
        return '减脂饮食不稳定';
      case WorkerProfileType.general:
        return '综合 / 其他';
    }
  }

  String get strategy {
    switch (this) {
      case WorkerProfileType.sedentaryOffice:
        return '优先髋、胸椎和核心激活，久坐后先活动再进入主训练。';
      case WorkerProfileType.overtimeHeavy:
        return '优先短时高效和恢复，不为补课额外堆量。';
      case WorkerProfileType.shiftWork:
        return '先看睡眠和清醒时段，准备度不足时以低强度训练为主。';
      case WorkerProfileType.highPressureKnowledge:
        return '避免叠加过多高强度刺激，先用低压热身确认状态。';
      case WorkerProfileType.standingJob:
        return '优先足底、小腿和下肢恢复，减少疲劳状态下的额外冲击。';
      case WorkerProfileType.racePrepWorker:
        return '只保留关键课并提高执行效率，工作压力高时优先保住恢复。';
      case WorkerProfileType.unstableDiet:
        return '优先坚持率、关节安全和可持续消耗，不用热量数字增加负担。';
      case WorkerProfileType.general:
        return '先按可用时间和当天准备度执行，收集反馈后再细调。';
    }
  }
}

WorkerProfileType workerProfileTypeFromJson(String? value) {
  switch (value) {
    case 'sedentary_office':
      return WorkerProfileType.sedentaryOffice;
    case 'overtime_heavy':
      return WorkerProfileType.overtimeHeavy;
    case 'shift_work':
      return WorkerProfileType.shiftWork;
    case 'high_pressure_knowledge':
      return WorkerProfileType.highPressureKnowledge;
    case 'standing_job':
      return WorkerProfileType.standingJob;
    case 'race_prep_worker':
      return WorkerProfileType.racePrepWorker;
    case 'unstable_diet':
      return WorkerProfileType.unstableDiet;
    case 'general':
    default:
      return WorkerProfileType.general;
  }
}

class UserProfile {
  final String id;
  final String name;
  final Gender gender;
  final int age;
  final double heightCm;
  final double weightKg;
  final String trainingGoal;
  final List<MainSport> mainSports;
  final int weeklyTrainingDays;
  final int dailyAvailableMinutes;
  final List<String> injuryHistory;
  final WorkScheduleType workScheduleType;
  final EquipmentAccessType equipmentAccessType;
  final WorkerProfileType workerProfileType;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    required this.name,
    required this.gender,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.trainingGoal,
    required this.mainSports,
    required this.weeklyTrainingDays,
    required this.dailyAvailableMinutes,
    required this.injuryHistory,
    required this.workScheduleType,
    this.equipmentAccessType = EquipmentAccessType.gym,
    this.workerProfileType = WorkerProfileType.general,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final List<dynamic> sportsJson = json['mainSports'] as List<dynamic>? ?? [];
    return UserProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      gender: genderFromJson(json['gender'] as String?),
      age: (json['age'] as num?)?.toInt() ?? 0,
      heightCm: (json['heightCm'] as num?)?.toDouble() ?? 0,
      weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
      trainingGoal: json['trainingGoal'] as String? ?? '',
      mainSports: sportsJson
          .map((dynamic value) => mainSportFromJson(value as String?))
          .toList(),
      weeklyTrainingDays: (json['weeklyTrainingDays'] as num?)?.toInt() ?? 0,
      dailyAvailableMinutes:
          (json['dailyAvailableMinutes'] as num?)?.toInt() ?? 0,
      injuryHistory:
          List<String>.from(json['injuryHistory'] as List<dynamic>? ?? []),
      workScheduleType:
          workScheduleTypeFromJson(json['workScheduleType'] as String?),
      equipmentAccessType: equipmentAccessTypeFromJson(
        json['equipmentAccessType'] as String?,
      ),
      workerProfileType: workerProfileTypeFromJson(
        json['workerProfileType'] as String?,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'gender': gender.jsonValue,
      'age': age,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'trainingGoal': trainingGoal,
      'mainSports': mainSports.map((MainSport item) => item.jsonValue).toList(),
      'weeklyTrainingDays': weeklyTrainingDays,
      'dailyAvailableMinutes': dailyAvailableMinutes,
      'injuryHistory': injuryHistory,
      'workScheduleType': workScheduleType.jsonValue,
      'equipmentAccessType': equipmentAccessType.jsonValue,
      'workerProfileType': workerProfileType.jsonValue,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? id,
    String? name,
    Gender? gender,
    int? age,
    double? heightCm,
    double? weightKg,
    String? trainingGoal,
    List<MainSport>? mainSports,
    int? weeklyTrainingDays,
    int? dailyAvailableMinutes,
    List<String>? injuryHistory,
    WorkScheduleType? workScheduleType,
    EquipmentAccessType? equipmentAccessType,
    WorkerProfileType? workerProfileType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      trainingGoal: trainingGoal ?? this.trainingGoal,
      mainSports: mainSports ?? this.mainSports,
      weeklyTrainingDays: weeklyTrainingDays ?? this.weeklyTrainingDays,
      dailyAvailableMinutes:
          dailyAvailableMinutes ?? this.dailyAvailableMinutes,
      injuryHistory: injuryHistory ?? this.injuryHistory,
      workScheduleType: workScheduleType ?? this.workScheduleType,
      equipmentAccessType: equipmentAccessType ?? this.equipmentAccessType,
      workerProfileType: workerProfileType ?? this.workerProfileType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
