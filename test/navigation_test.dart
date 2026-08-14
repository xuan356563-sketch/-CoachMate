import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/navigation/main_shell.dart';
import 'package:trainflow_ai/app/navigation/trainmate_bottom_navigation.dart';
import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/core/theme/trainflow_tokens.dart';

import 'support/test_harness.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    bool disableAnimations = false,
    Size size = const Size(393, 852),
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: disableAnimations,
          textScaler: textScaler,
        ),
        child: TestHarness().buildApp(const TrainFlowApp()),
      ),
    );
    router.go(AppRoutes.dashboard);
    await tester.pumpAndSettle();
    addTearDown(() => router.go(AppRoutes.dashboard));
  }

  TrainMateBottomNavigation bottomNavigation(WidgetTester tester) {
    return tester.widget<TrainMateBottomNavigation>(
      find.byType(TrainMateBottomNavigation),
    );
  }

  TrainMateNavigationBarPainter navigationPainter(WidgetTester tester) {
    return tester
        .widget<CustomPaint>(
          find.byKey(
            const Key('trainmate-bottom-navigation-dynamic-layer'),
          ),
        )
        .painter! as TrainMateNavigationBarPainter;
  }

  Future<void> pumpNavigationOnly(
    WidgetTester tester, {
    required Size size,
    required TextScaler textScaler,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: textScaler),
        child: MaterialApp(
          home: Scaffold(
            bottomNavigationBar: TrainMateBottomNavigation(
              items: bottomNavItems,
              selectedIndex: 0,
              animationDuration: Duration.zero,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('底部导航选中动画使用选择反馈时长', (tester) async {
    await pumpApp(tester);

    expect(
      bottomNavigation(tester).animationDuration,
      TrainFlowMotion.selection,
    );
  });

  testWidgets('减少动态效果时底部导航选中动画立即完成', (tester) async {
    await pumpApp(tester, disableAnimations: true);

    expect(bottomNavigation(tester).animationDuration, Duration.zero);
  });

  testWidgets('五个主路由的导航承接面保持透明，玻璃胶囊承接页面内容', (tester) async {
    await pumpApp(tester);

    for (int index = 0; index < 5; index += 1) {
      if (index != bottomNavigation(tester).selectedIndex) {
        await tester.tap(find.byKey(Key('bottom-nav-item-$index')));
        await tester.pumpAndSettle();
      }
      final ColoredBox surface = tester.widget<ColoredBox>(
        find.byKey(const Key('trainmate-bottom-navigation-surface')),
      );
      expect(surface.color, Colors.transparent);
    }
  });

  testWidgets('导航使用 70% 白色玻璃胶囊、暖黑圆盘与青柠选中态', (tester) async {
    await pumpApp(tester);

    final TrainMateNavigationStaticBarPainter staticPainter = tester
        .widget<CustomPaint>(
          find.byKey(const Key('trainmate-bottom-navigation-pill')),
        )
        .painter! as TrainMateNavigationStaticBarPainter;
    final TrainMateNavigationBarPainter dynamicPainter =
        navigationPainter(tester);
    expect(staticPainter.pillColor, const Color(0xB3FFFFFF));
    expect(dynamicPainter.surfaceColor, Colors.transparent);
    expect(dynamicPainter.inactiveColor, const Color(0xFF3E3A3E));
    expect(dynamicPainter.selectedFaceColor, TrainFlowTokens.accent);
    expect(dynamicPainter.selectedDiscColor, TrainFlowTokens.navigationInk);
    expect(
      find.byKey(const Key('trainmate-bottom-navigation-glow')),
      findsNothing,
    );
  });

  testWidgets('五个暖黑主标签使用浅色状态栏图标', (
    tester,
  ) async {
    await pumpApp(tester);

    AnnotatedRegion<SystemUiOverlayStyle> overlay = tester.widget(
      find.byKey(const Key('main-shell-system-ui-style')),
    );
    expect(overlay.value.statusBarIconBrightness, Brightness.light);

    await tester.tap(find.byKey(const Key('bottom-nav-item-0')));
    await tester.pumpAndSettle();
    overlay = tester.widget(
      find.byKey(const Key('main-shell-system-ui-style')),
    );
    expect(overlay.value.statusBarIconBrightness, Brightness.light);

    await tester.tap(find.byKey(const Key('bottom-nav-item-1')));
    await tester.pumpAndSettle();
    overlay = tester.widget(
      find.byKey(const Key('main-shell-system-ui-style')),
    );
    expect(overlay.value.statusBarIconBrightness, Brightness.light);

    await tester.tap(find.byKey(const Key('bottom-nav-item-3')));
    await tester.pumpAndSettle();
    overlay = tester.widget(
      find.byKey(const Key('main-shell-system-ui-style')),
    );
    expect(overlay.value.statusBarIconBrightness, Brightness.light);

    await tester.tap(find.byKey(const Key('bottom-nav-item-4')));
    await tester.pumpAndSettle();
    overlay = tester.widget(
      find.byKey(const Key('main-shell-system-ui-style')),
    );
    expect(overlay.value.statusBarIconBrightness, Brightness.light);
  });

  testWidgets('底部导航展示伙伴、计划、今日、动作库、我的五个可访问入口', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await pumpApp(tester);

      final TrainMateBottomNavigation navigation = bottomNavigation(tester);
      final List<String> labels =
          navigation.items.map((NavigationItem item) => item.label).toList();
      final List<String> displayLabels = navigation.items
          .map((NavigationItem item) => item.displayLabel)
          .toList();
      final List<NavigationItemRole> roles =
          navigation.items.map((NavigationItem item) => item.role).toList();

      expect(labels, <String>['运动搭子', '训练计划', '今日训练', '动作库', '我的']);
      expect(displayLabels, <String>['伙伴', '计划', '今日', '动作库', '我的']);
      expect(
        roles,
        const <NavigationItemRole>[
          NavigationItemRole.partner,
          NavigationItemRole.plan,
          NavigationItemRole.today,
          NavigationItemRole.exercises,
          NavigationItemRole.profile,
        ],
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const Key('global-ai-center-action')), findsNothing);

      for (int index = 0; index < 5; index += 1) {
        expect(find.text(displayLabels[index]), findsNothing);
        final Tooltip tooltip = tester.widget<Tooltip>(
          find.descendant(
            of: find.byKey(Key('bottom-nav-item-$index')),
            matching: find.byType(Tooltip),
          ),
        );
        expect(tooltip.message, labels[index]);
      }

      final SemanticsNode companion = tester.getSemantics(
        find.byKey(const Key('bottom-nav-item-0')),
      );
      final SemanticsNode plan = tester.getSemantics(
        find.byKey(const Key('bottom-nav-item-1')),
      );
      final SemanticsNode today = tester.getSemantics(
        find.byKey(const Key('bottom-nav-item-2')),
      );
      final SemanticsNode exercises = tester.getSemantics(
        find.byKey(const Key('bottom-nav-item-3')),
      );
      final SemanticsNode profile = tester.getSemantics(
        find.byKey(const Key('bottom-nav-item-4')),
      );
      expect(companion.label, '运动搭子');
      expect(companion.flagsCollection.isSelected, Tristate.isFalse);
      expect(plan.label, '训练计划');
      expect(plan.flagsCollection.isSelected, Tristate.isFalse);
      expect(today.label, '今日训练');
      expect(today.flagsCollection.isButton, isTrue);
      expect(today.flagsCollection.isSelected, Tristate.isTrue);
      expect(exercises.label, '动作库');
      expect(exercises.flagsCollection.isSelected, Tristate.isFalse);
      expect(profile.label, '我的');
      expect(profile.flagsCollection.isSelected, Tristate.isFalse);
      expect(
        navigationPainter(tester).selectionWeights,
        <double>[0, 0, 1, 0, 0],
      );
      expect(navigationPainter(tester).discPosition, 2.5);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('今日选中时官方 Flow 图形位于暖黑圆盘之上', (tester) async {
    await pumpApp(tester);

    expect(
      find.byKey(
        const Key('trainmate-bottom-navigation-brandmark-overlay'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const Key('trainmate-bottom-navigation-brandmark-overlay'),
        ),
        matching: find.byKey(const Key('trainmate-brandmark')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('底部导航在 393 宽度保持触控尺寸和胶囊比例', (tester) async {
    await pumpApp(tester);

    final Rect pill = tester.getRect(
      find.byKey(const Key('trainmate-bottom-navigation-pill')),
    );
    final Rect canvas = tester.getRect(
      find.byKey(const Key('trainmate-bottom-navigation')),
    );
    expect(pill.width, 313);
    expect(pill.height, 72);
    expect(canvas.height, 96);
    expect(pill.top - canvas.top, 24);
    expect(TrainFlowTokens.bottomNavigationSelectedSize, 56);
    expect(TrainFlowTokens.bottomNavigationIconSize, 28);

    for (int index = 0; index < 5; index += 1) {
      final Size itemSize = tester.getSize(
        find.byKey(Key('bottom-nav-item-$index')),
      );
      expect(itemSize.width, greaterThanOrEqualTo(48));
      expect(itemSize.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('五栏导航在窄屏、大字体与最大内容宽度下不溢出', (tester) async {
    for (final Size size in const <Size>[
      Size(320, 568),
      Size(430, 932),
    ]) {
      await pumpNavigationOnly(
        tester,
        size: size,
        textScaler: const TextScaler.linear(2),
      );
      final Rect pill = tester.getRect(
        find.byKey(const Key('trainmate-bottom-navigation-pill')),
      );
      expect(pill.width, lessThanOrEqualTo(size.width));
      for (int index = 0; index < 5; index += 1) {
        final Size itemSize = tester.getSize(
          find.byKey(Key('bottom-nav-item-$index')),
        );
        expect(itemSize.width, greaterThanOrEqualTo(48));
        expect(itemSize.height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('五栏路由与计划、今日、动作库上下文能力归属正确', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('bottom-nav-item-0')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.companion);
    expect(bottomNavigation(tester).selectedIndex, 0);

    await tester.tap(find.byKey(const Key('bottom-nav-item-1')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.plans);
    expect(bottomNavigation(tester).selectedIndex, 1);

    await tester.tap(find.byKey(const Key('bottom-nav-item-2')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.dashboard);
    expect(bottomNavigation(tester).selectedIndex, 2);

    await tester.tap(find.byKey(const Key('bottom-nav-item-3')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.exercises);
    expect(bottomNavigation(tester).selectedIndex, 3);

    await tester.tap(find.byKey(const Key('bottom-nav-item-4')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.profile);
    expect(bottomNavigation(tester).selectedIndex, 4);

    for (final String route in <String>[
      AppRoutes.plans,
      AppRoutes.races,
    ]) {
      router.go(route);
      await tester.pumpAndSettle();
      expect(bottomNavigation(tester).selectedIndex, 1, reason: '$route 属于计划');
    }

    router.go(AppRoutes.aiCenter);
    await tester.pumpAndSettle();
    expect(bottomNavigation(tester).selectedIndex, 2, reason: 'AI 属于今日');

    for (final String route in <String>[
      AppRoutes.exercises,
      AppRoutes.motionCheck,
    ]) {
      router.go(route);
      await tester.pumpAndSettle();
      expect(bottomNavigation(tester).selectedIndex, 3, reason: '$route 属于动作库');
    }

    router.go(AppRoutes.pet);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.companion);
    expect(bottomNavigation(tester).selectedIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单圆盘切换在 0、80、160、320ms 连续滑行并交叉淡化', (
    tester,
  ) async {
    await pumpApp(tester);

    TrainMateNavigationBarPainter painter = navigationPainter(tester);
    expect(painter.selectionWeights, <double>[0, 0, 1, 0, 0]);
    expect(painter.discPosition, 2.5);

    await tester.tap(find.byKey(const Key('bottom-nav-item-4')));
    await tester.pump();
    painter = navigationPainter(tester);
    expect(painter.selectionWeights, <double>[0, 0, 1, 0, 0]);
    expect(painter.discPosition, 2.5);

    await tester.pump(const Duration(milliseconds: 80));
    painter = navigationPainter(tester);
    expect(painter.selectionWeights, <double>[0, 0, 1, 0, 0]);
    expect(painter.discPosition, inExclusiveRange(2.5, 4.5));

    await tester.pump(const Duration(milliseconds: 80));
    painter = navigationPainter(tester);
    expect(painter.selectionWeights[2], inExclusiveRange(0, 1));
    expect(painter.selectionWeights[4], inExclusiveRange(0, 1));
    expect(painter.discPosition, inExclusiveRange(2.5, 4.5));

    await tester.pump(const Duration(milliseconds: 160));
    painter = navigationPainter(tester);
    expect(painter.selectionWeights, <double>[0, 0, 0, 0, 1]);
    expect(painter.discPosition, 4.5);
  });

  testWidgets('减少动态效果时五项权重直接显示最终帧', (tester) async {
    await pumpApp(tester, disableAnimations: true);

    await tester.tap(find.byKey(const Key('bottom-nav-item-0')));
    await tester.pump();

    final TrainMateNavigationBarPainter painter = navigationPainter(tester);
    expect(painter.selectionWeights, <double>[1, 0, 0, 0, 0]);
    expect(painter.discPosition, 0.5);
  });
}
