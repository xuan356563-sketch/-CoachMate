import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/features/capabilities/history_page.dart';
import 'package:trainflow_ai/features/profile/profile_page.dart';
import 'package:trainflow_ai/data/repositories/training_log_repository.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/dashboard/today_training_page.dart';
import 'package:trainflow_ai/features/dashboard/widgets/today_showcase_header.dart';
import 'package:trainflow_ai/features/training_log/presentation/training_record_editor.dart';
import 'package:trainflow_ai/plugins/history/core_history.dart';
import 'package:trainflow_ai/services/weekly_report_service.dart';

import '../resource_library/local_plan_test.dart' show LocalFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('核心历史区分步骤与整次训练且保留实际完成度', (tester) async {
    final fixture = await LocalFixture.create();
    addTearDown(fixture.close);
    final repository = PersistedTrainingLogRepository(fixture.storage);
    for (final kind in [
      TrainingLogKind.playerStep,
      TrainingLogKind.sessionReview
    ]) {
      repository.saveLog(TrainingLog(
        id: 'batch1-${kind.name}',
        workoutDayId: 'synthetic-strength',
        date: DateTime.now(),
        createdAt: DateTime.now(),
        completed: kind == TrainingLogKind.playerStep,
        kind: kind,
        rpe: 4,
        fatigueLevel: 4,
        sleepQuality: 7,
        painNote: null,
        userNote: '合成验收',
        actualDurationMinutes: kind == TrainingLogKind.sessionReview ? 20 : 0,
        completionPercentage: kind == TrainingLogKind.sessionReview ? 50 : 0,
      ));
    }
    final before =
        fixture.storage.readJson(PersistedTrainingLogRepository.storageKey);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: fixture.container,
      child: const MaterialApp(home: Scaffold(body: HistoryPage())),
    ));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('history-log-batch1-sessionReview'));
    await tester.scrollUntilVisible(card, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final title = find.descendant(of: card, matching: find.text('未完成训练'));
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(find.text('已完成跟练步骤'), findsOneWidget);
    expect(find.text('已完成训练'), findsNothing);
    expect(find.textContaining('实际 20 分钟 · 50% 完成'), findsOneWidget);
    expect(fixture.storage.readJson(PersistedTrainingLogRepository.storageKey),
        before);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: fixture.container,
      child: const MaterialApp(home: Scaffold(body: ProfilePage())),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('已完成跟练步骤'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('已完成跟练步骤'), findsOneWidget);
    expect(find.text('已完成训练'), findsNothing);
  });

  test('四天力量样例审核阻断仍保留原有效版本，三天适用样例可启用', () async {
    final fixture = await LocalFixture.create();
    addTearDown(fixture.close);
    await fixture.controller.createLocalDraft('plan.strength.baseline');
    await fixture.controller.activateLocalDraft(fixture.draft!.id);
    final original = fixture.repo.getHistory().toJson();
    final profiles = PersistedUserProfileRepository(fixture.storage);
    final profile = profiles.getProfile();
    for (final minutes in [45, 60]) {
      profiles.saveProfile(profile.copyWith(
        mainSports: [MainSport.strength],
        weeklyTrainingDays: 4,
        dailyAvailableMinutes: minutes,
      ));
      await fixture.controller.createLocalDraft(
        'plan.strength.baseline',
        replaceDraftId: fixture.draft?.id,
      );
      final reasons = fixture.draft!.auditSummary.blockingReasons;
      expect(reasons, isNotEmpty);
      expect(reasons.join('；'),
          contains(minutes == 45 ? '可用时间' : '第 2 周训练量增长超过 10%'));
      await expectLater(
        fixture.controller.activateLocalDraft(fixture.draft!.id),
        throwsStateError,
      );
      expect(fixture.repo.getHistory().toJson(), original);
    }
  });

  testWidgets('力量实际组数须明确填写，保存后历史与复盘一致且不改有效计划', (tester) async {
    final fixture = await LocalFixture.create();
    addTearDown(fixture.close);
    await fixture.controller.createLocalDraft('plan.strength.baseline');
    expect(fixture.draft!.auditSummary.blockingReasons, isEmpty);
    await fixture.controller.activateLocalDraft(fixture.draft!.id);
    final original = fixture.repo.getHistory().toJson();
    final state = fixture.container.read(trainingMvpProvider);
    final workout = state.activePlan.workoutDays.first;
    final controller = fixture.container.read(trainingMvpProvider.notifier);
    expect(controller.startWorkoutPlayer(workoutDayId: workout.id), isTrue);
    expect(
        fixture.container
            .read(trainingMvpProvider)
            .activeWorkoutPlayerWorkout
            .toJson(),
        workout.toJson());
    await tester.pumpWidget(UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => showTrainingRecordEditor(
                        context: context,
                        workout: workout,
                        requireActualValues: true,
                      ),
                      child: const Text('记录合成反馈'),
                    ),
                  ))),
    ));
    await tester.tap(find.text('记录合成反馈'));
    await tester.pumpAndSettle();
    // 使用真实弹层及滚动容器，验证首屏不能容纳完整表单时仍可填写。
    await tester.drag(
        find.byType(SingleChildScrollView).last, const Offset(0, -450));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
        of: find.byType(SingleChildScrollView).last,
        matching: find.byType(Scrollable));
    expect(tester.state<ScrollableState>(scrollable.first).position.pixels,
        greaterThan(0));
    final duration =
        find.byKey(const ValueKey('workout-review-duration-field'));
    await tester.ensureVisible(duration);
    await tester.enterText(duration, '20');
    final completion = find.widgetWithText(ChoiceChip, '50% 完成');
    await tester.ensureVisible(completion);
    await tester.tap(completion);
    final rpe = find.byKey(const ValueKey('workout-review-rpe-selector'));
    await tester.ensureVisible(rpe);
    await tester.tap(rpe);
    await tester.pumpAndSettle();
    await tester.tap(find.text('RPE 4').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(fixture.container.read(coreHistoryProvider).listLogs(), isEmpty);
    expect(find.textContaining('请填写'), findsWidgets);

    final fields = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>)
            .value
            .startsWith('workout-review-exercise-') &&
        (widget.key! as ValueKey<String>)
            .value
            .endsWith('-completed-sets-field'));
    final count = fields.evaluate().length;
    expect(count, greaterThan(1));
    await tester.ensureVisible(fields.first);
    await tester.enterText(fields.first, 'abc');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('实际完成组数请输入整数'), findsOneWidget);
    expect(fixture.container.read(coreHistoryProvider).listLogs(), isEmpty);
    for (var i = 0; i < count; i++) {
      final field = fields.at(i);
      await tester.ensureVisible(field);
      await tester.enterText(field, i == 0 ? '2' : '0');
    }
    final weight =
        find.byKey(const ValueKey('workout-review-exercise-0-weight-field'));
    await tester.ensureVisible(weight);
    await tester.enterText(weight, '8');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.byType(TrainingRecordEditor), findsNothing,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join('；'));
    final logs = fixture.container.read(coreHistoryProvider).listLogs();
    expect(logs, hasLength(1));
    final log = logs.single;
    expect(log.workoutDayId, workout.id);
    expect(log.actualDurationMinutes, 20);
    expect(log.completionPercentage, 50);
    expect(log.rpe, 4);
    expect(log.exerciseRecords.first.completedSetCount, 2);
    expect(log.exerciseRecords.first.weightKg, 8);
    expect(
        log.exerciseRecords
            .skip(1)
            .every((record) => record.completedSetCount == 0),
        isTrue);
    expect(
        PersistedTrainingLogRepository(fixture.storage)
            .listLogs()
            .single
            .toJson(),
        log.toJson());
    expect(fixture.repo.getHistory().toJson(), original);
    final report = WeeklyReportService().buildWeeklyReport(
      profile: state.profile,
      todayWorkout: workout,
      logs: logs,
      bodyMetrics: [],
      readinessScore: null,
      trainingStatusLabel: '无法评估',
      trainingStatusReason: '合成验收',
      recoveryCountdownLabel: '',
      recoveryAdvice: '',
      achievementSummaryLabel: '',
    );
    expect(report.completionRate, closeTo(0.5 / 3, 0.001));
    expect(report.recoverySummary, contains('无法评估'));
    await controller.stopWorkoutPlayer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: fixture.container,
      child: const MaterialApp(home: Scaffold(body: TodayTrainingPage())),
    ));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TodayShowcaseHeader>(find.byType(TodayShowcaseHeader))
            .completionRate,
        0.5);
    expect(find.text('力量 · 50% 完成'), findsOneWidget);
  });

  testWidgets('跟练反馈新增动作也不能预填已完成组数', (tester) async {
    final fixture = await LocalFixture.create();
    addTearDown(fixture.close);
    final state = fixture.container.read(trainingMvpProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp(
          home: Scaffold(
              body: TrainingRecordEditor(
        workout: state.activePlan.workoutDays.first,
        requireActualValues: true,
      ))),
    ));
    await tester.pumpAndSettle();
    final fields = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>)
            .value
            .startsWith('workout-review-exercise-') &&
        (widget.key! as ValueKey<String>)
            .value
            .endsWith('-completed-sets-field'));
    final beforeCount = fields.evaluate().length;
    final add = find.text('从动作库添加');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(ListTile, state.exercises.first.name).last);
    await tester.pumpAndSettle();
    expect(fields, findsNWidgets(beforeCount + 1));
    expect(tester.widget<TextField>(fields.last).controller!.text, isEmpty);
  });
}
