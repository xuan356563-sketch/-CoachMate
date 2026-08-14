class PlanGenerationContextSnapshot {
  final int weeklyTrainingDays;
  final int availableMinutes;
  final List<String> equipmentCodes;
  final String? populationTemplateId;
  final String? raceTypeCode;
  final DateTime? raceDate;
  final String? racePhaseCode;

  const PlanGenerationContextSnapshot({
    required this.weeklyTrainingDays,
    required this.availableMinutes,
    required this.equipmentCodes,
    this.populationTemplateId,
    this.raceTypeCode,
    this.raceDate,
    this.racePhaseCode,
  });

  factory PlanGenerationContextSnapshot.fromJson(Map<String, dynamic> json) {
    return PlanGenerationContextSnapshot(
      weeklyTrainingDays: (json['weeklyTrainingDays'] as num?)?.toInt() ?? 0,
      availableMinutes: (json['availableMinutes'] as num?)?.toInt() ?? 0,
      equipmentCodes: _strings(json['equipmentCodes']),
      populationTemplateId: json['populationTemplateId'] as String?,
      raceTypeCode: json['raceTypeCode'] as String?,
      raceDate: DateTime.tryParse(json['raceDate'] as String? ?? ''),
      racePhaseCode: json['racePhaseCode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'weeklyTrainingDays': weeklyTrainingDays,
        'availableMinutes': availableMinutes,
        'equipmentCodes': equipmentCodes,
        if (populationTemplateId != null)
          'populationTemplateId': populationTemplateId,
        if (raceTypeCode != null) 'raceTypeCode': raceTypeCode,
        if (raceDate != null) 'raceDate': _dateOnly(raceDate!),
        if (racePhaseCode != null) 'racePhaseCode': racePhaseCode,
      };
}

String _dateOnly(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().where((String item) => item.isNotEmpty).toList()
    : const <String>[];
