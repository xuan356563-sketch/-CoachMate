import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/ai_artifact.dart';
import 'package:trainflow_ai/data/models/ai_training_prescription.dart';
import 'package:trainflow_ai/data/models/pre_exercise_clearance.dart';
import 'package:trainflow_ai/data/models/plan_revision_proposal.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/repositories/generated_training_plan_repository.dart';
import 'package:trainflow_ai/features/ai_center/application/ai_artifact_controller.dart';
import 'package:trainflow_ai/features/ai_center/data/training_prescription_api_models.dart';
import 'package:trainflow_ai/features/ai_center/data/plan_revision_api_models.dart';
import 'package:trainflow_ai/features/profile/application/training_schedule_controller.dart';
import 'package:trainflow_ai/features/profile/application/user_profile_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/four_week_plan_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/pre_exercise_clearance_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/plan_revision_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/training_plan_generation_controller.dart';
import 'package:trainflow_ai/plugins/application/feature_controller_binding.dart';
import 'package:trainflow_ai/plugins/application/feature_access.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/plan_context_digest_service.dart';

void main() {
  test('插件未匹配到云端技能时不发起生成且有效计划保持不变', () async {
    final runtime = await _runtime();
    final ai = _ControlledArtifactController();
    final storage = InMemoryLocalStorageService();
    final container = _container(runtime, ai, storage: storage);
    addTearDown(container.dispose);
    _completeProfile(container);
    await container.read(trainingPlanGenerationControllerProvider.future);
    final controller =
        container.read(trainingPlanGenerationControllerProvider.notifier)
            as _ReadyGenerationController;
    final before =
        container.read(fourWeekPlanControllerProvider).generation.plan.toJson();
    controller.setCapabilities(const TrainingPrescriptionCapabilities(
        enabled: true, contractVersion: 1, skills: []));
    expect(
        await controller.generate(populationTemplateId: 'low_impact_fat_loss'),
        isFalse);
    expect(ai.generationCalls, 0);
    expect(
        container
            .read(trainingPlanGenerationControllerProvider)
            .requireValue
            .statusMessage,
        contains('未提供'));
    expect(
        container
            .read(trainingPlanGenerationControllerProvider)
            .requireValue
            .isGenerating,
        isFalse);
    expect(
        container.read(fourWeekPlanControllerProvider).generation.plan.toJson(),
        before);
  });

  test('生成等待中停用来源会清忙，重新启用后可以重试', () async {
    final runtime = await _runtime();
    final ai = _ControlledArtifactController();
    final container = _container(runtime, ai);
    addTearDown(container.dispose);
    _completeProfile(container);
    await container.read(trainingPlanGenerationControllerProvider.future);

    final first = Completer<AiArtifact?>();
    ai.generationResults.add(first);
    final pending = container
        .read(trainingPlanGenerationControllerProvider.notifier)
        .generate(populationTemplateId: 'low_impact_fat_loss');
    await Future<void>.delayed(Duration.zero);
    expect(
        container
            .read(trainingPlanGenerationControllerProvider)
            .value!
            .isGenerating,
        isTrue);

    await runtime.disable('feature.training_plan');
    first.complete(null);
    expect(await pending, isFalse);
    expect(
        container
            .read(trainingPlanGenerationControllerProvider)
            .value!
            .isGenerating,
        isFalse);

    await runtime.enable('feature.training_plan');
    final second = Completer<AiArtifact?>()..complete(null);
    ai.generationResults.add(second);
    expect(
      await container
          .read(trainingPlanGenerationControllerProvider.notifier)
          .generate(populationTemplateId: 'low_impact_fat_loss'),
      isFalse,
    );
    expect(ai.generationCalls, 2);
  });

  test('生成等待中账户变化或异常都会清忙并允许重试', () async {
    for (final bool accountChanges in <bool>[true, false]) {
      final runtime = await _runtime();
      final ai = _ControlledArtifactController();
      final container = _container(runtime, ai);
      addTearDown(container.dispose);
      _completeProfile(container);
      await container.read(trainingPlanGenerationControllerProvider.future);
      final first = Completer<AiArtifact?>();
      ai.generationResults.add(first);
      final pending = container
          .read(trainingPlanGenerationControllerProvider.notifier)
          .generate(populationTemplateId: 'low_impact_fat_loss');
      await Future<void>.delayed(Duration.zero);
      if (accountChanges) {
        await runtime.changeAccountScope();
        first.complete(null);
      } else {
        first.completeError(StateError('测试网络异常'));
      }
      expect(await pending, isFalse);
      expect(
        container
            .read(trainingPlanGenerationControllerProvider)
            .value!
            .isGenerating,
        isFalse,
      );
      final second = Completer<AiArtifact?>()..complete(null);
      ai.generationResults.add(second);
      expect(
        await container
            .read(trainingPlanGenerationControllerProvider.notifier)
            .generate(populationTemplateId: 'low_impact_fat_loss'),
        isFalse,
      );
      expect(ai.generationCalls, 2);
    }
  });

  test('远端拒绝返回空时保留本地 artifact 与草稿并显示失败', () async {
    final runtime = await _runtime();
    final ai = _ControlledArtifactController();
    final storage = InMemoryLocalStorageService();
    final container = _container(runtime, ai, storage: storage);
    addTearDown(container.dispose);
    _completeProfile(container);
    final profile = container.read(userProfileControllerProvider).profile;
    final context = buildTrainingPrescriptionRequestContext(
      profile: profile,
      race: null,
      now: DateTime(2026, 9, 4),
    )!;
    final digest = const PlanContextDigestService()
        .buildRequestContextDigest(context.toJson());
    final prescription = _prescription(digest);
    final artifact = _artifact(prescription);
    await container
        .read(fourWeekPlanControllerProvider.notifier)
        .createDraft(prescription: prescription, artifact: artifact);
    await container.read(trainingPlanGenerationControllerProvider.future);
    (container.read(trainingPlanGenerationControllerProvider.notifier)
            as _ReadyGenerationController)
        .setArtifact(artifact);
    ai.decisionResult = null;

    await container
        .read(trainingPlanGenerationControllerProvider.notifier)
        .reject();

    final state =
        container.read(trainingPlanGenerationControllerProvider).value!;
    expect(state.artifact?.id, artifact.id);
    expect(container.read(fourWeekPlanControllerProvider).draft?.artifactId,
        artifact.id);
    expect(state.isGenerating, isFalse);
    expect(state.statusMessage, contains('远端拒绝失败'));
    expect(state.statusMessage, isNot(contains('已拒绝该草稿')));
  });

  test('计划生成远端拒绝成功但本地删除落盘失败时恢复同一草稿', () async {
    final runtime = await _runtime();
    final ai = _ControlledArtifactController();
    final storage = _RejectFlushStorage();
    final container = _container(runtime, ai, storage: storage);
    addTearDown(container.dispose);
    _completeProfile(container);
    final profile = container.read(userProfileControllerProvider).profile;
    final context = buildTrainingPrescriptionRequestContext(
      profile: profile,
      race: null,
      now: DateTime(2026, 9, 4),
    )!;
    final digest = const PlanContextDigestService()
        .buildRequestContextDigest(context.toJson());
    final prescription = _prescription(digest);
    final artifact = _artifact(prescription);
    await container
        .read(fourWeekPlanControllerProvider.notifier)
        .createDraft(prescription: prescription, artifact: artifact);
    await container.read(trainingPlanGenerationControllerProvider.future);
    (container.read(trainingPlanGenerationControllerProvider.notifier)
            as _ReadyGenerationController)
        .setArtifact(artifact);
    ai.decisionResult = artifact.copyWith(
      decision: AiArtifactDecision.rejected,
      decidedAt: DateTime(2026, 9, 4, 12),
    );

    await container
        .read(trainingPlanGenerationControllerProvider.notifier)
        .reject();

    final state =
        container.read(trainingPlanGenerationControllerProvider).value!;
    final restored = GeneratedTrainingPlanRepository(storage).getDraft();
    expect(restored?.artifactId, artifact.id);
    expect(container.read(fourWeekPlanControllerProvider).draft?.artifactId,
        artifact.id);
    expect(state.artifact?.id, artifact.id);
    expect(state.isGenerating, isFalse);
    expect(state.statusMessage, contains('已恢复原草稿'));
    expect(state.statusMessage, isNot(contains('已拒绝该草稿')));
  });

  test('周期重排远端拒绝成功但本地删除落盘失败时恢复同一草稿', () async {
    final runtime = await _runtime();
    final ai = _ControlledArtifactController();
    final storage = _RejectFlushStorage();
    final container = _container(runtime, ai, storage: storage);
    addTearDown(container.dispose);
    _completeProfile(container);
    final profile = container.read(userProfileControllerProvider).profile;
    final context = buildTrainingPrescriptionRequestContext(
      profile: profile,
      race: null,
      now: DateTime(2026, 9, 4),
    )!;
    final digest = const PlanContextDigestService()
        .buildRequestContextDigest(context.toJson());
    final prescription = _prescription(digest);
    final artifact = _revisionArtifact(prescription);
    await container
        .read(fourWeekPlanControllerProvider.notifier)
        .createDraft(prescription: prescription, artifact: artifact);
    final revision = container.read(planRevisionControllerProvider.notifier)
        as _ReadyRevisionController;
    revision.setProposal(PlanRevisionProposal(
      artifact: artifact,
      revisedPrescription: prescription,
      differences: const <PlanRevisionDifference>[],
      generationMode: 'cloud_adaptation',
    ));
    ai.decisionResult = artifact.copyWith(
      decision: AiArtifactDecision.rejected,
      decidedAt: DateTime(2026, 9, 4, 12),
    );

    await revision.reject();

    final state = container.read(planRevisionControllerProvider);
    final restored = GeneratedTrainingPlanRepository(storage).getDraft();
    expect(restored?.artifactId, artifact.id);
    expect(container.read(fourWeekPlanControllerProvider).draft?.artifactId,
        artifact.id);
    expect(state.proposal?.artifact.id, artifact.id);
    expect(state.isBusy, isFalse);
    expect(state.statusMessage, contains('已恢复原草稿'));
    expect(state.statusMessage, isNot(contains('已拒绝重排草稿')));
  });

  test('草稿删除与恢复落盘都失败时保留内存证据并报告恢复失败', () async {
    final runtime = await _runtime();
    final ai = _ControlledArtifactController();
    final storage = _RejectFlushStorage(failRestore: true);
    final container = _container(runtime, ai, storage: storage);
    addTearDown(container.dispose);
    _completeProfile(container);
    final profile = container.read(userProfileControllerProvider).profile;
    final context = buildTrainingPrescriptionRequestContext(
      profile: profile,
      race: null,
      now: DateTime(2026, 9, 4),
    )!;
    final digest = const PlanContextDigestService()
        .buildRequestContextDigest(context.toJson());
    final prescription = _prescription(digest);
    final artifact = _artifact(prescription);
    final plans = container.read(fourWeekPlanControllerProvider.notifier);
    await plans.createDraft(prescription: prescription, artifact: artifact);

    await expectLater(
      plans.rejectDraft(artifactId: artifact.id),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          '错误提示',
          contains('恢复写入也失败'),
        ),
      ),
    );

    expect(GeneratedTrainingPlanRepository(storage).getDraft()?.artifactId,
        artifact.id);
    expect(container.read(fourWeekPlanControllerProvider).draft?.artifactId,
        artifact.id);
  });

  test('周期重排等待中来源失效会清忙，重新启用后可以重试', () async {
    final runtime = await _runtime();
    final ai = _ControlledArtifactController();
    final container = _container(runtime, ai);
    addTearDown(container.dispose);
    _completeProfile(container);
    await container.read(preExerciseClearanceControllerProvider.future);
    final profile = container.read(userProfileControllerProvider).profile;
    final context = buildTrainingPrescriptionRequestContext(
      profile: profile,
      race: null,
      now: DateTime(2026, 9, 4),
    )!;
    final digest = const PlanContextDigestService()
        .buildRequestContextDigest(context.toJson());
    final prescription = _prescription(digest);
    final artifact = _artifact(prescription);
    final plans = container.read(fourWeekPlanControllerProvider.notifier);
    await plans.createDraft(prescription: prescription, artifact: artifact);
    expect(await plans.activateDraft(artifactId: artifact.id), isTrue);
    final schedule =
        container.read(trainingScheduleControllerProvider.notifier);
    await schedule.addSlot(
      date: DateTime(2026, 9, 10),
      startMinute: 600,
      endMinute: 660,
    );
    await schedule.addSlot(
      date: DateTime(2026, 9, 12),
      startMinute: 600,
      endMinute: 660,
    );
    final revision = container.read(planRevisionControllerProvider.notifier);
    final first = Completer<PlanRevisionProposal?>();
    ai.revisionResults.add(first);

    final pending = revision.propose(missedSessions: 2);
    await Future<void>.delayed(Duration.zero);
    expect(ai.revisionCalls, 1,
        reason: container.read(planRevisionControllerProvider).statusMessage);
    expect(container.read(planRevisionControllerProvider).isBusy, isTrue);
    await runtime.disable('feature.training_plan');
    first.complete(null);
    expect(await pending, isFalse);
    expect(container.read(planRevisionControllerProvider).isBusy, isFalse);

    await runtime.enable('feature.training_plan');
    final second = Completer<PlanRevisionProposal?>()..complete(null);
    ai.revisionResults.add(second);
    expect(await revision.propose(missedSessions: 2), isFalse);
    expect(ai.revisionCalls, 2);
    expect(container.read(planRevisionControllerProvider).isBusy, isFalse);
  });
}

Future<PluginRuntime> _runtime() async {
  final runtime = PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
  await runtime.initialize();
  return runtime;
}

ProviderContainer _container(
  PluginRuntime runtime,
  _ControlledArtifactController ai, {
  InMemoryLocalStorageService? storage,
}) {
  final local = storage ?? InMemoryLocalStorageService();
  return ProviderContainer(overrides: [
    pluginRuntimeProvider.overrideWith((ref) => runtime),
    localStorageServiceProvider.overrideWithValue(local),
    fourWeekPlanNowProvider.overrideWithValue(DateTime(2026, 9, 4)),
    preExerciseClearanceRealtimeClockProvider
        .overrideWithValue(() => DateTime(2026, 9, 4)),
    preExerciseClearanceControllerProvider.overrideWith(_ReadyClearance.new),
    aiArtifactControllerProvider.overrideWith(() => ai),
    trainingPlanGenerationControllerProvider
        .overrideWith(_ReadyGenerationController.new),
    planRevisionControllerProvider.overrideWith(_ReadyRevisionController.new),
  ]);
}

void _completeProfile(ProviderContainer container) {
  final profile =
      container.read(userProfileControllerProvider).profile.copyWith(
    trainingExperienceLevel: TrainingExperienceLevel.intermediate,
    weeklyTrainingDays: 3,
    dailyAvailableMinutes: 45,
    mainSports: const <MainSport>[MainSport.generalFitness],
  );
  container.read(userProfileControllerProvider.notifier).save(profile);
}

class _ReadyClearance extends PreExerciseClearanceController {
  @override
  Future<PreExerciseClearanceState> build() async => PreExerciseClearanceState(
        clearance: PreExerciseClearance.recorded(
          status: PreExerciseClearanceStatus.selfCleared,
          currentInjuryOrRestriction: false,
          completedAt: DateTime(2026, 9, 1),
        ),
        isSaving: false,
        statusMessage: '测试筛查有效',
      );
}

class _ReadyGenerationController extends TrainingPlanGenerationController {
  @override
  Future<TrainingPlanGenerationUiState> build() async {
    bindFeatureController(ref, 'feature.training_plan', 'generation', this);
    return const TrainingPlanGenerationUiState(
      capabilities: TrainingPrescriptionCapabilities(
        enabled: true,
        contractVersion: 1,
        skills: <TrainingPrescriptionSkillCapability>[
          TrainingPrescriptionSkillCapability(
            id: 'training-plan-builder',
            version: '1.3.0',
            displayName: '测试训练技能',
            sports: ['general_fitness'],
            sourceSha256:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            runtimeSha256:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          ),
        ],
      ),
      knowledgeCatalog: KnowledgeCatalogSummary(
        version: 'catalog-v1',
        populationTemplates: <PopulationTemplateOption>[
          PopulationTemplateOption(
            id: 'low_impact_fat_loss',
            title: '低冲击减脂',
            automaticPlanAllowed: true,
            progressionMode: 'conservative',
          ),
        ],
        allPopulationTemplates: <PopulationTemplateOption>[],
        verifiedEntryIds: <String>{},
        verifiedPrincipleCount: 0,
        verifiedTrainingTemplateCount: 0,
      ),
      artifact: null,
      isGenerating: false,
      confirmedButNotActivated: false,
      statusMessage: '测试服务已就绪',
    );
  }

  void setCapabilities(TrainingPrescriptionCapabilities capabilities) {
    state = AsyncData(state.requireValue.copyWith(capabilities: capabilities));
  }

  void setArtifact(AiArtifact artifact) {
    state = AsyncData(state.requireValue.copyWith(artifact: artifact));
  }
}

class _ReadyRevisionController extends PlanRevisionController {
  @override
  PlanRevisionState build() {
    bindFeatureController(ref, 'feature.training_plan', 'revision', this);
    return const PlanRevisionState.initial();
  }

  void setProposal(PlanRevisionProposal proposal) {
    state = state.copyWith(proposal: proposal, statusMessage: '测试重排草稿待确认');
  }
}

class _ControlledArtifactController extends AiArtifactController {
  final List<Completer<AiArtifact?>> generationResults =
      <Completer<AiArtifact?>>[];
  final List<Completer<PlanRevisionProposal?>> revisionResults =
      <Completer<PlanRevisionProposal?>>[];
  int generationCalls = 0;
  int revisionCalls = 0;
  AiArtifact? recoveredArtifact;
  AiArtifact? decisionResult;

  @override
  AiArtifactState build() {
    bindFeatureController(ref, 'feature.ai_center', 'controller', this);
    return AiArtifactState(
      artifacts: recoveredArtifact == null
          ? const <AiArtifact>[]
          : <AiArtifact>[recoveredArtifact!],
      isSyncing: false,
      isGenerating: false,
      activeCapability: null,
      healthDataProcessingConsented: false,
      statusMessage: '远端拒绝失败，草稿已保留。',
    );
  }

  @override
  Future<AiArtifact?> generateTrainingPrescriptionV2(
    TrainingPrescriptionV2Request request, {
    FeatureOperation? sourceOperation,
  }) {
    generationCalls += 1;
    return generationResults.removeAt(0).future;
  }

  @override
  Future<AiArtifact?> decide({
    required AiArtifact artifact,
    required AiArtifactDecision decision,
  }) async =>
      decisionResult;

  @override
  Future<PlanRevisionProposal?> generatePlanRevision(
    PlanRevisionRequest request, {
    FeatureOperation? sourceOperation,
  }) {
    revisionCalls += 1;
    return revisionResults.removeAt(0).future;
  }
}

AiTrainingPrescription _prescription(String digest) => AiTrainingPrescription(
      cycleFocus: 'base',
      progressionMode: AiProgressionMode.conservative,
      weeklySessions: const <AiSessionBlueprint>[
        AiSessionBlueprint(
          trainingType: TrainingType.strength,
          durationMinutes: 45,
          intensityBand: AiIntensityBand.moderate,
          focusCodes: <String>['full_body_strength'],
        ),
        AiSessionBlueprint(
          trainingType: TrainingType.easyRun,
          durationMinutes: 40,
          intensityBand: AiIntensityBand.easy,
          focusCodes: <String>['aerobic_base'],
        ),
        AiSessionBlueprint(
          trainingType: TrainingType.mobility,
          durationMinutes: 30,
          intensityBand: AiIntensityBand.easy,
          focusCodes: <String>['mobility'],
        ),
      ],
      skill: const AiSkillRef(
        id: 'training-plan-builder',
        version: '1.0.0',
        displayName: '训练计划生成器',
        sourceSha256: _hash,
        runtimeSha256: _hash,
        coverage: 'general_fitness',
        selectionReason: '测试',
      ),
      generationMeta: AiGenerationMeta(
        contractVersion: '1',
        clientContextDigest: digest,
        model: 'test',
        cacheHit: false,
        promptContractVersion: 'training-prescription-v1',
        inputTokens: 1,
        outputTokens: 1,
      ),
      selectionReasonCode: 'generic_periodization_fallback',
    );

AiArtifact _artifact(AiTrainingPrescription prescription) => AiArtifact(
      id: 'artifact-reject-null',
      capability: AiCapability.trainer,
      artifactType: 'training_prescription_v1',
      schemaVersion: 1,
      decision: AiArtifactDecision.pending,
      contextDigest: _hash,
      payload: prescription.toJson(),
      warnings: const <String>[],
      provider: 'test',
      model: 'test',
      generatedAt: DateTime(2026, 9, 4),
    );

AiArtifact _revisionArtifact(AiTrainingPrescription prescription) => AiArtifact(
      id: 'artifact-revision-reject',
      capability: AiCapability.trainer,
      artifactType: 'plan_revision_v1',
      schemaVersion: 1,
      decision: AiArtifactDecision.pending,
      contextDigest: _hash,
      payload: <String, dynamic>{
        'revised_prescription': prescription.toJson(),
      },
      warnings: const <String>[],
      provider: 'test',
      model: 'test',
      generatedAt: DateTime(2026, 9, 4),
    );

class _RejectFlushStorage extends InMemoryLocalStorageService {
  _RejectFlushStorage({this.failRestore = false});

  final bool failRestore;
  var _draftRemoved = false;
  var _draftRestoring = false;

  @override
  void remove(String key) {
    if (key == GeneratedTrainingPlanRepository.draftStorageKey) {
      _draftRemoved = true;
    }
    super.remove(key);
  }

  @override
  void saveJson(String key, Map<String, dynamic> value) {
    if (key == GeneratedTrainingPlanRepository.draftStorageKey &&
        _draftRemoved) {
      _draftRestoring = true;
    }
    super.saveJson(key, value);
  }

  @override
  Future<void> flush() async {
    if (_draftRemoved && !_draftRestoring) {
      throw StateError('测试草稿删除落盘失败');
    }
    if (_draftRestoring && failRestore) {
      throw StateError('测试草稿恢复落盘失败');
    }
  }
}

const String _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
