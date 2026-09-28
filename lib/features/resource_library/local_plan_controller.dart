import '../../plugins/application/feature_controller_binding.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/generated_training_plan.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/generated_training_plan_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../../data/repositories/race_repository.dart';
import '../../plugins/application/feature_access.dart';
import '../../plugins/application/plugin_runtime_provider.dart';
import '../../plugins/features/resource_library_plugin.dart';
import '../../services/local_storage_service.dart';
import '../../services/plan_context_digest_service.dart';
import '../first_run_onboarding/application/first_run_onboarding_controller.dart';
import '../first_run_onboarding/application/membership_controller.dart';
import '../training_plan/application/four_week_plan_controller.dart';
import '../training_plan/application/pre_exercise_clearance_controller.dart';
import 'resource_catalog.dart';
import 'resource_library_controller.dart';
import 'resource_plan_preview.dart';
import 'local_plan_draft.dart';
import 'local_plan_service.dart';

final localPlanMembershipGateProvider =
    Provider<bool>((ref) => paidPlanGenerationGateEnabled);
final localPlanDraftRepositoryProvider =
    Provider<LocalPlanDraftRepository>((ref) {
  ref.watch(pluginRuntimeProvider.select((r) => r.accountEpoch));
  return LocalPlanDraftRepository(ref.watch(localStorageServiceProvider));
});

class LocalPlanState {
  const LocalPlanState(
      {this.draft,
      this.busy = false,
      this.message = '',
      this.activated = false});
  final LocalPlanDraft? draft;
  final bool busy, activated;
  final String message;
}

final localPlanControllerProvider =
    NotifierProvider<LocalPlanController, LocalPlanState>(
        LocalPlanController.new);

class LocalPlanController extends Notifier<LocalPlanState> {
  final _service = LocalPlanService();
  int _generation = 0;
  @override
  LocalPlanState build() {
    _generation++;
    void cancelPending() {
      _generation++;
      if (ref.mounted) {
        state = const LocalPlanState(message: '功能或账号已变化，请重新打开本地草稿。');
      }
    }

    bindFeatureController(ref, ResourceLibraryPlugin.id, 'local_plan', this,
        cleanup: cancelPending);
    bindFeatureController(
        ref, 'feature.training_plan', 'local_resource_plan', this,
        cleanup: cancelPending);
    ref.onDispose(() => _generation++);
    ref.watch(pluginRuntimeProvider.select((r) => r.accountEpoch));
    try {
      return LocalPlanState(
          draft: ref.watch(localPlanDraftRepositoryProvider).read());
    } catch (_) {
      return const LocalPlanState(message: '本地草稿格式不受支持，原始数据已保留。');
    }
  }

  UserProfile _profile() {
    final repo =
        PersistedUserProfileRepository(ref.read(localStorageServiceProvider));
    if (!repo.isProfileCompleted()) throw StateError('请先完成并确认个人档案');
    return repo.getProfile();
  }

  void _checkCurrent(FeatureOperation operation) {
    operation.checkActive();
    _profile();
    if (ref.read(localPlanMembershipGateProvider) &&
        ref
                .read(membershipControllerProvider)
                .value
                ?.entitlement
                .canGeneratePlan !=
            true) {
      throw StateError('生成或启用新的本地计划需要有效会员');
    }
    final reasons = ref
        .read(pluginRuntimeProvider)
        .activeUseReasons('feature.training_plan');
    if (reasons.isNotEmpty) throw StateError(reasons.join('\n'));
    final clearance = ref.read(preExerciseClearanceControllerProvider).value;
    final now = ref.read(preExerciseClearanceRealtimeClockProvider)();
    if (clearance == null ||
        clearance.isSaving ||
        !clearance.clearance.isValidAt(now)) {
      throw StateError(
          clearance?.clearance.blockingReasonAt(now) ?? '请先完成训练前检查');
    }
  }

  Future<void> _waitChecks(FeatureOperation operation) async {
    if (ref.read(localPlanMembershipGateProvider)) {
      await ref.read(membershipControllerProvider.future);
    }
    operation.checkActive();
    await ref.read(preExerciseClearanceControllerProvider.future);
    _checkCurrent(operation);
  }

  TrainingPlanResource _resource(String id) {
    final resource = ref.read(resourceCatalogProvider)?.require(id);
    if (resource is! TrainingPlanResource) throw StateError('训练计划资源不可用');
    return resource;
  }

  LocalPlanDraft _compile(
      String resourceId, String id, String? baseVersionId, DateTime now) {
    final resource = _resource(resourceId);
    final runtime = ref.read(pluginRuntimeProvider);
    final profile = _profile();
    final preview = runtime.registry
        .readCapability<ResourcePlanPreview>(ResourceLibraryPlugin.preview);
    if (preview == null) throw StateError('本地模板预览技能不可用');
    final sports = runtime.sportDirectory;
    final race = _service.selectRace(
        PersistedRaceRepository(ref.read(localStorageServiceProvider))
            .listRaces(),
        profile,
        now,
        sports);
    return _service.create(
        id: id,
        now: now,
        profile: profile,
        resource: resource,
        sports: sports,
        baseVersionId: baseVersionId,
        preview: preview,
        race: race,
        decorate: (sources) => [
              ...sources,
              runtime.registry.descriptors['feature.training_plan']!.ref,
              runtime.registry.descriptors[ResourceLibraryPlugin.id]!.ref,
            ]);
  }

  Future<void> createLocalDraft(String resourceId,
      {String? replaceDraftId}) async {
    if (state.busy) throw StateError('计划操作正在进行，请稍后重试');
    final resource = _resource(resourceId);
    final operation = ref.read(featureAccessProvider).beginOperation(
        'feature.training_plan',
        dependencies: [ResourceLibraryPlugin.id, resource.ownerPluginId]);
    final draftRepo = ref.read(localPlanDraftRepositoryProvider);
    final previous = draftRepo.read();
    if (previous != null && previous.id != replaceDraftId) {
      throw StateError('请先确认替换已有本地草稿');
    }
    final generation = ++_generation;
    state = LocalPlanState(draft: previous, busy: true);
    try {
      await _waitChecks(operation);
      final repo = GeneratedTrainingPlanRepository(
          ref.read(localStorageServiceProvider));
      final draft = _compile(resourceId, newResourceRecordId(),
          repo.getHistory().activeVersionId, ref.read(fourWeekPlanNowProvider));
      operation.includeDependencies(draft.pluginRefs.map((r) => r.id));
      await operation.commit(() async {
        _checkCurrent(operation);
        if (draftRepo.read()?.id != previous?.id) {
          throw StateError('本地草稿已变化，请重新打开');
        }
        await draftRepo.save(draft);
      });
      operation.checkActive();
      state = LocalPlanState(draft: draft, message: '草稿已保存，尚未启用；请查看完整课程和审核结果。');
    } catch (e) {
      if (ref.mounted && generation == _generation) {
        try {
          operation.checkActive();
          state = LocalPlanState(draft: previous, message: e.toString());
        } on FeatureOperationInvalidation {
          state = const LocalPlanState(message: '来源或账号已变化，请重新打开。');
        }
      }
      rethrow;
    }
  }

  Future<void> activateLocalDraft(String draftId) async {
    if (state.busy) throw StateError('计划操作正在进行，请稍后重试');
    final draftRepo = ref.read(localPlanDraftRepositoryProvider);
    final draft = draftRepo.read();
    if (draft == null || draft.id != draftId) {
      throw StateError('未找到对应本地草稿，请重新打开');
    }
    final operation = ref.read(featureAccessProvider).beginOperation(
        'feature.training_plan',
        dependencies: draft.pluginRefs.map((r) => r.id));
    final storage = ref.read(localStorageServiceProvider);
    final repo = GeneratedTrainingPlanRepository(storage);
    final generation = ++_generation;
    state = LocalPlanState(draft: draft, busy: true);
    try {
      await _waitChecks(operation);
      final now = ref.read(fourWeekPlanNowProvider);
      final versionId = 'local-version-${draft.id}';
      final alreadyActive = repo.getHistory().activeVersionId == versionId;
      final current =
          _compile(draft.resourceRef.id, draft.id, draft.baseVersionId, now);
      if (current.contextFingerprint != draft.contextFingerprint ||
          current.resourceRef != draft.resourceRef ||
          const PlanContextDigestService()
                  .buildCanonicalDigest(current.plan.toJson()) !=
              const PlanContextDigestService()
                  .buildCanonicalDigest(draft.plan.toJson()) ||
          !current.auditSummary.canActivate ||
          (!alreadyActive &&
              repo.getHistory().activeVersionId != draft.baseVersionId)) {
        throw StateError('草稿上下文、内容来源或有效计划已变化，或安全审核未通过；请重新生成');
      }
      operation.includeDependencies(current.pluginRefs.map((r) => r.id));
      final version = GeneratedPlanVersion(
          id: versionId,
          plan: draft.plan,
          weekPhases: draft.weekPhases,
          source: GeneratedPlanSource.localRules,
          createdAt: draft.createdAt,
          activatedAt: now,
          inputDigest: draft.businessFingerprint,
          artifactId: null,
          skillRef: null,
          compilerVersion: LocalPlanService.compilerVersion,
          auditSummary: current.auditSummary,
          pluginRefs: current.pluginRefs,
          resourceRef: current.resourceRef,
          generationContextSnapshot: current.contextSnapshot);
      String? warning;
      await operation.commit(() async {
        _checkCurrent(operation);
        if (draftRepo.read()?.id != draftId) throw StateError('待确认草稿已经变化');
        final history = repo.prepareLocalVersion(version,
            expectedBaseVersionId: draft.baseVersionId);
        await draftRepo.writer.write(
            GeneratedTrainingPlanRepository.versionsStorageKey,
            {'schemaVersion': 1, ...history.toJson()});
        try {
          repo.savePlan(version.plan);
          await storage.flush();
          await draftRepo.clear();
        } catch (_) {
          warning = '计划已启用，兼容镜像或草稿清理未完成，可重新打开后重试。';
        }
      });
      operation.checkActive();
      ref.invalidate(fourWeekPlanControllerProvider);
      state = LocalPlanState(
          message: warning ?? '计划已确认启用。',
          activated: true,
          draft: warning == null ? null : draft);
    } catch (e) {
      if (ref.mounted && generation == _generation) {
        try {
          operation.checkActive();
          state = LocalPlanState(draft: draft, message: e.toString());
        } on FeatureOperationInvalidation {
          state = const LocalPlanState(message: '来源或账号已变化，请重新打开。');
        }
      }
      rethrow;
    }
  }
}
