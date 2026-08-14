import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/seed/seed_races.dart';
import 'package:trainflow_ai/services/plan_context_digest_service.dart';

void main() {
  const PlanContextDigestService service = PlanContextDigestService();

  test('网络摘要与 Map 键顺序无关且为 64 位小写 SHA-256', () {
    final String first = service.buildRequestContextDigest(
      <String, dynamic>{'primary_sport': 'hyrox', 'available_minutes': 45},
    );
    final String second = service.buildRequestContextDigest(
      <String, dynamic>{'available_minutes': 45, 'primary_sport': 'hyrox'},
    );

    expect(first, second);
    expect(first, matches(RegExp(r'^[a-f0-9]{64}$')));
  });

  test('本地指纹覆盖目标、器械、天数、赛事和基准版本', () {
    final UserProfile base =
        InMemoryUserProfileRepository.defaultProfile.copyWith(
      trainingExperienceLevel: TrainingExperienceLevel.intermediate,
    );
    String digest(UserProfile profile, {bool race = false, String? version}) {
      return service.buildLocalFingerprint(
        profile: profile,
        startsOn: DateTime(2026, 7, 13),
        race: race ? seedRaces.first : null,
        activeVersionId: version,
      );
    }

    final String baseline = digest(base);
    expect(digest(base.copyWith(trainingGoal: '新目标')), isNot(baseline));
    expect(
      digest(base.copyWith(equipmentAccessType: EquipmentAccessType.none)),
      isNot(baseline),
    );
    expect(digest(base.copyWith(weeklyTrainingDays: 3)), isNot(baseline));
    expect(digest(base, race: true), isNot(baseline));
    expect(digest(base, version: 'version-2'), isNot(baseline));
  });
}
