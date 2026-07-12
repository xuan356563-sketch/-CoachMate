import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/meal_guide.dart';
import 'package:trainflow_ai/features/meal_guide/application/meal_preference_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  ProviderContainer createContainer(InMemoryLocalStorageService storage) {
    return ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
  }

  test('初始状态读取外卖照吃场景', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);

    expect(
      container.read(mealPreferenceControllerProvider).scenario,
      MealScenario.takeaway,
    );
  });

  test('保存和清除照吃场景会更新独立状态并保留本地兼容', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer first = createContainer(storage);
    expect(
      first.read(mealPreferenceControllerProvider).scenario,
      MealScenario.takeaway,
    );

    first
        .read(mealPreferenceControllerProvider.notifier)
        .saveScenario(MealScenario.homeCooking);
    expect(
      first.read(mealPreferenceControllerProvider).scenario,
      MealScenario.homeCooking,
    );
    first.dispose();

    final ProviderContainer restored = createContainer(storage);
    addTearDown(restored.dispose);
    expect(
      restored.read(mealPreferenceControllerProvider).scenario,
      MealScenario.homeCooking,
    );
    restored.read(mealPreferenceControllerProvider.notifier).clear();
    expect(
      restored.read(mealPreferenceControllerProvider).scenario,
      MealScenario.takeaway,
    );
  });
}
