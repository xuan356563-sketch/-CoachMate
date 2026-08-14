import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/race.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/seed/seed_races.dart';
import 'package:trainflow_ai/features/training_plan/application/training_plan_generation_controller.dart';
import 'package:trainflow_ai/services/plan_context_digest_service.dart';

void main() {
  test('7 天可用仍只发送 6 练，网络摘要只覆盖白名单 context', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
      weeklyTrainingDays: 7,
      mainSports: const <MainSport>[MainSport.hyrox, MainSport.marathon],
    );
    final context = buildTrainingPrescriptionRequestContext(
      profile: profile,
      race: seedRaces.last,
      now: DateTime(2026, 7, 17),
    );

    expect(context, isNotNull);
    expect(context!.weeklyTrainingDays, 6);
    // 默认档案的性别是 unknown，因此 biological_sex 不出现在键集合里。
    expect(context.toJson().keys, <String>{
      'goal',
      'primary_sport',
      'secondary_sport',
      'experience_level',
      'weekly_training_days',
      'available_minutes',
      'equipment_access',
      'race_type',
      'days_until_race',
    });
    final String digest = const PlanContextDigestService()
        .buildRequestContextDigest(context.toJson());
    expect(digest, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(context.toJson(), isNot(contains('trainingGoal')));
    expect(context.toJson(), isNot(contains('injuryHistory')));
  });

  group('生理性别需要用户授权才会出网', () {
    UserProfile profileWith(Gender gender, {required bool consented}) {
      return InMemoryUserProfileRepository.defaultProfile.copyWith(
        trainingExperienceLevel: TrainingExperienceLevel.intermediate,
        mainSports: const <MainSport>[MainSport.marathon],
        gender: gender,
        allowBiologicalSexInAiPlanning: consented,
      );
    }

    Map<String, dynamic> contextJson(Gender gender, {required bool consented}) {
      final context = buildTrainingPrescriptionRequestContext(
        profile: profileWith(gender, consented: consented),
        race: null,
        now: DateTime(2026, 7, 17),
      );
      expect(context, isNotNull);
      return context!.toJson();
    }

    test('默认档案未授权，性别不会出现在请求体里', () {
      expect(
        InMemoryUserProfileRepository
            .defaultProfile.allowBiologicalSexInAiPlanning,
        isFalse,
      );
      expect(
        contextJson(Gender.female, consented: false),
        isNot(contains('biological_sex')),
      );
      expect(
        contextJson(Gender.male, consented: false),
        isNot(contains('biological_sex')),
      );
    });

    test('授权后男女才映射成白名单代码', () {
      expect(
        contextJson(Gender.male, consented: true)['biological_sex'],
        'male',
      );
      expect(
        contextJson(Gender.female, consented: true)['biological_sex'],
        'female',
      );
    });

    test('即使授权，其他与暂不填写也不出网', () {
      expect(
        contextJson(Gender.other, consented: true),
        isNot(contains('biological_sex')),
      );
      expect(
        contextJson(Gender.unknown, consented: true),
        isNot(contains('biological_sex')),
      );
    });

    test('授权状态与性别都会影响网络摘要，且结果稳定', () {
      const PlanContextDigestService service = PlanContextDigestService();
      final String femaleOn = service.buildRequestContextDigest(
        contextJson(Gender.female, consented: true),
      );
      final String maleOn = service.buildRequestContextDigest(
        contextJson(Gender.male, consented: true),
      );
      final String femaleOff = service.buildRequestContextDigest(
        contextJson(Gender.female, consented: false),
      );
      final String maleOff = service.buildRequestContextDigest(
        contextJson(Gender.male, consented: false),
      );

      expect(femaleOn, isNot(maleOn));
      expect(femaleOn, isNot(femaleOff));
      // 未授权时两种性别都省略该键，摘要必须一致——否则等于把性别泄露进了摘要。
      expect(femaleOff, maleOff);
      expect(
        service.buildRequestContextDigest(
          contextJson(Gender.female, consented: true),
        ),
        femaleOn,
      );
    });

    test('撤回授权会让本地陈旧指纹失效', () {
      const PlanContextDigestService service = PlanContextDigestService();
      final DateTime startsOn = DateTime(2026, 7, 20);
      final String consented = service.buildLocalFingerprint(
        profile: profileWith(Gender.female, consented: true),
        startsOn: startsOn,
      );
      final String revoked = service.buildLocalFingerprint(
        profile: profileWith(Gender.female, consented: false),
        startsOn: startsOn,
      );
      expect(consented, isNot(revoked));
    });

    test('授权状态可以往返序列化，旧档案缺键时视为未授权', () {
      final UserProfile consented =
          profileWith(Gender.female, consented: true);
      expect(
        UserProfile.fromJson(consented.toJson())
            .allowBiologicalSexInAiPlanning,
        isTrue,
      );

      final Map<String, dynamic> legacy = consented.toJson()
        ..remove('allowBiologicalSexInAiPlanning');
      final UserProfile hydrated = UserProfile.fromJson(legacy);
      expect(hydrated.allowBiologicalSexInAiPlanning, isFalse);
      expect(hydrated.aiPlanningBiologicalSexCode, isNull);
    });
  });

  test('康复主次项目与无法安全分类的路跑赛事均使用本地计划', () {
    final UserProfile base =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
      mainSports: const <MainSport>[MainSport.marathon, MainSport.rehab],
    );
    expect(
      buildTrainingPrescriptionRequestContext(
        profile: base,
        race: null,
        now: DateTime(2026, 7, 17),
      ),
      isNull,
    );

    final RacePlan roadRace = seedRaces.first.copyWith(
      type: RaceType.roadRunning,
      raceDate: DateTime(2026, 9, 1),
    );
    expect(
      buildTrainingPrescriptionRequestContext(
        profile: base.copyWith(
          mainSports: const <MainSport>[MainSport.marathon],
        ),
        race: roadRace,
        now: DateTime(2026, 7, 17),
      ),
      isNull,
    );
  });

  test('赛事倒计时不在 1 到 730 天时使用本地计划', () {
    final UserProfile profile =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
      mainSports: const <MainSport>[MainSport.marathon],
    );
    final RacePlan pastRace = seedRaces.first.copyWith(
      raceDate: DateTime(2026, 7, 1),
    );
    expect(
      buildTrainingPrescriptionRequestContext(
        profile: profile,
        race: pastRace,
        now: DateTime(2026, 7, 17),
      ),
      isNull,
    );

    final RacePlan distantRace = seedRaces.first.copyWith(
      type: RaceType.marathon,
      raceDate: DateTime(2028, 7, 18),
    );
    expect(
      buildTrainingPrescriptionRequestContext(
        profile: profile,
        race: distantRace,
        now: DateTime(2026, 7, 17),
      ),
      isNull,
    );
  });
}
