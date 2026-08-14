import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';

import '../support/test_harness.dart';

void main() {
  final List<({String name, String path, String fallback})> childPages = [
    (
      name: '每日调整',
      path: AppRoutes.dailyAdjustment,
      fallback: AppRoutes.dashboard,
    ),
    (
      name: '精简签到',
      path: AppRoutes.dailyCheckIn,
      fallback: AppRoutes.dashboard,
    ),
    (
      name: '成长证据',
      path: AppRoutes.growthEvidence,
      fallback: AppRoutes.dashboard,
    ),
    (
      name: '身体节奏',
      path: AppRoutes.rhythmDetail,
      fallback: AppRoutes.dashboard,
    ),
    (
      name: '15 天复盘',
      path: AppRoutes.progressReview,
      fallback: AppRoutes.rhythmDetail,
    ),
    (
      name: '30 天引导',
      path: AppRoutes.starterProgram,
      fallback: AppRoutes.dailyCheckIn,
    ),
    (
      name: '毕业报告',
      path: AppRoutes.starterGraduation,
      fallback: AppRoutes.starterProgram,
    ),
    (
      name: '普通跟练',
      path: AppRoutes.workoutPlayer,
      fallback: AppRoutes.dashboard,
    ),
    (
      name: '计划生成',
      path: AppRoutes.planGenerate,
      fallback: AppRoutes.plans,
    ),
    (
      name: '比赛备战',
      path: AppRoutes.races,
      fallback: AppRoutes.plans,
    ),
    (
      name: '跳绳课程目录',
      path: AppRoutes.guidedWorkouts,
      fallback: AppRoutes.plans,
    ),
    (
      name: '不存在的跳绳课程',
      path: AppRoutes.guidedWorkoutDetail('course-not-found'),
      fallback: AppRoutes.guidedWorkouts,
    ),
    (
      name: '不存在的跳绳跟练',
      path: AppRoutes.guidedWorkoutSession('course-not-found'),
      fallback: AppRoutes.guidedWorkoutDetail('course-not-found'),
    ),
    (
      name: '不存在的计划',
      path: AppRoutes.planDetail('plan-not-found'),
      fallback: AppRoutes.plans,
    ),
    (
      name: '不存在的训练日',
      path: AppRoutes.workoutDetail('plan-not-found', 'day-not-found'),
      fallback: AppRoutes.planDetail('plan-not-found'),
    ),
    (
      name: '不存在的动作',
      path: AppRoutes.exerciseDetail('exercise-not-found'),
      fallback: AppRoutes.exercises,
    ),
    (
      name: '动作检测',
      path: AppRoutes.motionCheck,
      fallback: AppRoutes.exercises,
    ),
    (
      name: '伙伴数据',
      path: AppRoutes.petData,
      fallback: AppRoutes.companion,
    ),
    (
      name: '成长档案',
      path: AppRoutes.companionArchive,
      fallback: AppRoutes.companion,
    ),
    (
      name: '伙伴记忆',
      path: AppRoutes.companionMemories,
      fallback: AppRoutes.companion,
    ),
    (
      name: '基础资料',
      path: AppRoutes.onboarding,
      fallback: AppRoutes.profile,
    ),
    (
      name: '身体数据',
      path: AppRoutes.dataCenter,
      fallback: AppRoutes.profile,
    ),
    (
      name: '训练文件导入',
      path: AppRoutes.activityImport,
      fallback: AppRoutes.dataCenter,
    ),
    (
      name: '康复',
      path: AppRoutes.rehab,
      fallback: AppRoutes.profile,
    ),
    (
      name: '饮食',
      path: AppRoutes.mealGuide,
      fallback: AppRoutes.profile,
    ),
    (
      name: '周期报告',
      path: AppRoutes.weeklyReport,
      fallback: AppRoutes.profile,
    ),
    (
      name: '用户画像',
      path: AppRoutes.userInsights,
      fallback: AppRoutes.profile,
    ),
    (
      name: '自用验收',
      path: AppRoutes.selfUseAcceptance,
      fallback: AppRoutes.profile,
    ),
    (
      name: '内测验证',
      path: AppRoutes.pilotValidation,
      fallback: AppRoutes.profile,
    ),
    (
      name: '知识库',
      path: AppRoutes.knowledge,
      fallback: AppRoutes.aiCenter,
    ),
  ];

  testWidgets('30 个业务子页直接打开时显示品牌返回按钮并回到父页面', (tester) async {
    await _pumpApp(tester);

    for (final page in childPages) {
      router.go(page.path);
      await _pumpRoute(tester, page.path);

      final Finder backButton = find.byKey(
        const ValueKey<String>('trainmate-back-button'),
      );
      expect(backButton, findsOneWidget);
      expect(tester.getSize(backButton).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(backButton).height, greaterThanOrEqualTo(48));

      await tester.tap(backButton);
      await _pumpRoute(tester, page.fallback);
      expect(
        _currentPath(),
        page.fallback,
        reason: '${page.name}应回到 ${page.fallback}',
      );
    }
  });

  testWidgets('四个主导航页面及今日上下文入口不显示返回按钮', (tester) async {
    await _pumpApp(tester);

    for (final String path in <String>[
      AppRoutes.dashboard,
      AppRoutes.plans,
      AppRoutes.companion,
      AppRoutes.exercises,
      AppRoutes.aiCenter,
      AppRoutes.profile,
    ]) {
      router.go(path);
      await _pumpRoute(tester, path);
      expect(
        find.byKey(const ValueKey<String>('trainmate-back-button')),
        findsNothing,
        reason: '$path 不应显示业务子页返回按钮',
      );
    }
  });
}

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => router.go(AppRoutes.dashboard));

  await tester.pumpWidget(TestHarness().buildApp(const TrainFlowApp()));
  router.go(AppRoutes.dashboard);
  await tester.pumpAndSettle();
}

String _currentPath() {
  return router.routerDelegate.currentConfiguration.uri.path;
}

Future<void> _pumpRoute(WidgetTester tester, String path) async {
  final bool hasContinuousAiGlow = path.startsWith(AppRoutes.aiCenter) ||
      path.startsWith(AppRoutes.aiCoach) ||
      path.startsWith(AppRoutes.knowledge);
  if (!hasContinuousAiGlow) {
    await tester.pumpAndSettle();
    return;
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
