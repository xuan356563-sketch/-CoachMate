class FormalAiPlan {
  final String id;
  final DateTime generatedAt;
  final String title;
  final String goalLabel;
  final String durationLabel;
  final String weeklyStructure;
  final String progressionRule;
  final String safetyRule;
  final List<String> weeklyFocus;
  final List<String> decisionRules;

  const FormalAiPlan({
    required this.id,
    required this.generatedAt,
    required this.title,
    required this.goalLabel,
    required this.durationLabel,
    required this.weeklyStructure,
    required this.progressionRule,
    required this.safetyRule,
    required this.weeklyFocus,
    required this.decisionRules,
  });

  String get generatedDateLabel {
    return '${generatedAt.year}-${generatedAt.month.toString().padLeft(2, '0')}-${generatedAt.day.toString().padLeft(2, '0')}';
  }

  factory FormalAiPlan.fromJson(Map<String, dynamic> json) {
    return FormalAiPlan(
      id: json['id'] as String? ?? '',
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      title: json['title'] as String? ?? '',
      goalLabel: json['goalLabel'] as String? ?? '',
      durationLabel: json['durationLabel'] as String? ?? '',
      weeklyStructure: json['weeklyStructure'] as String? ?? '',
      progressionRule: json['progressionRule'] as String? ?? '',
      safetyRule: json['safetyRule'] as String? ?? '',
      weeklyFocus:
          List<String>.from(json['weeklyFocus'] as List<dynamic>? ?? []),
      decisionRules:
          List<String>.from(json['decisionRules'] as List<dynamic>? ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'generatedAt': generatedAt.toIso8601String(),
      'title': title,
      'goalLabel': goalLabel,
      'durationLabel': durationLabel,
      'weeklyStructure': weeklyStructure,
      'progressionRule': progressionRule,
      'safetyRule': safetyRule,
      'weeklyFocus': weeklyFocus,
      'decisionRules': decisionRules,
    };
  }
}
