import '../../data/models/generated_training_plan.dart';
import '../../data/models/resource_ref.dart';
import '../../data/models/training_plan.dart';
import '../../data/models/plan_generation_context_snapshot.dart';
import '../../plugins/core/plugin_ref.dart';
import '../../services/local_storage_service.dart';
import 'assessment_record_repository.dart';

class LocalPlanDraft {
  const LocalPlanDraft(
      {required this.id,
      required this.plan,
      required this.createdAt,
      required this.weekPhases,
      required this.resourceRef,
      required this.pluginRefs,
      required this.contextFingerprint,
      required this.businessFingerprint,
      required this.baseVersionId,
      required this.auditSummary,
      required this.warnings,
      required this.contextSnapshot});
  final String id, contextFingerprint, businessFingerprint;
  final String? baseVersionId;
  final TrainingPlan plan;
  final DateTime createdAt;
  final List<String> weekPhases, warnings;
  final ResourceRef resourceRef;
  final List<PluginRef> pluginRefs;
  final PlanAuditSummary auditSummary;
  final PlanGenerationContextSnapshot contextSnapshot;
  Map<String, dynamic> toJson() => {
        'id': id,
        'plan': plan.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'weekPhases': weekPhases,
        'resourceRef': resourceRef.toJson(),
        'pluginRefs': pluginRefs.map((r) => r.toJson()).toList(),
        'contextFingerprint': contextFingerprint,
        'businessFingerprint': businessFingerprint,
        'baseVersionId': baseVersionId,
        'auditSummary': auditSummary.toJson(),
        'warnings': warnings,
        'contextSnapshot': contextSnapshot.toJson()
      };
  factory LocalPlanDraft.fromJson(Map<String, dynamic> j) {
    final refs = PluginRef.parseOptionalList(j['pluginRefs']);
    if ((j['id'] as String).isEmpty ||
        refs == null ||
        refs.isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$')
            .hasMatch(j['contextFingerprint'] as String)) {
      throw const FormatException('本地草稿来源或指纹无效');
    }
    return LocalPlanDraft(
        id: j['id'] as String,
        plan:
            TrainingPlan.fromJson(Map<String, dynamic>.from(j['plan'] as Map)),
        createdAt: DateTime.parse(j['createdAt'] as String),
        weekPhases: List<String>.from(j['weekPhases'] as List),
        resourceRef: ResourceRef.fromJson(
            Map<String, dynamic>.from(j['resourceRef'] as Map)),
        pluginRefs: refs,
        contextFingerprint: j['contextFingerprint'] as String,
        businessFingerprint: j['businessFingerprint'] as String,
        baseVersionId: j['baseVersionId'] as String?,
        auditSummary: PlanAuditSummary.fromJson(
            Map<String, dynamic>.from(j['auditSummary'] as Map)),
        warnings: List<String>.from(j['warnings'] as List),
        contextSnapshot: PlanGenerationContextSnapshot.fromJson(
            Map<String, dynamic>.from(j['contextSnapshot'] as Map)));
  }
}

class LocalPlanDraftRepository {
  LocalPlanDraftRepository(this.storage)
      : writer = ResourceDocumentWriter(storage);
  static const storageKey = 'trainflow.local_plan_draft.v1';
  final LocalStorageService storage;
  final ResourceDocumentWriter writer;
  LocalPlanDraft? read() {
    final j = storage.readJson(storageKey);
    if (j == null) return null;
    if (j['schemaVersion'] != 1 || j['draft'] is! Map) {
      throw const FormatException('本地草稿格式不受支持，已保留原始数据');
    }
    return LocalPlanDraft.fromJson(
        Map<String, dynamic>.from(j['draft'] as Map));
  }

  Future<void> save(LocalPlanDraft draft) {
    read();
    LocalPlanDraft.fromJson(draft.toJson());
    return writer
        .write(storageKey, {'schemaVersion': 1, 'draft': draft.toJson()});
  }

  Future<void> clear() => writer.write(storageKey, null);
}
