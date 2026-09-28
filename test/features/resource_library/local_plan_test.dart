import 'package:flutter/foundation.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';
import 'package:trainflow_ai/features/reminders/application/reminder_settings_controller.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/pre_exercise_clearance.dart';
import 'package:trainflow_ai/data/models/generated_training_plan.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/repositories/generated_training_plan_repository.dart';
import 'package:trainflow_ai/data/seed/seed_training_plans.dart';
import 'package:trainflow_ai/features/resource_library/resource_catalog.dart';
import 'package:trainflow_ai/features/resource_library/resource_plan_preview.dart';
import 'package:trainflow_ai/features/resource_library/local_plan_service.dart';
import 'package:trainflow_ai/features/resource_library/local_plan_controller.dart';
import 'package:trainflow_ai/features/resource_library/local_plan_draft.dart';
import 'package:trainflow_ai/features/training_plan/application/four_week_plan_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/pre_exercise_clearance_controller.dart';
import 'package:trainflow_ai/features/first_run_onboarding/application/membership_controller.dart';
import 'package:trainflow_ai/features/first_run_onboarding/domain/first_run_models.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/sports/sport_capability_directory.dart';
import 'assessment_test.dart' show FailStorage;

final now = DateTime(2026, 9, 12, 12);
UserProfile profile(MainSport sport) =>
    InMemoryUserProfileRepository.defaultProfile.copyWith(
        mainSports: [sport],
        injuryHistory: [],
        dailyAvailableMinutes: 60,
        weeklyTrainingDays: 3,
        trainingExperienceLevel: TrainingExperienceLevel.intermediate);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('旧计划和损坏资源来源仍可读取，本地版本不绕过筛查', () {
    final old = GeneratedPlanVersion(id: 'local-test', plan: seedTrainingPlans.first, weekPhases: const [], source: GeneratedPlanSource.localRules,
      createdAt: now, activatedAt: now, inputDigest: '', artifactId: null, skillRef: null, compilerVersion: 'resource-local-v1',
      auditSummary: const PlanAuditSummary(passCount: 1, warningCount: 0, failCount: 0, blockingReasons: []));
    final damaged = {...old.toJson(), 'resourceRef': {'id': 1}};
    final restored = GeneratedPlanVersion.fromJson(damaged);
    expect(restored.plan.toJson(), old.plan.toJson());
    expect(restored.resourceRef, isNull);
    expect(restored.requiresClearance, isTrue);
  });
  test('四项运动及主次组合、器械条件保持原处方，仅新增已批准动作关联和第四周时长差异', () {
    final sports = SportCapabilityDirectory.builtIn();
    for (final resource
        in ResourceCatalog().list().whereType<TrainingPlanResource>()) {
      for (final equipment in EquipmentAccessType.values) {
        final p = profile(resource.sport)
            .copyWith(equipmentAccessType: equipment, mainSports: [
          resource.sport,
          resource.sport == MainSport.strength
              ? MainSport.marathon
              : MainSport.strength
        ]);
        final draft = LocalPlanService().create(
            id: 'test',
            now: now,
            profile: p,
            resource: resource,
            sports: sports,
            baseVersionId: null,
            preview: ResourcePlanPreview(),
            decorate: (r) => r);
        final old = FourWeekPlanGenerator(sportDirectory: sports)
            .generate(profile: p, startsOn: LocalPlanService.monday(now));
        final withoutBindings = draft.plan.copyWith(workoutDays: [
          for (var i = 0; i < draft.plan.workoutDays.length; i++)
            draft.plan.workoutDays[i].copyWith(
              workoutExercises: old.plan.workoutDays[i].workoutExercises,
              estimatedMinutes: draft.plan.workoutDays[i].weekIndex == 4
                  ? old.plan.workoutDays[i].estimatedMinutes : null),
        ]);
        expect(withoutBindings.toJson(), old.plan.toJson());
        expect(
            LocalPlanDraft.fromJson(draft.toJson()).toJson(), draft.toJson());
      }
    }
  });
  test('本地草稿不改变计划和云端草稿，确认后持久化真实本地来源', () async {
    final f = await LocalFixture.create();
    addTearDown(f.close);
    f.repo.savePlan(seedTrainingPlans.first);
    final before = f.repo.getPlan()!.toJson();
    f.storage.saveJson(
        GeneratedTrainingPlanRepository.draftStorageKey, {'sentinel': '云端草稿'});
    await f.controller.createLocalDraft('plan.strength.baseline');
    final draft = f.draft!;
    expect(f.repo.getPlan()!.toJson(), before);
    expect(draft.auditSummary.blockingReasons, isEmpty);
    await f.controller.activateLocalDraft(draft.id);
    final active = f.repo.getHistory().activeVersion!;
    expect(active.source, GeneratedPlanSource.localRules);
    expect(active.resourceRef, draft.resourceRef);
    expect(active.artifactId, isNull);
    expect(active.skillRef, isNull);
    expect(active.prescription, isNull);
    expect(active.requiresClearance, isTrue);
    expect(f.storage.readJson(GeneratedTrainingPlanRepository.draftStorageKey),
        {'sentinel': '云端草稿'});
    final restored = GeneratedTrainingPlanRepository(f.storage).getHistory();
    expect(restored.activeVersion!.resourceRef, draft.resourceRef);
    expect(f.repo.getPlan()!.toJson(), draft.plan.toJson());
  });
  test('替换草稿需确认，主运动不符不改档案', () async {
    final f = await LocalFixture.create();
    addTearDown(f.close);
    await expectLater(f.controller.createLocalDraft('plan.marathon.baseline'),
        throwsStateError);
    expect(f.draft, isNull);
    await f.controller.createLocalDraft('plan.strength.baseline');
    final first = f.draft!;
    await expectLater(f.controller.createLocalDraft('plan.strength.baseline'),
        throwsStateError);
    expect(f.draft!.id, first.id);
    await f.controller
        .createLocalDraft('plan.strength.baseline', replaceDraftId: first.id);
    expect(f.draft!.id, isNot(first.id));
  });
  test('档案和资源内容变化使草稿失效，不覆盖有效计划', () async {
    final f = await LocalFixture.create();
    addTearDown(f.close);
    await f.controller.createLocalDraft('plan.strength.baseline');
    final draft = f.draft!;
    PersistedUserProfileRepository(f.storage).saveProfile(
        profile(MainSport.strength).copyWith(dailyAvailableMinutes: 45));
    await expectLater(
        f.controller.activateLocalDraft(draft.id), throwsStateError);
    expect(f.repo.getHistory().activeVersion, isNull);
  });
  test('激活写入失败保持原有效版本，重试不重复添加版本', () async {
    final storage = FailStorage();
    final f = await LocalFixture.create(storage: storage);
    addTearDown(f.close);
    f.repo.savePlan(seedTrainingPlans.first);
    final before = f.repo.getPlan()!.toJson();
    await f.controller.createLocalDraft('plan.strength.baseline');
    final draft = f.draft!;
    storage.fail = true;
    await expectLater(
        f.controller.activateLocalDraft(draft.id), throwsStateError);
    expect(f.repo.getHistory().activeVersion, isNull);
    expect(f.repo.getPlan()!.toJson(), before);
    expect(f.draft!.id, draft.id);
    await f.controller.activateLocalDraft(draft.id);
    final count = f.repo.getHistory().versions.length;
    await expectLater(
        f.controller.activateLocalDraft(draft.id), throwsStateError);
    expect(f.repo.getHistory().versions, hasLength(count));
  });
  test('训练中、会员不足及筛查失效阻断，恢复后可重试', () async {
    final f = await LocalFixture.create();
    addTearDown(f.close);
    final unlock =
        f.runtime.registerDisableLock('feature.training_plan', () => '训练尚未结束');
    await expectLater(f.controller.createLocalDraft('plan.strength.baseline'),
        throwsStateError);
    unlock();
    await f.controller.createLocalDraft('plan.strength.baseline');
    final draft = f.draft!;
    (f.container.read(preExerciseClearanceControllerProvider.notifier)
            as TestClearance)
        .expire();
    await expectLater(
        f.controller.activateLocalDraft(draft.id), throwsStateError);
    expect(f.repo.getHistory().activeVersion, isNull);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final gated = await LocalFixture.create(gated: true);
    addTearDown(gated.close);
    await expectLater(
        gated.controller.createLocalDraft('plan.strength.baseline'),
        throwsStateError);
    expect(gated.draft, isNull);
  });
  test('等待筛查期间停用或账号切换，迟到结果不得写入新域', () async {
    final pending = Completer<PreExerciseClearanceState>();
    final f = await LocalFixture.create(pending: pending);
    addTearDown(f.close);
    final future = f.controller.createLocalDraft('plan.strength.baseline');
    await Future<void>.delayed(Duration.zero);
    await f.runtime.changeAccountScope(replaceScope: () async {
      f.storage.clearBusinessData();
      await f.storage.flush();
    });
    pending.complete(TestClearance.ready());
    await expectLater(future, throwsStateError);
    expect(f.draft, isNull);
    expect(f.repo.getHistory().activeVersion, isNull);
  });
  test('停用后阻止激活，重新启用保留草稿供重试', () async {
    final f = await LocalFixture.create();
    addTearDown(f.close);
    await f.controller.createLocalDraft('plan.strength.baseline');
    final draft = f.draft!;
    await f.runtime.disable('feature.resource_library');
    await expectLater(
        f.controller.activateLocalDraft(draft.id), throwsStateError);
    await f.runtime.enable('feature.resource_library');
    await f.controller.activateLocalDraft(draft.id);
    expect(f.repo.getHistory().activeVersion, isNotNull);
  });
}

class TestClearance extends PreExerciseClearanceController {
  TestClearance([this.pending]);
  final Completer<PreExerciseClearanceState>? pending;
  static PreExerciseClearanceState ready() => PreExerciseClearanceState(
      clearance: PreExerciseClearance.recorded(
          status: PreExerciseClearanceStatus.selfCleared,
          currentInjuryOrRestriction: false,
          completedAt: now),
      isSaving: false,
      statusMessage: '合成有效筛查');
  @override
  Future<PreExerciseClearanceState> build() async =>
      pending == null ? ready() : await pending!.future;
  void expire() => state = const AsyncData(PreExerciseClearanceState(
      clearance: PreExerciseClearance.notCompleted(),
      isSaving: false,
      statusMessage: '合成失效'));
}

class NoMembership extends MembershipController {
  @override
  Future<MembershipUiState> build() async => const MembershipUiState(
      entitlement: MembershipEntitlement(
          status: MembershipEntitlementStatus.none, canGeneratePlan: false));
}

class LocalFixture {
  LocalFixture(this.storage, this.runtime, this.container);
  final InMemoryLocalStorageService storage;
  final PluginRuntime runtime;
  final ProviderContainer container;
  LocalPlanController get controller =>
      container.read(localPlanControllerProvider.notifier);
  LocalPlanDraft? get draft => LocalPlanDraftRepository(storage).read();
  GeneratedTrainingPlanRepository get repo =>
      GeneratedTrainingPlanRepository(storage);
  static Future<LocalFixture> create(
      {InMemoryLocalStorageService? storage,
      TrainingNotificationScheduler? notificationScheduler,
      bool gated = false,
      Completer<PreExerciseClearanceState>? pending}) async {
    final local = storage ?? InMemoryLocalStorageService();
    PersistedUserProfileRepository(local)
        .saveProfile(profile(MainSport.strength));
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    final container = ProviderContainer(overrides: [
      if (notificationScheduler != null)
        trainingNotificationSchedulerProvider.overrideWithValue(notificationScheduler),
      localStorageServiceProvider.overrideWithValue(local),
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      fourWeekPlanNowProvider.overrideWithValue(now),
      preExerciseClearanceRealtimeClockProvider.overrideWithValue(() => now),
      preExerciseClearanceControllerProvider
          .overrideWith(() => TestClearance(pending)),
      localPlanMembershipGateProvider.overrideWithValue(gated),
      membershipControllerProvider.overrideWith(NoMembership.new)
    ]);
    return LocalFixture(local, runtime, container);
  }

  void close() => container.dispose();
}
