import 'evidence_source.dart';

const Object _raceValueUnchanged = Object();

enum RaceType {
  marathon,
  trailRunning,
  hyrox,
  roadRunning,
}

extension RaceTypeJson on RaceType {
  String get jsonValue {
    switch (this) {
      case RaceType.marathon:
        return 'marathon';
      case RaceType.trailRunning:
        return 'trail_running';
      case RaceType.hyrox:
        return 'hyrox';
      case RaceType.roadRunning:
        return 'road_running';
    }
  }

  String get label {
    switch (this) {
      case RaceType.marathon:
        return '马拉松';
      case RaceType.trailRunning:
        return '越野跑';
      case RaceType.hyrox:
        return 'HYROX';
      case RaceType.roadRunning:
        return '路跑';
    }
  }
}

RaceType raceTypeFromJson(String? value) {
  switch (value) {
    case 'marathon':
      return RaceType.marathon;
    case 'trail_running':
      return RaceType.trailRunning;
    case 'hyrox':
      return RaceType.hyrox;
    case 'road_running':
      return RaceType.roadRunning;
    default:
      return RaceType.roadRunning;
  }
}

enum RacePhaseType {
  base,
  build,
  specific,
  taper,
  raceWeek,
}

extension RacePhaseTypeJson on RacePhaseType {
  String get jsonValue {
    switch (this) {
      case RacePhaseType.base:
        return 'base';
      case RacePhaseType.build:
        return 'build';
      case RacePhaseType.specific:
        return 'specific';
      case RacePhaseType.taper:
        return 'taper';
      case RacePhaseType.raceWeek:
        return 'race_week';
    }
  }

  String get label {
    switch (this) {
      case RacePhaseType.base:
        return '基础期';
      case RacePhaseType.build:
        return '强化期';
      case RacePhaseType.specific:
        return '专项期';
      case RacePhaseType.taper:
        return '赛前减量';
      case RacePhaseType.raceWeek:
        return '比赛周';
    }
  }
}

RacePhaseType racePhaseTypeFromJson(String? value) {
  switch (value) {
    case 'base':
      return RacePhaseType.base;
    case 'build':
      return RacePhaseType.build;
    case 'specific':
      return RacePhaseType.specific;
    case 'taper':
      return RacePhaseType.taper;
    case 'race_week':
      return RacePhaseType.raceWeek;
    default:
      return RacePhaseType.base;
  }
}

class RaceTrainingPhase {
  final RacePhaseType phaseType;
  final String weekRange;
  final String focus;
  final List<String> keyWorkouts;

  const RaceTrainingPhase({
    required this.phaseType,
    required this.weekRange,
    required this.focus,
    required this.keyWorkouts,
  });

  factory RaceTrainingPhase.fromJson(Map<String, dynamic> json) {
    return RaceTrainingPhase(
      phaseType: racePhaseTypeFromJson(json['phaseType'] as String?),
      weekRange: json['weekRange'] as String? ?? '',
      focus: json['focus'] as String? ?? '',
      keyWorkouts:
          List<String>.from(json['keyWorkouts'] as List<dynamic>? ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'phaseType': phaseType.jsonValue,
      'weekRange': weekRange,
      'focus': focus,
      'keyWorkouts': keyWorkouts,
    };
  }
}

class RaceStrategySection {
  final String title;
  final List<String> items;

  const RaceStrategySection({
    required this.title,
    required this.items,
  });

  factory RaceStrategySection.fromJson(Map<String, dynamic> json) {
    return RaceStrategySection(
      title: json['title'] as String? ?? '',
      items: List<String>.from(json['items'] as List<dynamic>? ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'items': items,
    };
  }
}

enum OfficialRaceResultStatus {
  active,
  revoked,
}

extension OfficialRaceResultStatusJson on OfficialRaceResultStatus {
  String get jsonValue {
    switch (this) {
      case OfficialRaceResultStatus.active:
        return 'active';
      case OfficialRaceResultStatus.revoked:
        return 'revoked';
    }
  }
}

/// 由用户明确确认并关联到一条训练事实的正式比赛成绩。
///
/// 旧版 [RacePlan.actualResult] 只是自由文本，不会自动转换为本对象，也不会
/// 获得 PB 语义。
class OfficialRaceResult {
  final int durationSeconds;
  final DateTime confirmedAt;
  final String trainingLogId;
  final String workoutDayId;
  final OfficialRaceResultStatus status;
  final DateTime? revokedAt;

  const OfficialRaceResult({
    required this.durationSeconds,
    required this.confirmedAt,
    required this.trainingLogId,
    required this.workoutDayId,
    required this.status,
    required this.revokedAt,
  });

  bool get isActive => status == OfficialRaceResultStatus.active;

  String get durationLabel => formatDuration(durationSeconds);

  OfficialRaceResult revoke(DateTime at) {
    if (!isActive) {
      return this;
    }
    return copyWith(
      status: OfficialRaceResultStatus.revoked,
      revokedAt: at,
    );
  }

  OfficialRaceResult copyWith({
    int? durationSeconds,
    DateTime? confirmedAt,
    String? trainingLogId,
    String? workoutDayId,
    OfficialRaceResultStatus? status,
    Object? revokedAt = _raceValueUnchanged,
  }) {
    return OfficialRaceResult(
      durationSeconds: durationSeconds ?? this.durationSeconds,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      trainingLogId: trainingLogId ?? this.trainingLogId,
      workoutDayId: workoutDayId ?? this.workoutDayId,
      status: status ?? this.status,
      revokedAt: identical(revokedAt, _raceValueUnchanged)
          ? this.revokedAt
          : revokedAt as DateTime?,
    );
  }

  static int parseDurationSeconds(String rawValue) {
    final String value = rawValue.trim().replaceAll('：', ':');
    final List<String> parts = value.split(':');
    final bool shapeIsValid = parts.length == 2 || parts.length == 3;
    final bool valuesAreNumeric = parts.every(
      (String part) => RegExp(r'^\d+$').hasMatch(part),
    );
    if (!shapeIsValid || !valuesAreNumeric) {
      throw const FormatException(
        '成绩格式无效：请使用 4:30:00 或 45:30 这类时:分:秒/分:秒格式。',
      );
    }

    final List<int> values = parts.map(int.parse).toList(growable: false);
    final int hours = parts.length == 3 ? values[0] : 0;
    final int minutes = parts.length == 3 ? values[1] : values[0];
    final int seconds = parts.length == 3 ? values[2] : values[1];
    if (hours > 99 || (parts.length == 3 && minutes > 59) || seconds > 59) {
      throw const FormatException(
        '成绩格式无效：小时不能超过 99，分和秒需要在 0 到 59 之间。',
      );
    }
    final int totalSeconds = hours * 3600 + minutes * 60 + seconds;
    if (totalSeconds <= 0) {
      throw const FormatException('成绩必须大于 0 秒。');
    }
    if (totalSeconds > 359999) {
      throw const FormatException('成绩不能超过 99:59:59。');
    }
    return totalSeconds;
  }

  static int? tryParseDurationSeconds(String rawValue) {
    try {
      return parseDurationSeconds(rawValue);
    } on FormatException {
      return null;
    }
  }

  static String formatDuration(int totalSeconds) {
    final int safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
    final int hours = safeSeconds ~/ 3600;
    final int minutes = (safeSeconds % 3600) ~/ 60;
    final int seconds = safeSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  static OfficialRaceResult? tryFromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final Map<String, dynamic> json = Map<String, dynamic>.from(value);
    final int durationSeconds = (json['durationSeconds'] as num?)?.toInt() ?? 0;
    final DateTime? confirmedAt =
        DateTime.tryParse(json['confirmedAt'] as String? ?? '');
    final String trainingLogId =
        (json['trainingLogId'] as String? ?? '').trim();
    final String workoutDayId = (json['workoutDayId'] as String? ?? '').trim();
    final DateTime? revokedAt =
        DateTime.tryParse(json['revokedAt'] as String? ?? '');
    final String? rawStatus = json['status'] as String?;
    final bool statusIsValid = rawStatus == 'active' || rawStatus == 'revoked';
    final bool revoked = rawStatus == 'revoked' || revokedAt != null;
    if (!statusIsValid ||
        durationSeconds <= 0 ||
        durationSeconds > 359999 ||
        confirmedAt == null ||
        trainingLogId.isEmpty ||
        workoutDayId.isEmpty ||
        (revoked && revokedAt == null)) {
      return null;
    }
    return OfficialRaceResult(
      durationSeconds: durationSeconds,
      confirmedAt: confirmedAt,
      trainingLogId: trainingLogId,
      workoutDayId: workoutDayId,
      status: revoked
          ? OfficialRaceResultStatus.revoked
          : OfficialRaceResultStatus.active,
      revokedAt: revokedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'durationSeconds': durationSeconds,
      'confirmedAt': confirmedAt.toIso8601String(),
      'trainingLogId': trainingLogId,
      'workoutDayId': workoutDayId,
      'status': status.jsonValue,
      'revokedAt': revokedAt?.toIso8601String(),
    };
  }
}

class RacePlan {
  final String id;
  final RaceType type;
  final String name;
  final DateTime raceDate;
  final String targetResult;
  final String? actualResult;
  final OfficialRaceResult? officialRaceResult;
  final String predictedResult;
  final String currentPhase;
  final String courseInfo;
  final List<RaceTrainingPhase> phases;
  final List<String> taperPlan;
  final List<String> gearAdvice;
  final List<RaceStrategySection> strategySections;
  final List<String> postRaceRecovery;
  final List<EvidenceSource> evidenceSources;

  const RacePlan({
    required this.id,
    required this.type,
    required this.name,
    required this.raceDate,
    required this.targetResult,
    required this.actualResult,
    this.officialRaceResult,
    required this.predictedResult,
    required this.currentPhase,
    required this.courseInfo,
    required this.phases,
    required this.taperPlan,
    required this.gearAdvice,
    required this.strategySections,
    required this.postRaceRecovery,
    required this.evidenceSources,
  });

  String get raceDateLabel {
    return '${raceDate.year}-${raceDate.month.toString().padLeft(2, '0')}-${raceDate.day.toString().padLeft(2, '0')}';
  }

  bool isOnRaceDate(DateTime date) {
    return date.year == raceDate.year &&
        date.month == raceDate.month &&
        date.day == raceDate.day;
  }

  bool get hasActiveOfficialRaceResult => officialRaceResult?.isActive == true;

  RacePlan confirmOfficialRaceResult({
    required int durationSeconds,
    required DateTime confirmedAt,
    required String trainingLogId,
    required String workoutDayId,
  }) {
    if (durationSeconds <= 0 ||
        trainingLogId.trim().isEmpty ||
        workoutDayId.trim().isEmpty) {
      throw const FormatException('正式比赛成绩缺少合法用时或训练事实关联。');
    }
    return copyWith(
      officialRaceResult: OfficialRaceResult(
        durationSeconds: durationSeconds,
        confirmedAt: confirmedAt,
        trainingLogId: trainingLogId.trim(),
        workoutDayId: workoutDayId.trim(),
        status: OfficialRaceResultStatus.active,
        revokedAt: null,
      ),
    );
  }

  RacePlan revokeOfficialRaceResult(DateTime revokedAt) {
    final OfficialRaceResult? result = officialRaceResult;
    if (result == null || !result.isActive) {
      return this;
    }
    return copyWith(officialRaceResult: result.revoke(revokedAt));
  }

  RacePlan copyWith({
    String? id,
    RaceType? type,
    String? name,
    DateTime? raceDate,
    String? targetResult,
    Object? actualResult = _raceValueUnchanged,
    Object? officialRaceResult = _raceValueUnchanged,
    String? predictedResult,
    String? currentPhase,
    String? courseInfo,
    List<RaceTrainingPhase>? phases,
    List<String>? taperPlan,
    List<String>? gearAdvice,
    List<RaceStrategySection>? strategySections,
    List<String>? postRaceRecovery,
    List<EvidenceSource>? evidenceSources,
  }) {
    return RacePlan(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      raceDate: raceDate ?? this.raceDate,
      targetResult: targetResult ?? this.targetResult,
      actualResult: identical(actualResult, _raceValueUnchanged)
          ? this.actualResult
          : actualResult as String?,
      officialRaceResult: identical(officialRaceResult, _raceValueUnchanged)
          ? this.officialRaceResult
          : officialRaceResult as OfficialRaceResult?,
      predictedResult: predictedResult ?? this.predictedResult,
      currentPhase: currentPhase ?? this.currentPhase,
      courseInfo: courseInfo ?? this.courseInfo,
      phases: phases ?? this.phases,
      taperPlan: taperPlan ?? this.taperPlan,
      gearAdvice: gearAdvice ?? this.gearAdvice,
      strategySections: strategySections ?? this.strategySections,
      postRaceRecovery: postRaceRecovery ?? this.postRaceRecovery,
      evidenceSources: evidenceSources ?? this.evidenceSources,
    );
  }

  factory RacePlan.fromJson(Map<String, dynamic> json) {
    final List<dynamic> phasesJson = json['phases'] as List<dynamic>? ?? [];
    final List<dynamic> strategyJson =
        json['strategySections'] as List<dynamic>? ?? [];
    final List<dynamic> evidenceJson =
        json['evidenceSources'] as List<dynamic>? ?? [];
    return RacePlan(
      id: json['id'] as String? ?? '',
      type: raceTypeFromJson(json['type'] as String?),
      name: json['name'] as String? ?? '',
      raceDate: DateTime.tryParse(json['raceDate'] as String? ?? '') ??
          DateTime(2026),
      targetResult: json['targetResult'] as String? ?? '',
      actualResult: json['actualResult'] as String?,
      officialRaceResult:
          OfficialRaceResult.tryFromJson(json['officialRaceResult']),
      predictedResult: json['predictedResult'] as String? ?? '',
      currentPhase: json['currentPhase'] as String? ?? '',
      courseInfo: json['courseInfo'] as String? ?? '',
      phases: phasesJson
          .map(
            (dynamic value) =>
                RaceTrainingPhase.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
      taperPlan: List<String>.from(json['taperPlan'] as List<dynamic>? ?? []),
      gearAdvice: List<String>.from(json['gearAdvice'] as List<dynamic>? ?? []),
      strategySections: strategyJson
          .map(
            (dynamic value) =>
                RaceStrategySection.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
      postRaceRecovery:
          List<String>.from(json['postRaceRecovery'] as List<dynamic>? ?? []),
      evidenceSources: evidenceJson
          .map(
            (dynamic value) =>
                EvidenceSource.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.jsonValue,
      'name': name,
      'raceDate': raceDate.toIso8601String(),
      'targetResult': targetResult,
      'actualResult': actualResult,
      'officialRaceResult': officialRaceResult?.toJson(),
      'predictedResult': predictedResult,
      'currentPhase': currentPhase,
      'courseInfo': courseInfo,
      'phases':
          phases.map((RaceTrainingPhase phase) => phase.toJson()).toList(),
      'taperPlan': taperPlan,
      'gearAdvice': gearAdvice,
      'strategySections': strategySections
          .map((RaceStrategySection section) => section.toJson())
          .toList(),
      'postRaceRecovery': postRaceRecovery,
      'evidenceSources': evidenceSources
          .map((EvidenceSource source) => source.toJson())
          .toList(),
    };
  }
}

class RaceAutoScheduleItem {
  final int weekOffset;
  final DateTime weekStart;
  final DateTime weekEnd;
  final RacePhaseType phaseType;
  final String focus;
  final List<String> keyWorkouts;
  final String nutritionCue;
  final String recoveryRule;
  final String safetyGate;

  const RaceAutoScheduleItem({
    required this.weekOffset,
    required this.weekStart,
    required this.weekEnd,
    required this.phaseType,
    required this.focus,
    required this.keyWorkouts,
    required this.nutritionCue,
    required this.recoveryRule,
    required this.safetyGate,
  });

  String get weekLabel {
    return '${weekStart.month}/${weekStart.day}-${weekEnd.month}/${weekEnd.day}';
  }
}

class RaceAutoSchedule {
  final String raceId;
  final String raceName;
  final DateTime generatedAt;
  final int daysUntilRace;
  final String statusLabel;
  final List<RaceAutoScheduleItem> items;

  const RaceAutoSchedule({
    required this.raceId,
    required this.raceName,
    required this.generatedAt,
    required this.daysUntilRace,
    required this.statusLabel,
    required this.items,
  });

  RaceAutoScheduleItem? get currentItem {
    if (items.isEmpty) {
      return null;
    }
    return items.first;
  }

  String get countdownLabel {
    if (daysUntilRace <= 0) {
      return '比赛日已到或已结束';
    }
    return '距比赛 $daysUntilRace 天';
  }
}
