import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/core/theme/trainflow_tokens.dart';
import 'package:trainflow_ai/core/theme/trainmate_visual_mode.dart';
import 'package:trainflow_ai/core/widgets/trainmate_showcase_widgets.dart';

import '../../support/test_harness.dart';

void main() {
  Future<void> pumpProfilePage(
    WidgetTester tester, {
    Size size = const Size(393, 852),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(TestHarness().buildApp(const TrainFlowApp()));
    router.go(AppRoutes.profile);
    await tester.pumpAndSettle();
    addTearDown(() => router.go(AppRoutes.dashboard));
  }

  testWidgets('我的首屏使用参考图身份指标成长和记录结构', (tester) async {
    await pumpProfilePage(tester);

    expect(
      find.byKey(const ValueKey<String>('profile-showcase-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-showcase-avatar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-showcase-name')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-showcase-goal')),
      findsOneWidget,
    );
    expect(find.byType(TrainMateSceneHero), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('profile-showcase-overview-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-showcase-stat-capsule')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-showcase-growth-progress')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-showcase-xp-rail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-showcase-records')),
      findsOneWidget,
    );

    final Semantics header = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('profile-showcase-header')),
    );
    expect(header.properties.label, contains('个人档案'));
  });

  testWidgets('我的首屏将双指标与成长进度收敛为紧凑档案卡', (tester) async {
    await pumpProfilePage(tester);

    final Finder compactCard =
        find.byKey(const ValueKey<String>('profile-showcase-stat-capsule'));
    final Finder records =
        find.byKey(const ValueKey<String>('profile-showcase-records'));

    expect(compactCard, findsOneWidget);
    expect(records, findsOneWidget);
    expect(find.byType(TrainMateOverviewGrid), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('profile-readiness-metric')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-completed-metric')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-record-achievements')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-record-report')),
      findsOneWidget,
    );
    expect(tester.getRect(records).top, lessThan(560));
    expect(
      find.byKey(const ValueKey<String>('profile-training-profile-card')),
      findsOneWidget,
    );
  });

  testWidgets('我的成长轨道使用真实 XP 的黄紫双色分段', (tester) async {
    await pumpProfilePage(tester);

    final Finder rail =
        find.byKey(const ValueKey<String>('profile-showcase-xp-rail'));
    expect(rail, findsOneWidget);
    expect(
      find.descendant(
        of: rail,
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is ColoredBox && widget.color == TrainFlowTokens.yellow,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: rail,
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is ColoredBox && widget.color == TrainFlowTokens.purple,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('我的作为主标签时使用纸白与深紫行动分区', (tester) async {
    await pumpProfilePage(tester);

    final TrainMateImmersiveHubPage hubPage = tester.widget(
      find.byType(TrainMateImmersiveHubPage),
    );
    expect(hubPage.mode, TrainMateVisualMode.referenceShowcase);
    final Theme theme = tester.widget(
      find.byKey(const ValueKey<String>('trainmate-immersive-hub-theme')),
    );
    expect(theme.data.brightness, Brightness.light);
  });

  testWidgets('我的首屏在窄屏和两倍文字下不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 700),
          textScaler: TextScaler.linear(2),
        ),
        child: TestHarness().buildApp(const TrainFlowApp()),
      ),
    );
    router.go(AppRoutes.profile);
    await tester.pumpAndSettle();
    addTearDown(() => router.go(AppRoutes.dashboard));

    expect(
      find.byKey(const ValueKey<String>('profile-showcase-header')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
