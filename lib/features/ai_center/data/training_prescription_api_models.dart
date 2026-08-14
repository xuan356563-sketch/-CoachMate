import '../../../data/models/adaptation_signals.dart';

class TrainingPrescriptionSkillCapability {
  final String id;
  final String version;
  final String displayName;
  final List<String> sports;
  final String sourceSha256;
  final String runtimeSha256;
  final Map<String, String> fragmentSha256;

  const TrainingPrescriptionSkillCapability({
    required this.id,
    required this.version,
    required this.displayName,
    required this.sports,
    required this.sourceSha256,
    required this.runtimeSha256,
    this.fragmentSha256 = const <String, String>{},
  });

  factory TrainingPrescriptionSkillCapability.fromJson(
    Map<String, dynamic> json,
  ) {
    final Object? rawId = json['id'];
    final Object? rawVersion = json['version'];
    final Object? rawDisplayName = json['display_name'];
    final Object? rawSports = json['sports'];
    final Object? rawSourceSha256 = json['source_sha256'];
    final Object? rawRuntimeSha256 = json['runtime_sha256'];
    final Object? rawFragmentSha256 = json['fragment_sha256'];
    if (rawId is! String ||
        rawId.trim().isEmpty ||
        rawVersion is! String ||
        !_semanticVersion.hasMatch(rawVersion) ||
        rawDisplayName is! String ||
        rawDisplayName.trim().isEmpty ||
        rawSports is! List ||
        rawSports.isEmpty ||
        rawSports.any(
          (Object? sport) => sport is! String || sport.trim().isEmpty,
        ) ||
        rawSourceSha256 is! String ||
        !_sha256.hasMatch(rawSourceSha256) ||
        rawRuntimeSha256 is! String ||
        !_sha256.hasMatch(rawRuntimeSha256) ||
        (rawFragmentSha256 != null && rawFragmentSha256 is! Map)) {
      throw const FormatException('Skill 能力元数据格式无效');
    }
    final Map<String, String> fragmentSha256 = <String, String>{};
    if (rawFragmentSha256 is Map) {
      for (final MapEntry<Object?, Object?> item in rawFragmentSha256.entries) {
        if (item.key is! String ||
            (item.key! as String).trim().isEmpty ||
            item.value is! String ||
            !_sha256.hasMatch(item.value! as String)) {
          throw const FormatException('Skill 专项片段元数据格式无效');
        }
        fragmentSha256[item.key! as String] = item.value! as String;
      }
    }
    return TrainingPrescriptionSkillCapability(
      id: rawId.trim(),
      version: rawVersion,
      displayName: rawDisplayName.trim(),
      sports: rawSports.cast<String>().toList(growable: false),
      sourceSha256: rawSourceSha256,
      runtimeSha256: rawRuntimeSha256,
      fragmentSha256: Map<String, String>.unmodifiable(fragmentSha256),
    );
  }
}

class TrainingPrescriptionCapabilities {
  final bool enabled;
  final int contractVersion;
  final List<TrainingPrescriptionSkillCapability> skills;

  const TrainingPrescriptionCapabilities({
    required this.enabled,
    required this.contractVersion,
    required this.skills,
  });

  const TrainingPrescriptionCapabilities.unavailable()
      : this(enabled: false, contractVersion: 1, skills: const []);

  factory TrainingPrescriptionCapabilities.fromJson(
    Map<String, dynamic> json,
  ) {
    final Object? rawEnabled = json['enabled'];
    final Object? rawContractVersion = json['contract_version'];
    final Object? rawSkills = json['skills'];
    if (rawEnabled is! bool ||
        rawContractVersion is! int ||
        rawContractVersion != 1 ||
        rawSkills is! List ||
        (rawEnabled && rawSkills.isEmpty) ||
        rawSkills.any((Object? item) => item is! Map)) {
      throw const FormatException('训练计划能力契约格式无效');
    }
    final List<TrainingPrescriptionSkillCapability> skills = rawSkills
        .map(
          (Object? item) => TrainingPrescriptionSkillCapability.fromJson(
            Map<String, dynamic>.from(item! as Map),
          ),
        )
        .toList(growable: false);
    if (skills.map((skill) => skill.id).toSet().length != skills.length) {
      throw const FormatException('训练计划能力中存在重复的 Skill ID');
    }
    return TrainingPrescriptionCapabilities(
      enabled: rawEnabled,
      contractVersion: rawContractVersion,
      skills: skills,
    );
  }
}

class PopulationTemplateOption {
  final String id;
  final String title;
  final bool automaticPlanAllowed;
  final String progressionMode;
  final String? scheduleModifier;
  final List<String> screeningExtensionCodes;
  final List<String> derivedConstraintCodes;
  final List<String> sessionStructureCodes;
  final List<String> progressionRuleCodes;

  const PopulationTemplateOption({
    required this.id,
    required this.title,
    required this.automaticPlanAllowed,
    required this.progressionMode,
    this.scheduleModifier,
    this.screeningExtensionCodes = const <String>[],
    this.derivedConstraintCodes = const <String>[],
    this.sessionStructureCodes = const <String>[],
    this.progressionRuleCodes = const <String>[],
  });

  factory PopulationTemplateOption.fromJson(Map<String, dynamic> json) {
    final String id = json['id'] as String? ?? '';
    final String title = json['title'] as String? ?? '';
    final bool? automaticPlanAllowed = json['automatic_plan_allowed'] as bool?;
    final String progressionMode = json['progression_mode'] as String? ?? '';
    if (!_populationTemplateIds.contains(id) ||
        title.isEmpty ||
        automaticPlanAllowed == null ||
        !const <String>{'conservative', 'balanced'}.contains(progressionMode)) {
      throw const FormatException('训练模式目录格式无效');
    }
    return PopulationTemplateOption(
      id: id,
      title: title,
      automaticPlanAllowed: automaticPlanAllowed,
      progressionMode: progressionMode,
      scheduleModifier: json['schedule_modifier'] as String?,
      screeningExtensionCodes: _stringList(json['screening_extension_codes']),
      derivedConstraintCodes: _stringList(json['derived_constraint_codes']),
      sessionStructureCodes: _stringList(json['session_structure_codes']),
      progressionRuleCodes: _stringList(json['progression_rule_codes']),
    );
  }
}

class KnowledgeCatalogSummary {
  final String version;
  final List<PopulationTemplateOption> populationTemplates;
  final List<PopulationTemplateOption> allPopulationTemplates;
  final Set<String> verifiedEntryIds;
  final int verifiedPrincipleCount;
  final int verifiedTrainingTemplateCount;

  const KnowledgeCatalogSummary({
    required this.version,
    required this.populationTemplates,
    required this.allPopulationTemplates,
    required this.verifiedEntryIds,
    required this.verifiedPrincipleCount,
    required this.verifiedTrainingTemplateCount,
  });

  factory KnowledgeCatalogSummary.fromJson(Map<String, dynamic> json) {
    final String version = json['version'] as String? ?? '';
    final Object? rawPopulations = json['population_templates'];
    final Object? rawPrinciples = json['principles'];
    final Object? rawTemplates = json['training_templates'];
    if (version.isEmpty ||
        rawPopulations is! List ||
        rawPrinciples is! List ||
        rawTemplates is! List) {
      throw const FormatException('训练知识目录格式无效');
    }
    final List<PopulationTemplateOption> allPopulations = rawPopulations
        .whereType<Map>()
        .map(
          (Map<dynamic, dynamic> item) => PopulationTemplateOption.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
    final List<PopulationTemplateOption> populations = allPopulations
        .where((PopulationTemplateOption item) => item.automaticPlanAllowed)
        .toList(growable: false);
    if (allPopulations.length != 8 ||
        populations.length != 7 ||
        allPopulations.map((item) => item.id).toSet().length != 8) {
      throw const FormatException('自动训练模式目录不完整');
    }
    final Set<String> verifiedEntryIds = <String>{
      ...rawPrinciples
          .whereType<Map>()
          .where((Map item) => item['status'] == 'verified')
          .map((Map item) => item['id'])
          .whereType<String>(),
      ...rawTemplates
          .whereType<Map>()
          .where((Map item) => item['status'] == 'verified')
          .map((Map item) => item['id'])
          .whereType<String>(),
    };
    return KnowledgeCatalogSummary(
      version: version,
      populationTemplates: populations,
      allPopulationTemplates:
          List<PopulationTemplateOption>.unmodifiable(allPopulations),
      verifiedEntryIds: Set<String>.unmodifiable(verifiedEntryIds),
      verifiedPrincipleCount: rawPrinciples
          .whereType<Map>()
          .where((Map item) => item['status'] == 'verified')
          .length,
      verifiedTrainingTemplateCount: rawTemplates
          .whereType<Map>()
          .where((Map item) => item['status'] == 'verified')
          .length,
    );
  }
}

class TrainingPrescriptionRequestContext {
  final String goal;
  final String primarySport;
  final String? secondarySport;
  final String experienceLevel;

  /// 生理性别，只允许 `male` / `female`。
  ///
  /// 与其他字段不同，这一项**可选且默认为空**：档案里的「其他」「暂不填写」
  /// 没有可用于训练处方的确定含义，映射时会直接留空，请求体里也不会出现该键。
  final String? biologicalSex;

  final int weeklyTrainingDays;
  final int availableMinutes;
  final List<String> equipmentAccess;
  final String? raceType;
  final int? daysUntilRace;

  const TrainingPrescriptionRequestContext({
    required this.goal,
    required this.primarySport,
    required this.secondarySport,
    required this.experienceLevel,
    required this.weeklyTrainingDays,
    required this.availableMinutes,
    required this.equipmentAccess,
    required this.raceType,
    required this.daysUntilRace,
    this.biologicalSex,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'goal': goal,
        'primary_sport': primarySport,
        if (secondarySport != null) 'secondary_sport': secondarySport,
        'experience_level': experienceLevel,
        if (biologicalSex != null) 'biological_sex': biologicalSex,
        'weekly_training_days': weeklyTrainingDays,
        'available_minutes': availableMinutes,
        'equipment_access': equipmentAccess,
        if (raceType != null) 'race_type': raceType,
        if (daysUntilRace != null) 'days_until_race': daysUntilRace,
      };
}

class TrainingPrescriptionRequest {
  final int contractVersion;
  final String clientContextDigest;
  final TrainingPrescriptionRequestContext context;
  final bool force;

  const TrainingPrescriptionRequest({
    required this.contractVersion,
    required this.clientContextDigest,
    required this.context,
    this.force = false,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'contract_version': contractVersion,
        'client_context_digest': clientContextDigest,
        'context': context.toJson(),
        'force': force,
      };
}

class TrainingPrescriptionV2Request {
  final String clientContextDigest;
  final String populationTemplateId;
  final String knowledgeSnapshotVersion;
  final TrainingPrescriptionRequestContext context;
  final AdaptationSignals? adaptationSignals;
  final bool force;

  const TrainingPrescriptionV2Request({
    required this.clientContextDigest,
    required this.populationTemplateId,
    required this.knowledgeSnapshotVersion,
    required this.context,
    this.adaptationSignals,
    this.force = false,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'contract_version': 2,
        'client_context_digest': clientContextDigest,
        'population_template_id': populationTemplateId,
        'knowledge_snapshot_version': knowledgeSnapshotVersion,
        'context': context.toJson(),
        if (adaptationSignals != null)
          'adaptation_signals': adaptationSignals!.toJson(),
        'force': force,
      };
}

const Set<String> _populationTemplateIds = <String>{
  'sedentary_beginner',
  'low_impact_fat_loss',
  'strength_progression',
  'running_entry_or_race',
  'hyrox_hybrid',
  'older_adult_foundation',
  'shift_worker_flexible',
  'return_to_training_guarded',
};

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().where((String item) => item.isNotEmpty).toList()
    : const <String>[];

final RegExp _semanticVersion = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?'
  r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
);
final RegExp _sha256 = RegExp(r'^[a-f0-9]{64}$');
