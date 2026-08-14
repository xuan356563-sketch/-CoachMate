import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/repositories/generated_training_plan_repository.dart';
import 'package:trainflow_ai/data/models/ai_training_prescription.dart';
import 'package:trainflow_ai/data/models/generated_training_plan.dart';
import 'package:trainflow_ai/data/models/plan_generation_preferences.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('生成的四周计划可完整保存并从本地恢复', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final plan = FourWeekPlanGenerator()
        .generate(
          profile: InMemoryUserProfileRepository.defaultProfile,
          startsOn: DateTime(2026, 7, 13),
        )
        .plan;
    final GeneratedTrainingPlanRepository repository =
        GeneratedTrainingPlanRepository(storage);

    repository.savePlan(plan);
    final restored = GeneratedTrainingPlanRepository(storage).getPlan();

    expect(restored?.id, plan.id);
    expect(restored?.workoutDays, hasLength(16));
    expect(restored?.workoutDays.last.weekIndex, 4);
    expect(
      storage.readJson(
          GeneratedTrainingPlanRepository.storageKey)?['schemaVersion'],
      1,
    );
  });

  test('生成计划键被纳入 SharedPreferences Web 回退白名单', () {
    expect(
      SharedPreferencesLocalStorageService.allowedKeys,
      contains(GeneratedTrainingPlanRepository.storageKey),
    );
    expect(
      SharedPreferencesLocalStorageService.allowedKeys,
      contains(GeneratedTrainingPlanRepository.draftStorageKey),
    );
    expect(
      SharedPreferencesLocalStorageService.allowedKeys,
      contains(GeneratedTrainingPlanRepository.versionsStorageKey),
    );
  });

  test('待确认草稿不替换 legacy 计划，激活时迁移并可回退', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final GeneratedTrainingPlanRepository repository =
        GeneratedTrainingPlanRepository(storage);
    final legacy = FourWeekPlanGenerator()
        .generate(
          profile: InMemoryUserProfileRepository.defaultProfile,
          startsOn: DateTime(2026, 7, 13),
        )
        .plan;
    repository.savePlan(legacy);
    final PlanGenerationDraft draft = _draft('artifact-1');

    repository.saveDraft(draft);
    expect(repository.getPlan()?.id, legacy.id);
    expect(repository.getDraft()?.artifactId, 'artifact-1');

    final GeneratedPlanVersion activated = repository.activateDraft(
      draft,
      activatedAt: DateTime(2026, 7, 14),
    );
    expect(repository.getPlan()?.id, draft.plan.id);
    expect(repository.getHistory().activeVersionId, activated.id);
    expect(activated.compilerVersion, 'skill-compiler-v2');
    expect(repository.getHistory().versions, hasLength(2));
    expect(repository.getHistory().versions.first.source,
        GeneratedPlanSource.legacy);
    expect(repository.getDraft(), isNull);

    final Map<String, dynamic> immutableSnapshot = activated.toJson();
    final GeneratedPlanVersion retried = repository.activateDraft(
      draft,
      activatedAt: DateTime(2026, 8, 1),
    );
    expect(retried.toJson(), immutableSnapshot);
    expect(repository.getHistory().versions, hasLength(2));

    final GeneratedPlanVersion legacyVersion =
        repository.getHistory().versions.first;
    expect(
      repository
          .activateVersion(
            legacyVersion.id,
            activatedAt: DateTime(2026, 7, 15),
          )
          ?.id,
      legacyVersion.id,
    );
    expect(repository.getPlan()?.id, legacy.id);
  });

  test('版本历史最多保留最近 5 个计划', () {
    final GeneratedTrainingPlanRepository repository =
        GeneratedTrainingPlanRepository(InMemoryLocalStorageService());
    for (int index = 0; index < 7; index += 1) {
      repository.activateDraft(
        _draft('artifact-$index'),
        activatedAt: DateTime(2026, 7, 14 + index),
      );
    }

    expect(repository.getHistory().versions, hasLength(5));
    expect(repository.getHistory().activeVersion?.artifactId, 'artifact-6');
  });
}

PlanGenerationDraft _draft(String artifactId) {
  const String hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final AiTrainingPrescription prescription = AiTrainingPrescription(
    cycleFocus: 'base',
    progressionMode: AiProgressionMode.conservative,
    weeklySessions: const <AiSessionBlueprint>[
      AiSessionBlueprint(
        trainingType: TrainingType.easyRun,
        durationMinutes: 40,
        intensityBand: AiIntensityBand.easy,
        focusCodes: <String>['aerobic_base'],
      ),
    ],
    skill: const AiSkillRef(
      id: 'training-plan-builder',
      version: '1.0.0',
      displayName: '训练计划生成器',
      sourceSha256: hash,
      runtimeSha256: hash,
      coverage: 'general_fitness',
      selectionReason: '通用规则',
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
  final plan = FourWeekPlanGenerator()
      .generate(
        profile: InMemoryUserProfileRepository.defaultProfile.copyWith(
          weeklyTrainingDays: 1,
          trainingExperienceLevel: TrainingExperienceLevel.intermediate,
        ),
        startsOn: DateTime(2026, 7, 13),
        preferences: PlanGenerationPreferences.fromPrescription(
          prescription: prescription,
          generationId: artifactId,
        ),
      )
      .plan;
  return PlanGenerationDraft(
    id: 'draft-$artifactId',
    artifactId: artifactId,
    plan: plan,
    weekPhases: const <String>['baseline', 'build', 'specific', 'deload'],
    prescription: prescription,
    createdAt: DateTime(2026, 7, 13),
    baseVersionId: null,
    contextDigest: hash,
    localContextFingerprint: hash,
    auditSummary: const PlanAuditSummary(
      passCount: 10,
      warningCount: 0,
      failCount: 0,
      blockingReasons: <String>[],
    ),
  );
}
