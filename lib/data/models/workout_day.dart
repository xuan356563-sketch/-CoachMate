import 'evidence_source.dart';

enum TrainingType {
  easyRun,
  tempoRun,
  intervalRun,
  longRun,
  strength,
  hyrox,
  mobility,
  rehab,
  rest,
  crossTraining,
}

enum TrainingDecisionType {
  normal,
  deload,
  recovery,
  technique,
  rest,
}

enum WorkoutExerciseModule {
  foamRolling,
  dynamicStretch,
  activation,
  warmup,
  hipDrive,
  calf,
  mainTraining,
  accessory,
  cooldown,
}

extension WorkoutExerciseModuleText on WorkoutExerciseModule {
  String get jsonValue {
    switch (this) {
      case WorkoutExerciseModule.foamRolling:
        return 'foam_rolling';
      case WorkoutExerciseModule.dynamicStretch:
        return 'dynamic_stretch';
      case WorkoutExerciseModule.activation:
        return 'activation';
      case WorkoutExerciseModule.warmup:
        return 'warmup';
      case WorkoutExerciseModule.hipDrive:
        return 'hip_drive';
      case WorkoutExerciseModule.calf:
        return 'calf';
      case WorkoutExerciseModule.mainTraining:
        return 'main_training';
      case WorkoutExerciseModule.accessory:
        return 'accessory';
      case WorkoutExerciseModule.cooldown:
        return 'cooldown';
    }
  }

  String get label {
    switch (this) {
      case WorkoutExerciseModule.foamRolling:
        return '泡沫轴';
      case WorkoutExerciseModule.dynamicStretch:
        return '动态拉伸';
      case WorkoutExerciseModule.activation:
        return '激活';
      case WorkoutExerciseModule.warmup:
        return '热身';
      case WorkoutExerciseModule.hipDrive:
        return '提髋';
      case WorkoutExerciseModule.calf:
        return '小腿';
      case WorkoutExerciseModule.mainTraining:
        return '主训练';
      case WorkoutExerciseModule.accessory:
        return '辅助';
      case WorkoutExerciseModule.cooldown:
        return '放松';
    }
  }
}

WorkoutExerciseModule workoutExerciseModuleFromJson(String? value) {
  switch (value) {
    case 'foam_rolling':
      return WorkoutExerciseModule.foamRolling;
    case 'dynamic_stretch':
      return WorkoutExerciseModule.dynamicStretch;
    case 'activation':
      return WorkoutExerciseModule.activation;
    case 'warmup':
      return WorkoutExerciseModule.warmup;
    case 'hip_drive':
      return WorkoutExerciseModule.hipDrive;
    case 'calf':
      return WorkoutExerciseModule.calf;
    case 'accessory':
      return WorkoutExerciseModule.accessory;
    case 'cooldown':
      return WorkoutExerciseModule.cooldown;
    case 'main_training':
    default:
      return WorkoutExerciseModule.mainTraining;
  }
}

class WorkoutExerciseLink {
  final String id;
  final String exerciseId;
  final int sequence;
  final WorkoutExerciseModule module;
  final int plannedSetCount;
  final int repetitionsPerSet;
  final String plannedWeightOrIntensity;
  final int restSeconds;

  const WorkoutExerciseLink({
    required this.id,
    required this.exerciseId,
    required this.sequence,
    required this.module,
    required this.plannedSetCount,
    required this.repetitionsPerSet,
    required this.plannedWeightOrIntensity,
    required this.restSeconds,
  });

  factory WorkoutExerciseLink.fromJson(Map<String, dynamic> json) {
    return WorkoutExerciseLink(
      id: json['id'] as String? ?? '',
      exerciseId: json['exerciseId'] as String? ?? '',
      sequence: ((json['sequence'] as num?)?.toInt() ?? 1).clamp(1, 99).toInt(),
      module: workoutExerciseModuleFromJson(json['module'] as String?),
      plannedSetCount: ((json['plannedSetCount'] as num?)?.toInt() ?? 0)
          .clamp(0, 99)
          .toInt(),
      repetitionsPerSet: ((json['repetitionsPerSet'] as num?)?.toInt() ?? 0)
          .clamp(0, 999)
          .toInt(),
      plannedWeightOrIntensity:
          json['plannedWeightOrIntensity'] as String? ?? '',
      restSeconds:
          ((json['restSeconds'] as num?)?.toInt() ?? 0).clamp(0, 1800).toInt(),
    );
  }

  String get prescriptionLabel {
    final List<String> items = [];
    if (plannedSetCount > 0) {
      final String repetitions =
          repetitionsPerSet > 0 ? ' x $repetitionsPerSet 次' : '';
      items.add('$plannedSetCount 组$repetitions');
    }
    if (plannedWeightOrIntensity.isNotEmpty) {
      items.add(plannedWeightOrIntensity);
    }
    if (restSeconds > 0) {
      items.add('休息 $restSeconds 秒');
    }
    return items.isEmpty ? '按教练提示执行' : items.join(' · ');
  }

  WorkoutExerciseLink copyWith({
    String? id,
    String? exerciseId,
    int? sequence,
    WorkoutExerciseModule? module,
    int? plannedSetCount,
    int? repetitionsPerSet,
    String? plannedWeightOrIntensity,
    int? restSeconds,
  }) {
    return WorkoutExerciseLink(
      id: id ?? this.id,
      exerciseId: exerciseId ?? this.exerciseId,
      sequence: sequence ?? this.sequence,
      module: module ?? this.module,
      plannedSetCount: plannedSetCount ?? this.plannedSetCount,
      repetitionsPerSet: repetitionsPerSet ?? this.repetitionsPerSet,
      plannedWeightOrIntensity:
          plannedWeightOrIntensity ?? this.plannedWeightOrIntensity,
      restSeconds: restSeconds ?? this.restSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'exerciseId': exerciseId,
      'sequence': sequence,
      'module': module.jsonValue,
      'plannedSetCount': plannedSetCount,
      'repetitionsPerSet': repetitionsPerSet,
      'plannedWeightOrIntensity': plannedWeightOrIntensity,
      'restSeconds': restSeconds,
    };
  }
}

extension TrainingDecisionTypeJson on TrainingDecisionType {
  String get jsonValue {
    switch (this) {
      case TrainingDecisionType.normal:
        return 'normal';
      case TrainingDecisionType.deload:
        return 'deload';
      case TrainingDecisionType.recovery:
        return 'recovery';
      case TrainingDecisionType.technique:
        return 'technique';
      case TrainingDecisionType.rest:
        return 'rest';
    }
  }

  String get label {
    switch (this) {
      case TrainingDecisionType.normal:
        return '正常';
      case TrainingDecisionType.deload:
        return '降级';
      case TrainingDecisionType.recovery:
        return '恢复';
      case TrainingDecisionType.technique:
        return '技术';
      case TrainingDecisionType.rest:
        return '休息';
    }
  }
}

TrainingDecisionType trainingDecisionTypeFromJson(String? value) {
  switch (value) {
    case 'normal':
      return TrainingDecisionType.normal;
    case 'deload':
      return TrainingDecisionType.deload;
    case 'recovery':
      return TrainingDecisionType.recovery;
    case 'technique':
      return TrainingDecisionType.technique;
    case 'rest':
      return TrainingDecisionType.rest;
    default:
      return TrainingDecisionType.normal;
  }
}

extension TrainingTypeJson on TrainingType {
  String get jsonValue {
    switch (this) {
      case TrainingType.easyRun:
        return 'easy_run';
      case TrainingType.tempoRun:
        return 'tempo_run';
      case TrainingType.intervalRun:
        return 'interval_run';
      case TrainingType.longRun:
        return 'long_run';
      case TrainingType.strength:
        return 'strength';
      case TrainingType.hyrox:
        return 'hyrox';
      case TrainingType.mobility:
        return 'mobility';
      case TrainingType.rehab:
        return 'rehab';
      case TrainingType.rest:
        return 'rest';
      case TrainingType.crossTraining:
        return 'cross_training';
    }
  }

  String get label {
    switch (this) {
      case TrainingType.easyRun:
        return '轻松跑';
      case TrainingType.tempoRun:
        return '节奏跑';
      case TrainingType.intervalRun:
        return '间歇跑';
      case TrainingType.longRun:
        return '长距离';
      case TrainingType.strength:
        return '力量';
      case TrainingType.hyrox:
        return 'HYROX';
      case TrainingType.mobility:
        return '灵活性';
      case TrainingType.rehab:
        return '康复';
      case TrainingType.rest:
        return '休息';
      case TrainingType.crossTraining:
        return '交叉训练';
    }
  }
}

TrainingType trainingTypeFromJson(String? value) {
  switch (value) {
    case 'easy_run':
      return TrainingType.easyRun;
    case 'tempo_run':
      return TrainingType.tempoRun;
    case 'interval_run':
      return TrainingType.intervalRun;
    case 'long_run':
      return TrainingType.longRun;
    case 'strength':
      return TrainingType.strength;
    case 'hyrox':
      return TrainingType.hyrox;
    case 'mobility':
      return TrainingType.mobility;
    case 'rehab':
      return TrainingType.rehab;
    case 'rest':
      return TrainingType.rest;
    case 'cross_training':
      return TrainingType.crossTraining;
    default:
      return TrainingType.easyRun;
  }
}

class WorkoutDay {
  final String id;
  final String planId;
  final int weekIndex;
  final int dayIndex;
  final String title;
  final TrainingType trainingType;
  final TrainingDecisionType decisionType;
  final int estimatedMinutes;
  final String intensity;
  final List<String> foamRollingSteps;
  final List<String> dynamicStretchSteps;
  final List<String> activationSteps;
  final List<String> warmupSteps;
  final List<String> mainSets;
  final List<String> accessoryWork;
  final List<String> cooldownSteps;
  final String coachNotes;
  final List<EvidenceSource> evidenceSources;
  final List<WorkoutExerciseLink> workoutExercises;

  const WorkoutDay({
    required this.id,
    required this.planId,
    required this.weekIndex,
    required this.dayIndex,
    required this.title,
    required this.trainingType,
    required this.decisionType,
    required this.estimatedMinutes,
    required this.intensity,
    required this.foamRollingSteps,
    required this.dynamicStretchSteps,
    required this.activationSteps,
    required this.warmupSteps,
    required this.mainSets,
    required this.accessoryWork,
    required this.cooldownSteps,
    required this.coachNotes,
    required this.evidenceSources,
    this.workoutExercises = const [],
  });

  factory WorkoutDay.fromJson(Map<String, dynamic> json) {
    final List<dynamic> evidenceJson =
        json['evidenceSources'] as List<dynamic>? ?? [];
    final List<dynamic> workoutExercisesJson =
        json['workoutExercises'] as List<dynamic>? ?? [];
    return WorkoutDay(
      id: json['id'] as String? ?? '',
      planId: json['planId'] as String? ?? '',
      weekIndex: (json['weekIndex'] as num?)?.toInt() ?? 0,
      dayIndex: (json['dayIndex'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      trainingType: trainingTypeFromJson(json['trainingType'] as String?),
      decisionType: trainingDecisionTypeFromJson(
        json['decisionType'] as String?,
      ),
      estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt() ?? 0,
      intensity: json['intensity'] as String? ?? '',
      foamRollingSteps:
          List<String>.from(json['foamRollingSteps'] as List<dynamic>? ?? []),
      dynamicStretchSteps: List<String>.from(
        json['dynamicStretchSteps'] as List<dynamic>? ?? [],
      ),
      activationSteps:
          List<String>.from(json['activationSteps'] as List<dynamic>? ?? []),
      warmupSteps:
          List<String>.from(json['warmupSteps'] as List<dynamic>? ?? []),
      mainSets: List<String>.from(json['mainSets'] as List<dynamic>? ?? []),
      accessoryWork:
          List<String>.from(json['accessoryWork'] as List<dynamic>? ?? []),
      cooldownSteps:
          List<String>.from(json['cooldownSteps'] as List<dynamic>? ?? []),
      coachNotes: json['coachNotes'] as String? ?? '',
      evidenceSources: evidenceJson
          .map(
            (dynamic value) =>
                EvidenceSource.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
      workoutExercises: workoutExercisesJson
          .map(
            (dynamic value) => WorkoutExerciseLink.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'planId': planId,
      'weekIndex': weekIndex,
      'dayIndex': dayIndex,
      'title': title,
      'trainingType': trainingType.jsonValue,
      'decisionType': decisionType.jsonValue,
      'estimatedMinutes': estimatedMinutes,
      'intensity': intensity,
      'foamRollingSteps': foamRollingSteps,
      'dynamicStretchSteps': dynamicStretchSteps,
      'activationSteps': activationSteps,
      'warmupSteps': warmupSteps,
      'mainSets': mainSets,
      'accessoryWork': accessoryWork,
      'cooldownSteps': cooldownSteps,
      'coachNotes': coachNotes,
      'evidenceSources': evidenceSources
          .map((EvidenceSource source) => source.toJson())
          .toList(),
      'workoutExercises': (workoutExercises.toList()
            ..sort(
              (WorkoutExerciseLink first, WorkoutExerciseLink second) =>
                  first.sequence.compareTo(second.sequence),
            ))
          .map((WorkoutExerciseLink item) => item.toJson())
          .toList(),
    };
  }

  WorkoutDay copyWith({
    String? id,
    String? planId,
    int? weekIndex,
    int? dayIndex,
    String? title,
    TrainingType? trainingType,
    TrainingDecisionType? decisionType,
    int? estimatedMinutes,
    String? intensity,
    List<String>? foamRollingSteps,
    List<String>? dynamicStretchSteps,
    List<String>? activationSteps,
    List<String>? warmupSteps,
    List<String>? mainSets,
    List<String>? accessoryWork,
    List<String>? cooldownSteps,
    String? coachNotes,
    List<EvidenceSource>? evidenceSources,
    List<WorkoutExerciseLink>? workoutExercises,
  }) {
    return WorkoutDay(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      weekIndex: weekIndex ?? this.weekIndex,
      dayIndex: dayIndex ?? this.dayIndex,
      title: title ?? this.title,
      trainingType: trainingType ?? this.trainingType,
      decisionType: decisionType ?? this.decisionType,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      intensity: intensity ?? this.intensity,
      foamRollingSteps: foamRollingSteps ?? this.foamRollingSteps,
      dynamicStretchSteps: dynamicStretchSteps ?? this.dynamicStretchSteps,
      activationSteps: activationSteps ?? this.activationSteps,
      warmupSteps: warmupSteps ?? this.warmupSteps,
      mainSets: mainSets ?? this.mainSets,
      accessoryWork: accessoryWork ?? this.accessoryWork,
      cooldownSteps: cooldownSteps ?? this.cooldownSteps,
      coachNotes: coachNotes ?? this.coachNotes,
      evidenceSources: evidenceSources ?? this.evidenceSources,
      workoutExercises: workoutExercises ?? this.workoutExercises,
    );
  }
}
