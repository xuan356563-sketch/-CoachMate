enum PsychRiskLevel {
  normal('normal', '常规'),
  observe('observe', '观察'),
  advise('advise', '建议恢复'),
  protect('protect', '保护');

  const PsychRiskLevel(this.jsonValue, this.label);

  final String jsonValue;
  final String label;

  static PsychRiskLevel fromJson(String? value) {
    return PsychRiskLevel.values.firstWhere(
      (PsychRiskLevel item) => item.jsonValue == value,
      orElse: () => PsychRiskLevel.normal,
    );
  }
}

class WeeklyPsychCheckIn {
  const WeeklyPsychCheckIn({
    this.motivation,
    this.perceivedStress,
    this.recoveryFeel,
    this.weekNote,
  });

  final int? motivation;
  final int? perceivedStress;
  final int? recoveryFeel;
  final String? weekNote;

  factory WeeklyPsychCheckIn.fromJson(Map<String, dynamic> json) {
    return WeeklyPsychCheckIn(
      motivation: _optionalFivePointValue(json['motivation']),
      perceivedStress: _optionalFivePointValue(json['perceivedStress']),
      recoveryFeel: _optionalFivePointValue(json['recoveryFeel']),
      weekNote: _optionalText(json['weekNote']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'motivation': motivation,
        'perceivedStress': perceivedStress,
        'recoveryFeel': recoveryFeel,
        'weekNote': weekNote,
      };
}

class WeeklyReportOption {
  const WeeklyReportOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;

  factory WeeklyReportOption.fromJson(Map<String, dynamic> json) {
    return WeeklyReportOption(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
      };
}

int? _optionalFivePointValue(Object? value) {
  final int? parsed = (value as num?)?.toInt();
  if (parsed == null || parsed < 1 || parsed > 5) return null;
  return parsed;
}

String? _optionalText(Object? value) {
  final String text = (value as String? ?? '').trim();
  return text.isEmpty ? null : text;
}
