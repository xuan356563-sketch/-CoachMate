import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trainflow_ai/data/models/ai_artifact.dart';
import 'package:trainflow_ai/data/models/ai_training_prescription.dart';
import 'package:trainflow_ai/data/models/pre_exercise_clearance.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/features/ai_center/application/ai_artifact_controller.dart';
import 'package:trainflow_ai/features/auth/data/authenticated_api_client.dart';
import 'package:trainflow_ai/features/auth/data/session_token_store.dart';
import 'package:trainflow_ai/features/training_plan/application/four_week_plan_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/pre_exercise_clearance_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/training_plan_generation_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/plan_context_digest_service.dart';

class _TokenStore implements SessionTokenStore {
  @override
  String? accessToken = 'token';

  @override
  Future<void> clear() async => accessToken = null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> updateAccessToken(String accessToken) async {
    this.accessToken = accessToken;
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
  }
}

class _DelayedClearanceController extends PreExerciseClearanceController {
  _DelayedClearanceController(this.ready);

  final Future<PreExerciseClearanceState> ready;

  @override
  Future<PreExerciseClearanceState> build() => ready;
}

class _RemoteAcceptedController extends AiArtifactController {
  _RemoteAcceptedController(this.artifact);

  final AiArtifact artifact;
  bool syncCalled = false;

  @override
  AiArtifactState build() => AiArtifactState(
        artifacts: <AiArtifact>[artifact],
        isSyncing: false,
        isGenerating: false,
        activeCapability: null,
        healthDataProcessingConsented: false,
        statusMessage: '等待同步',
      );

  @override
  Future<void> sync() async {
    syncCalled = true;
  }
}

void main() {
  test('启动先同步远端 accepted，并等待异步筛查加载后重建可激活草稿', () async {
    final DateTime now = DateTime(2026, 7, 17, 8);
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
      weeklyTrainingDays: 4,
      dailyAvailableMinutes: 60,
      mainSports: const <MainSport>[MainSport.generalFitness],
    );
    PersistedUserProfileRepository(storage).saveProfile(profile);
    final context = buildTrainingPrescriptionRequestContext(
      profile: profile,
      race: null,
      now: now,
    )!;
    final String digest = const PlanContextDigestService()
        .buildRequestContextDigest(context.toJson());
    final AiTrainingPrescription prescription = _prescription(digest);
    final AiArtifact accepted = _artifact(prescription);
    final Completer<PreExerciseClearanceState> clearance =
        Completer<PreExerciseClearanceState>();
    final MockClient client = MockClient((http.Request request) async {
      if (request.url.path == '/v1/ai/training-prescriptions/capabilities') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'enabled': true,
            'contract_version': 1,
            'skills': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'training-plan-builder',
                'version': '1.0.0',
                'display_name': '训练计划生成器',
                'sports': <String>['general_fitness', 'hyrox'],
                'source_sha256': _hashA,
                'runtime_sha256': _hashA,
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      throw StateError('测试收到未预期请求：${request.url.path}');
    });
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        httpClientProvider.overrideWithValue(client),
        sessionTokenStoreProvider.overrideWithValue(_TokenStore()),
        aiArtifactControllerProvider.overrideWith(
          () => _RemoteAcceptedController(accepted),
        ),
        fourWeekPlanNowProvider.overrideWithValue(now),
        preExerciseClearanceRealtimeClockProvider.overrideWithValue(() => now),
        preExerciseClearanceControllerProvider.overrideWith(
          () => _DelayedClearanceController(clearance.future),
        ),
      ],
    );
    addTearDown(container.dispose);

    bool settled = false;
    final Future<TrainingPlanGenerationUiState> generation = container
        .read(trainingPlanGenerationControllerProvider.future)
      ..then((_) => settled = true);
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);

    clearance.complete(
      PreExerciseClearanceState(
        clearance: PreExerciseClearance.recorded(
          status: PreExerciseClearanceStatus.selfCleared,
          currentInjuryOrRestriction: false,
          completedAt: now,
        ),
        isSaving: false,
        statusMessage: '测试筛查有效',
      ),
    );
    final TrainingPlanGenerationUiState recovered = await generation;

    expect(
      (container.read(aiArtifactControllerProvider.notifier)
              as _RemoteAcceptedController)
          .syncCalled,
      isTrue,
    );
    expect(recovered.artifact?.id, accepted.id);
    expect(recovered.confirmedButNotActivated, isTrue);
    expect(container.read(fourWeekPlanControllerProvider).draft?.artifactId,
        accepted.id);
    expect(container.read(fourWeekPlanControllerProvider).canActivateDraft,
        isTrue);
  });
}

AiTrainingPrescription _prescription(String digest) => AiTrainingPrescription(
      cycleFocus: 'base',
      progressionMode: AiProgressionMode.conservative,
      weeklySessions: const <AiSessionBlueprint>[
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
      skill: const AiSkillRef(
        id: 'training-plan-builder',
        version: '1.0.0',
        displayName: '训练计划生成器',
        sourceSha256: _hashA,
        runtimeSha256: _hashA,
        coverage: 'general_fitness',
        selectionReason: '通用周期化规则',
      ),
      generationMeta: AiGenerationMeta(
        contractVersion: '1',
        clientContextDigest: digest,
        model: 'deepseek-chat',
        cacheHit: false,
        promptContractVersion: 'training-prescription-v1',
      ),
      selectionReasonCode: 'generic_periodization_fallback',
    );

AiArtifact _artifact(AiTrainingPrescription prescription) => AiArtifact(
      id: 'accepted-remote',
      capability: AiCapability.trainer,
      artifactType: 'training_prescription_v1',
      schemaVersion: 1,
      decision: AiArtifactDecision.accepted,
      contextDigest: _hashB,
      payload: prescription.toJson(),
      warnings: const <String>[],
      provider: 'deepseek',
      model: 'deepseek-chat',
      generatedAt: DateTime(2026, 7, 17),
    );

const String _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
