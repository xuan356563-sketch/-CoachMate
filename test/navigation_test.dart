import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/navigation/main_shell.dart';
import 'package:trainflow_ai/app/navigation/trainmate_bottom_navigation.dart';
import 'package:trainflow_ai/app/navigation/trainmate_bottom_navigation_v2.dart';
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

  TrainMateBottomNavigationV2 bottomNavigation(WidgetTester tester) {
    return tester.widget<TrainMateBottomNavigationV2>(
      find.byType(TrainMateBottomNavigationV2),
    );
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
            bottomNavigationBar: TrainMateBottomNavigationV2(
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

  testWidgets('导航使用悬浮 90% 白玻璃胶囊、中央球体与青柠选中态', (tester) async {
    await pumpApp(tester);

    final Container capsule = tester.widget<Container>(
      find.byKey(const Key('trainmate-bottom-navigation-v2-capsule')),
    );
    final BoxDecoration decoration = capsule.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFFFFFFFF));
    expect(find.byKey(const Key('central-hero-orb')), findsOneWidget);

    Icon iconOf(int index) => tester.widget<Icon>(
          find.descendant(
            of: find.byKey(Key('bottom-nav-item-$index')),
            matching: find.byType(Icon),
          ),
        );
    // 默认选中「今日」（index 1）：角落图标青柠，其余暖灰。
    expect(iconOf(1).color, TrainFlowTokens.accent);
    expect(iconOf(0).color, TrainFlowTokens.navigationInactive);
    expect(iconOf(4).color, TrainFlowTokens.navigationInactive);
  });

  testWidgets('五个暖黑主标签使用浅色状态栏图标', (
    tester,
  ) async {
    await pumpApp(tester);

    AnnotatedRegion<SystemUiOverlayStyle> overlay = tester.widget(
      find.byKey(const Key('main-shell-system-ui-style')),
    );
    expect(overlay.value.statusBarIconBrightness, Brightness.dark);

    await tester.tap(find.byKey(const Key('bottom-nav-item-0')));
    await tester.pumpAndSettle();
    overlay = tester.widget(
      find.byKey(const Key('main-shell-system-ui-style')),
    );
    expect(overlay.value.statusBarIconBrightness, Brightness.dark);

    await tester.tap(find.byKey(const Key('bottom-nav-item-1')));
    await tester.pumpAndSettle();
    overlay = tester.widget(
      find.byKey(const Key('main-shell-system-ui-style')),
    );
    expect(overlay.value.statusBarIconBrightness, Brightness.dark);

    await tester.tap(find.byKey(const Key('bottom-nav-item-3')));
    await tester.pumpAndSettle();
    overlay = tester.widget(
      find.byKey(const Key('main-shell-system-ui-style')),
    );
    expect(overlay.value.statusBarIconBrightness, Brightness.dark);

    await tester.tap(find.byKey(const Key('bottom-nav-item-4')));
    await tester.pumpAndSettle();
    overlay = tester.widget(
      find.byKey(const Key('main-shell-system-ui-style')),
    );
    expect(overlay.value.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('底部导航展示训练计划、今日训练、运动搭子、动作库、我的五个可访问入口', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await pumpApp(tester);

      final TrainMateBottomNavigationV2 navigation = bottomNavigation(tester);
      final List<String> labels =
          navigation.items.map((NavigationItem item) => item.label).toList();
      final List<String> displayLabels = navigation.items
          .map((NavigationItem item) => item.displayLabel)
          .toList();
      final List<NavigationItemRole> roles =
          navigation.items.map((NavigationItem item) => item.role).toList();

      expect(labels, <String>['训练计划', '今日训练', '运动搭子', '动作库', '我的']);
      expect(displayLabels, <String>['计划', '今日', '伙伴', '动作库', '我的']);
      expect(
        roles,
        const <NavigationItemRole>[
          NavigationItemRole.plan,
          NavigationItemRole.today,
          NavigationItemRole.partner,
          NavigationItemRole.exercises,
          NavigationItemRole.profile,
        ],
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const Key('global-ai-center-action')), findsNothing);

      for (int index = 0; index < 5; index += 1) {
        expect(find.text(displayLabels[index]), findsOneWidget);
        final Tooltip tooltip = tester.widget<Tooltip>(
          find.descendant(
            of: find.byKey(Key('bottom-nav-item-$index')),
            matching: find.byType(Tooltip),
          ),
        );
        expect(tooltip.message, labels[index]);
      }

      final SemanticsNode plan = tester.getSemantics(
        find.byKey(const Key('bottom-nav-item-0')),
      );
      final SemanticsNode today = tester.getSemantics(
        find.byKey(const Key('bottom-nav-item-1')),
      );
      final SemanticsNode companion = tester.getSemantics(
        find.byKey(const Key('bottom-nav-item-2')),
      );
      final SemanticsNode exercises = tester.getSemantics(
        find.byKey(const Key('bottom-nav-item-3')),
      );
      final SemanticsNode profile = tester.getSemantics(
        find.byKey(const Key('bottom-nav-item-4')),
      );
      expect(plan.label, '训练计划');
      expect(plan.flagsCollection.isSelected, Tristate.isFalse);
      expect(today.label, '今日训练');
      expect(today.flagsCollection.isButton, isTrue);
      expect(today.flagsCollection.isSelected, Tristate.isTrue);
      expect(companion.label, '运动搭子');
      expect(companion.flagsCollection.isSelected, Tristate.isFalse);
      expect(exercises.label, '动作库');
      expect(exercises.flagsCollection.isSelected, Tristate.isFalse);
      expect(profile.label, '我的');
      expect(profile.flagsCollection.isSelected, Tristate.isFalse);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('运动搭子选中时中央球体语义为选中态', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await pumpApp(tester);

      final SemanticsNode idle = tester.getSemantics(
        find.byKey(const Key('bottom-nav-item-2')),
      );
      expect(idle.flagsCollection.isSelected, Tristate.isFalse);

      await tester.tap(find.byKey(const Key('bottom-nav-item-2')));
      await tester.pumpAndSettle();
      final SemanticsNode active = tester.getSemantics(
        find.byKey(const Key('bottom-nav-item-2')),
      );
      expect(active.flagsCollection.isSelected, Tristate.isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('底部导航在 393 宽度保持触控尺寸和胶囊比例', (tester) async {
    await pumpApp(tester);

    final Rect capsule = tester.getRect(
      find.byKey(const Key('trainmate-bottom-navigation-v2-capsule')),
    );
    expect(capsule.width, 361); // 393 - 32
    expect(capsule.height, 76);
    expect(capsule.left, 16);
    expect(find.byKey(const Key('central-hero-orb')), findsOneWidget);

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
      final Rect capsule = tester.getRect(
        find.byKey(const Key('trainmate-bottom-navigation-v2-capsule')),
      );
      expect(capsule.width, lessThanOrEqualTo(size.width));
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

  testWidgets('五栏路由与训练计划、今日、运动搭子、动作库、我的归属正确', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('bottom-nav-item-0')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.plans);
    expect(bottomNavigation(tester).selectedIndex, 0);

    await tester.tap(find.byKey(const Key('bottom-nav-item-1')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.dashboard);
    expect(bottomNavigation(tester).selectedIndex, 1);

    await tester.tap(find.byKey(const Key('bottom-nav-item-2')));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.companion,
    );
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
      expect(bottomNavigation(tester).selectedIndex, 0, reason: '$route 属于计划');
    }

    router.go(AppRoutes.aiCenter);
    await tester.pumpAndSettle();
    expect(bottomNavigation(tester).selectedIndex, 1, reason: 'AI 属于今日');

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
    expect(bottomNavigation(tester).selectedIndex, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('角落 Tab 选中切换后图标变为青柠并保持其他为暖灰', (tester) async {
    await pumpApp(tester);

    Icon iconOf(int index) => tester.widget<Icon>(
          find.descendant(
            of: find.byKey(Key('bottom-nav-item-$index')),
            matching: find.byType(Icon),
          ),
        );
    expect(iconOf(1).color, TrainFlowTokens.accent);
    expect(iconOf(4).color, TrainFlowTokens.navigationInactive);

    await tester.tap(find.byKey(const Key('bottom-nav-item-4')));
    await tester.pump();
    expect(iconOf(4).color, TrainFlowTokens.accent);
    expect(iconOf(1).color, TrainFlowTokens.navigationInactive);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动态效果时角落 Tab 直接显示最终选中态', (tester) async {
    await pumpApp(tester, disableAnimations: true);

    Icon iconOf(int index) => tester.widget<Icon>(
          find.descendant(
            of: find.byKey(Key('bottom-nav-item-$index')),
            matching: find.byType(Icon),
          ),
        );
    expect(iconOf(1).color, TrainFlowTokens.accent);

    await tester.tap(find.byKey(const Key('bottom-nav-item-0')));
    await tester.pump();
    expect(iconOf(0).color, TrainFlowTokens.accent);
    expect(iconOf(1).color, TrainFlowTokens.navigationInactive);
    expect(tester.takeException(), isNull);
  });
}
