import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/navigation/main_shell.dart';
import 'package:trainflow_ai/app/navigation/trainmate_bottom_navigation_v2.dart';
import 'package:trainflow_ai/core/theme/tdesign_theme.dart';
import 'package:trainflow_ai/core/theme/trainflow_tokens.dart';

void main() {
  void configureView(
    WidgetTester tester, {
    required Size size,
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget navigation({
    required int selectedIndex,
    required ValueChanged<int> onDestinationSelected,
  }) {
    return TrainMateBottomNavigationV2(
      items: bottomNavItems,
      selectedIndex: selectedIndex,
      surfaceColor: TrainFlowTokens.darkTrainingSurface,
      animationDuration: Duration.zero,
      onDestinationSelected: onDestinationSelected,
    );
  }

  testWidgets('5 tab 完整视觉基线（含中央球体）', (WidgetTester tester) async {
    final Size viewSize = Size(393, 120.0 * bottomNavItems.length);
    configureView(tester, size: viewSize);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TDesignTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData(
            size: viewSize,
            disableAnimations: true,
          ),
          child: ColoredBox(
            color: TrainFlowTokens.darkTrainingSurface,
            child: Column(
              children: <Widget>[
                for (int index = 0; index < bottomNavItems.length; index += 1)
                  SizedBox(
                    height: 120,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: navigation(
                        selectedIndex: index,
                        onDestinationSelected: (_) {},
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('baselines/navigation-all-selected-states.png'),
    );
  });

  testWidgets('中央球体选中态视觉基线', (WidgetTester tester) async {
    configureView(tester, size: const Size(393, 124));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TDesignTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(393, 124),
            disableAnimations: true,
          ),
          child: Scaffold(
            backgroundColor: TrainFlowTokens.darkTrainingSurface,
            bottomNavigationBar: navigation(
              selectedIndex: 2,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('baselines/navigation-orb-active.png'),
    );
  });
}
