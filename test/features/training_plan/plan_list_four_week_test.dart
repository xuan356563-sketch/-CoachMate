import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/features/training_plan/plan_list_page.dart';

import '../../support/test_harness.dart';

void main() {
  testWidgets('训练计划页展示滚动四周阶段与主次目标', (WidgetTester tester) async {
    final TestHarness harness = TestHarness();
    PersistedUserProfileRepository(harness.storageService).saveProfile(
      InMemoryUserProfileRepository.defaultProfile.copyWith(
        mainSports: const <MainSport>[
          MainSport.generalFitness,
          MainSport.strength,
        ],
        weeklyTrainingDays: 4,
      ),
    );

    await tester.pumpWidget(
      harness.buildApp(
        const MaterialApp(home: PlanListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('plans-showcase-header')),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('4 周阶段'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('4 周阶段'), findsOneWidget);
    expect(find.text('基线周'), findsOneWidget);
    expect(find.text('提升周'), findsOneWidget);
    expect(find.text('专项周'), findsOneWidget);
    expect(find.text('减量周'), findsOneWidget);
    final Finder planTitle = find.textContaining('基础体能 4 周计划');
    await tester.scrollUntilVisible(
      planTitle,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(planTitle, findsOneWidget);
    expect(find.textContaining('兼顾力量训练'), findsWidgets);
  });
}
