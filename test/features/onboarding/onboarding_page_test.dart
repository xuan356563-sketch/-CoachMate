import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/features/dashboard/today_training_page.dart';
import 'package:trainflow_ai/features/onboarding/onboarding_page.dart';

import '../../support/test_harness.dart';

void main() {
  Future<void> openProfileEditor(
    WidgetTester tester,
    TestHarness harness,
  ) async {
    await tester.pumpWidget(harness.buildApp(const TrainFlowApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom-nav-item-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑资料'));
    await tester.pumpAndSettle();
  }

  Future<void> selectGender(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<Gender>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> saveProfile(WidgetTester tester) async {
    final Finder saveButton = find.text('确认资料并生成计划');
    await tester.scrollUntilVisible(
      saveButton,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }

  testWidgets('AI 性别授权只对男女显示且默认关闭', (WidgetTester tester) async {
    final TestHarness harness = TestHarness();
    await openProfileEditor(tester, harness);

    const Key consentKey = Key('onboarding-ai-biological-sex-consent');
    expect(find.byKey(consentKey), findsNothing);

    await selectGender(tester, '男');
    expect(find.byKey(consentKey), findsOneWidget);
    expect(
        tester.widget<SwitchListTile>(find.byKey(consentKey)).value, isFalse);

    await selectGender(tester, '女');
    expect(find.byKey(consentKey), findsOneWidget);
    expect(
        tester.widget<SwitchListTile>(find.byKey(consentKey)).value, isFalse);

    await selectGender(tester, '其他');
    expect(find.byKey(consentKey), findsNothing);

    await selectGender(tester, '暂不填写');
    expect(find.byKey(consentKey), findsNothing);
  });

  testWidgets('AI 性别授权可保存恢复且切换到其他时自动撤回', (WidgetTester tester) async {
    final TestHarness harness = TestHarness();
    await openProfileEditor(tester, harness);

    const Key consentKey = Key('onboarding-ai-biological-sex-consent');
    await selectGender(tester, '女');
    await tester.tap(find.byKey(consentKey));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(consentKey)).value, isTrue);

    await saveProfile(tester);
    Map<String, dynamic> profile = harness.storageService.readJson(
      PersistedUserProfileRepository.storageKey,
    )!['profile'] as Map<String, dynamic>;
    expect(profile['gender'], 'female');
    expect(profile['allowBiologicalSexInAiPlanning'], isTrue);

    await tester.tap(find.byKey(const Key('bottom-nav-item-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑资料'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(consentKey)).value, isTrue);

    await selectGender(tester, '其他');
    expect(find.byKey(consentKey), findsNothing);
    await saveProfile(tester);

    profile = harness.storageService.readJson(
      PersistedUserProfileRepository.storageKey,
    )!['profile'] as Map<String, dynamic>;
    expect(profile['gender'], 'other');
    expect(profile['allowBiologicalSexInAiPlanning'], isFalse);
  });

  testWidgets('基础资料可以选择职业分型并回到今日训练', (WidgetTester tester) async {
    final TestHarness harness = TestHarness();
    await tester.pumpWidget(harness.buildApp(const TrainFlowApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottom-nav-item-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑资料'));
    await tester.pumpAndSettle();

    expect(find.text('职业 / 生活分型'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('职业 / 生活分型'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('久坐办公室').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('经常加班').last);
    await tester.pumpAndSettle();

    expect(find.text('职业 / 生活分型'), findsOneWidget);
    expect(find.textContaining('短时高效和恢复'), findsOneWidget);

    expect(find.text('器械条件'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('器械条件'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('健身房').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('基本无器械').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('器械条件会参与今日训练替代'), findsOneWidget);

    final Finder saveButton = find.text('确认资料并生成计划');
    await tester.scrollUntilVisible(
      saveButton,
      180,
      scrollable: find.byType(Scrollable).first,
    );
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

    await tester.tap(find.byKey(const Key('bottom-nav-item-1')));
    await tester.pumpAndSettle();

    final Finder prompt = find.text('首次进入请填写基础资料');
    final Finder useCurrentProfile = find.widgetWithText(
      FilledButton,
      '使用当前资料',
    );
    await tester.scrollUntilVisible(
      prompt,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final Finder pageScrollable =
        find.ancestor(of: prompt, matching: find.byType(Scrollable)).first;
    await tester.drag(pageScrollable, const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(prompt, findsOneWidget);
    await tester.tap(useCurrentProfile);
    await tester.pumpAndSettle();

    final Map<String, dynamic>? storedProfile = harness.storageService.readJson(
      PersistedUserProfileRepository.storageKey,
    );
    expect(storedProfile, isNotNull);
    expect(storedProfile!['profileCompleted'], isTrue);
    expect(prompt, findsNothing);
  });

  testWidgets('用户可编辑档案并选择一个主目标和可选次目标', (WidgetTester tester) async {
    final TestHarness harness = TestHarness();
    await tester.pumpWidget(harness.buildApp(const TrainFlowApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottom-nav-item-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑资料'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('onboarding-name-field')),
      '小高',
    );
    await tester.enterText(
      find.byKey(const Key('onboarding-target-field')),
      '提升全身力量基础',
    );
    await tester.enterText(
      find.byKey(const Key('onboarding-max-heart-rate-field')),
      '189',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('onboarding-primary-goal')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-primary-goal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('力量训练').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('onboarding-secondary-goal')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-secondary-goal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('无次目标').last);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();

    final Finder saveButton = find.text('确认资料并生成计划');
    await tester.scrollUntilVisible(
      saveButton,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -140),
    );
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final Map<String, dynamic> profile = harness.storageService.readJson(
      PersistedUserProfileRepository.storageKey,
    )!['profile'] as Map<String, dynamic>;
    expect(profile['name'], '小高');
    expect(profile['trainingGoal'], '提升全身力量基础');
    expect(profile['mainSports'], <String>['strength']);
    expect(profile['maxHeartRate'], 189);
  });

  testWidgets('最大心率只接受合理的本人实测范围，也允许留空', (WidgetTester tester) async {
    final TestHarness harness = TestHarness();
    await tester.pumpWidget(harness.buildApp(const TrainFlowApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottom-nav-item-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑资料'));
    await tester.pumpAndSettle();

    final Finder field =
        find.byKey(const Key('onboarding-max-heart-rate-field'));
    await tester.enterText(field, '260');
    await tester.pump();
    expect(find.textContaining('请输入 80–240'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
    );

    await tester.enterText(field, '');
    await tester.pump();
    expect(find.textContaining('请输入 80–240'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNotNull,
    );
  });
}
