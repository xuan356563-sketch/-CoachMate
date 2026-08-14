import 'ai_knowledge_citation.dart';
import 'workout_day.dart';
import 'exercise_training_profile.dart';

enum AiIntensityBand { recovery, easy, moderate, challenging }

extension AiIntensityBandJson on AiIntensityBand {
  String get jsonValue => switch (this) {
        AiIntensityBand.recovery => 'recovery',
        AiIntensityBand.easy => 'easy',
        AiIntensityBand.moderate => 'moderate',
        AiIntensityBand.challenging => 'challenging',
      };
}

AiIntensityBand aiIntensityBandFromJson(String? value) => switch (value) {
      'recovery' => AiIntensityBand.recovery,
      'easy' => AiIntensityBand.easy,
      'moderate' => AiIntensityBand.moderate,
      'challenging' => AiIntensityBand.challenging,
      _ => throw const FormatException('训练处方包含未知强度等级'),
    };

enum AiProgressionMode { conservative, balanced }

extension AiProgressionModeJson on AiProgressionMode {
  String get jsonValue => switch (this) {
        AiProgressionMode.conservative => 'conservative',
        AiProgressionMode.balanced => 'balanced',
      };
}

AiProgressionMode aiProgressionModeFromJson(String? value) => switch (value) {
      'balanced' => AiProgressionMode.balanced,
      'conservative' => AiProgressionMode.conservative,
      _ => throw const FormatException('训练处方包含未知进阶模式'),
    };

class AiSessionBlueprint {
  final TrainingType trainingType;
  final int durationMinutes;
  final AiIntensityBand intensityBand;
  final List<String> focusCodes;
  final DimensionFocus dimensionFocus;
  final List<LegTrainingElement> legElements;

  const AiSessionBlueprint({
    required this.trainingType,
    required this.durationMinutes,
    required this.intensityBand,
    required this.focusCodes,
    this.dimensionFocus = const DimensionFocus(),
    this.legElements = const <LegTrainingElement>[],
  });

  factory AiSessionBlueprint.fromJson(Map<String, dynamic> json) {
    final TrainingType trainingType = _strictTrainingType(
      json['training_type'] as String? ?? json['trainingType'] as String?,
    );
    final List<String> focusCodes =
        _strings(json['focus_codes'] ?? json['focus']);
    if (focusCodes.isEmpty ||
        focusCodes.length > 3 ||
        focusCodes.toSet().length != focusCodes.length ||
        focusCodes.any((String item) => !_allowedFocusCodes.contains(item))) {
      throw const FormatException('训练处方包含未知课程重点');
    }
    final int durationMinutes = (json['duration_minutes'] as num?)?.toInt() ??
        (json['durationMinutes'] as num?)?.toInt() ??
        0;
    if (durationMinutes < 20 || durationMinutes > 180) {
      throw const FormatException('训练处方课程时长必须在 20–180 分钟之间');
    }
    final Object? rawStructure = json['structure_profile'];
    DimensionFocus dimensionFocus = const DimensionFocus();
    List<LegTrainingElement> legElements = const <LegTrainingElement>[];
    if (rawStructure != null) {
      if (rawStructure is! Map) {
        throw const FormatException('训练处方结构标签格式无效');
      }
      final List<String> primaryCodes =
          _strings(rawStructure['primary_dimension_codes']);
      final List<String> touchCodes =
          _strings(rawStructure['touch_dimension_codes']);
      final List<String> legCodes = _strings(rawStructure['leg_element_codes']);
      if (<String>[...primaryCodes, ...touchCodes]
              .any((String code) => trainingDimensionFromJson(code) == null) ||
          legCodes
              .any((String code) => legTrainingElementFromJson(code) == null)) {
        throw const FormatException('训练处方包含未知结构标签');
      }
      dimensionFocus = DimensionFocus(
        primary: primaryCodes
            .map(trainingDimensionFromJson)
            .whereType<TrainingDimension>()
            .take(2)
            .toList(growable: false),
        touch: touchCodes
            .map(trainingDimensionFromJson)
            .whereType<TrainingDimension>()
            .toList(growable: false),
      );
      legElements = legCodes
          .map(legTrainingElementFromJson)
          .whereType<LegTrainingElement>()
          .toList(growable: false);
    }
    return AiSessionBlueprint(
      trainingType: trainingType,
      durationMinutes: durationMinutes,
      intensityBand: aiIntensityBandFromJson(
        json['intensity_band'] as String? ?? json['intensityBand'] as String?,
      ),
      focusCodes: focusCodes,
      dimensionFocus: dimensionFocus,
      legElements: legElements,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'training_type': trainingType.jsonValue,
        'duration_minutes': durationMinutes,
        'intensity_band': intensityBand.jsonValue,
        'focus_codes': focusCodes,
        if (!dimensionFocus.isEmpty || legElements.isNotEmpty)
          'structure_profile': <String, dynamic>{
            'primary_dimension_codes': dimensionFocus.primary
                .map((TrainingDimension item) => item.jsonValue)
                .toList(growable: false),
            'touch_dimension_codes': dimensionFocus.touch
                .map((TrainingDimension item) => item.jsonValue)
                .toList(growable: false),
            'leg_element_codes': legElements
                .map((LegTrainingElement item) => item.jsonValue)
                .toList(growable: false),
          },
      };
}

class AiSkillRef {
  final String id;
  final String version;
  final String displayName;
  final String sourceSha256;
  final String runtimeSha256;
  final String? fragmentSha256;
  final String coverage;
  final String selectionReason;

  const AiSkillRef({
    required this.id,
    required this.version,
    required this.displayName,
    required this.sourceSha256,
    required this.runtimeSha256,
    this.fragmentSha256,
    required this.coverage,
    required this.selectionReason,
  });

  factory AiSkillRef.fromJson(
    Map<String, dynamic> json, {
    String? selectionReason,
  }) {
    final String id = json['id'] as String? ?? '';
    final String version = json['version'] as String? ?? '';
    final String displayName =
        json['display_name'] as String? ?? json['displayName'] as String? ?? '';
    final String sourceSha256 = json['source_sha256'] as String? ??
        json['sourceSha256'] as String? ??
        '';
    final String runtimeSha256 = json['runtime_sha256'] as String? ??
        json['runtimeSha256'] as String? ??
        '';
    final String? fragmentSha256 = json['fragment_sha256'] as String?;
    final String coverage = json['coverage'] as String? ?? '';
    final String resolvedReason =
        json['selection_reason'] as String? ?? selectionReason ?? '';
    if (id.isEmpty ||
        version.isEmpty ||
        displayName.isEmpty ||
        !_isSha256(sourceSha256) ||
        !_isSha256(runtimeSha256) ||
        (fragmentSha256 != null && !_isSha256(fragmentSha256)) ||
        !_allowedCoverage.contains(coverage) ||
        resolvedReason.isEmpty) {
      throw const FormatException('Skill 来源元数据不完整或未通过校验');
    }
    return AiSkillRef(
      id: id,
      version: version,
      displayName: displayName,
      sourceSha256: sourceSha256,
      runtimeSha256: runtimeSha256,
      fragmentSha256: fragmentSha256,
      coverage: coverage,
      selectionReason: resolvedReason,
    );
  }

  String get shortRuntimeHash =>
      runtimeSha256.length <= 8 ? runtimeSha256 : runtimeSha256.substring(0, 8);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'version': version,
        'display_name': displayName,
        'source_sha256': sourceSha256,
        'runtime_sha256': runtimeSha256,
        'fragment_sha256': fragmentSha256,
        'coverage': coverage,
        'selection_reason': selectionReason,
      };
}

class AiGenerationMeta {
  final String contractVersion;
  final String clientContextDigest;
  final String model;
  final bool cacheHit;
  final String promptContractVersion;
  final String? knowledgeSnapshotVersion;
  final String? structurePolicyVersion;
  final String generationMode;
  final bool appCacheHit;
  final int inputTokens;
  final int outputTokens;
  final int promptCacheHitTokens;
  final int promptCacheMissTokens;

  const AiGenerationMeta({
    required this.contractVersion,
    required this.clientContextDigest,
    required this.model,
    required this.cacheHit,
    this.promptContractVersion = '',
    this.knowledgeSnapshotVersion,
    this.structurePolicyVersion,
    this.generationMode = 'cloud_adaptation',
    this.appCacheHit = false,
    int? tokenUsage,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.promptCacheHitTokens = 0,
    this.promptCacheMissTokens = 0,
  }) : _legacyTokenUsage = tokenUsage;

  final int? _legacyTokenUsage;

  int get tokenUsage => _legacyTokenUsage ?? (inputTokens + outputTokens);

  factory AiGenerationMeta.fromJson(Map<String, dynamic> json) {
    final Object? contractVersion =
        json['contract_version'] ?? json['contractVersion'];
    final Object? tokenUsage = json['token_usage'] ?? json['tokenUsage'];
    final int inputTokens = (json['input_tokens'] as num?)?.toInt() ??
        (tokenUsage is Map
            ? (tokenUsage['input_tokens'] as num?)?.toInt()
            : null) ??
        0;
    final int outputTokens = (json['output_tokens'] as num?)?.toInt() ??
        (tokenUsage is Map
            ? (tokenUsage['output_tokens'] as num?)?.toInt()
            : null) ??
        0;
    final String normalizedContract = contractVersion?.toString() ?? '';
    final String clientContextDigest =
        json['client_context_digest'] as String? ??
            json['clientContextDigest'] as String? ??
            '';
    final String model = json['model'] as String? ?? '';
    final Object? cacheHitValue = json['cache_hit'] ?? json['cacheHit'];
    final Object? appCacheHitValue =
        json['app_cache_hit'] ?? json['appCacheHit'] ?? cacheHitValue;
    final String promptContractVersion =
        json['prompt_contract_version'] as String? ?? '';
    final String? knowledgeSnapshotVersion =
        json['knowledge_snapshot_version'] as String?;
    final String? structurePolicyVersion =
        json['structure_policy_version'] as String?;
    final String generationMode =
        json['generation_mode'] as String? ?? 'cloud_adaptation';
    final Set<String> supportedContracts = <String>{'1', '2'};
    final Set<String> supportedPromptContracts = <String>{
      'training-prescription-v1',
      'training-prescription-v2',
    };
    if (!supportedContracts.contains(normalizedContract) ||
        !_isSha256(clientContextDigest) ||
        model.isEmpty ||
        cacheHitValue is! bool ||
        appCacheHitValue is! bool ||
        !supportedPromptContracts.contains(promptContractVersion) ||
        (normalizedContract == '2' &&
            (knowledgeSnapshotVersion == null ||
                knowledgeSnapshotVersion.isEmpty)) ||
        !const <String>{
          'local_template',
          'cloud_adaptation',
          'local_safe_fallback',
        }.contains(generationMode)) {
      throw const FormatException('训练处方生成元数据不完整或版本不受支持');
    }
    return AiGenerationMeta(
      contractVersion: normalizedContract,
      clientContextDigest: clientContextDigest,
      model: model,
      cacheHit: cacheHitValue,
      promptContractVersion: promptContractVersion,
      knowledgeSnapshotVersion: knowledgeSnapshotVersion,
      structurePolicyVersion: structurePolicyVersion,
      generationMode: generationMode,
      appCacheHit: appCacheHitValue,
      tokenUsage: tokenUsage is num ? tokenUsage.toInt() : null,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      promptCacheHitTokens:
          (json['prompt_cache_hit_tokens'] as num?)?.toInt() ?? 0,
      promptCacheMissTokens:
          (json['prompt_cache_miss_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'contract_version': contractVersion,
        'client_context_digest': clientContextDigest,
        'model': model,
        'cache_hit': cacheHit,
        'app_cache_hit': appCacheHit,
        'prompt_contract_version': promptContractVersion,
        if (knowledgeSnapshotVersion != null)
          'knowledge_snapshot_version': knowledgeSnapshotVersion,
        if (structurePolicyVersion != null)
          'structure_policy_version': structurePolicyVersion,
        'generation_mode': generationMode,
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'prompt_cache_hit_tokens': promptCacheHitTokens,
        'prompt_cache_miss_tokens': promptCacheMissTokens,
        if (_legacyTokenUsage != null) 'token_usage': _legacyTokenUsage,
      };
}

class AiTrainingPrescription {
  final String cycleFocus;
  final AiProgressionMode progressionMode;
  final List<AiSessionBlueprint> weeklySessions;
  final AiSkillRef skill;
  final AiGenerationMeta generationMeta;
  final String selectionReasonCode;
  final List<AiKnowledgeCitation> knowledgeCitations;

  const AiTrainingPrescription({
    required this.cycleFocus,
    required this.progressionMode,
    required this.weeklySessions,
    required this.skill,
    required this.generationMeta,
    this.selectionReasonCode = '',
    this.knowledgeCitations = const <AiKnowledgeCitation>[],
  });

  factory AiTrainingPrescription.fromJson(Map<String, dynamic> json) {
    final Object? rawSessions = json['weekly_sessions'] ?? json['sessions'];
    if (rawSessions is! List) {
      throw const FormatException('训练处方缺少每周课程列表');
    }
    if (rawSessions.isEmpty || rawSessions.length > 6) {
      throw const FormatException('训练处方每周课程数必须在 1–6 次之间');
    }
    final Object? rawSkill = json['applied_skill'];
    final Object? rawMeta = json['generation_meta'];
    if (rawSkill is! Map || rawMeta is! Map) {
      throw const FormatException('训练处方缺少 Skill 或生成元数据');
    }
    final String cycleFocus =
        json['cycle_focus'] as String? ?? json['cycle_label'] as String? ?? '';
    if (!const <String>{'base', 'build', 'specific', 'taper'}
        .contains(cycleFocus)) {
      throw const FormatException('训练处方包含未知周期重点');
    }
    final String selectionReasonCode =
        json['selection_reason_code'] as String? ?? '';
    if (!_allowedSelectionReasonCodes.contains(selectionReasonCode)) {
      throw const FormatException('Skill 选择原因代码不受支持');
    }
    final AiGenerationMeta generationMeta =
        AiGenerationMeta.fromJson(Map<String, dynamic>.from(rawMeta));
    final Object? rawCitations = json['knowledge_citations'];
    if (rawCitations != null && rawCitations is! List) {
      throw const FormatException('训练知识引用格式错误');
    }
    final List<AiKnowledgeCitation> citations =
        (rawCitations as List? ?? const []).map((Object? value) {
      if (value is! Map) {
        throw const FormatException('训练知识引用格式错误');
      }
      return AiKnowledgeCitation.fromJson(
        Map<String, dynamic>.from(value),
      );
    }).toList(growable: false);
    if (generationMeta.contractVersion == '2' && citations.isEmpty) {
      throw const FormatException('V2 训练处方缺少审核知识引用');
    }
    if (generationMeta.contractVersion == '2' &&
        citations.any(
          (AiKnowledgeCitation item) =>
              item.contentVersion != generationMeta.knowledgeSnapshotVersion,
        )) {
      throw const FormatException('训练知识引用版本与目录快照不一致');
    }
    return AiTrainingPrescription(
      cycleFocus: cycleFocus,
      progressionMode: aiProgressionModeFromJson(
        json['progression_mode'] as String? ??
            json['progression_focus'] as String?,
      ),
      weeklySessions: rawSessions.map((Object? value) {
        if (value is! Map) {
          throw const FormatException('训练处方课程格式错误');
        }
        return AiSessionBlueprint.fromJson(Map<String, dynamic>.from(value));
      }).toList(growable: false),
      skill: AiSkillRef.fromJson(
        Map<String, dynamic>.from(rawSkill),
        selectionReason: json['selection_reason'] as String?,
      ),
      generationMeta: generationMeta,
      selectionReasonCode: selectionReasonCode,
      knowledgeCitations: List<AiKnowledgeCitation>.unmodifiable(citations),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cycle_focus': cycleFocus,
        'progression_mode': progressionMode.jsonValue,
        'weekly_sessions': weeklySessions
            .map((AiSessionBlueprint item) => item.toJson())
            .toList(growable: false),
        'applied_skill': skill.toJson(),
        'selection_reason': skill.selectionReason,
        'selection_reason_code': selectionReasonCode,
        'generation_meta': generationMeta.toJson(),
        if (knowledgeCitations.isNotEmpty)
          'knowledge_citations': knowledgeCitations
              .map((AiKnowledgeCitation item) => item.toJson())
              .toList(growable: false),
      };
}

TrainingType _strictTrainingType(String? value) => switch (value) {
      'easy_run' => TrainingType.easyRun,
      'tempo_run' => TrainingType.tempoRun,
      'interval_run' => TrainingType.intervalRun,
      'long_run' => TrainingType.longRun,
      'strength' => TrainingType.strength,
      'hyrox' => TrainingType.hyrox,
      'mobility' => TrainingType.mobility,
      'cross_training' => TrainingType.crossTraining,
      'rehab' || 'rest' => throw const FormatException('训练处方不允许康复或休息类型'),
      _ => throw const FormatException('训练处方包含未知训练类型'),
    };

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().where((String item) => item.isNotEmpty).toList()
    : const <String>[];

const Set<String> _allowedFocusCodes = <String>{
  'aerobic_base',
  'movement_quality',
  'full_body_strength',
  'lower_body_strength',
  'upper_body_strength',
  'threshold',
  'speed',
  'long_endurance',
  'hyrox_transition',
  'hyrox_station',
  'mobility',
  'recovery',
};

const Set<String> _allowedCoverage = <String>{
  'general_fitness',
  'strength',
  'fat_loss',
  'marathon',
  'trail_running',
  'hyrox',
};

const Set<String> _allowedSelectionReasonCodes = <String>{
  'generic_periodization_fallback',
  'hyrox_fragment_exact_match',
  'primary_sport_exact_match',
  'generic_fallback',
};

bool _isSha256(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
