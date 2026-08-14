import '../../../data/models/cloud_sync.dart';
import '../../auth/data/authenticated_api_client.dart';
import '../../cloud_sync/data/cloud_sync_api.dart';
import '../domain/first_run_models.dart';

class FirstRunRemoteApi {
  const FirstRunRemoteApi(this._client);

  final AuthenticatedApiClient _client;

  Future<void> saveConfirmedProfile({
    required String userId,
    required FirstRunDraft draft,
    required HealthCloudConsent consent,
  }) async {
    final PersonalProfileDraft personal = draft.personal!;
    final TrainingBaselineDraft training = draft.training!;
    await _client.putJson(
      '/v1/account/consents/health-profile-cloud',
      <String, dynamic>{
        'granted': consent.includesHealth,
        'document_version': consent.documentVersion,
      },
      authenticated: true,
    );
    final Map<String, Object?> payload = <String, Object?>{
      'schema_version': 1,
      'nickname': personal.nickname,
      'gender': personal.gender,
      'declared_age': personal.declaredAge,
      'height_cm': consent.includeHeight ? personal.heightCm : null,
      'weight_kg': consent.includeWeight ? personal.weightKg : null,
      'worker_profile_type': personal.workerProfileType,
      'work_schedule_type': personal.workScheduleType,
      'training_goal': personal.trainingGoal,
      'main_sports': List<String>.of(personal.mainSports),
      'training_experience_level': personal.trainingExperienceLevel,
      'training_environment': training.trainingEnvironment,
      'weekly_training_days': training.weeklyTrainingDays,
      'daily_available_minutes': training.dailyAvailableMinutes,
      'core_self_report': training.coreSelfReport,
      'aerobic_talk_test': training.aerobicTalkTest,
      'cardio_recovery': training.cardioRecovery,
      'injuries': consent.includeInjuries
          ? personal.injuries
              .map((StructuredInjuryProfile value) => value.toJson())
              .toList(growable: false)
          : <Map<String, Object?>>[],
      'health_fields_included': consent.includesHealth,
    };
    await CloudSyncApi(_client).sendMutations(<CloudSyncMutation>[
      CloudSyncMutation.userProfile(
        mutationId: generateCloudSyncMutationId(),
        entityId: stableCloudSyncEntityId('user-profile', userId),
        baseVersion: null,
        confirmedProfile: payload,
      ),
    ]);
  }
}
