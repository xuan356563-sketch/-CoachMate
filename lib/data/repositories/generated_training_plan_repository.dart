import '../../services/local_storage_service.dart';
import '../models/generated_training_plan.dart';
import '../models/training_plan.dart';

class GeneratedTrainingPlanRepository {
  const GeneratedTrainingPlanRepository(this._storage);

  static const String storageKey = 'trainflow.generated_training_plan.v1';
  static const String draftStorageKey =
      'trainflow.generated_training_plan_draft.v1';
  static const String versionsStorageKey =
      'trainflow.generated_training_plan_versions.v1';

  final LocalStorageService _storage;

  TrainingPlan? getPlan() {
    final Object? planJson = _storage.readJson(storageKey)?['plan'];
    if (planJson is! Map<String, dynamic>) {
      return null;
    }
    try {
      return TrainingPlan.fromJson(planJson);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  void savePlan(TrainingPlan plan, {bool isAutoFallback = false}) {
    _storage.saveJson(storageKey, <String, dynamic>{
      'schemaVersion': 1,
      if (isAutoFallback) 'source': 'auto_fallback',
      'plan': plan.toJson(),
    });
  }

  bool isAutoFallbackPlan() =>
      _storage.readJson(storageKey)?['source'] == 'auto_fallback';

  void clearPlan() {
    _storage.remove(storageKey);
  }

  PlanGenerationDraft? getDraft() {
    final Object? value = _storage.readJson(draftStorageKey)?['draft'];
    if (value is! Map) return null;
    try {
      return PlanGenerationDraft.fromJson(Map<String, dynamic>.from(value));
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  void saveDraft(PlanGenerationDraft draft) {
    _storage.saveJson(draftStorageKey, <String, dynamic>{
      'schemaVersion': 1,
      'draft': draft.toJson(),
    });
  }

  void clearDraft() {
    _storage.remove(draftStorageKey);
  }

  GeneratedTrainingPlanHistory getHistory() {
    final Map<String, dynamic>? value = _storage.readJson(versionsStorageKey);
    if (value == null) return GeneratedTrainingPlanHistory.empty;
    try {
      return GeneratedTrainingPlanHistory.fromJson(value);
    } on FormatException {
      return GeneratedTrainingPlanHistory.empty;
    } on TypeError {
      return GeneratedTrainingPlanHistory.empty;
    }
  }

  GeneratedPlanVersion activateDraft(
    PlanGenerationDraft draft, {
    required DateTime activatedAt,
    bool preserveDraft = false,
  }) {
    final GeneratedPlanVersion version = commitDraftVersion(
      draft,
      activatedAt: activatedAt,
    );
    savePlan(version.plan);
    if (!preserveDraft) clearDraft();
    return version;
  }

  /// 只提交版本单键权威状态，legacy 镜像与草稿清理由上层在 flush 成功后处理。
  GeneratedPlanVersion commitDraftVersion(
    PlanGenerationDraft draft, {
    required DateTime activatedAt,
  }) {
    GeneratedTrainingPlanHistory history = getHistory();
    final List<GeneratedPlanVersion> versions =
        List<GeneratedPlanVersion>.from(history.versions);
    if (versions.isEmpty) {
      final TrainingPlan? legacyPlan = getPlan();
      if (legacyPlan != null && legacyPlan.id != draft.plan.id) {
        versions.add(_legacyVersion(legacyPlan, activatedAt));
      }
    }

    final String versionId = 'version-${draft.artifactId}';
    GeneratedPlanVersion? existing;
    for (final GeneratedPlanVersion item in versions) {
      if (item.id == versionId) {
        existing = item;
        break;
      }
    }
    final GeneratedPlanVersion version = existing ??
        GeneratedPlanVersion(
          id: versionId,
          plan: draft.plan,
          weekPhases: List<String>.unmodifiable(draft.weekPhases),
          source: GeneratedPlanSource.skillAi,
          createdAt: draft.createdAt,
          activatedAt: activatedAt,
          inputDigest: draft.localContextFingerprint,
          clientContextDigest: draft.contextDigest,
          artifactId: draft.artifactId,
          skillRef: draft.skillRef,
          prescription: draft.prescription,
          compilerVersion: 'skill-compiler-v2',
          auditSummary: draft.auditSummary,
          generationContextSnapshot: draft.generationContextSnapshot,
        );
    if (existing == null) versions.add(version);
    while (versions.length > 5) {
      versions.removeAt(0);
    }
    history = GeneratedTrainingPlanHistory(
      activeVersionId: versionId,
      versions: List<GeneratedPlanVersion>.unmodifiable(versions),
      activationEvents: history.activeVersionId == versionId
          ? history.activationEvents
          : _appendEvent(
              history.activationEvents,
              GeneratedPlanActivationEvent(
                versionId: versionId,
                activatedAt: activatedAt,
                action: 'activate',
              ),
            ),
    );
    _saveHistory(history);
    return version;
  }

  GeneratedPlanVersion? activateVersion(
    String versionId, {
    required DateTime activatedAt,
    bool historyOnly = false,
  }) {
    final GeneratedTrainingPlanHistory history = getHistory();
    GeneratedPlanVersion? selected;
    for (final GeneratedPlanVersion version in history.versions) {
      if (version.id == versionId) {
        selected = version;
        break;
      }
    }
    if (selected == null) return null;
    final GeneratedTrainingPlanHistory updated = GeneratedTrainingPlanHistory(
      activeVersionId: versionId,
      versions: history.versions,
      activationEvents: _appendEvent(
        history.activationEvents,
        GeneratedPlanActivationEvent(
          versionId: versionId,
          activatedAt: activatedAt,
          action: 'rollback',
        ),
      ),
    );
    _saveHistory(updated);
    if (!historyOnly) savePlan(selected.plan);
    return selected;
  }

  void restoreHistory(GeneratedTrainingPlanHistory history) {
    _saveHistory(history);
  }

  void clearVersionedPlans() {
    _storage.remove(versionsStorageKey);
    clearDraft();
  }

  void _saveHistory(GeneratedTrainingPlanHistory history) {
    _storage.saveJson(versionsStorageKey, <String, dynamic>{
      'schemaVersion': 1,
      ...history.toJson(),
    });
  }

  GeneratedPlanVersion _legacyVersion(
    TrainingPlan plan,
    DateTime activatedAt,
  ) {
    return GeneratedPlanVersion(
      id: 'legacy-${plan.id}',
      plan: plan,
      weekPhases: const <String>[],
      source: GeneratedPlanSource.legacy,
      createdAt: plan.createdAt,
      activatedAt: activatedAt,
      inputDigest: '',
      artifactId: null,
      skillRef: null,
      compilerVersion: 'legacy',
      auditSummary: const PlanAuditSummary(
        passCount: 0,
        warningCount: 0,
        failCount: 0,
        blockingReasons: <String>[],
      ),
    );
  }

  List<GeneratedPlanActivationEvent> _appendEvent(
    List<GeneratedPlanActivationEvent> source,
    GeneratedPlanActivationEvent event,
  ) {
    final List<GeneratedPlanActivationEvent> events =
        <GeneratedPlanActivationEvent>[...source, event];
    if (events.length > 20) {
      events.removeRange(0, events.length - 20);
    }
    return List<GeneratedPlanActivationEvent>.unmodifiable(events);
  }
}
