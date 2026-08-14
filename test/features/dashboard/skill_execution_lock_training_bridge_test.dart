import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/ai_artifact.dart';
import 'package:trainflow_ai/data/models/ai_training_prescription.dart';
import 'package:trainflow_ai/data/models/pre_exercise_clearance.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/profile/application/user_profile_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/four_week_plan_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/pre_exercise_clearance_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

class _ClearanceController extends PreExerciseClearanceController {
  @override
  Future<PreExerciseClearanceState> build() async => PreExerciseClearanceState(
        clearance: PreExerciseClearance.recorded(
          status: PreExerciseClearanceStatus.selfCleared,
          currentInjuryOrRestriction: false,
          completedAt: DateTime(2025, 7, 15, 8),
        ),
        isSaving: false,
        statusMessage: '测试筛查有效',
      );
}

void main() {
  test('长期前台跨过筛查有效期后停止旧 Skill 计时并切换本地计划', () async {
    DateTime liveNow = DateTime(2026, 7, 14, 8);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
        fourWeekPlanNowProvider.overrideWithValue(DateTime(2026, 7, 14, 8)),
        preExerciseClearanceRealtimeClockProvider.overrideWithValue(
          () => liveNow,
        ),
        trainingExecutionClockProvider.overrideWithValue(() => liveNow),
        preExerciseClearanceControllerProvider.overrideWith(
          _ClearanceController.new,
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
    container.read(trainingMvpProvider);

    final AiTrainingPrescription prescription = _prescription();
    final AiArtifact artifact = _artifact(prescription);
    final FourWeekPlanController plans =
        container.read(fourWeekPlanControllerProvider.notifier);
    plans.createDraft(prescription: prescription, artifact: artifact);
    expect(await plans.activateDraft(artifactId: artifact.id), isTrue);
    await Future<void>.delayed(Duration.zero);
    final String skillPlanId =
        container.read(fourWeekPlanControllerProvider).history.last.plan.id;
    expect(container.read(trainingMvpProvider).activePlan.id, skillPlanId);

    final TrainingMvpController training =
        container.read(trainingMvpProvider.notifier);
    expect(training.startWorkoutPlayer(), isTrue);
    training.startWorkoutPlayerCountdown();
    expect(
        container.read(trainingMvpProvider).workoutPlayerTimerRunning, isTrue);

    liveNow = DateTime(2026, 7, 16, 8);
    training.startWorkoutPlayerCountdown();

    final TrainingMvpState locked = container.read(trainingMvpProvider);
    final String fallbackPlanId = container
        .read(fourWeekPlanControllerProvider)
        .fallbackGeneration
        .plan
        .id;
    expect(locked.activePlan.id, fallbackPlanId);
    expect(locked.activePlan.id, isNot(skillPlanId));
    expect(locked.workoutPlayerTimerRunning, isFalse);
    expect(locked.activeWorkoutPlayerDayId, isNull);
    expect(locked.workoutPlayerStatusMessage, contains('旧 Skill 跟练已停止'));
  });
}

AiTrainingPrescription _prescription() {
  const String hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  return const AiTrainingPrescription(
    cycleFocus: 'base',
    progressionMode: AiProgressionMode.conservative,
    weeklySessions: <AiSessionBlueprint>[
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
    ],
    skill: AiSkillRef(
      id: 'training-plan-builder',
      version: '1.0.0',
      displayName: '训练计划生成器',
      sourceSha256: hash,
      runtimeSha256: hash,
      coverage: 'general_fitness',
      selectionReason: '通用周期化规则',
    ),
    generationMeta: AiGenerationMeta(
      contractVersion: '1',
      clientContextDigest: hash,
      model: 'deepseek-chat',
      cacheHit: false,
      promptContractVersion: 'training-prescription-v1',
    ),
    selectionReasonCode: 'generic_periodization_fallback',
  );
}

AiArtifact _artifact(AiTrainingPrescription prescription) => AiArtifact(
      id: 'artifact-execution-lock',
      capability: AiCapability.trainer,
      artifactType: 'training_prescription_v1',
      schemaVersion: 1,
      decision: AiArtifactDecision.accepted,
      contextDigest:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      payload: prescription.toJson(),
      warnings: const <String>[],
      provider: 'deepseek',
      model: 'deepseek-chat',
      generatedAt: DateTime(2026, 7, 14),
    );
