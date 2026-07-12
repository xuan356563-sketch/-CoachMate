import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/meal_guide.dart';
import 'package:trainflow_ai/data/repositories/meal_preference_repository.dart';

import '../../support/test_harness.dart';

void main() {
  test('照吃偏好仓库默认使用外卖场景并持久化 meal_preference', () {
    final TestHarness harness = TestHarness();
    final PersistedMealPreferenceRepository repository =
        PersistedMealPreferenceRepository(harness.storageService);

    expect(PersistedMealPreferenceRepository.storageKey,
        'trainflow.meal_preference.v1');
    expect(repository.getPreference().scenario, MealScenario.takeaway);

    repository.savePreference(
      const MealPreference(scenario: MealScenario.homeCooking),
    );

    final Map<String, dynamic>? storedState = harness.storageService
        .readJson(PersistedMealPreferenceRepository.storageKey);
    expect(storedState?['schemaVersion'], 1);
    expect(
      (storedState?['preference'] as Map<String, dynamic>)['scenario'],
      'home_cooking',
    );

    final PersistedMealPreferenceRepository restoredRepository =
        PersistedMealPreferenceRepository(harness.storageService);

    expect(
        restoredRepository.getPreference().scenario, MealScenario.homeCooking);

    restoredRepository.clearPreference();

    final PersistedMealPreferenceRepository clearedRepository =
        PersistedMealPreferenceRepository(harness.storageService);

    expect(clearedRepository.getPreference().scenario, MealScenario.takeaway);
  });

  test('照吃偏好仓库会兼容旧 JSON 并持久化场景', () {
    final TestHarness harness = TestHarness();
    harness.storageService
        .saveJson(PersistedMealPreferenceRepository.storageKey, {
      'schemaVersion': 1,
      'preference': <String, dynamic>{},
    });

    expect(
      PersistedMealPreferenceRepository(harness.storageService)
          .getPreference()
          .scenario,
      MealScenario.takeaway,
    );

    final PersistedMealPreferenceRepository repository =
        PersistedMealPreferenceRepository(harness.storageService);
    repository.savePreference(
      const MealPreference(scenario: MealScenario.canteen),
    );

    expect(
      PersistedMealPreferenceRepository(harness.storageService)
          .getPreference()
          .scenario,
      MealScenario.canteen,
    );

    repository.clearPreference();

    expect(
      PersistedMealPreferenceRepository(harness.storageService)
          .getPreference()
          .scenario,
      MealScenario.takeaway,
    );
  });

  test('照吃偏好仓库会把缺少 preference 或未知场景的旧 JSON 回退为外卖', () {
    final TestHarness missingPreferenceHarness = TestHarness();
    missingPreferenceHarness.storageService.saveJson(
      PersistedMealPreferenceRepository.storageKey,
      {
        'schemaVersion': 1,
      },
    );

    expect(
      PersistedMealPreferenceRepository(missingPreferenceHarness.storageService)
          .getPreference()
          .scenario,
      MealScenario.takeaway,
    );

    final TestHarness unknownScenarioHarness = TestHarness();
    unknownScenarioHarness.storageService.saveJson(
      PersistedMealPreferenceRepository.storageKey,
      {
        'schemaVersion': 1,
        'preference': <String, dynamic>{
          'scenario': 'unknown',
        },
      },
    );

    expect(
      PersistedMealPreferenceRepository(unknownScenarioHarness.storageService)
          .getPreference()
          .scenario,
      MealScenario.takeaway,
    );
  });
}
