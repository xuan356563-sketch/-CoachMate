import 'ai_knowledge_citation.dart';
import 'evidence_source.dart';
import 'user_profile.dart';
import 'workout_day.dart';

class TrainingPlan {
  final String id;
  final String title;
  final String description;
  final MainSport sportType;
  final String level;
  final int durationWeeks;
  final String goal;
  final String weeklyStructure;
  final List<WorkoutDay> workoutDays;
  final List<EvidenceSource> evidenceSources;
  final List<AiKnowledgeCitation> knowledgeCitations;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TrainingPlan({
    required this.id,
    required this.title,
    required this.description,
    required this.sportType,
    required this.level,
    required this.durationWeeks,
    required this.goal,
    required this.weeklyStructure,
    required this.workoutDays,
    required this.evidenceSources,
    this.knowledgeCitations = const <AiKnowledgeCitation>[],
    required this.createdAt,
    required this.updatedAt,
  });

  factory TrainingPlan.fromJson(Map<String, dynamic> json) {
    final List<dynamic> workoutJson =
        json['workoutDays'] as List<dynamic>? ?? [];
    final List<dynamic> evidenceJson =
        json['evidenceSources'] as List<dynamic>? ?? [];
    final List<dynamic> citationJson =
        json['knowledgeCitations'] as List<dynamic>? ?? [];
    return TrainingPlan(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      sportType: mainSportFromJson(json['sportType'] as String?),
      level: json['level'] as String? ?? '',
      durationWeeks: (json['durationWeeks'] as num?)?.toInt() ?? 0,
      goal: json['goal'] as String? ?? '',
      weeklyStructure: json['weeklyStructure'] as String? ?? '',
      workoutDays: workoutJson
          .map(
            (dynamic value) => WorkoutDay.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList(),
      evidenceSources: evidenceJson
          .map(
            (dynamic value) =>
                EvidenceSource.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
      knowledgeCitations: citationJson
          .whereType<Map>()
          .map(
            (Map<dynamic, dynamic> value) => AiKnowledgeCitation.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList(growable: false),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'sportType': sportType.jsonValue,
      'level': level,
      'durationWeeks': durationWeeks,
      'goal': goal,
      'weeklyStructure': weeklyStructure,
      'workoutDays': workoutDays.map((WorkoutDay day) => day.toJson()).toList(),
      'evidenceSources': evidenceSources
          .map((EvidenceSource source) => source.toJson())
          .toList(),
      'knowledgeCitations': knowledgeCitations
          .map((AiKnowledgeCitation source) => source.toJson())
          .toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  TrainingPlan copyWith({
    String? id,
    String? title,
    String? description,
    MainSport? sportType,
    String? level,
    int? durationWeeks,
    String? goal,
    String? weeklyStructure,
    List<WorkoutDay>? workoutDays,
    List<EvidenceSource>? evidenceSources,
    List<AiKnowledgeCitation>? knowledgeCitations,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TrainingPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      sportType: sportType ?? this.sportType,
      level: level ?? this.level,
      durationWeeks: durationWeeks ?? this.durationWeeks,
      goal: goal ?? this.goal,
      weeklyStructure: weeklyStructure ?? this.weeklyStructure,
      workoutDays: workoutDays ?? this.workoutDays,
      evidenceSources: evidenceSources ?? this.evidenceSources,
      knowledgeCitations: knowledgeCitations ?? this.knowledgeCitations,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
