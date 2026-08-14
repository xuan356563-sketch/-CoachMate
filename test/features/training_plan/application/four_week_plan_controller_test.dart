import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/ai_artifact.dart';
import 'package:trainflow_ai/data/models/ai_training_prescription.dart';
import 'package:trainflow_ai/data/models/generated_training_plan.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/models/pre_exercise_clearance.dart';
import 'package:trainflow_ai/data/repositories/generated_training_plan_repository.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/features/profile/application/user_profile_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/four_week_plan_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/pre_exercise_clearance_controller.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('已确认档案会生成并持久化对应主目标的四周计划', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        fourWeekPlanNowProvider.overrideWithValue(DateTime(2026, 7, 14, 8)),
      ],
    );
    addTearDown(container.dispose);
    final profile =
        container.read(userProfileControllerProvider).profile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
      weeklyTrainingDays: 3,
      trainingGoal: '提升全身力量基础',
    );
    container.read(userProfileControllerProvider.notifier).save(profile);

    final FourWeekPlanState state =
        container.read(fourWeekPlanControllerProvider);

    expect(state.generation.plan.title, contains('健身力量'));
    expect(state.generation.plan.workoutDays, hasLength(12));
    expect(state.activeRace, isNull);
    expect(
      GeneratedTrainingPlanRepository(storage).getPlan()?.id,
      state.generation.plan.id,
    );
  });

  test('档案主目标变化后会重建计划并选择最近的匹配赛事', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        fourWeekPlanNowProvider.overrideWithValue(DateTime(2026, 7, 14, 8)),
      ],
    );
    addTearDown(container.dispose);

    final FourWeekPlanState before =
        container.read(fourWeekPlanControllerProvider);
    final UserProfile hyroxProfile =
        container.read(userProfileControllerProvider).profile.copyWith(
      mainSports: const <MainSport>[MainSport.hyrox],
      weeklyTrainingDays: 5,
    );
    container.read(userProfileControllerProvider.notifier).save(hyroxProfile);
    final FourWeekPlanState after =
        container.read(fourWeekPlanControllerProvider);

    expect(after.generation.plan.id, isNot(before.generation.plan.id));
    expect(after.generation.plan.title, contains('HYROX'));
    expect(after.generation.plan.workoutDays, hasLength(20));
    expect(after.activeRace?.id, 'race-hyrox-open-2026');
    expect(after.currentPhase, TrainingCyclePhase.baseline);
  });

  test('草稿未确认不替换当前计划，确认后才激活版本', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = _container(storage);
    addTearDown(container.dispose);
    await container.read(preExerciseClearanceControllerProvider.future);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              trainingExperienceLevel: TrainingExperienceLevel.intermediate,
              weeklyTrainingDays: 4,
              dailyAvailableMinutes: 60,
            );
    container.read(userProfileControllerProvider.notifier).save(profile);
    final String beforeId =
        container.read(fourWeekPlanControllerProvider).activePlan.id;
    final AiTrainingPrescription prescription = _prescription(
      artifactId: 'artifact-1',
      sessionCount: 4,
    );

    final PlanGenerationDraft draft =
        container.read(fourWeekPlanControllerProvider.notifier).createDraft(
              prescription: prescription,
              artifact: _artifact('artifact-1', prescription),
            );

    expect(
        container.read(fourWeekPlanControllerProvider).activePlan.id, beforeId);
    expect(draft.artifactId, 'artifact-1');
    expect(container.read(fourWeekPlanControllerProvider).canActivateDraft,
        isTrue);
    expect(
      await container
          .read(fourWeekPlanControllerProvider.notifier)
          .activateDraft(artifactId: 'artifact-1'),
      isTrue,
    );
    final FourWeekPlanState activated =
        container.read(fourWeekPlanControllerProvider);
    expect(activated.activePlan.id, isNot(beforeId));
    expect(activated.history.last.artifactId, 'artifact-1');
    expect(activated.draft, isNull);
  });

  test('档案变化会阻断陈旧草稿，不会静默替换已激活计划', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = _container(storage);
    addTearDown(container.dispose);
    await container.read(preExerciseClearanceControllerProvider.future);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              trainingExperienceLevel: TrainingExperienceLevel.intermediate,
              weeklyTrainingDays: 4,
              dailyAvailableMinutes: 60,
            );
    container.read(userProfileControllerProvider.notifier).save(profile);
    final AiTrainingPrescription first =
        _prescription(artifactId: 'artifact-1', sessionCount: 4);
    final notifier = container.read(fourWeekPlanControllerProvider.notifier);
    notifier.createDraft(
      prescription: first,
      artifact: _artifact('artifact-1', first),
    );
    expect(await notifier.activateDraft(artifactId: 'artifact-1'), isTrue);
    final String activeId =
        container.read(fourWeekPlanControllerProvider).activePlan.id;

    final AiTrainingPrescription second =
        _prescription(artifactId: 'artifact-2', sessionCount: 4);
    notifier.createDraft(
      prescription: second,
      artifact: _artifact('artifact-2', second),
    );
    container.read(userProfileControllerProvider.notifier).save(
          profile.copyWith(dailyAvailableMinutes: 45),
        );

    final FourWeekPlanState stale =
        container.read(fourWeekPlanControllerProvider);
    expect(stale.staleReason, 'draft_context_changed');
    expect(stale.updateAvailable, isTrue);
    expect(stale.canActivateDraft, isFalse);
    expect(await notifier.activateDraft(artifactId: 'artifact-2'), isFalse);
    expect(
        container.read(fourWeekPlanControllerProvider).activePlan.id, activeId);
  });

  test('长期前台跨过筛查有效期后不得激活新 Skill 版本', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    DateTime liveNow = DateTime(2026, 7, 14, 8);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        fourWeekPlanNowProvider.overrideWithValue(DateTime(2026, 7, 14, 8)),
        preExerciseClearanceRealtimeClockProvider.overrideWithValue(
          () => liveNow,
        ),
        preExerciseClearanceControllerProvider.overrideWith(
          _TestClearanceController.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(preExerciseClearanceControllerProvider.future);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              trainingExperienceLevel: TrainingExperienceLevel.intermediate,
              weeklyTrainingDays: 4,
              dailyAvailableMinutes: 60,
            );
    container.read(userProfileControllerProvider.notifier).save(profile);
    final AiTrainingPrescription prescription =
        _prescription(artifactId: 'artifact-expired', sessionCount: 4);
    final FourWeekPlanController notifier =
        container.read(fourWeekPlanControllerProvider.notifier);
    notifier.createDraft(
      prescription: prescription,
      artifact: _artifact('artifact-expired', prescription),
    );

    liveNow = DateTime(2027, 7, 2, 8);

    expect(
      await notifier.activateDraft(artifactId: 'artifact-expired'),
      isFalse,
    );
    expect(container.read(fourWeekPlanControllerProvider).history, isEmpty);
    expect(
      container.read(fourWeekPlanControllerProvider).statusMessage,
      contains('有效期'),
    );
  });

  test('已激活的 Skill 版本可通过指针回退且不复制计划', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = _container(storage);
    addTearDown(container.dispose);
    await container.read(preExerciseClearanceControllerProvider.future);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              trainingExperienceLevel: TrainingExperienceLevel.intermediate,
              weeklyTrainingDays: 4,
              dailyAvailableMinutes: 60,
            );
    container.read(userProfileControllerProvider.notifier).save(profile);
    final notifier = container.read(fourWeekPlanControllerProvider.notifier);
    for (final String id in <String>['artifact-1', 'artifact-2']) {
      final AiTrainingPrescription prescription =
          _prescription(artifactId: id, sessionCount: 4);
      notifier.createDraft(
        prescription: prescription,
        artifact: _artifact(id, prescription),
      );
      expect(await notifier.activateDraft(artifactId: id), isTrue);
    }
    final List<GeneratedPlanVersion> skillVersions = container
        .read(fourWeekPlanControllerProvider)
        .history
        .where((GeneratedPlanVersion item) => item.isSkillGenerated)
        .toList();

    expect(await notifier.rollbackToVersion(skillVersions.first.id), isTrue);
    expect(
      container.read(fourWeekPlanControllerProvider).activePlan.id,
      skillVersions.first.plan.id,
    );
    expect(
      GeneratedTrainingPlanRepository(storage).getHistory().versions.length,
      container.read(fourWeekPlanControllerProvider).history.length,
    );
  });

  test('本地 flush 失败时不宣称激活并保留可重试草稿', () async {
    final _FailingFlushStorage storage = _FailingFlushStorage();
    final ProviderContainer container = _container(storage);
    addTearDown(container.dispose);
    await container.read(preExerciseClearanceControllerProvider.future);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              trainingExperienceLevel: TrainingExperienceLevel.intermediate,
              weeklyTrainingDays: 4,
              dailyAvailableMinutes: 60,
            );
    container.read(userProfileControllerProvider.notifier).save(profile);
    final String originalPlanId =
        container.read(fourWeekPlanControllerProvider).activePlan.id;
    final AiTrainingPrescription prescription =
        _prescription(artifactId: 'artifact-fail', sessionCount: 4);
    final notifier = container.read(fourWeekPlanControllerProvider.notifier);
    notifier.createDraft(
      prescription: prescription,
      artifact: _artifact('artifact-fail', prescription),
    );
    storage.failFlush = true;

    expect(await notifier.activateDraft(artifactId: 'artifact-fail'), isFalse);
    expect(container.read(fourWeekPlanControllerProvider).activePlan.id,
        originalPlanId);
    expect(
      GeneratedTrainingPlanRepository(storage).getDraft()?.artifactId,
      'artifact-fail',
    );
    expect(
      container.read(fourWeekPlanControllerProvider).statusMessage,
      contains('尚未完成持久化'),
    );
    storage.failFlush = false;
    expect(await notifier.activateDraft(artifactId: 'artifact-fail'), isTrue);
    expect(
      GeneratedTrainingPlanRepository(storage).getHistory().versions.where(
          (GeneratedPlanVersion item) => item.artifactId == 'artifact-fail'),
      hasLength(1),
    );
  });

  test('权威版本成功后镜像 flush 失败仍以已激活恢复', () async {
    final _FailOnSecondFlushStorage storage = _FailOnSecondFlushStorage();
    final ProviderContainer container = _container(storage);
    await container.read(preExerciseClearanceControllerProvider.future);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              trainingExperienceLevel: TrainingExperienceLevel.intermediate,
              weeklyTrainingDays: 4,
              dailyAvailableMinutes: 60,
            );
    container.read(userProfileControllerProvider.notifier).save(profile);
    final AiTrainingPrescription prescription =
        _prescription(artifactId: 'artifact-partial', sessionCount: 4);
    final notifier = container.read(fourWeekPlanControllerProvider.notifier);
    notifier.createDraft(
      prescription: prescription,
      artifact: _artifact('artifact-partial', prescription),
    );

    expect(
      await notifier.activateDraft(artifactId: 'artifact-partial'),
      isTrue,
    );
    final String? activeVersionId =
        GeneratedTrainingPlanRepository(storage).getHistory().activeVersionId;
    container.dispose();

    final ProviderContainer restored = _container(storage);
    addTearDown(restored.dispose);
    await restored.read(preExerciseClearanceControllerProvider.future);
    expect(
      restored.read(fourWeekPlanControllerProvider).activeVersionId,
      activeVersionId,
    );
    expect(
        restored.read(fourWeekPlanControllerProvider).executionLocked, isFalse);
  });

  test('筛查失效后立即锁定 Skill 执行并切回本地计划', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = _container(storage);
    addTearDown(container.dispose);
    await container.read(preExerciseClearanceControllerProvider.future);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              trainingExperienceLevel: TrainingExperienceLevel.intermediate,
              weeklyTrainingDays: 4,
              dailyAvailableMinutes: 60,
            );
    container.read(userProfileControllerProvider.notifier).save(profile);
    final AiTrainingPrescription prescription =
        _prescription(artifactId: 'artifact-clearance', sessionCount: 4);
    final notifier = container.read(fourWeekPlanControllerProvider.notifier);
    notifier.createDraft(
      prescription: prescription,
      artifact: _artifact('artifact-clearance', prescription),
    );
    expect(
      await notifier.activateDraft(artifactId: 'artifact-clearance'),
      isTrue,
    );
    final String? activeVersionId =
        container.read(fourWeekPlanControllerProvider).activeVersionId;

    (container.read(preExerciseClearanceControllerProvider.notifier)
            as _TestClearanceController)
        .setClearance(const PreExerciseClearance.notCompleted());
    final FourWeekPlanState locked =
        container.read(fourWeekPlanControllerProvider);

    expect(locked.executionLocked, isTrue);
    expect(locked.staleReason, 'clearance_invalid');
    expect(locked.activePlan.id, locked.fallbackGeneration.plan.id);
    expect(locked.generation.plan.id, locked.fallbackGeneration.plan.id);
    expect(locked.activeVersionId, activeVersionId);
  });

  test('已激活 Skill 在成年、非康复或经验资格失效时立即锁定', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = _container(storage);
    addTearDown(container.dispose);
    await container.read(preExerciseClearanceControllerProvider.future);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              age: 30,
              mainSports: const <MainSport>[MainSport.strength],
              trainingExperienceLevel: TrainingExperienceLevel.intermediate,
              weeklyTrainingDays: 4,
              dailyAvailableMinutes: 60,
            );
    container.read(userProfileControllerProvider.notifier).save(profile);
    final AiTrainingPrescription prescription =
        _prescription(artifactId: 'artifact-eligibility', sessionCount: 4);
    final notifier = container.read(fourWeekPlanControllerProvider.notifier);
    notifier.createDraft(
      prescription: prescription,
      artifact: _artifact('artifact-eligibility', prescription),
    );
    expect(
      await notifier.activateDraft(artifactId: 'artifact-eligibility'),
      isTrue,
    );
    final String? activeVersionId =
        container.read(fourWeekPlanControllerProvider).activeVersionId;
    final List<UserProfile> ineligibleProfiles = <UserProfile>[
      profile.copyWith(age: 17),
      profile.copyWith(
        mainSports: const <MainSport>[MainSport.strength, MainSport.rehab],
      ),
      profile.copyWith(
        trainingExperienceLevel: TrainingExperienceLevel.unknown,
      ),
    ];

    for (final UserProfile ineligible in ineligibleProfiles) {
      container.read(userProfileControllerProvider.notifier).save(ineligible);
      final FourWeekPlanState locked =
          container.read(fourWeekPlanControllerProvider);
      expect(locked.executionLocked, isTrue);
      expect(locked.staleReason, 'profile_ineligible');
      expect(locked.updateAvailable, isTrue);
      expect(locked.activePlan.id, locked.fallbackGeneration.plan.id);
      expect(locked.activeVersionId, activeVersionId);
      expect(locked.executionLockReason, isNotEmpty);
      expect(
        await notifier.rollbackToVersion(activeVersionId!),
        isFalse,
      );
      container.read(userProfileControllerProvider.notifier).save(profile);
      expect(
        container.read(fourWeekPlanControllerProvider).executionLocked,
        isFalse,
      );
    }
  });

  test('能力发现检测到当前运动专项片段变化时只标记可更新', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = _container(storage);
    addTearDown(container.dispose);
    await container.read(preExerciseClearanceControllerProvider.future);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              trainingExperienceLevel: TrainingExperienceLevel.intermediate,
              weeklyTrainingDays: 4,
              dailyAvailableMinutes: 60,
            );
    container.read(userProfileControllerProvider.notifier).save(profile);
    final AiTrainingPrescription prescription = _prescription(
      artifactId: 'artifact-update',
      sessionCount: 4,
      coverage: 'marathon',
      fragmentSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    final notifier = container.read(fourWeekPlanControllerProvider.notifier);
    notifier.createDraft(
      prescription: prescription,
      artifact: _artifact('artifact-update', prescription),
    );
    expect(await notifier.activateDraft(artifactId: 'artifact-update'), isTrue);
    final String activePlanId =
        container.read(fourWeekPlanControllerProvider).activePlan.id;

    notifier.discoverSkillVersion(
      id: 'training-plan-builder',
      version: '1.0.0',
      runtimeHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sourceHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      fragmentHashes: const <String, String>{
        'marathon':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      },
    );

    expect(
        container.read(fourWeekPlanControllerProvider).updateAvailable, isTrue);
    expect(container.read(fourWeekPlanControllerProvider).activePlan.id,
        activePlanId);
  });

  test('进入下一自然周不会误判已激活计划陈旧', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer first = _container(storage);
    await first.read(preExerciseClearanceControllerProvider.future);
    final UserProfile profile =
        first.read(userProfileControllerProvider).profile.copyWith(
              trainingExperienceLevel: TrainingExperienceLevel.intermediate,
              weeklyTrainingDays: 4,
              dailyAvailableMinutes: 60,
            );
    first.read(userProfileControllerProvider.notifier).save(profile);
    final AiTrainingPrescription prescription =
        _prescription(artifactId: 'artifact-week', sessionCount: 4);
    final notifier = first.read(fourWeekPlanControllerProvider.notifier);
    notifier.createDraft(
      prescription: prescription,
      artifact: _artifact('artifact-week', prescription),
    );
    expect(await notifier.activateDraft(artifactId: 'artifact-week'), isTrue);
    first.dispose();

    final ProviderContainer nextWeek = _container(
      storage,
      now: DateTime(2026, 7, 21, 8),
    );
    addTearDown(nextWeek.dispose);
    await nextWeek.read(preExerciseClearanceControllerProvider.future);
    final FourWeekPlanState restored =
        nextWeek.read(fourWeekPlanControllerProvider);

    expect(restored.staleReason, isNull);
    expect(restored.updateAvailable, isFalse);
  });

  test('旧键中的计划在启动时不被覆盖且首次激活时无损导入', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final GeneratedTrainingPlanRepository repository =
        GeneratedTrainingPlanRepository(storage);
    final legacy = FourWeekPlanGenerator()
        .generate(
          profile: InMemoryUserProfileRepository.defaultProfile.copyWith(
            mainSports: const <MainSport>[MainSport.strength],
          ),
          startsOn: DateTime(2026, 6, 1),
        )
        .plan
        .copyWith(title: '用户原有计划');
    repository.savePlan(legacy);
    final ProviderContainer container = _container(storage);
    addTearDown(container.dispose);
    await container.read(preExerciseClearanceControllerProvider.future);

    expect(container.read(fourWeekPlanControllerProvider).activePlan.toJson(),
        legacy.toJson());
    expect(repository.getPlan()?.toJson(), legacy.toJson());
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
              trainingExperienceLevel: TrainingExperienceLevel.intermediate,
              weeklyTrainingDays: 4,
              dailyAvailableMinutes: 60,
            );
    container.read(userProfileControllerProvider.notifier).save(profile);
    final AiTrainingPrescription prescription =
        _prescription(artifactId: 'artifact-migrate', sessionCount: 4);
    final notifier = container.read(fourWeekPlanControllerProvider.notifier);
    notifier.createDraft(
      prescription: prescription,
      artifact: _artifact('artifact-migrate', prescription),
    );
    expect(
        await notifier.activateDraft(artifactId: 'artifact-migrate'), isTrue);

    final GeneratedPlanVersion migrated = repository
        .getHistory()
        .versions
        .singleWhere((GeneratedPlanVersion item) =>
            item.source == GeneratedPlanSource.legacy);
    expect(migrated.plan.toJson(), legacy.toJson());
  });
}

ProviderContainer _container(
  InMemoryLocalStorageService storage, {
  DateTime? now,
}) {
  return ProviderContainer(
    overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      fourWeekPlanNowProvider.overrideWithValue(
        now ?? DateTime(2026, 7, 14, 8),
      ),
      preExerciseClearanceRealtimeClockProvider.overrideWithValue(
        () => now ?? DateTime(2026, 7, 14, 8),
      ),
      preExerciseClearanceControllerProvider.overrideWith(
        _TestClearanceController.new,
      ),
    ],
  );
}

class _TestClearanceController extends PreExerciseClearanceController {
  @override
  Future<PreExerciseClearanceState> build() async {
    return PreExerciseClearanceState(
      clearance: PreExerciseClearance.recorded(
        status: PreExerciseClearanceStatus.selfCleared,
        currentInjuryOrRestriction: false,
        completedAt: DateTime(2026, 7, 1),
      ),
      isSaving: false,
      statusMessage: '测试筛查有效',
    );
  }

  void setClearance(PreExerciseClearance clearance) {
    state = AsyncData<PreExerciseClearanceState>(
      PreExerciseClearanceState(
        clearance: clearance,
        isSaving: false,
        statusMessage: '测试更新',
      ),
    );
  }
}

class _FailingFlushStorage extends InMemoryLocalStorageService {
  bool failFlush = false;

  @override
  Future<void> flush() async {
    if (failFlush) throw StateError('测试用持久化失败');
  }
}

class _FailOnSecondFlushStorage extends InMemoryLocalStorageService {
  int flushCount = 0;

  @override
  Future<void> flush() async {
    flushCount += 1;
    if (flushCount == 2) throw StateError('测试用镜像写入失败');
  }
}

AiTrainingPrescription _prescription({
  required String artifactId,
  required int sessionCount,
  String coverage = 'general_fitness',
  String? fragmentSha256,
}) {
  const String hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const List<AiSessionBlueprint> catalog = <AiSessionBlueprint>[
    AiSessionBlueprint(
      trainingType: TrainingType.easyRun,
      durationMinutes: 45,
      intensityBand: AiIntensityBand.easy,
      focusCodes: <String>['aerobic_base'],
    ),
    AiSessionBlueprint(
      trainingType: TrainingType.strength,
      durationMinutes: 45,
      intensityBand: AiIntensityBand.moderate,
      focusCodes: <String>['full_body_strength'],
    ),
    AiSessionBlueprint(
      trainingType: TrainingType.tempoRun,
      durationMinutes: 45,
      intensityBand: AiIntensityBand.challenging,
      focusCodes: <String>['threshold'],
    ),
    AiSessionBlueprint(
      trainingType: TrainingType.mobility,
      durationMinutes: 30,
      intensityBand: AiIntensityBand.recovery,
      focusCodes: <String>['recovery'],
    ),
  ];
  return AiTrainingPrescription(
    cycleFocus: 'base',
    progressionMode: AiProgressionMode.conservative,
    weeklySessions: catalog.take(sessionCount).toList(growable: false),
    skill: AiSkillRef(
      id: 'training-plan-builder',
      version: '1.0.0',
      displayName: '训练计划生成器',
      sourceSha256: hash,
      runtimeSha256: hash,
      fragmentSha256: fragmentSha256,
      coverage: coverage,
      selectionReason: '主运动精确匹配',
    ),
    generationMeta: const AiGenerationMeta(
      contractVersion: '1',
      clientContextDigest: hash,
      model: 'deepseek-chat',
      cacheHit: false,
      promptContractVersion: 'training-prescription-v1',
    ),
    selectionReasonCode: 'generic_periodization_fallback',
  );
}

AiArtifact _artifact(String id, AiTrainingPrescription prescription) {
  const String artifactDigest =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  return AiArtifact(
    id: id,
    capability: AiCapability.trainer,
    artifactType: 'training_prescription_v1',
    schemaVersion: 1,
    decision: AiArtifactDecision.pending,
    contextDigest: artifactDigest,
    payload: prescription.toJson(),
    warnings: const <String>[],
    provider: 'deepseek',
    model: 'deepseek-chat',
    generatedAt: DateTime(2026, 7, 14),
  );
}
