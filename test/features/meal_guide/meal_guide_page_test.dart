import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/core/theme/tdesign_theme.dart';
import 'package:trainflow_ai/data/models/meal_guide.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/meal_guide/application/meal_preference_controller.dart';
import 'package:trainflow_ai/features/meal_guide/meal_guide_page.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('照吃页下拉框写入独立偏好控制器并同步训练投影', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: const MealGuidePage(),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<MealScenario>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自炊').last);
    await tester.pumpAndSettle();

    expect(
      container.read(mealPreferenceControllerProvider).scenario,
      MealScenario.homeCooking,
    );
    expect(
      container.read(trainingMvpProvider).mealScenario,
      MealScenario.homeCooking,
    );
  });
}
