import 'evidence_source.dart';
import 'exercise_body_profile.dart';
import 'user_profile.dart';

enum ExerciseCategory {
  runningDrill,
  endurance,
  strength,
  mobility,
  activation,
  rehab,
  core,
  warmup,
  cooldown,
  hyrox,
}

extension ExerciseCategoryJson on ExerciseCategory {
  String get jsonValue {
    switch (this) {
      case ExerciseCategory.runningDrill:
        return 'running_drill';
      case ExerciseCategory.endurance:
        return 'endurance';
      case ExerciseCategory.strength:
        return 'strength';
      case ExerciseCategory.mobility:
        return 'mobility';
      case ExerciseCategory.activation:
        return 'activation';
      case ExerciseCategory.rehab:
        return 'rehab';
      case ExerciseCategory.core:
        return 'core';
      case ExerciseCategory.warmup:
        return 'warmup';
      case ExerciseCategory.cooldown:
        return 'cooldown';
      case ExerciseCategory.hyrox:
        return 'hyrox';
    }
  }

  String get label {
    switch (this) {
      case ExerciseCategory.runningDrill:
        return '跑姿技术';
      case ExerciseCategory.endurance:
        return '跑步耐力';
      case ExerciseCategory.strength:
        return '力量';
      case ExerciseCategory.mobility:
        return '灵活性';
      case ExerciseCategory.activation:
        return '激活';
      case ExerciseCategory.rehab:
        return '康复';
      case ExerciseCategory.core:
        return '核心';
      case ExerciseCategory.warmup:
        return '热身';
      case ExerciseCategory.cooldown:
        return '放松';
      case ExerciseCategory.hyrox:
        return 'HYROX';
    }
  }
}

ExerciseCategory exerciseCategoryFromJson(String? value) {
  switch (value) {
    case 'running_drill':
      return ExerciseCategory.runningDrill;
    case 'endurance':
      return ExerciseCategory.endurance;
    case 'strength':
      return ExerciseCategory.strength;
    case 'mobility':
      return ExerciseCategory.mobility;
    case 'activation':
      return ExerciseCategory.activation;
    case 'rehab':
      return ExerciseCategory.rehab;
    case 'core':
      return ExerciseCategory.core;
    case 'warmup':
      return ExerciseCategory.warmup;
    case 'cooldown':
      return ExerciseCategory.cooldown;
    case 'hyrox':
      return ExerciseCategory.hyrox;
    default:
      return ExerciseCategory.strength;
  }
}

enum ExerciseMediaStatus {
  precise,
  reference,
  placeholder,
}

extension ExerciseMediaStatusJson on ExerciseMediaStatus {
  String get jsonValue {
    switch (this) {
      case ExerciseMediaStatus.precise:
        return 'precise';
      case ExerciseMediaStatus.reference:
        return 'reference';
      case ExerciseMediaStatus.placeholder:
        return 'placeholder';
    }
  }

  String get label {
    switch (this) {
      case ExerciseMediaStatus.precise:
        return '精确示范';
      case ExerciseMediaStatus.reference:
        return '通用参考';
      case ExerciseMediaStatus.placeholder:
        return '媒体占位';
    }
  }
}

ExerciseMediaStatus exerciseMediaStatusFromJson(String? value) {
  switch (value) {
    case 'precise':
      return ExerciseMediaStatus.precise;
    case 'reference':
      return ExerciseMediaStatus.reference;
    case 'placeholder':
    default:
      return ExerciseMediaStatus.placeholder;
  }
}

enum ExerciseRelationType {
  replacement,
  regression,
  progression,
}

extension ExerciseRelationTypeJson on ExerciseRelationType {
  String get jsonValue {
    switch (this) {
      case ExerciseRelationType.replacement:
        return 'replacement';
      case ExerciseRelationType.regression:
        return 'regression';
      case ExerciseRelationType.progression:
        return 'progression';
    }
  }

  String get label {
    switch (this) {
      case ExerciseRelationType.replacement:
        return '替代';
      case ExerciseRelationType.regression:
        return '退阶';
      case ExerciseRelationType.progression:
        return '进阶';
    }
  }
}

ExerciseRelationType exerciseRelationTypeFromJson(String? value) {
  switch (value) {
    case 'regression':
      return ExerciseRelationType.regression;
    case 'progression':
      return ExerciseRelationType.progression;
    case 'replacement':
    default:
      return ExerciseRelationType.replacement;
  }
}

class ExerciseRelation {
  final ExerciseRelationType type;
  final String targetExerciseId;
  final String reason;

  const ExerciseRelation({
    required this.type,
    required this.targetExerciseId,
    required this.reason,
  });

  factory ExerciseRelation.fromJson(Map<String, dynamic> json) {
    return ExerciseRelation(
      type: exerciseRelationTypeFromJson(json['type'] as String?),
      targetExerciseId: json['targetExerciseId'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.jsonValue,
      'targetExerciseId': targetExerciseId,
      'reason': reason,
    };
  }
}

class Exercise {
  final String id;
  final String name;
  final ExerciseCategory category;
  final List<String> targetMuscles;
  final List<MainSport> sportTags;
  final String description;
  final List<String> steps;
  final List<String> commonMistakes;
  final String setsAndReps;
  final List<String> equipment;
  final String? mediaUrl;
  final List<String> mediaUrls;
  final ExerciseMediaStatus mediaStatus;
  final ExerciseBodyProfile? bodyProfile;
  final String breathingCue;
  final List<String> contraindications;
  final List<String> suitableFor;
  final List<EvidenceSource> evidenceSources;
  final List<ExerciseRelation> relations;

  const Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.targetMuscles,
    required this.sportTags,
    required this.description,
    required this.steps,
    required this.commonMistakes,
    required this.setsAndReps,
    required this.equipment,
    required this.mediaUrl,
    this.mediaUrls = const [],
    this.mediaStatus = ExerciseMediaStatus.placeholder,
    this.bodyProfile,
    this.breathingCue = '保持平稳呼吸，动作质量下降就停止。',
    this.contraindications = const ['出现尖锐疼痛、头晕或动作失稳时停止。'],
    this.suitableFor = const ['基础训练'],
    required this.evidenceSources,
    this.relations = const [],
  });

  factory Exercise.fromJson(Map<String, dynamic> json) {
    final List<dynamic> sportsJson = json['sportTags'] as List<dynamic>? ?? [];
    final List<dynamic> evidenceJson =
        json['evidenceSources'] as List<dynamic>? ?? [];
    final List<dynamic> relationsJson =
        json['relations'] as List<dynamic>? ?? [];
    return Exercise(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: exerciseCategoryFromJson(json['category'] as String?),
      targetMuscles:
          List<String>.from(json['targetMuscles'] as List<dynamic>? ?? []),
      sportTags: sportsJson
          .map((dynamic value) => mainSportFromJson(value as String?))
          .toList(),
      description: json['description'] as String? ?? '',
      steps: List<String>.from(json['steps'] as List<dynamic>? ?? []),
      commonMistakes:
          List<String>.from(json['commonMistakes'] as List<dynamic>? ?? []),
      setsAndReps: json['setsAndReps'] as String? ?? '',
      equipment: List<String>.from(json['equipment'] as List<dynamic>? ?? []),
      mediaUrl: json['mediaUrl'] as String?,
      mediaUrls: List<String>.from(json['mediaUrls'] as List<dynamic>? ?? []),
      mediaStatus: exerciseMediaStatusFromJson(json['mediaStatus'] as String?),
      bodyProfile: json['bodyProfile'] is Map<String, dynamic>
          ? ExerciseBodyProfile.fromJson(
              json['bodyProfile'] as Map<String, dynamic>,
            )
          : bodyProfileForExercise(json['id'] as String? ?? ''),
      breathingCue: json['breathingCue'] as String? ?? '保持平稳呼吸，动作质量下降就停止。',
      contraindications: List<String>.from(
        json['contraindications'] as List<dynamic>? ?? ['出现尖锐疼痛、头晕或动作失稳时停止。'],
      ),
      suitableFor: List<String>.from(
        json['suitableFor'] as List<dynamic>? ?? ['基础训练'],
      ),
      evidenceSources: evidenceJson
          .map(
            (dynamic value) =>
                EvidenceSource.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
      relations: relationsJson
          .map(
            (dynamic value) => ExerciseRelation.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category.jsonValue,
      'targetMuscles': targetMuscles,
      'sportTags': sportTags.map((MainSport item) => item.jsonValue).toList(),
      'description': description,
      'steps': steps,
      'commonMistakes': commonMistakes,
      'setsAndReps': setsAndReps,
      'equipment': equipment,
      'mediaUrl': mediaUrl,
      'mediaUrls': mediaUrls,
      'mediaStatus': mediaStatus.jsonValue,
      'bodyProfile': bodyEngineProfile.toJson(),
      'breathingCue': breathingCue,
      'contraindications': contraindications,
      'suitableFor': suitableFor,
      'evidenceSources': evidenceSources
          .map((EvidenceSource source) => source.toJson())
          .toList(),
      'relations': relations
          .map((ExerciseRelation relation) => relation.toJson())
          .toList(),
    };
  }

  ExerciseBodyProfile get bodyEngineProfile {
    return bodyProfile ?? bodyProfileForExercise(id);
  }
}
