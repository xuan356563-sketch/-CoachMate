import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/features/dashboard/today_training_page.dart';
import 'package:trainflow_ai/features/onboarding/onboarding_page.dart';

import '../../support/test_harness.dart';

void main() {
  testWidgets('基础资料可以选择职业分型并回到今日训练', (WidgetTester tester) async {
    final TestHarness harness = TestHarness();
    await tester.pumpWidget(harness.buildApp(const TrainFlowApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑资料'));
    await tester.pumpAndSettle();

    expect(find.text('职业 / 生活分型'), findsOneWidget);
    await tester.tap(find.text('久坐办公室').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('经常加班').last);
    await tester.pumpAndSettle();

    expect(find.text('职业 / 生活分型'), findsOneWidget);
    expect(find.textContaining('短时高效和恢复'), findsOneWidget);

    expect(find.text('器械条件'), findsOneWidget);
    await tester.tap(find.text('健身房').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('基本无器械').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('器械条件会参与今日训练替代'), findsOneWidget);

    final Finder saveButton = find.text('确认资料并生成计划');
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final Map<String, dynamic>? storedProfile = harness.storageService.readJson(
      PersistedUserProfileRepository.storageKey,
    );
    expect(storedProfile, isNotNull);
    expect(storedProfile!['profileCompleted'], isTrue);
    expect(
      (storedProfile['profile'] as Map<String, dynamic>)['equipmentAccessType'],
      'none',
    );
    expect(find.byType(OnboardingPage), findsNothing);
    expect(find.byType(TodayTrainingPage), findsOneWidget);
  });

  testWidgets('今日训练可以使用当前资料完成首次设置', (WidgetTester tester) async {
    final TestHarness harness = TestHarness();
    await tester.pumpWidget(harness.buildApp(const TrainFlowApp()));
    await tester.pumpAndSettle();

    expect(find.text('首次进入请填写基础资料'), findsOneWidget);
    await tester.tap(find.text('使用当前资料'));
    await tester.pumpAndSettle();

    final Map<String, dynamic>? storedProfile = harness.storageService.readJson(
      PersistedUserProfileRepository.storageKey,
    );
    expect(storedProfile, isNotNull);
    expect(storedProfile!['profileCompleted'], isTrue);
    expect(find.text('首次进入请填写基础资料'), findsNothing);
  });
}
