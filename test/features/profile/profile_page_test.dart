import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';
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
      find.byKey(const ValueKey<String>('profile-showcase-stat-capsule')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-showcase-growth-progress')),
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

  testWidgets('我的作为主标签时使用暖黑与青柠训练体系', (tester) async {
    await pumpProfilePage(tester);

    final TrainMateImmersiveHubPage hubPage = tester.widget(
      find.byType(TrainMateImmersiveHubPage),
    );
    expect(hubPage.mode, TrainMateVisualMode.darkTraining);
    final Theme theme = tester.widget(
      find.byKey(const ValueKey<String>('trainmate-immersive-hub-theme')),
    );
    expect(theme.data.brightness, Brightness.dark);
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
