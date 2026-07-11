import 'evidence_source.dart';

enum MealScenario {
  takeaway,
  canteen,
  homeCooking,
}

extension MealScenarioJson on MealScenario {
  String get jsonValue {
    switch (this) {
      case MealScenario.takeaway:
        return 'takeaway';
      case MealScenario.canteen:
        return 'canteen';
      case MealScenario.homeCooking:
        return 'home_cooking';
    }
  }

  String get label {
    switch (this) {
      case MealScenario.takeaway:
        return '外卖';
      case MealScenario.canteen:
        return '食堂';
      case MealScenario.homeCooking:
        return '自炊';
    }
  }
}

MealScenario mealScenarioFromJson(String? value) {
  switch (value) {
    case 'takeaway':
      return MealScenario.takeaway;
    case 'canteen':
      return MealScenario.canteen;
    case 'home_cooking':
      return MealScenario.homeCooking;
    default:
      return MealScenario.takeaway;
  }
}

class MealPreference {
  final MealScenario scenario;

  const MealPreference({
    required this.scenario,
  });

  factory MealPreference.fromJson(Map<String, dynamic> json) {
    return MealPreference(
      scenario: mealScenarioFromJson(json['scenario'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scenario': scenario.jsonValue,
    };
  }
}

class MealGuide {
  final String id;
  final MealScenario scenario;
  final String title;
  final String dayLabel;
  final String instruction;
  final String formula;
  final String addOneThing;
  final List<String> avoidItems;
  final String reason;
  final List<EvidenceSource> evidenceSources;

  const MealGuide({
    required this.id,
    required this.scenario,
    required this.title,
    required this.dayLabel,
    required this.instruction,
    required this.formula,
    required this.addOneThing,
    required this.avoidItems,
    required this.reason,
    required this.evidenceSources,
  });

  factory MealGuide.fromJson(Map<String, dynamic> json) {
    final List<dynamic> evidenceJson =
        json['evidenceSources'] as List<dynamic>? ?? [];
    return MealGuide(
      id: json['id'] as String? ?? '',
      scenario: mealScenarioFromJson(json['scenario'] as String?),
      title: json['title'] as String? ?? '',
      dayLabel: json['dayLabel'] as String? ?? '',
      instruction: json['instruction'] as String? ?? '',
      formula: json['formula'] as String? ?? '',
      addOneThing: json['addOneThing'] as String? ?? '',
      avoidItems: List<String>.from(json['avoidItems'] as List<dynamic>? ?? []),
      reason: json['reason'] as String? ?? '',
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
      'scenario': scenario.jsonValue,
      'title': title,
      'dayLabel': dayLabel,
      'instruction': instruction,
      'formula': formula,
      'addOneThing': addOneThing,
      'avoidItems': avoidItems,
      'reason': reason,
      'evidenceSources': evidenceSources
          .map((EvidenceSource source) => source.toJson())
          .toList(),
    };
  }
}
