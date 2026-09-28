import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/features/dashboard/today_training_page.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

import '../../support/test_harness.dart';

void main() {
  Finder immersiveScrollable() => find.byType(Scrollable).first;

  Future<void> pumpPage(
    WidgetTester tester,
    TestHarness harness, {
    Size size = const Size(393, 7000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      harness.buildApp(
        const MaterialApp(
          home: Scaffold(body: TodayTrainingPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TrainingLog createLog({
    required String id,
    required DateTime createdAt,
    required String note,
    TrainingLogKind kind = TrainingLogKind.manual,
    bool completed = true,
    int rpe = 6,
    int completionPercentage = 0,
    int actualDurationMinutes = 0,
  }) {
    return TrainingLog(
      id: id,
      workoutDayId: 'workout-test',
      date: createdAt,
      completed: completed,
      rpe: rpe,
      fatigueLevel: rpe,
      sleepQuality: 7,
      painNote: null,
      userNote: note,
      createdAt: createdAt,
      kind: kind,
      actualDurationMinutes: actualDurationMinutes,
      completionPercentage: completionPercentage,
    );
  }

  void seedLogs(
    InMemoryLocalStorageService storage,
    List<TrainingLog> logs,
  ) {
    storage.saveJson('trainflow.training_logs.v1', {
      'schemaVersion': 1,
      'logs': logs.map((TrainingLog log) => log.toJson()).toList(),
    });
  }

  testWidgets('今日首屏使用沉浸场景结构并保留真实训练入口', (tester) async {
    await pumpPage(tester, TestHarness());

    expect(
      find.byKey(const ValueKey<String>('today-showcase-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('today-showcase-metric-capsule')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('trainmate-scene-hero')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('trainmate-status-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('today-health-overview')),
      findsOneWidget,
    );
    expect(find.text('习惯追踪'), findsOneWidget);
    expect(find.text('健康概览'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('today-health-steps-card')),
      findsOneWidget,
    );
    expect(find.text('开始'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey<String>('today-showcase-header')),
          )
          .properties
          .label,
      contains('今日训练'),
    );
  });

  testWidgets('393 宽度下沉浸 Hero 使用紧凑训练页头', (tester) async {
    await pumpPage(tester, TestHarness(), size: const Size(393, 852));

    final Rect hero = tester.getRect(
      find.byKey(const ValueKey<String>('trainmate-scene-hero')),
    );
    expect(hero.height, inInclusiveRange(248, 304));
    expect(
      tester
          .getRect(find
              .byKey(const ValueKey<String>('today-showcase-metric-capsule')))
          .top,
      greaterThanOrEqualTo(hero.top),
    );
  });

  testWidgets('首页按四个核心分区连续展示，迁移工具不再重复出现', (tester) async {
    final TestHarness harness = TestHarness();
    await pumpPage(tester, harness);

    const List<String> sectionTitles = [
      '今日状态与签到',
      '今日训练内容',
      '训练完成记录',
      'AI 教练建议（本地规则）',
    ];
    for (final String title in sectionTitles) {
      expect(find.text(title), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey<String>('today-growth-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('today-growth-rhythm-entry')),
      findsOneWidget,
    );
    expect(find.text('L1 训练执行'), findsOneWidget);
    expect(find.text('本周一致性'), findsWidgets);
    expect(find.text('今日训练判定'), findsOneWidget);
    expect(find.text('负荷状态'), findsOneWidget);
    expect(find.textContaining('结构化数据库不可用'), findsNothing);
    expect(find.textContaining('当前仅显示兼容预览'), findsNothing);
    expect(find.text('训练依据'), findsNothing);
    expect(find.text('本次训练回执'), findsNothing);

    final List<double> sectionOffsets = sectionTitles
        .map((String title) => tester.getTopLeft(find.text(title)).dy)
        .toList();
    for (int index = 1; index < sectionOffsets.length; index += 1) {
      expect(sectionOffsets[index], greaterThan(sectionOffsets[index - 1]));
    }

    expect(find.text('更多工具'), findsNothing);
    expect(find.text('主动提醒'), findsNothing);
    expect(find.text('身体数据'), findsNothing);
    expect(find.byTooltip('照吃卡'), findsNothing);
    expect(find.byTooltip('记录疼痛'), findsNothing);

    expect(find.text('训练负荷工程估算'), findsNothing);
    expect(find.text('30 天渐进引导'), findsNothing);
    expect(find.text('康复记录：记录疼痛后今日训练会自动降级'), findsNothing);
    expect(find.text('身体数据'), findsNothing);
    expect(find.text('今日照吃卡'), findsNothing);
    expect(find.text('动作纠错'), findsNothing);
    expect(find.text('比赛备战'), findsNothing);
    expect(find.text('晨间报告'), findsNothing);
    expect(find.text('昨晚睡眠'), findsNothing);
    expect(find.text('HRV'), findsOneWidget);
    expect(find.text('恢复倒计时'), findsNothing);
    expect(find.text('训练准备度'), findsOneWidget);
  });

  testWidgets('成长详情默认折叠且展开后保留计算依据', (tester) async {
    await pumpPage(tester, TestHarness());

    expect(find.textContaining('计算依据：'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('today-growth-details-expandable')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('计算依据：'), findsOneWidget);
    expect(find.textContaining('结构化数据库不可用'), findsOneWidget);
    expect(find.textContaining('当前仅显示兼容预览'), findsOneWidget);
  });

  testWidgets('训练五步和教练说明默认折叠且不重复主训练与冷身', (tester) async {
    await pumpPage(tester, TestHarness());

    expect(
      find.textContaining('训练后放松与反馈', findRichText: true),
      findsNothing,
    );
    expect(find.text('主训练'), findsNothing);
    expect(find.text('冷身'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('today-workout-coach-notes-full')),
      findsNothing,
    );

    final Finder fiveStepTitle = find.text('今日训练五步');
    await tester.scrollUntilVisible(
      fiveStepTitle,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(fiveStepTitle);
    await tester.pumpAndSettle();
    expect(fiveStepTitle.hitTestable(), findsOneWidget);
    await tester.tap(fiveStepTitle.hitTestable());
    await tester.pumpAndSettle();
    final Finder fiveStepExpandable = find.byKey(
      const ValueKey<String>('today-workout-five-step-expandable'),
    );
    expect(
      tester
          .widget<AnimatedRotation>(
            find.descendant(
              of: fiveStepExpandable,
              matching: find.byType(AnimatedRotation),
            ),
          )
          .turns,
      0.5,
    );
    expect(
      find.textContaining('训练后放松与反馈', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('主训练'), findsNothing);
    expect(find.text('冷身'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey<String>('today-workout-coach-notes-expandable'),
      ),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>('today-workout-coach-notes-expandable'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('today-workout-coach-notes-full')),
      findsOneWidget,
    );
  });

  testWidgets('AI 建议默认折叠且展开后显示全部建议', (tester) async {
    await pumpPage(tester, TestHarness());

    expect(
      find.textContaining('今日决策为'),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('today-coach-advice-expandable')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('today-coach-advice-expandable')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('今日决策为'), findsOneWidget);
  });

  testWidgets('开始跟练按钮位于五步流程之前并显示预计时长', (tester) async {
    await pumpPage(tester, TestHarness());

    final Finder startButton = find.byKey(
      const ValueKey<String>('today-workout-start-button'),
    );
    final Finder fiveStep = find.byKey(
      const ValueKey<String>('today-workout-five-step-expandable'),
    );

    expect(startButton, findsOneWidget);
    expect(find.textContaining('开始跟练 · 约'), findsOneWidget);
    expect(
      tester.getTopLeft(startButton).dy,
      lessThan(tester.getTopLeft(fiveStep).dy),
    );
  });

  testWidgets('393 × 852 默认态保留纸白数据区与深紫行动区', (tester) async {
    final TestHarness harness = TestHarness();
    await pumpPage(
      tester,
      harness,
      size: const Size(393, 852),
    );

    final ScrollableState scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    final double maxScrollExtent = scrollable.position.maxScrollExtent;
    expect(maxScrollExtent, greaterThan(0));
    await tester.scrollUntilVisible(
      find.text('继续今日训练'),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('trainmate-wave-action-section')),
      findsOneWidget,
    );
    expect(find.text('继续今日训练'), findsOneWidget);
  });

  testWidgets('393 × 852 手机尺寸下四个分区不被底部导航遮挡', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TestHarness().buildApp(const TrainFlowApp()),
    );
    router.go(AppRoutes.dashboard);
    await tester.pumpAndSettle();

    final Finder navigationBar =
        find.byKey(const Key('trainmate-bottom-navigation'));
    expect(navigationBar, findsOneWidget);
    final double navigationTop = tester.getTopLeft(navigationBar).dy;

    for (final String title in [
      '今日状态与签到',
      '今日训练内容',
      '训练完成记录',
      'AI 教练建议（本地规则）',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        300,
        scrollable: immersiveScrollable(),
      );
      await tester.pumpAndSettle();

      expect(find.text(title), findsOneWidget);
      expect(
          tester.getBottomRight(find.text(title)).dy, lessThan(navigationTop));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('没有完整训练日志时显示空记录状态', (tester) async {
    await pumpPage(tester, TestHarness());

    expect(find.text('最近训练记录'), findsOneWidget);
    expect(find.text('还没有完整训练记录，完成今日训练后会显示在这里。'), findsOneWidget);
  });

  testWidgets('今日页可以打开共享训练记录编辑器', (tester) async {
    await pumpPage(tester, TestHarness(), size: const Size(393, 852));

    final Finder entry = find.byKey(
      const ValueKey<String>('today-training-record-entry'),
    );
    expect(entry, findsOneWidget);
    await tester.scrollUntilVisible(
      entry,
      260,
      scrollable: immersiveScrollable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('training-record-editor')),
      findsOneWidget,
    );
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('运动项目'), findsOneWidget);
    expect(find.text('训练数据'), findsOneWidget);
    expect(find.text('动作记录'), findsOneWidget);
    expect(find.text('今日计划'), findsOneWidget);
    expect(find.text('额外训练'), findsOneWidget);
  });

  testWidgets('额外训练切换与取消不会写入训练记录', (tester) async {
    final TestHarness harness = TestHarness();
    await pumpPage(tester, harness, size: const Size(393, 852));

    final Finder entry = find.byKey(
      const ValueKey<String>('today-training-record-entry'),
    );
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    await tester.tap(find.text('额外训练'));
    await tester.pumpAndSettle();
    expect(find.text('从动作库添加'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    final Map<String, dynamic>? stored =
        harness.storageService.readJson('trainflow.training_logs.v1');
    expect(stored?['logs'] as List<dynamic>? ?? const <dynamic>[], isEmpty);
  });

  testWidgets('最近记录排除逐动作日志并只显示最新三条完整记录', (tester) async {
    final TestHarness harness = TestHarness();
    seedLogs(harness.storageService, [
      createLog(
        id: 'player-step',
        createdAt: DateTime(2026, 7, 13, 11),
        note: '逐动作日志不展示',
        kind: TrainingLogKind.playerStep,
      ),
      createLog(
        id: 'latest-manual',
        createdAt: DateTime(2026, 7, 13, 10),
        note: '最近手动记录',
      ),
      createLog(
        id: 'session-review',
        createdAt: DateTime(2026, 7, 13, 9),
        note: '完整训练复盘',
        kind: TrainingLogKind.sessionReview,
        completed: false,
        rpe: 7,
        completionPercentage: 75,
        actualDurationMinutes: 42,
      ),
      createLog(
        id: 'third-session',
        createdAt: DateTime(2026, 7, 13, 8),
        note: '第三条完整记录',
      ),
      createLog(
        id: 'fourth-session',
        createdAt: DateTime(2026, 7, 13, 7),
        note: '第四条不展示',
      ),
    ]);

    await pumpPage(tester, harness);

    expect(find.text('最近手动记录'), findsOneWidget);
    expect(find.textContaining('实际 42 分钟 · 75% 完成 · RPE 7'), findsOneWidget);
    expect(find.text('第三条完整记录'), findsOneWidget);
    expect(find.text('逐动作日志不展示'), findsNothing);
    expect(find.text('第四条不展示'), findsNothing);
  });

  testWidgets('保存今日反馈后只显示一次成长回执并更新折叠的教练建议', (tester) async {
    await pumpPage(tester, TestHarness());

    expect(find.text('按计划完成'), findsNothing);
    expect(find.text('最近训练完成度不错，可以维持当前节奏，不急着加量。'), findsNothing);

    final Finder entry = find.byKey(
      const ValueKey<String>('today-training-record-entry'),
    );
    await tester.scrollUntilVisible(
      entry,
      260,
      scrollable: immersiveScrollable(),
    );
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('按计划完成'), findsOneWidget);
    expect(find.textContaining('成长分'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, '查看证据'), findsOneWidget);
    expect(find.text('本次训练回执'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('today-coach-advice-expandable')),
    );
    await tester.tap(find.text('建议详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不急着加量'), findsOneWidget);

    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('成长回执可进入证据页且返回后不重复显示', (tester) async {
    tester.view.physicalSize = const Size(393, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TestHarness().buildApp(const TrainFlowApp()),
    );
    router.go(AppRoutes.dashboard);
    await tester.pumpAndSettle();

    final Finder entry = find.byKey(
      const ValueKey<String>('today-training-record-entry'),
    );
    await tester.scrollUntilVisible(
      entry,
      260,
      scrollable: immersiveScrollable(),
    );
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SnackBarAction, '查看证据'));
    await tester.pumpAndSettle();

    expect(find.text('成长时间线'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('trainmate-back-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('today-showcase-header')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });
}
