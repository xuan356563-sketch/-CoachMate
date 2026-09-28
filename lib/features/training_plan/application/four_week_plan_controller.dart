import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import '../../../plugins/core/plugin_ref.dart';
import '../../../plugins/sports/sport_capability_directory.dart';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/ai_artifact.dart';
import '../../../data/models/ai_training_prescription.dart';
import '../../../data/models/generated_training_plan.dart';
import '../../../data/models/plan_generation_preferences.dart';
import '../../../data/models/plan_generation_context_snapshot.dart';
import '../../../data/models/pre_exercise_clearance.dart';
import '../../../data/models/race.dart';
import '../../../data/models/training_plan.dart';
import '../../../data/models/training_rule_audit.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/models/workout_day.dart';
import '../../../data/repositories/generated_training_plan_repository.dart';
import '../../../data/repositories/race_repository.dart';
import '../../../data/seed/seed_exercises.dart';
import '../../../services/four_week_plan_generator.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/plan_context_digest_service.dart';
import '../../../services/training_prescription_safety_audit_service.dart';
import '../../../services/training_rule_audit_service.dart';
import '../../profile/application/user_profile_controller.dart';
import '../../first_run_onboarding/application/first_run_onboarding_controller.dart';
import '../../first_run_onboarding/application/membership_controller.dart';
import 'pre_exercise_clearance_controller.dart';

/// 新生成使用可用运动目录；历史与安全回退保持独立可读。
final sportCapabilityDirectoryProvider = Provider<SportCapabilityDirectory>(
    (Ref ref) => SportCapabilityDirectory.builtIn());

/// 宿主可组合实际参与的功能来源；不应返回全部启用插件。
typedef PlanPluginSourceResolver = List<PluginRef>? Function(
    List<PluginRef>? refs);
final planPluginSourceResolverProvider = Provider<PlanPluginSourceResolver>(
    (Ref ref) => ref.watch(sportCapabilityDirectoryProvider).resolveRefs);

/// 发行宿主只加入真正参与编译的功能来源，独立策略测试保持原默认。
final planPluginSourceDecoratorProvider =
    Provider<List<PluginRef> Function(List<PluginRef>)>(
  (ref) => (sources) => sources,
);

final fourWeekPlanNowProvider = Provider<DateTime>((Ref ref) => DateTime.now());

final fourWeekPlanControllerProvider =
    NotifierProvider<FourWeekPlanController, FourWeekPlanState>(
  FourWeekPlanController.new,
);

class FourWeekPlanState {
  const FourWeekPlanState({
    required this.generation,
    required this.fallbackGeneration,
    required this.activePlan,
    required this.activeRace,
    required this.draft,
    required this.history,
    required this.activeVersionId,
    required this.staleReason,
    required this.updateAvailable,
    required this.canActivateDraft,
    required this.executionLocked,
    required this.clearanceBlockingReason,
    required this.auditReport,
    required this.prescriptionAuditReport,
    required this.currentContextFingerprint,
    required this.statusMessage,
  });

  /// 兼容旧调用方：始终指向当前有效的计划生成结果。
  final FourWeekPlanGeneration generation;
  final FourWeekPlanGeneration fallbackGeneration;
  final TrainingPlan activePlan;
  final RacePlan? activeRace;
  final PlanGenerationDraft? draft;
  final List<GeneratedPlanVersion> history;
  final String? activeVersionId;
  final String? staleReason;
  final bool updateAvailable;
  final bool canActivateDraft;
  final bool executionLocked;
  final String? clearanceBlockingReason;
  String? get executionLockReason => clearanceBlockingReason;
  final TrainingRuleAuditReport? auditReport;
  final TrainingPrescriptionSafetyAuditReport? prescriptionAuditReport;
  final String currentContextFingerprint;
  final String statusMessage;

  TrainingCyclePhase get currentPhase => generation.weeks.isEmpty
      ? TrainingCyclePhase.baseline
      : generation.weeks.first.phase;

  FourWeekPlanState copyWithStatus(String message) => FourWeekPlanState(
        generation: generation,
        fallbackGeneration: fallbackGeneration,
        activePlan: activePlan,
        activeRace: activeRace,
        draft: draft,
        history: history,
        activeVersionId: activeVersionId,
        staleReason: staleReason,
        updateAvailable: updateAvailable,
        canActivateDraft: canActivateDraft,
        executionLocked: executionLocked,
        clearanceBlockingReason: clearanceBlockingReason,
        auditReport: auditReport,
        prescriptionAuditReport: prescriptionAuditReport,
        currentContextFingerprint: currentContextFingerprint,
        statusMessage: message,
      );
}

class FourWeekPlanController extends Notifier<FourWeekPlanState> {
  static const String compilerVersion = 'skill-compiler-v2';

  final FourWeekPlanGenerator _generator = FourWeekPlanGenerator();
  final TrainingRuleAuditService _ruleAudit = TrainingRuleAuditService();
  final TrainingPrescriptionSafetyAuditService _safetyAudit =
      TrainingPrescriptionSafetyAuditService();
  final PlanContextDigestService _digestService =
      const PlanContextDigestService();
  _DiscoveredSkillVersion? _discoveredSkill;
  void Function()? _pendingSourceListener;

  @override
  FourWeekPlanState build() {
    bindFeatureController(ref, 'feature.training_plan', 'fourWeek', this);
    ref.watch(planPluginSourceResolverProvider);
    final UserProfileState profileState =
        ref.watch(userProfileControllerProvider);
    final LocalStorageService storage = ref.watch(localStorageServiceProvider);
    _listenDraftSources(
        GeneratedTrainingPlanRepository(storage).getDraft(), storage);
    final DateTime now = ref.watch(fourWeekPlanNowProvider);
    final PreExerciseClearance? clearance =
        ref.watch(preExerciseClearanceControllerProvider).value?.clearance;
    return _buildState(
      profileState: profileState,
      storage: storage,
      now: now,
      clearance: clearance,
    );
  }

  Future<PlanGenerationDraft> createDraft({
    required AiTrainingPrescription prescription,
    required AiArtifact artifact,
    String? populationTemplateId,
    FeatureOperation? sourceOperation,
  }) async {
    final FeatureOperation operation = sourceOperation ??
        ref.read(featureAccessProvider).beginOperation(
          'feature.training_plan',
          dependencies: const <String>['feature.ai_center'],
        );
    final UserProfileState profileState =
        ref.read(userProfileControllerProvider);
    final LocalStorageService storage = ref.read(localStorageServiceProvider);
    final DateTime now = ref.read(fourWeekPlanNowProvider);
    final PreExerciseClearance? clearance =
        ref.read(preExerciseClearanceControllerProvider).value?.clearance;
    final GeneratedTrainingPlanRepository repository =
        GeneratedTrainingPlanRepository(storage);
    final RacePlan? activeRace = _selectActiveRace(
      races: PersistedRaceRepository(storage).listRaces(),
      profile: profileState.profile,
      now: now,
    );
    final DateTime startsOn = _mondayOf(now);
    final GeneratedTrainingPlanHistory history = repository.getHistory();
    final PlanGenerationContextSnapshot? previousContext =
        history.activeVersion?.generationContextSnapshot;
    final String businessFingerprint = _digestService.buildLocalFingerprint(
      profile: profileState.profile,
      startsOn: startsOn,
      race: activeRace,
    );
    final FourWeekPlanGeneration generation = FourWeekPlanGenerator(
      sportDirectory: ref.read(sportCapabilityDirectoryProvider),
    ).generate(
      profile: profileState.profile,
      startsOn: startsOn,
      race: activeRace,
      preferences: PlanGenerationPreferences.fromPrescription(
        prescription: prescription,
        generationId: artifact.id,
      ),
    );
    final compiledSources =
        ref.read(planPluginSourceDecoratorProvider)(generation.pluginRefs);
    operation.includeDependencies(compiledSources.map((source) => source.id));
    final TrainingRuleAuditReport ruleReport = _ruleAudit.buildReport(
      generation.plan,
      exercises: seedExercises,
      availableMinutes: profileState.profile.dailyAvailableMinutes,
    );
    final TrainingPrescriptionSafetyAuditReport prescriptionReport =
        _safetyAudit.auditPrescription(
      prescription: prescription,
      profile: profileState.profile,
      hasActiveRace: activeRace != null,
    );
    final TrainingPrescriptionSafetyAuditReport compiledReport =
        _safetyAudit.auditCompiledPlan(
      plan: generation.plan,
      profile: profileState.profile,
      enforceFourWeekDeload: activeRace == null,
      racePhaseOverride: activeRace != null,
    );
    final List<String> protocolFailures = <String>[
      if (artifact.id.isEmpty) '服务端产物 ID 为空。',
      if (artifact.artifactType != 'training_prescription_v1' &&
          artifact.artifactType != 'training_prescription_v2' &&
          artifact.artifactType != 'plan_revision_v1')
        '服务端产物类型不是受支持的训练处方。',
      if ((artifact.artifactType == 'training_prescription_v1' &&
              artifact.schemaVersion != 1) ||
          (artifact.artifactType == 'training_prescription_v2' &&
              artifact.schemaVersion != 2) ||
          (artifact.artifactType == 'plan_revision_v1' &&
              artifact.schemaVersion != 1))
        '服务端产物 Schema 版本不受支持。',
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(artifact.contextDigest))
        '服务端产物缓存摘要格式错误。',
    ];
    final List<String> blockingReasons = <String>[
      for (final TrainingRuleAuditItem item in ruleReport.items)
        if (item.severity == TrainingRuleAuditSeverity.fail) item.description,
      ...prescriptionReport.failures,
      ...compiledReport.failures,
      ...protocolFailures,
    ];
    final PlanGenerationDraft draft = PlanGenerationDraft(
      id: 'draft-${artifact.id}',
      artifactId: artifact.id,
      plan: generation.plan,
      weekPhases: generation.weeks
          .map((GeneratedPlanWeek item) => item.phase.jsonValue)
          .toList(growable: false),
      prescription: prescription,
      createdAt: now,
      baseVersionId: history.activeVersionId,
      contextDigest: prescription.generationMeta.clientContextDigest,
      pluginRefs: compiledSources,
      businessContextFingerprint: businessFingerprint,
      localContextFingerprint: _digestService.buildLocalFingerprint(
        profile: profileState.profile,
        startsOn: startsOn,
        race: activeRace,
        pluginRefs: compiledSources,
      ),
      auditSummary: PlanAuditSummary(
        passCount: ruleReport.passCount +
            (prescriptionReport.canActivate ? 1 : 0) +
            (compiledReport.canActivate ? 1 : 0),
        warningCount: ruleReport.warningCount +
            prescriptionReport.warnings.length +
            compiledReport.warnings.length,
        failCount: blockingReasons.length,
        blockingReasons: List<String>.unmodifiable(blockingReasons),
      ),
      generationContextSnapshot:
          artifact.artifactType == 'plan_revision_v1' && previousContext != null
              ? previousContext
              : PlanGenerationContextSnapshot(
                  weeklyTrainingDays: profileState.profile.weeklyTrainingDays,
                  availableMinutes: profileState.profile.dailyAvailableMinutes,
                  equipmentCodes: _equipmentCodes(
                    profileState.profile.equipmentAccessType,
                  ),
                  populationTemplateId: populationTemplateId,
                  raceTypeCode: activeRace?.type.jsonValue,
                  raceDate: activeRace?.raceDate,
                  racePhaseCode: activeRace?.currentPhase,
                ),
    );
    await operation.commit(() async {
      repository.saveDraft(draft);
      await storage.flush();
    });
    _listenDraftSources(draft, storage);
    state = _buildState(
      profileState: profileState,
      storage: storage,
      now: now,
      clearance: clearance,
    );
    return draft;
  }

  Future<bool> activateDraft({required String artifactId}) async {
    final operation = ref.read(featureAccessProvider).beginOperation(
        'feature.training_plan',
        dependencies: ['feature.ai_center']);
    final UserProfileState profileState =
        ref.read(userProfileControllerProvider);
    final LocalStorageService storage = ref.read(localStorageServiceProvider);
    final DateTime now = ref.read(fourWeekPlanNowProvider);
    final PreExerciseClearanceState clearanceState =
        await ref.read(preExerciseClearanceControllerProvider.future);
    operation.checkActive();
    final DateTime clearanceNow =
        ref.read(preExerciseClearanceRealtimeClockProvider)();
    final GeneratedTrainingPlanRepository repository =
        GeneratedTrainingPlanRepository(storage);
    state = _buildState(
      profileState: profileState,
      storage: storage,
      now: now,
      clearance: clearanceState.clearance,
    );
    final PlanGenerationDraft? draft = repository.getDraft();
    if (draft == null || draft.artifactId != artifactId) {
      state = state.copyWithStatus('未找到与已确认产物匹配的待激活草稿。');
      return false;
    }
    if (!clearanceState.clearance.isValidAt(clearanceNow)) {
      state = state.copyWithStatus(
        clearanceState.clearance.blockingReasonAt(clearanceNow),
      );
      return false;
    }
    final GeneratedTrainingPlanHistory persistedHistory =
        repository.getHistory();
    GeneratedPlanVersion? existingVersion;
    for (final GeneratedPlanVersion version in persistedHistory.versions) {
      if (version.artifactId == artifactId) {
        existingVersion = version;
        break;
      }
    }
    operation.includeDependencies(
        draft.pluginRefs?.map((source) => source.id) ?? []);
    return operation.commit(() async {
      if (existingVersion != null &&
          persistedHistory.activeVersionId == existingVersion.id) {
        try {
          repository.savePlan(existingVersion.plan);
          repository.clearDraft();
          await storage.flush();
        } on Object {
          // 版本单键已是权威激活状态，镜像失败不回滚激活事实。
        }
        state = _buildState(
          profileState: profileState,
          storage: storage,
          now: now,
          clearance: clearanceState.clearance,
        );
        return true;
      }
      if (!state.canActivateDraft) {
        state = state.copyWithStatus('草稿已陈旧或未通过安全审计，当前计划未替换。');
        return false;
      }
      final FourWeekPlanState previousState = state;
      final GeneratedTrainingPlanHistory previousHistory =
          repository.getHistory();
      late final GeneratedPlanVersion committedVersion;
      try {
        committedVersion = repository.commitDraftVersion(
          draft,
          activatedAt: now,
        );
        await storage.flush();
      } on Object {
        repository.restoreHistory(previousHistory);
        try {
          await storage.flush();
        } on Object {
          // 恢复写入仍失败时保留页面旧状态，不宣称激活。
        }
        state = previousState.copyWithStatus(
          '服务端已确认，但本地版本尚未完成持久化，可使用同一产物重试。',
        );
        return false;
      }
      String? mirrorWarning;
      try {
        repository.savePlan(committedVersion.plan);
        repository.clearDraft();
        await storage.flush();
      } on Object {
        mirrorWarning = '计划已激活，但旧版兼容镜像尚未刷新，不影响当前版本。';
      }
      state = _buildState(
        profileState: profileState,
        storage: storage,
        now: now,
        clearance: clearanceState.clearance,
      );
      if (mirrorWarning != null) state = state.copyWithStatus(mirrorWarning);
      return true;
    });
  }

  Future<void> rejectDraft({
    required String artifactId,
    FeatureOperation? sourceOperation,
  }) async {
    final FeatureOperation operation = sourceOperation ??
        ref.read(featureAccessProvider).beginOperation('feature.training_plan');
    final LocalStorageService storage = ref.read(localStorageServiceProvider);
    final GeneratedTrainingPlanRepository repository =
        GeneratedTrainingPlanRepository(storage);
    final PlanGenerationDraft? draft = repository.getDraft();
    if (draft == null || draft.artifactId != artifactId) {
      throw StateError('待拒绝草稿已经变化，未删除任何本地草稿。');
    }
    await operation.commit(() async {
      repository.clearDraft();
      try {
        await storage.flush();
      } on Object {
        repository.saveDraft(draft);
        try {
          await storage.flush();
        } on Object {
          throw StateError(
            '草稿删除落盘失败，恢复写入也失败；内存中的原草稿仍保留，请不要关闭应用并重试。',
          );
        }
        throw StateError('草稿删除未完成，已恢复原草稿，请重试。');
      }
    });
    state = _buildState(
      profileState: ref.read(userProfileControllerProvider),
      storage: storage,
      now: ref.read(fourWeekPlanNowProvider),
      clearance:
          ref.read(preExerciseClearanceControllerProvider).value?.clearance,
    );
  }

  Future<bool> rollbackToVersion(String versionId) async {
    final operation =
        ref.read(featureAccessProvider).beginOperation('feature.training_plan');
    final UserProfileState profileState =
        ref.read(userProfileControllerProvider);
    final LocalStorageService storage = ref.read(localStorageServiceProvider);
    final DateTime now = ref.read(fourWeekPlanNowProvider);
    final PreExerciseClearanceState clearanceState =
        await ref.read(preExerciseClearanceControllerProvider.future);
    operation.checkActive();
    final DateTime clearanceNow =
        ref.read(preExerciseClearanceRealtimeClockProvider)();
    final GeneratedTrainingPlanRepository repository =
        GeneratedTrainingPlanRepository(storage);
    GeneratedPlanVersion? target;
    for (final GeneratedPlanVersion version
        in repository.getHistory().versions) {
      if (version.id == versionId) {
        target = version;
        break;
      }
    }
    if (target == null) {
      state = state.copyWithStatus('未找到需要回退的计划版本。');
      return false;
    }
    if (target.isSkillGenerated) {
      final String? eligibilityBlockingReason =
          _skillProfileEligibilityBlockingReason(profileState.profile);
      if (eligibilityBlockingReason != null) {
        state = state.copyWithStatus(eligibilityBlockingReason);
        return false;
      }
      if (!clearanceState.clearance.isValidAt(clearanceNow)) {
        state = state.copyWithStatus(
          clearanceState.clearance.blockingReasonAt(clearanceNow),
        );
        return false;
      }
    }
    if (target.requiresClearance && !clearanceState.clearance.isValidAt(clearanceNow)) {
      state = state.copyWithStatus(clearanceState.clearance.blockingReasonAt(clearanceNow));
      return false;
    }
    final TrainingRuleAuditReport ruleReport = _ruleAudit.buildReport(
      target.plan,
      exercises: seedExercises,
      availableMinutes: profileState.profile.dailyAvailableMinutes,
    );
    final TrainingPrescriptionSafetyAuditReport safetyReport =
        _safetyAudit.auditCompiledPlan(
      plan: target.plan,
      profile: profileState.profile,
      enforceFourWeekDeload:
          target.weekPhases.contains(TrainingCyclePhase.deload.jsonValue),
      racePhaseOverride: target.weekPhases.any(
        (String phase) =>
            phase == TrainingCyclePhase.taper.jsonValue ||
            phase == TrainingCyclePhase.raceWeek.jsonValue ||
            phase == TrainingCyclePhase.postRaceRecovery.jsonValue,
      ),
    );
    if (ruleReport.failCount > 0 || !safetyReport.canActivate) {
      state = state.copyWithStatus('旧版本未通过当前安全复核，未执行回退。');
      return false;
    }
    operation.includeDependencies(
        target.pluginRefs?.map((source) => source.id) ?? []);
    return operation.commit(() async {
      final FourWeekPlanState previousState = state;
      final GeneratedTrainingPlanHistory previousHistory =
          repository.getHistory();
      late final GeneratedPlanVersion selected;
      try {
        selected = repository.activateVersion(
          versionId,
          activatedAt: now,
          historyOnly: true,
        )!;
        await storage.flush();
      } on Object {
        repository.restoreHistory(previousHistory);
        try {
          await storage.flush();
        } on Object {
          // 权威指针恢复失败时仍保留页面原状态。
        }
        state = previousState.copyWithStatus('回退版本未完成持久化，当前页面仍保留原计划。');
        return false;
      }
      String? mirrorWarning;
      try {
        repository.savePlan(selected.plan);
        await storage.flush();
      } on Object {
        mirrorWarning = '已回退到目标版本，但旧版兼容镜像稍后再刷新。';
      }
      state = _buildState(
        profileState: profileState,
        storage: storage,
        now: now,
        clearance: clearanceState.clearance,
      );
      if (mirrorWarning != null) state = state.copyWithStatus(mirrorWarning);
      return true;
    });
  }

  void regenerate() {
    ref.read(featureAccessProvider).requireEnabled('feature.training_plan');
    if (paidPlanGenerationGateEnabled &&
        ref
                .read(membershipControllerProvider)
                .value
                ?.entitlement
                .canGeneratePlan !=
            true) {
      state = state.copyWithStatus('生成新的本地模板计划需要有效会员；已有计划保持不变。');
      return;
    }
    ref.invalidateSelf();
  }

  void discoverSkillVersion({
    required String id,
    required String version,
    required String runtimeHash,
    String? sourceHash,
    Map<String, String> fragmentHashes = const <String, String>{},
  }) {
    ref.read(featureAccessProvider).requireEnabled('feature.training_plan');
    if (id.isEmpty ||
        version.isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(runtimeHash) ||
        (sourceHash != null &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceHash)) ||
        fragmentHashes.values.any(
          (String hash) => !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash),
        )) {
      return;
    }
    _discoveredSkill = _DiscoveredSkillVersion(
      id: id,
      version: version,
      runtimeHash: runtimeHash,
      sourceHash: sourceHash,
      fragmentHashes: Map<String, String>.unmodifiable(fragmentHashes),
    );
    state = _buildState(
      profileState: ref.read(userProfileControllerProvider),
      storage: ref.read(localStorageServiceProvider),
      now: ref.read(fourWeekPlanNowProvider),
      clearance:
          ref.read(preExerciseClearanceControllerProvider).value?.clearance,
    );
  }

  void _listenDraftSources(
      PlanGenerationDraft? draft, LocalStorageService storage) {
    _pendingSourceListener?.call();
    _pendingSourceListener = null;
    if (draft == null) return;
    final runtime = ref.read(pluginRuntimeProvider);
    final ids = {
      ...?draft.pluginRefs?.map((source) => source.id),
      'feature.ai_center',
      'feature.training_plan'
    };
    String availability() =>
        ids.map((id) => '$id:${runtime.isEnabled(id)}').join('|');
    var previous = availability();
    void changed() {
      final next = availability();
      if (next == previous || !ref.mounted) return;
      previous = next;
      state = _buildState(
          profileState: ref.read(userProfileControllerProvider),
          storage: storage,
          now: ref.read(fourWeekPlanNowProvider),
          clearance: ref
              .read(preExerciseClearanceControllerProvider)
              .value
              ?.clearance);
    }

    runtime.addListener(changed);
    _pendingSourceListener = () => runtime.removeListener(changed);
    ref.onDispose(() => runtime.removeListener(changed));
  }

  /// 活跃工作台的显式初始化；历史读取和停用状态不会执行补写。
  Future<void> initializeDefaultPlan() async {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation('feature.training_plan');
    final UserProfileState profileState =
        ref.read(userProfileControllerProvider);
    final LocalStorageService storage = ref.read(localStorageServiceProvider);
    final DateTime now = ref.read(fourWeekPlanNowProvider);
    await operation.commit(() async {
      final bool changed = _initializeStoredPlan(
        profileState: profileState,
        storage: storage,
        now: now,
      );
      if (changed) await storage.flush();
    });
    state = _buildState(
      profileState: profileState,
      storage: storage,
      now: now,
      clearance:
          ref.read(preExerciseClearanceControllerProvider).value?.clearance,
    );
  }

  bool _initializeStoredPlan(
      {required UserProfileState profileState,
      required LocalStorageService storage,
      required DateTime now}) {
    ref.read(featureAccessProvider).requireEnabled('feature.training_plan');
    final repository = GeneratedTrainingPlanRepository(storage);
    if (repository.getDraft() != null) return false;
    final activeVersion = repository.getHistory().activeVersion;
    if (activeVersion != null) {
      if (jsonEncode(repository.getPlan()?.toJson()) !=
          jsonEncode(activeVersion.plan.toJson())) {
        repository.savePlan(activeVersion.plan);
        return true;
      }
      return false;
    }
    final activeRace = _selectActiveRace(
        races: PersistedRaceRepository(storage).listRaces(),
        profile: profileState.profile,
        now: now);
    final fallback = FourWeekPlanGenerator(
      sportDirectory: ref.read(sportCapabilityDirectoryProvider),
    ).generate(
        profile: profileState.profile,
        startsOn: _mondayOf(now),
        race: activeRace);
    if (activeVersion == null) {
      final TrainingPlan? savedPlan = repository.getPlan();
      if (savedPlan == null) {
        repository.savePlan(fallback.plan, isAutoFallback: true);
        return true;
      } else if (repository.isAutoFallbackPlan()) {
        if (jsonEncode(savedPlan.toJson()) !=
            jsonEncode(fallback.plan.toJson())) {
          repository.savePlan(fallback.plan, isAutoFallback: true);
          return true;
        }
      }
    }
    return false;
  }

  FourWeekPlanState _buildState({
    required UserProfileState profileState,
    required LocalStorageService storage,
    required DateTime now,
    required PreExerciseClearance? clearance,
  }) {
    final RacePlan? activeRace = _selectActiveRace(
      races: PersistedRaceRepository(storage).listRaces(),
      profile: profileState.profile,
      now: now,
    );
    final DateTime startsOn = _mondayOf(now);
    final FourWeekPlanGeneration fallback = _generator.generate(
      profile: profileState.profile,
      startsOn: startsOn,
      race: activeRace,
    );
    final GeneratedTrainingPlanRepository repository =
        GeneratedTrainingPlanRepository(storage);
    final GeneratedTrainingPlanHistory versionHistory = repository.getHistory();
    final GeneratedPlanVersion? activeVersion = versionHistory.activeVersion;
    final TrainingPlan? unversionedLegacyPlan =
        activeVersion == null && !repository.isAutoFallbackPlan()
            ? repository.getPlan()
            : null;
    final DateTime clearanceNow =
        ref.read(preExerciseClearanceRealtimeClockProvider)();
    final String? profileEligibilityBlockingReason =
        _skillProfileEligibilityBlockingReason(profileState.profile);
    final bool profileEligibilityInvalid =
        activeVersion?.isSkillGenerated == true &&
            profileEligibilityBlockingReason != null;
    final bool clearanceInvalid = activeVersion?.requiresClearance == true &&
        (clearance == null || !clearance.isValidAt(clearanceNow));
    final bool executionLocked = profileEligibilityInvalid || clearanceInvalid;
    final String? clearanceBlockingReason = executionLocked
        ? profileEligibilityBlockingReason ??
            clearance?.blockingReasonAt(clearanceNow) ??
            '筛查状态尚未完成加载。'
        : null;
    final FourWeekPlanGeneration generation = executionLocked
        ? fallback
        : activeVersion != null
            ? _generationFromVersion(activeVersion, fallback, activeRace)
            : unversionedLegacyPlan != null
                ? _generationFromStoredPlan(
                    unversionedLegacyPlan,
                    fallback,
                    activeRace,
                  )
                : fallback;
    final TrainingPlan activePlan = generation.plan;
    final String currentFingerprint = _digestService.buildLocalFingerprint(
      profile: profileState.profile,
      startsOn: startsOn,
      race: activeRace,
    );
    final String activeFingerprint = _digestService.buildLocalFingerprint(
      profile: profileState.profile,
      startsOn: activeVersion?.plan.createdAt ?? startsOn,
      race: activeRace,
    );
    final PlanGenerationDraft? storedDraft = repository.getDraft();
    final PlanGenerationDraft? draft = storedDraft != null &&
            activeVersion?.artifactId == storedDraft.artifactId
        ? null
        : storedDraft;
    final List<PluginRef>? currentDraftRefs =
        ref.read(planPluginSourceResolverProvider)(draft?.pluginRefs);
    final String draftFingerprint = _digestService.buildLocalFingerprint(
      profile: profileState.profile,
      startsOn: startsOn,
      race: activeRace,
      pluginRefs: currentDraftRefs,
    );
    final bool draftStale = draft != null &&
        (!draft.canActivate ||
            currentDraftRefs == null ||
            currentDraftRefs.isEmpty ||
            draft.localContextFingerprint != draftFingerprint ||
            draft.baseVersionId != versionHistory.activeVersionId);
    final bool activeStale = activeVersion != null &&
        activeVersion.inputDigest.isNotEmpty &&
        activeVersion.inputDigest != activeFingerprint;
    final String? staleReason = profileEligibilityInvalid
        ? 'profile_ineligible'
        : clearanceInvalid
            ? 'clearance_invalid'
            : draftStale
                ? 'draft_context_changed'
                : activeStale
                    ? 'active_plan_context_changed'
                    : null;

    TrainingRuleAuditReport? ruleReport;
    TrainingPrescriptionSafetyAuditReport? prescriptionReport;
    TrainingPrescriptionSafetyAuditReport? compiledReport;
    if (draft != null) {
      ruleReport = _ruleAudit.buildReport(
        draft.plan,
        exercises: seedExercises,
        availableMinutes: profileState.profile.dailyAvailableMinutes,
      );
      prescriptionReport = _safetyAudit.auditPrescription(
        prescription: draft.prescription,
        profile: profileState.profile,
        hasActiveRace: activeRace != null,
      );
      compiledReport = _safetyAudit.auditCompiledPlan(
        plan: draft.plan,
        profile: profileState.profile,
        enforceFourWeekDeload: activeRace == null,
        racePhaseOverride: activeRace != null,
      );
    }
    final bool clearanceValid =
        clearance != null && clearance.isValidAt(clearanceNow);
    final bool canActivateDraft =
        ref.read(featureAccessProvider).isWritable('feature.training_plan') &&
            ref.read(featureAccessProvider).isWritable('feature.ai_center') &&
            draft != null &&
            !draftStale &&
            clearanceValid &&
            draft.canActivate &&
            ruleReport?.failCount == 0 &&
            prescriptionReport?.canActivate == true &&
            compiledReport?.canActivate == true;
    final bool draftSkillChanged = draft != null &&
        activeVersion?.skillRef != null &&
        (activeVersion!.skillRef!.version != draft.skillRef.version ||
            activeVersion.skillRef!.runtimeSha256 !=
                draft.skillRef.runtimeSha256);
    final bool discoveredSkillChanged = activeVersion?.skillRef != null &&
        _discoveredSkill != null &&
        (_discoveredSkill!.id != activeVersion!.skillRef!.id ||
            _discoveredSkill!.version != activeVersion.skillRef!.version ||
            _discoveredSkill!.runtimeHash !=
                activeVersion.skillRef!.runtimeSha256 ||
            (_discoveredSkill!.sourceHash != null &&
                _discoveredSkill!.sourceHash !=
                    activeVersion.skillRef!.sourceSha256) ||
            (_discoveredSkill!
                        .fragmentHashes[activeVersion.skillRef!.coverage] !=
                    null &&
                _discoveredSkill!
                        .fragmentHashes[activeVersion.skillRef!.coverage] !=
                    activeVersion.skillRef!.fragmentSha256));
    final bool updateAvailable = profileEligibilityInvalid ||
        activeStale ||
        draftSkillChanged ||
        discoveredSkillChanged;

    final String draftLabel = profileState.isCompleted ? '' : '档案尚未确认，当前为预览。';
    final String raceLabel = activeRace == null
        ? '当前按基础 4 周周期推进。'
        : '已关联 ${activeRace.name}，比赛阶段规则优先。';
    final String staleLabel = staleReason == null
        ? ''
        : staleReason == 'draft_context_changed'
            ? '生成后的档案或当前版本已变化，需重新生成。'
            : staleReason == 'profile_ineligible'
                ? clearanceBlockingReason ?? '当前档案不再符合 Skill 计划的低风险资格。'
                : staleReason == 'clearance_invalid'
                    ? clearanceBlockingReason ?? '筛查状态无效，已切换到本地安全计划。'
                    : '已激活计划与当前档案不同，已保留原版本等待用户决定。';
    return FourWeekPlanState(
      generation: generation,
      fallbackGeneration: fallback,
      activePlan: activePlan,
      activeRace: activeRace,
      draft: draft,
      history: List<GeneratedPlanVersion>.unmodifiable(versionHistory.versions),
      activeVersionId: versionHistory.activeVersionId,
      staleReason: staleReason,
      updateAvailable: updateAvailable,
      canActivateDraft: canActivateDraft,
      executionLocked: executionLocked,
      clearanceBlockingReason: clearanceBlockingReason,
      auditReport: ruleReport,
      prescriptionAuditReport: prescriptionReport,
      currentContextFingerprint: currentFingerprint,
      statusMessage: '$draftLabel$raceLabel$staleLabel',
    );
  }

  String? _skillProfileEligibilityBlockingReason(UserProfile profile) {
    if (profile.age < 18) {
      return 'Skill 计划 V1 仅支持 18 岁及以上用户，已切换到本地计划。';
    }
    if (profile.mainSports.contains(MainSport.rehab)) {
      return '当前档案包含康复目标，不在 Skill 计划 V1 范围内。';
    }
    if (profile.trainingExperienceLevel == TrainingExperienceLevel.unknown) {
      return '训练经验已变为未知，补充后才能继续执行 Skill 计划。';
    }
    return null;
  }

  FourWeekPlanGeneration _generationFromVersion(
    GeneratedPlanVersion version,
    FourWeekPlanGeneration fallback,
    RacePlan? activeRace,
  ) {
    return _generationFromStoredPlan(
      version.plan,
      fallback,
      activeRace,
      weekPhases: version.weekPhases,
      pluginRefs: version.pluginRefs,
    );
  }

  FourWeekPlanGeneration _generationFromStoredPlan(
    TrainingPlan plan,
    FourWeekPlanGeneration fallback,
    RacePlan? activeRace, {
    List<String> weekPhases = const <String>[],
    List<PluginRef>? pluginRefs,
  }) {
    final List<GeneratedPlanWeek> weeks = <GeneratedPlanWeek>[];
    for (int weekIndex = 1; weekIndex <= 4; weekIndex += 1) {
      final TrainingCyclePhase phase = weekPhases.length >= weekIndex
          ? trainingCyclePhaseFromJson(weekPhases[weekIndex - 1])
          : fallback.weeks[weekIndex - 1].phase;
      weeks.add(
        GeneratedPlanWeek(
          weekIndex: weekIndex,
          startsOn: plan.createdAt.add(
            Duration(days: (weekIndex - 1) * 7),
          ),
          phase: phase,
          focus: phase.focus,
          workouts: plan.workoutDays
              .where((WorkoutDay item) => item.weekIndex == weekIndex)
              .toList(growable: false),
        ),
      );
    }
    return FourWeekPlanGeneration(
      plan: plan,
      weeks: List<GeneratedPlanWeek>.unmodifiable(weeks),
      pluginRefs: pluginRefs ?? const [],
      primarySport: plan.sportType,
      secondarySport: fallback.secondarySport,
      appliedRace: activeRace,
    );
  }

  RacePlan? _selectActiveRace({
    required List<RacePlan> races,
    required UserProfile profile,
    required DateTime now,
  }) {
    final DateTime today = _dateOnly(now);
    final Set<MainSport> selectedSports = profile.mainSports.toSet();
    final List<RacePlan> upcoming = races.where((RacePlan race) {
      return !_dateOnly(race.raceDate).isBefore(today) &&
          selectedSports.contains(_sportForRace(race.type));
    }).toList()
      ..sort(
        (RacePlan first, RacePlan second) =>
            first.raceDate.compareTo(second.raceDate),
      );
    return upcoming.isEmpty ? null : upcoming.first;
  }

  MainSport _sportForRace(RaceType type) => switch (type) {
        RaceType.hyrox => MainSport.hyrox,
        RaceType.trailRunning => MainSport.trailRunning,
        RaceType.marathon || RaceType.roadRunning => MainSport.marathon,
      };

  List<String> _equipmentCodes(EquipmentAccessType value) => switch (value) {
        EquipmentAccessType.none => const <String>['bodyweight'],
        EquipmentAccessType.basicHome => const <String>[
            'bodyweight',
            'dumbbell',
          ],
        EquipmentAccessType.gym || EquipmentAccessType.mixed => const <String>[
            'bodyweight',
            'dumbbell',
            'barbell',
            'kettlebell',
            'machines',
            'cardio_machines',
          ],
      };

  DateTime _mondayOf(DateTime value) {
    final DateTime date = _dateOnly(value);
    return date.subtract(Duration(days: date.weekday - DateTime.monday));
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class _DiscoveredSkillVersion {
  const _DiscoveredSkillVersion({
    required this.id,
    required this.version,
    required this.runtimeHash,
    required this.sourceHash,
    required this.fragmentHashes,
  });

  final String id;
  final String version;
  final String runtimeHash;
  final String? sourceHash;
  final Map<String, String> fragmentHashes;
}
