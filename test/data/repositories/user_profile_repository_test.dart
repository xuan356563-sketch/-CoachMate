import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/seed/seed_training_plans.dart';
import 'package:trainflow_ai/services/ai_training_service.dart';

import '../../support/test_harness.dart';

void main() {
  test('生日按本地日期持久化且旧资料缺失生日时保持兼容', () {
    final DateTime birthday = DateTime(1994, 11, 11);
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      birthDate: birthday,
    );

    final UserProfile restored = UserProfile.fromJson(profile.toJson());
    final UserProfile legacy = UserProfile.fromJson(
      <String, dynamic>{...profile.toJson()}..remove('birthDate'),
    );

    expect(restored.birthDate, birthday);
    expect(legacy.birthDate, isNull);
    expect(legacy.age, profile.age);
  });

  test('打工人分型可向后兼容并进入 AI 决策建议', () {
    final Map<String, dynamic> legacyJson = Map<String, dynamic>.from(
        InMemoryUserProfileRepository.defaultProfile.toJson())
      ..remove('workerProfileType')
      ..remove('equipmentAccessType')
      ..remove('maxHeartRate');
    final UserProfile legacyProfile = UserProfile.fromJson(legacyJson);
    expect(legacyProfile.workerProfileType, WorkerProfileType.general);
    expect(legacyProfile.equipmentAccessType, EquipmentAccessType.gym);
    expect(legacyProfile.maxHeartRate, isNull);
    expect(
      legacyProfile.trainingExperienceLevel,
      TrainingExperienceLevel.unknown,
    );

    final UserProfile standingProfile = legacyProfile.copyWith(
      workerProfileType: WorkerProfileType.standingJob,
      equipmentAccessType: EquipmentAccessType.none,
      maxHeartRate: 188,
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
    );
    final UserProfile restoredProfile =
        UserProfile.fromJson(standingProfile.toJson());
    expect(restoredProfile.workerProfileType, WorkerProfileType.standingJob);
    expect(restoredProfile.equipmentAccessType, EquipmentAccessType.none);
    expect(restoredProfile.maxHeartRate, 188);
    expect(
      restoredProfile.trainingExperienceLevel,
      TrainingExperienceLevel.intermediate,
    );
    expect(restoredProfile.workerProfileType.strategy, contains('足底'));

    final List<String> advice = AiTrainingService().buildMockCoachAdvice(
      profile: restoredProfile,
      todayWorkout: seedTrainingPlans.first.workoutDays.first,
    );
    expect(advice, contains(contains('久站工作')));
    expect(advice, contains(contains('足底')));
    expect(advice, contains(contains('竞技型决策口径')));
  });

  test('用户资料仓库会持久化已确认资料状态', () {
    final TestHarness harness = TestHarness();
    final PersistedUserProfileRepository repository =
        PersistedUserProfileRepository(harness.storageService);
    final UserProfile profile = repository.getProfile().copyWith(
          name: '测试训练者',
          age: 36,
          trainingGoal: '验证本地资料恢复',
          mainSports: const [MainSport.strength, MainSport.rehab],
          dailyAvailableMinutes: 35,
          maxHeartRate: 191,
          injuryHistory: const ['测试旧伤'],
        );

    expect(repository.isProfileCompleted(), isFalse);

    repository.saveProfile(profile);

    final PersistedUserProfileRepository restoredRepository =
        PersistedUserProfileRepository(harness.storageService);

    expect(restoredRepository.isProfileCompleted(), isTrue);
    expect(restoredRepository.getProfile().name, '测试训练者');
    expect(restoredRepository.getProfile().trainingGoal, '验证本地资料恢复');
    expect(restoredRepository.getProfile().mainSports,
        const [MainSport.strength, MainSport.rehab]);
    expect(restoredRepository.getProfile().injuryHistory, const ['测试旧伤']);
    expect(restoredRepository.getProfile().maxHeartRate, 191);

    restoredRepository.clearProfile();

    final PersistedUserProfileRepository clearedRepository =
        PersistedUserProfileRepository(harness.storageService);

    expect(clearedRepository.isProfileCompleted(), isFalse);
    expect(clearedRepository.getProfile().name, '训练者');
  });
}
