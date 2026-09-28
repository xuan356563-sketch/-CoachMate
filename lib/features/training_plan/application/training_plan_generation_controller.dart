import '../../../plugins/application/sport_skill_binding.dart';
import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/ai_artifact.dart';
import '../../../data/models/ai_training_prescription.dart';
import '../../../data/models/pre_exercise_clearance.dart';
import '../../../data/models/race.dart';
import '../../../data/models/user_profile.dart';
import '../../../services/plan_context_digest_service.dart';
import '../../ai_center/application/ai_artifact_controller.dart';
import '../../ai_center/data/ai_api.dart';
import '../../ai_center/data/training_prescription_api_models.dart';
import '../../auth/data/authenticated_api_client.dart';
import '../../first_run_onboarding/application/first_run_onboarding_controller.dart';
import '../../first_run_onboarding/application/membership_controller.dart';
import '../../profile/application/user_profile_controller.dart';
import 'four_week_plan_controller.dart';
import 'pre_exercise_clearance_controller.dart';

final trainingPlanGenerationControllerProvider = AsyncNotifierProvider<
    TrainingPlanGenerationController,
    TrainingPlanGenerationUiState>(TrainingPlanGenerationController.new);

class TrainingPlanGenerationUiState {
  final TrainingPrescriptionCapabilities capabilities;
  final KnowledgeCatalogSummary? knowledgeCatalog;
  final AiArtifact? artifact;
  final bool isGenerating;
  final bool confirmedButNotActivated;
  final String statusMessage;

  const TrainingPlanGenerationUiState({
    required this.capabilities,
    required this.knowledgeCatalog,
    required this.artifact,
    required this.isGenerating,
    required this.confirmedButNotActivated,
    required this.statusMessage,
  });

  TrainingPlanGenerationUiState copyWith({
    TrainingPrescriptionCapabilities? capabilities,
    KnowledgeCatalogSummary? knowledgeCatalog,
    AiArtifact? artifact,
    bool clearArtifact = false,
    bool? isGenerating,
    bool? confirmedButNotActivated,
    String? statusMessage,
  }) {
    return TrainingPlanGenerationUiState(
      capabilities: capabilities ?? this.capabilities,
      knowledgeCatalog: knowledgeCatalog ?? this.knowledgeCatalog,
      artifact: clearArtifact ? null : artifact ?? this.artifact,
      isGenerating: isGenerating ?? this.isGenerating,
      confirmedButNotActivated:
          confirmedButNotActivated ?? this.confirmedButNotActivated,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

class TrainingPlanGenerationController
    extends AsyncNotifier<TrainingPlanGenerationUiState> {
  @override
  Future<TrainingPlanGenerationUiState> build() async {
    bindFeatureController(ref, 'feature.training_plan', 'generation', this);
    if (!ref.read(featureAccessProvider).isWritable('feature.training_plan')) {
      return const TrainingPlanGenerationUiState(
          capabilities: TrainingPrescriptionCapabilities.unavailable(),
          knowledgeCatalog: null,
          artifact: null,
          isGenerating: false,
          confirmedButNotActivated: false,
          statusMessage: '计划功能已停用，已有版本可从历史记录查看。');
    }
    final operation = ref.read(featureAccessProvider).beginOperation(
        'feature.training_plan',
        dependencies: ['feature.ai_center']);
    try {
      await readFeatureController<AiArtifactController>(
          ref,
          'feature.ai_center',
          'controller',
          () => ref.read(aiArtifactControllerProvider.notifier)).sync();
      operation.checkActive();
    } on Object {
      // 同步失败时继续使用本机 Artifact，不能让恢复入口整体失效。
    }
    operation.checkActive();
    final AiArtifact? recoveredArtifact = _recoverUnactivatedArtifact();
    String? recoveryError;
    if (recoveredArtifact != null &&
        ref.read(fourWeekPlanControllerProvider).draft == null) {
      try {
        final PreExerciseClearance clearance =
            (await ref.read(preExerciseClearanceControllerProvider.future))
                .clearance;
        operation.checkActive();
        final DateTime clearanceNow =
            ref.read(preExerciseClearanceRealtimeClockProvider)();
        if (!clearance.isValidAt(clearanceNow)) {
          recoveryError =
              '${clearance.blockingReasonAt(clearanceNow)}已确认处方会保留，补齐筛查后可重试。';
        }
        final AiTrainingPrescription? prescription =
            recoveredArtifact.trainingPrescription;
        if (prescription == null) {
          throw const FormatException('处方类型不受支持');
        }
        final String? currentDigest = _currentRequestDigest();
        if (currentDigest == null ||
            prescription.generationMeta.clientContextDigest != currentDigest) {
          recoveryError = '已确认处方对应的档案或赛事已变化，请重新生成。';
        } else if (recoveryError == null) {
          await readFeatureController<FourWeekPlanController>(
                  ref,
                  'feature.training_plan',
                  'fourWeek',
                  () => ref.read(fourWeekPlanControllerProvider.notifier))
              .createDraft(
            prescription: prescription,
            artifact: recoveredArtifact,
          );
        }
      } on Object {
        recoveryError = '已找到待恢复产物，但处方格式无效，不能激活。';
      }
    }
    operation.checkActive();
    try {
      final TrainingPrescriptionCapabilities capabilities =
          await ref.read(aiApiProvider).trainingPrescriptionCapabilities();
      operation.checkActive();
      final KnowledgeCatalogSummary knowledgeCatalog =
          await ref.read(aiApiProvider).knowledgeCatalog();
      operation.checkActive();
      if (capabilities.skills.isNotEmpty) {
        final TrainingPrescriptionSkillCapability skill = capabilities.skills
                .where(
                  (TrainingPrescriptionSkillCapability item) =>
                      item.id == 'training-plan-builder',
                )
                .firstOrNull ??
            capabilities.skills.first;
        readFeatureController<FourWeekPlanController>(
                ref,
                'feature.training_plan',
                'fourWeek',
                () => ref.read(fourWeekPlanControllerProvider.notifier))
            .discoverSkillVersion(
          id: skill.id,
          version: skill.version,
          runtimeHash: skill.runtimeSha256,
          sourceHash: skill.sourceSha256,
          fragmentHashes: skill.fragmentSha256,
        );
      }
      return TrainingPlanGenerationUiState(
        capabilities: capabilities,
        knowledgeCatalog: knowledgeCatalog,
        artifact: recoveredArtifact,
        isGenerating: false,
        confirmedButNotActivated:
            recoveredArtifact?.decision == AiArtifactDecision.accepted,
        statusMessage: recoveryError ??
            (recoveredArtifact?.decision == AiArtifactDecision.accepted
                ? '处方已确认但尚未激活，可直接重试本地激活。'
                : capabilities.enabled
                    ? 'Skill 计划服务已就绪。'
                    : 'Skill 计划服务当前已关闭，现有计划不会改变。'),
      );
    } on ApiException catch (error) {
      return TrainingPlanGenerationUiState(
        capabilities: const TrainingPrescriptionCapabilities.unavailable(),
        knowledgeCatalog: null,
        artifact: recoveredArtifact,
        isGenerating: false,
        confirmedButNotActivated:
            recoveredArtifact?.decision == AiArtifactDecision.accepted,
        statusMessage: recoveryError ??
            (recoveredArtifact?.decision == AiArtifactDecision.accepted
                ? '处方已确认但尚未激活；联网复核当前 Skill 后可重试。'
                : '暂时无法读取 Skill 能力：${error.message}'),
      );
    }
  }

  Future<bool> generate({
    required String populationTemplateId,
    bool force = false,
  }) async {
    final operation = ref
        .read(featureAccessProvider)
        .beginOperation('feature.training_plan', dependencies: [
      'feature.ai_center',
      ...ref
          .read(fourWeekPlanControllerProvider)
          .generation
          .pluginRefs
          .map((source) => source.id)
    ]);
    final TrainingPlanGenerationUiState? current = state.value;
    if (current == null || current.isGenerating) return false;
    if (paidPlanGenerationGateEnabled) {
      final MembershipUiState membership =
          await ref.read(membershipControllerProvider.future);
      operation.checkActive();
      if (!membership.entitlement.canGeneratePlan) {
        state = AsyncData<TrainingPlanGenerationUiState>(
          current.copyWith(statusMessage: '生成新计划需要有效会员；已有计划仍可查看和执行。'),
        );
        return false;
      }
    }
    if (!current.capabilities.enabled) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(statusMessage: 'Skill 计划服务当前不可用，请使用本地规则计划。'),
      );
      return false;
    }
    final KnowledgeCatalogSummary? knowledgeCatalog = current.knowledgeCatalog;
    if (knowledgeCatalog == null ||
        !knowledgeCatalog.populationTemplates.any(
            (PopulationTemplateOption item) =>
                item.id == populationTemplateId)) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(statusMessage: '训练模式目录未就绪，请使用本地规则计划。'),
      );
      return false;
    }
    final String? localBlocker = await _localEligibilityBlocker();
    operation.checkActive();
    if (localBlocker != null) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(statusMessage: localBlocker),
      );
      return false;
    }
    final UserProfile profile = ref.read(userProfileControllerProvider).profile;
    final FourWeekPlanState planState =
        ref.read(fourWeekPlanControllerProvider);
    final TrainingPrescriptionRequestContext? requestContext =
        buildTrainingPrescriptionRequestContext(
      profile: profile,
      race: planState.activeRace,
      now: ref.read(fourWeekPlanNowProvider),
    );
    if (requestContext == null) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(statusMessage: '档案无法安全映射为白名单字段，请使用本地规则计划。'),
      );
      return false;
    }
    final runtime = ref.read(pluginRuntimeProvider);
    final definition =
        runtime.sportDirectory.require(profile.mainSports.first).definition;
    final skillBlocker = cloudSportSkillBlocker(
        runtime.registry.descriptors[definition.pluginRef.id]!,
        current.capabilities);
    if (skillBlocker != null) {
      state = AsyncData(current.copyWith(statusMessage: skillBlocker));
      return false;
    }
    final String digest = const PlanContextDigestService()
        .buildRequestContextDigest(requestContext.toJson());
    state = AsyncData<TrainingPlanGenerationUiState>(
      current.copyWith(
        isGenerating: true,
        confirmedButNotActivated: false,
        statusMessage: '正在生成结构化处方…',
      ),
    );
    AiArtifact? artifact;
    try {
      artifact = await readFeatureController<AiArtifactController>(
              ref,
              'feature.ai_center',
              'controller',
              () => ref.read(aiArtifactControllerProvider.notifier))
          .generateTrainingPrescriptionV2(
        TrainingPrescriptionV2Request(
          clientContextDigest: digest,
          populationTemplateId: populationTemplateId,
          knowledgeSnapshotVersion: knowledgeCatalog.version,
          context: requestContext,
          force: force,
        ),
        sourceOperation: operation,
      );
      operation.checkActive();
    } on Object catch (error) {
      if (ref.mounted) {
        state = AsyncData<TrainingPlanGenerationUiState>(
          current.copyWith(
            isGenerating: false,
            statusMessage: _operationFailureMessage(error, action: '生成'),
          ),
        );
      }
      return false;
    }
    if (artifact == null) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(
          isGenerating: false,
          statusMessage: ref.read(aiArtifactControllerProvider).statusMessage,
        ),
      );
      return false;
    }
    try {
      final AiTrainingPrescription? prescription =
          artifact.trainingPrescription;
      if (prescription == null ||
          prescription.generationMeta.clientContextDigest != digest) {
        throw const FormatException('训练处方上下文摘要不一致');
      }
      final String? citationBlocker = _knowledgeCitationBlocker(
        prescription: prescription,
        catalog: knowledgeCatalog,
      );
      if (citationBlocker != null) {
        throw FormatException(citationBlocker);
      }
      await readFeatureController<FourWeekPlanController>(
          ref,
          'feature.training_plan',
          'fourWeek',
          () => ref.read(fourWeekPlanControllerProvider.notifier)).createDraft(
        prescription: prescription,
        artifact: artifact,
        populationTemplateId: populationTemplateId,
        sourceOperation: operation,
      );
      final FourWeekPlanState compiled =
          ref.read(fourWeekPlanControllerProvider);
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(
          artifact: artifact,
          isGenerating: false,
          statusMessage: compiled.canActivateDraft
              ? '四周计划已完成本地编译和安全审计，请核对后确认。'
              : '本地安全审计发现阻断项，现有计划不会改变。',
        ),
      );
      return true;
    } on FormatException catch (error) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(
          artifact: artifact,
          isGenerating: false,
          statusMessage: '${error.message}，现有计划不会改变。',
        ),
      );
      return false;
    } on Object catch (error) {
      if (ref.mounted) {
        state = AsyncData<TrainingPlanGenerationUiState>(
          current.copyWith(
            artifact: artifact,
            isGenerating: false,
            statusMessage: _operationFailureMessage(error, action: '保存草稿'),
          ),
        );
      }
      return false;
    }
  }

  Future<bool> confirmAndActivate() async {
    final operation = ref
        .read(featureAccessProvider)
        .beginOperation('feature.training_plan', dependencies: [
      'feature.ai_center',
      ...ref
          .read(fourWeekPlanControllerProvider)
          .generation
          .pluginRefs
          .map((source) => source.id)
    ]);
    final TrainingPlanGenerationUiState? current = state.value;
    final AiArtifact? artifact = current?.artifact;
    if (current == null || artifact == null || current.isGenerating) {
      return false;
    }
    if (artifact.decision == AiArtifactDecision.rejected) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(statusMessage: '该处方已被拒绝，不能激活，请重新生成。'),
      );
      return false;
    }
    final String? blocker = await _localEligibilityBlocker();
    operation.checkActive();
    if (blocker != null) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(statusMessage: blocker),
      );
      return false;
    }
    AiTrainingPrescription? prescription;
    try {
      prescription = artifact.trainingPrescription;
    } on Object {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(statusMessage: '处方格式无效，不能激活，现有计划不会改变。'),
      );
      return false;
    }
    final String? requestDigest = _currentRequestDigest();
    if (prescription == null ||
        requestDigest == null ||
        prescription.generationMeta.clientContextDigest != requestDigest) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(statusMessage: '档案或赛事已变化，请重新生成后再确认。'),
      );
      return false;
    }
    final String? citationBlocker = _knowledgeCitationBlocker(
      prescription: prescription,
      catalog: current.knowledgeCatalog,
    );
    if (citationBlocker != null) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(statusMessage: '$citationBlocker，现有计划不会改变。'),
      );
      return false;
    }
    FourWeekPlanState planState = ref.read(fourWeekPlanControllerProvider);
    if (planState.draft == null) {
      await readFeatureController<FourWeekPlanController>(
          ref,
          'feature.training_plan',
          'fourWeek',
          () => ref.read(fourWeekPlanControllerProvider.notifier)).createDraft(
        prescription: prescription,
        artifact: artifact,
        sourceOperation: operation,
      );
      planState = ref.read(fourWeekPlanControllerProvider);
    }
    if (planState.draft?.artifactId != artifact.id) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(statusMessage: '待确认草稿与服务端产物不匹配，请重新生成。'),
      );
      return false;
    }
    if (!planState.canActivateDraft) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(statusMessage: planState.statusMessage),
      );
      return false;
    }
    state = AsyncData<TrainingPlanGenerationUiState>(
      current.copyWith(isGenerating: true, statusMessage: '正在确认并激活计划…'),
    );
    // pending 与 accepted 均调用服务端。accepted→accepted 用于重新校验
    // Kill Switch、Skill 撤销与哈希状态，成功后才允许本地激活。
    AiArtifact? accepted;
    try {
      accepted = await operation.commit(() =>
          readFeatureController<AiArtifactController>(
              ref,
              'feature.ai_center',
              'controller',
              () => ref.read(aiArtifactControllerProvider.notifier)).decide(
            artifact: artifact,
            decision: AiArtifactDecision.accepted,
          ));
      operation.checkActive();
    } on Object catch (error) {
      if (ref.mounted) {
        state = AsyncData<TrainingPlanGenerationUiState>(
          current.copyWith(
            artifact: artifact,
            isGenerating: false,
            confirmedButNotActivated:
                artifact.decision == AiArtifactDecision.accepted,
            statusMessage: _operationFailureMessage(error, action: '确认'),
          ),
        );
      }
      return false;
    }
    if (accepted == null) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(
          artifact: artifact,
          isGenerating: false,
          confirmedButNotActivated:
              artifact.decision == AiArtifactDecision.accepted,
          statusMessage: ref.read(aiArtifactControllerProvider).statusMessage,
        ),
      );
      return false;
    }
    final String? acceptedBlocker = trainingPrescriptionAcceptanceBlocker(
      original: artifact,
      accepted: accepted,
      expectedPrescription: planState.draft!.prescription,
    );
    if (acceptedBlocker != null) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(
          artifact: artifact,
          isGenerating: false,
          confirmedButNotActivated:
              artifact.decision == AiArtifactDecision.accepted,
          statusMessage: acceptedBlocker,
        ),
      );
      return false;
    }
    try {
      final bool activated = await ref
          .read(fourWeekPlanControllerProvider.notifier)
          .activateDraft(artifactId: accepted.id);
      operation.checkActive();
      final FourWeekPlanState activatedState =
          ref.read(fourWeekPlanControllerProvider);
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(
          artifact: accepted,
          isGenerating: false,
          confirmedButNotActivated: !activated,
          statusMessage: activated
              ? '新计划已激活，旧版本仍可回退。'
              : '处方已确认但尚未激活：${activatedState.statusMessage}',
        ),
      );
      return activated;
    } catch (_) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(
          artifact: accepted,
          isGenerating: false,
          confirmedButNotActivated: true,
          statusMessage: '处方已确认但尚未激活，请重试本地激活。',
        ),
      );
      return false;
    }
  }

  Future<void> reject() async {
    final operation = ref
        .read(featureAccessProvider)
        .beginOperation('feature.training_plan', dependencies: [
      'feature.ai_center',
      ...ref
          .read(fourWeekPlanControllerProvider)
          .generation
          .pluginRefs
          .map((source) => source.id)
    ]);
    final TrainingPlanGenerationUiState? current = state.value;
    final AiArtifact? artifact = current?.artifact;
    if (current == null || artifact == null || current.isGenerating) return;
    if (!artifact.isPending) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(statusMessage: '已确认的处方不能再拒绝，请重试激活或保留现有计划。'),
      );
      return;
    }
    state = AsyncData<TrainingPlanGenerationUiState>(
      current.copyWith(isGenerating: true, statusMessage: '正在拒绝计划草稿…'),
    );
    try {
      final AiArtifact? rejected = await operation.commit(() =>
          readFeatureController<AiArtifactController>(
              ref,
              'feature.ai_center',
              'controller',
              () => ref.read(aiArtifactControllerProvider.notifier)).decide(
            artifact: artifact,
            decision: AiArtifactDecision.rejected,
          ));
      operation.checkActive();
      if (rejected == null) {
        state = AsyncData<TrainingPlanGenerationUiState>(
          current.copyWith(
            artifact: artifact,
            isGenerating: false,
            statusMessage: ref.read(aiArtifactControllerProvider).statusMessage,
          ),
        );
        return;
      }
      final bool matches = rejected.id == artifact.id &&
          rejected.artifactType == artifact.artifactType &&
          rejected.schemaVersion == artifact.schemaVersion &&
          rejected.contextDigest == artifact.contextDigest &&
          rejected.decision == AiArtifactDecision.rejected &&
          jsonEncode(rejected.payload) == jsonEncode(artifact.payload);
      if (!matches) {
        state = AsyncData<TrainingPlanGenerationUiState>(
          current.copyWith(
            artifact: artifact,
            isGenerating: false,
            statusMessage: '服务端拒绝结果与当前草稿不一致，草稿已保留，请重试。',
          ),
        );
        return;
      }
      await readFeatureController<FourWeekPlanController>(
          ref,
          'feature.training_plan',
          'fourWeek',
          () => ref.read(fourWeekPlanControllerProvider.notifier)).rejectDraft(
        artifactId: artifact.id,
        sourceOperation: operation,
      );
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(
          clearArtifact: true,
          isGenerating: false,
          confirmedButNotActivated: false,
          statusMessage: '已拒绝该草稿，现有计划未改变。',
        ),
      );
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(
          artifact: artifact,
          isGenerating: false,
          statusMessage: _operationFailureMessage(error, action: '拒绝'),
        ),
      );
    }
  }

  Future<bool> rollback(String versionId) async {
    final operation = ref
        .read(featureAccessProvider)
        .beginOperation('feature.training_plan', dependencies: [
      'feature.ai_center',
      ...ref
          .read(fourWeekPlanControllerProvider)
          .generation
          .pluginRefs
          .map((source) => source.id)
    ]);
    final bool rolledBack = await ref
        .read(fourWeekPlanControllerProvider.notifier)
        .rollbackToVersion(versionId);
    operation.checkActive();
    final TrainingPlanGenerationUiState? current = state.value;
    if (current != null) {
      state = AsyncData<TrainingPlanGenerationUiState>(
        current.copyWith(
          statusMessage: ref.read(fourWeekPlanControllerProvider).statusMessage,
        ),
      );
    }
    return rolledBack;
  }

  AiArtifact? _recoverUnactivatedArtifact() {
    final FourWeekPlanState planState =
        ref.read(fourWeekPlanControllerProvider);
    final Set<String> activatedArtifactIds = <String>{
      for (final version in planState.history)
        if (version.artifactId != null) version.artifactId!,
    };
    final String? draftArtifactId = planState.draft?.artifactId;
    for (final AiArtifact artifact
        in ref.read(aiArtifactControllerProvider).artifacts) {
      if (artifact.artifactType != 'training_prescription_v1' &&
          artifact.artifactType != 'training_prescription_v2') {
        continue;
      }
      if (draftArtifactId != null && artifact.id == draftArtifactId) {
        return artifact;
      }
      if (draftArtifactId == null &&
          artifact.decision == AiArtifactDecision.accepted &&
          !activatedArtifactIds.contains(artifact.id)) {
        return artifact;
      }
    }
    return null;
  }

  String? _currentRequestDigest() {
    final UserProfile profile = ref.read(userProfileControllerProvider).profile;
    final FourWeekPlanState planState =
        ref.read(fourWeekPlanControllerProvider);
    final TrainingPrescriptionRequestContext? context =
        buildTrainingPrescriptionRequestContext(
      profile: profile,
      race: planState.activeRace,
      now: ref.read(fourWeekPlanNowProvider),
    );
    if (context == null) return null;
    return const PlanContextDigestService()
        .buildRequestContextDigest(context.toJson());
  }

  Future<String?> _localEligibilityBlocker() async {
    final UserProfileState profileState =
        ref.read(userProfileControllerProvider);
    final UserProfile profile = profileState.profile;
    if (!profileState.isCompleted) return '请先完成并确认训练档案。';
    if (profile.age < 18) return 'V1 仅开放给 18 岁以上成人内测者。';
    if (profile.mainSports.isEmpty) return '请先选择主运动。';
    if (profile.mainSports.contains(MainSport.rehab)) {
      return '康复或受监督训练不进入 V1 Skill 计划。';
    }
    if (profile.trainingExperienceLevel == TrainingExperienceLevel.unknown) {
      return '请先补充训练经验等级。';
    }
    final PreExerciseClearance clearance =
        (await ref.read(preExerciseClearanceControllerProvider.future))
            .clearance;
    final DateTime now = ref.read(preExerciseClearanceRealtimeClockProvider)();
    if (!clearance.isValidAt(now)) return clearance.blockingReasonAt(now);
    return null;
  }
}

String? trainingPrescriptionAcceptanceBlocker({
  required AiArtifact original,
  required AiArtifact accepted,
  required AiTrainingPrescription expectedPrescription,
}) {
  AiTrainingPrescription? acceptedPrescription;
  try {
    acceptedPrescription = accepted.trainingPrescription;
  } on Object {
    return '服务返回的确认处方格式无效，不能激活，现有计划不会改变。';
  }
  final AiSkillRef expectedSkill = expectedPrescription.skill;
  final AiSkillRef? actualSkill = acceptedPrescription?.skill;
  final bool supportedArtifactType =
      original.artifactType == 'training_prescription_v1' ||
          original.artifactType == 'training_prescription_v2';
  if (accepted.id != original.id ||
      accepted.decision != AiArtifactDecision.accepted ||
      accepted.capability != AiCapability.trainer ||
      !supportedArtifactType ||
      accepted.artifactType != original.artifactType ||
      accepted.schemaVersion != original.schemaVersion ||
      accepted.contextDigest != original.contextDigest ||
      acceptedPrescription == null ||
      acceptedPrescription.cycleFocus != expectedPrescription.cycleFocus ||
      acceptedPrescription.progressionMode !=
          expectedPrescription.progressionMode ||
      jsonEncode(
            acceptedPrescription.weeklySessions
                .map((item) => item.toJson())
                .toList(growable: false),
          ) !=
          jsonEncode(
            expectedPrescription.weeklySessions
                .map((item) => item.toJson())
                .toList(growable: false),
          ) ||
      acceptedPrescription.selectionReasonCode !=
          expectedPrescription.selectionReasonCode ||
      acceptedPrescription.generationMeta.contractVersion !=
          expectedPrescription.generationMeta.contractVersion ||
      acceptedPrescription.generationMeta.promptContractVersion !=
          expectedPrescription.generationMeta.promptContractVersion ||
      acceptedPrescription.generationMeta.knowledgeSnapshotVersion !=
          expectedPrescription.generationMeta.knowledgeSnapshotVersion ||
      acceptedPrescription.generationMeta.generationMode !=
          expectedPrescription.generationMeta.generationMode ||
      acceptedPrescription.generationMeta.model !=
          expectedPrescription.generationMeta.model ||
      acceptedPrescription.generationMeta.clientContextDigest !=
          expectedPrescription.generationMeta.clientContextDigest ||
      jsonEncode(
            acceptedPrescription.knowledgeCitations
                .map((item) => item.toJson())
                .toList(growable: false),
          ) !=
          jsonEncode(
            expectedPrescription.knowledgeCitations
                .map((item) => item.toJson())
                .toList(growable: false),
          ) ||
      actualSkill == null ||
      actualSkill.id != expectedSkill.id ||
      actualSkill.version != expectedSkill.version ||
      actualSkill.displayName != expectedSkill.displayName ||
      actualSkill.sourceSha256 != expectedSkill.sourceSha256 ||
      actualSkill.runtimeSha256 != expectedSkill.runtimeSha256 ||
      actualSkill.fragmentSha256 != expectedSkill.fragmentSha256 ||
      actualSkill.coverage != expectedSkill.coverage ||
      actualSkill.selectionReason != expectedSkill.selectionReason) {
    return '服务返回的确认结果与待激活草稿不一致，现有计划不会改变。';
  }
  return null;
}

String? _knowledgeCitationBlocker({
  required AiTrainingPrescription prescription,
  required KnowledgeCatalogSummary? catalog,
}) {
  if (prescription.generationMeta.contractVersion != '2') return null;
  if (catalog == null) return '训练知识目录尚未就绪，不能确认 V2 处方';
  if (prescription.knowledgeCitations.isEmpty) return 'V2 处方缺少审核知识引用';
  if (prescription.generationMeta.knowledgeSnapshotVersion != catalog.version ||
      prescription.knowledgeCitations.any(
        (item) =>
            item.contentVersion != catalog.version ||
            !catalog.verifiedEntryIds.contains(item.id),
      )) {
    return '处方引用已失效，请刷新知识目录后重新生成';
  }
  return null;
}

String _operationFailureMessage(Object error, {required String action}) {
  if (error is StateError) {
    return '${error.message}；$action未完成，请重新操作。';
  }
  return '$action失败，草稿与当前计划均已保留，请重试。';
}

TrainingPrescriptionRequestContext? buildTrainingPrescriptionRequestContext({
  required UserProfile profile,
  required RacePlan? race,
  required DateTime now,
}) {
  if (profile.mainSports.isEmpty ||
      profile.mainSports.contains(MainSport.rehab) ||
      profile.trainingExperienceLevel == TrainingExperienceLevel.unknown ||
      profile.weeklyTrainingDays < 1 ||
      profile.dailyAvailableMinutes < 20) {
    return null;
  }
  final MainSport primary = profile.mainSports.first;
  MainSport? secondary;
  for (final MainSport sport in profile.mainSports.skip(1)) {
    if (sport != primary) {
      secondary = sport;
      break;
    }
  }
  if (secondary == MainSport.rehab) return null;
  final String? raceType = _raceTypeCode(race);
  if (race != null && raceType == null) return null;
  final int rawDaysUntilRace = race == null
      ? 0
      : DateTime(race.raceDate.year, race.raceDate.month, race.raceDate.day)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
  if (race != null && (rawDaysUntilRace < 1 || rawDaysUntilRace > 730)) {
    return null;
  }
  final bool includesRace = race != null;
  return TrainingPrescriptionRequestContext(
    goal: _goalCode(
      profile.trainingGoal,
      primary,
      hasSupportedRace: includesRace,
    ),
    primarySport: primary.jsonValue,
    secondarySport: secondary?.jsonValue,
    experienceLevel: profile.trainingExperienceLevel.jsonValue,
    biologicalSex: profile.aiPlanningBiologicalSexCode,
    weeklyTrainingDays: profile.weeklyTrainingDays.clamp(1, 6),
    availableMinutes: profile.dailyAvailableMinutes.clamp(20, 180),
    equipmentAccess: _equipmentCodes(profile.equipmentAccessType),
    raceType: includesRace ? raceType : null,
    daysUntilRace: includesRace ? rawDaysUntilRace : null,
  );
}

String _goalCode(
  String raw,
  MainSport primary, {
  required bool hasSupportedRace,
}) {
  if (hasSupportedRace || raw.contains('备赛') || raw.contains('比赛')) {
    return 'race_preparation';
  }
  if (raw.contains('减脂') || raw.contains('体重')) return 'fat_loss';
  if (raw.contains('力量') || raw.contains('增肌')) return 'strength';
  if (raw.contains('耐力') || raw.contains('跑')) return 'endurance';
  return switch (primary) {
    MainSport.strength => 'strength',
    MainSport.fatLoss => 'fat_loss',
    MainSport.marathon || MainSport.trailRunning => 'endurance',
    MainSport.hyrox => 'race_preparation',
    MainSport.generalFitness => 'general_fitness',
    MainSport.rehab => 'general_fitness',
  };
}

String? _raceTypeCode(RacePlan? race) => switch (race?.type) {
      RaceType.marathon => 'marathon',
      RaceType.trailRunning => 'trail',
      RaceType.hyrox => 'hyrox',
      RaceType.roadRunning || null => null,
    };

List<String> _equipmentCodes(EquipmentAccessType type) => switch (type) {
      EquipmentAccessType.none => const <String>['bodyweight'],
      EquipmentAccessType.basicHome => const <String>['bodyweight', 'dumbbell'],
      EquipmentAccessType.gym || EquipmentAccessType.mixed => const <String>[
          'bodyweight',
          'dumbbell',
          'barbell',
          'kettlebell',
          'machines',
          'cardio_machines',
        ],
    };
