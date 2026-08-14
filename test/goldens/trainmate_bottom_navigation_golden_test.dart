import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/navigation/main_shell.dart';
import 'package:trainflow_ai/app/navigation/trainmate_bottom_navigation.dart';
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
    return TrainMateBottomNavigation(
      items: bottomNavItems,
      selectedIndex: selectedIndex,
      surfaceColor: TrainFlowTokens.navigationSurface,
      animationDuration: TrainFlowMotion.selection,
      onDestinationSelected: onDestinationSelected,
    );
  }

  testWidgets('完整选中状态视觉基线', (WidgetTester tester) async {
    final Size viewSize = Size(393, 110.0 * bottomNavItems.length);
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
            color: TrainFlowTokens.navigationSurface,
            child: Column(
              children: <Widget>[
                for (int index = 0; index < bottomNavItems.length; index += 1)
                  SizedBox(
                    height: 110,
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

  testWidgets('单圆槽连续滑行 160ms 的视觉基线', (WidgetTester tester) async {
    configureView(tester, size: const Size(393, 124));
    final ValueNotifier<int> selectedIndex = ValueNotifier<int>(0);
    addTearDown(selectedIndex.dispose);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TDesignTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(393, 124)),
          child: Scaffold(
            backgroundColor: TrainFlowTokens.navigationSurface,
            bottomNavigationBar: ValueListenableBuilder<int>(
              valueListenable: selectedIndex,
              builder: (BuildContext context, int value, Widget? child) {
                return navigation(
                  selectedIndex: value,
                  onDestinationSelected: (int index) {
                    selectedIndex.value = index;
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('bottom-nav-item-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('baselines/navigation-liquid-handoff-midpoint.png'),
    );
  });
}
