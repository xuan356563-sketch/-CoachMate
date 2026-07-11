import 'evidence_source.dart';

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

class RacePlan {
  final String id;
  final RaceType type;
  final String name;
  final DateTime raceDate;
  final String targetResult;
  final String? actualResult;
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
