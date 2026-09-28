import 'resource_ref.dart';
import '../../plugins/core/plugin_ref.dart';
import 'ai_training_prescription.dart';
import 'training_plan.dart';
import 'plan_generation_context_snapshot.dart';

enum GeneratedPlanSource { localRules, skillAi, legacy }

extension GeneratedPlanSourceJson on GeneratedPlanSource {
  String get jsonValue => switch (this) {
        GeneratedPlanSource.localRules => 'local_rules',
        GeneratedPlanSource.skillAi => 'skill_ai',
        GeneratedPlanSource.legacy => 'legacy',
      };
}

GeneratedPlanSource generatedPlanSourceFromJson(String? value) =>
    switch (value) {
      'skill_ai' => GeneratedPlanSource.skillAi,
      'legacy' => GeneratedPlanSource.legacy,
      _ => GeneratedPlanSource.localRules,
    };

class PlanAuditSummary {
  final int passCount;
  final int warningCount;
  final int failCount;
  final List<String> blockingReasons;

  const PlanAuditSummary({
    required this.passCount,
    required this.warningCount,
    required this.failCount,
    required this.blockingReasons,
  });

  bool get canActivate => failCount == 0 && blockingReasons.isEmpty;

  factory PlanAuditSummary.fromJson(Map<String, dynamic> json) =>
      PlanAuditSummary(
        passCount: (json['passCount'] as num?)?.toInt() ?? 0,
        warningCount: (json['warningCount'] as num?)?.toInt() ?? 0,
        failCount: (json['failCount'] as num?)?.toInt() ?? 0,
        blockingReasons: _strings(json['blockingReasons']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'passCount': passCount,
        'warningCount': warningCount,
        'failCount': failCount,
        'blockingReasons': blockingReasons,
      };
}

class PlanGenerationDraft {
  final String id;
  final String artifactId;
  final TrainingPlan plan;
  final List<String> weekPhases;
  final AiTrainingPrescription prescription;
  final DateTime createdAt;
  final String? baseVersionId;
  final String contextDigest;
  final String localContextFingerprint;

  /// 激活版本继续使用旧业务摘要，插件变化仅影响待确认草稿。
  final String? businessContextFingerprint;
  final PlanAuditSummary auditSummary;
  final PlanGenerationContextSnapshot? generationContextSnapshot;
  final List<PluginRef>? pluginRefs;

  const PlanGenerationDraft({
    required this.id,
    required this.artifactId,
    required this.plan,
    required this.weekPhases,
    required this.prescription,
    required this.createdAt,
    required this.baseVersionId,
    required this.contextDigest,
    required this.localContextFingerprint,
    this.businessContextFingerprint,
    required this.auditSummary,
    this.generationContextSnapshot,
    this.pluginRefs,
  });

  bool get canActivate =>
      auditSummary.canActivate && pluginRefs != null && pluginRefs!.isNotEmpty;
  AiSkillRef get skillRef => prescription.skill;
  AiGenerationMeta get generationMeta => prescription.generationMeta;

  factory PlanGenerationDraft.fromJson(Map<String, dynamic> json) {
    return PlanGenerationDraft(
      id: json['id'] as String? ?? '',
      artifactId: json['artifactId'] as String? ?? '',
      plan: TrainingPlan.fromJson(
        Map<String, dynamic>.from(
            json['plan'] as Map? ?? const <String, dynamic>{}),
      ),
      weekPhases: _strings(json['weekPhases']),
      prescription: AiTrainingPrescription.fromJson(
        Map<String, dynamic>.from(
          json['prescription'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      baseVersionId: json['baseVersionId'] as String?,
      contextDigest: json['contextDigest'] as String? ?? '',
      localContextFingerprint: json['localContextFingerprint'] as String? ?? '',
      businessContextFingerprint: json['businessContextFingerprint'] as String?,
      auditSummary: PlanAuditSummary.fromJson(
        Map<String, dynamic>.from(
          json['auditSummary'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      pluginRefs: PluginRef.parseOptionalList(json['pluginRefs']),
      generationContextSnapshot: json['generationContextSnapshot'] is Map
          ? PlanGenerationContextSnapshot.fromJson(
              Map<String, dynamic>.from(
                json['generationContextSnapshot'] as Map,
              ),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'artifactId': artifactId,
        'plan': plan.toJson(),
        'weekPhases': weekPhases,
        'prescription': prescription.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'baseVersionId': baseVersionId,
        'contextDigest': contextDigest,
        'localContextFingerprint': localContextFingerprint,
        if (businessContextFingerprint != null)
          'businessContextFingerprint': businessContextFingerprint,
        'auditSummary': auditSummary.toJson(),
        if (pluginRefs != null)
          'pluginRefs':
              pluginRefs!.map((ref) => ref.toJson()).toList(growable: false),
        if (generationContextSnapshot != null)
          'generationContextSnapshot': generationContextSnapshot!.toJson(),
      };
}

class GeneratedPlanVersion {
  final ResourceRef? resourceRef;
  final String id;
  final TrainingPlan plan;
  final List<String> weekPhases;
  final GeneratedPlanSource source;
  final DateTime createdAt;
  final DateTime activatedAt;
  final String inputDigest;
  final String clientContextDigest;
  final String? artifactId;
  final AiSkillRef? skillRef;
  final AiTrainingPrescription? prescription;
  final String compilerVersion;
  final PlanAuditSummary auditSummary;
  final PlanGenerationContextSnapshot? generationContextSnapshot;
  final List<PluginRef>? pluginRefs;

  const GeneratedPlanVersion({
    this.resourceRef,
    required this.id,
    required this.plan,
    required this.weekPhases,
    required this.source,
    required this.createdAt,
    required this.activatedAt,
    required this.inputDigest,
    this.clientContextDigest = '',
    required this.artifactId,
    required this.skillRef,
    this.prescription,
    required this.compilerVersion,
    required this.auditSummary,
    this.generationContextSnapshot,
    this.pluginRefs,
  });

  bool get requiresClearance => isSkillGenerated || resourceRef != null || const ['resource-local-v1', 'resource-local-v2', 'resource-local-v3'].contains(compilerVersion);

  bool get isSkillGenerated => source == GeneratedPlanSource.skillAi;

  factory GeneratedPlanVersion.fromJson(Map<String, dynamic> json) {
    final Object? skillJson = json['skillRef'];
    return GeneratedPlanVersion(
      resourceRef: _readHistoricalResourceRef(json['resourceRef']),
      id: json['id'] as String? ?? '',
      plan: TrainingPlan.fromJson(
        Map<String, dynamic>.from(
            json['plan'] as Map? ?? const <String, dynamic>{}),
      ),
      weekPhases: _strings(json['weekPhases']),
      source: generatedPlanSourceFromJson(json['source'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      activatedAt: DateTime.tryParse(json['activatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      inputDigest: json['inputDigest'] as String? ?? '',
      clientContextDigest: json['clientContextDigest'] as String? ?? '',
      artifactId: json['artifactId'] as String?,
      skillRef: skillJson is Map
          ? AiSkillRef.fromJson(Map<String, dynamic>.from(skillJson))
          : null,
      prescription: json['prescription'] is Map
          ? AiTrainingPrescription.fromJson(
              Map<String, dynamic>.from(json['prescription'] as Map),
            )
          : null,
      compilerVersion: json['compilerVersion'] as String? ?? 'legacy',
      auditSummary: PlanAuditSummary.fromJson(
        Map<String, dynamic>.from(
          json['auditSummary'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      pluginRefs: _readHistoricalPluginRefs(json['pluginRefs']),
      generationContextSnapshot: json['generationContextSnapshot'] is Map
          ? PlanGenerationContextSnapshot.fromJson(
              Map<String, dynamic>.from(
                json['generationContextSnapshot'] as Map,
              ),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (resourceRef != null) 'resourceRef': resourceRef!.toJson(),
        'id': id,
        'plan': plan.toJson(),
        'weekPhases': weekPhases,
        'source': source.jsonValue,
        'createdAt': createdAt.toIso8601String(),
        'activatedAt': activatedAt.toIso8601String(),
        'inputDigest': inputDigest,
        'clientContextDigest': clientContextDigest,
        'artifactId': artifactId,
        'skillRef': skillRef?.toJson(),
        'prescription': prescription?.toJson(),
        'compilerVersion': compilerVersion,
        'auditSummary': auditSummary.toJson(),
        if (pluginRefs != null)
          'pluginRefs':
              pluginRefs!.map((ref) => ref.toJson()).toList(growable: false),
        if (generationContextSnapshot != null)
          'generationContextSnapshot': generationContextSnapshot!.toJson(),
      };
}

class GeneratedPlanActivationEvent {
  final String versionId;
  final DateTime activatedAt;
  final String action;

  const GeneratedPlanActivationEvent({
    required this.versionId,
    required this.activatedAt,
    required this.action,
  });

  factory GeneratedPlanActivationEvent.fromJson(Map<String, dynamic> json) =>
      GeneratedPlanActivationEvent(
        versionId: json['versionId'] as String? ?? '',
        activatedAt: DateTime.tryParse(json['activatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        action: json['action'] as String? ?? 'activate',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'versionId': versionId,
        'activatedAt': activatedAt.toIso8601String(),
        'action': action,
      };
}

class GeneratedTrainingPlanHistory {
  final String? activeVersionId;
  final List<GeneratedPlanVersion> versions;
  final List<GeneratedPlanActivationEvent> activationEvents;

  const GeneratedTrainingPlanHistory({
    required this.activeVersionId,
    required this.versions,
    required this.activationEvents,
  });

  static const GeneratedTrainingPlanHistory empty =
      GeneratedTrainingPlanHistory(
    activeVersionId: null,
    versions: <GeneratedPlanVersion>[],
    activationEvents: <GeneratedPlanActivationEvent>[],
  );

  GeneratedPlanVersion? get activeVersion {
    for (final GeneratedPlanVersion version in versions) {
      if (version.id == activeVersionId) return version;
    }
    return null;
  }

  factory GeneratedTrainingPlanHistory.fromJson(Map<String, dynamic> json) {
    return GeneratedTrainingPlanHistory(
      activeVersionId: json['activeVersionId'] as String?,
      versions: _maps(json['versions'])
          .map(GeneratedPlanVersion.fromJson)
          .toList(growable: false),
      activationEvents: _maps(json['activationEvents'])
          .map(GeneratedPlanActivationEvent.fromJson)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'activeVersionId': activeVersionId,
        'versions': versions
            .map((GeneratedPlanVersion item) => item.toJson())
            .toList(growable: false),
        'activationEvents': activationEvents
            .map((GeneratedPlanActivationEvent item) => item.toJson())
            .toList(growable: false),
      };
}

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().where((String item) => item.isNotEmpty).toList()
    : const <String>[];

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value
        .whereType<Map>()
        .map((Map<dynamic, dynamic> item) => Map<String, dynamic>.from(item))
        .toList()
    : const <Map<String, dynamic>>[];

/// 来源损坏不能阻断已保存计划的只读历史；此结果不能用于信任新草稿。
List<PluginRef>? _readHistoricalPluginRefs(Object? value) {
  try {
    return PluginRef.parseOptionalList(value);
  } on FormatException {
    return null;
  }
}

/// 历史内容来源损坏不隐藏已保存计划；本地编译版本仍保留筛查要求。
ResourceRef? _readHistoricalResourceRef(Object? value) {
  if (value is! Map) return null;
  try {
    return ResourceRef.fromJson(Map<String, dynamic>.from(value));
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}
