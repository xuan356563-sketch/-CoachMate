import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/weekly_report/weekly_report_page.dart';

import '../../support/test_harness.dart';

void main() {
  testWidgets('周报允许跳过评分并保存本地 GROW 方向', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TestHarness().buildApp(
        const MaterialApp(home: WeeklyReportPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('weekly-psych-check-in-card')),
      findsOneWidget,
    );
    expect(find.textContaining('未选择会保存为未采集'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('weekly-psych-save')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('周报状态已保存在本地'), findsOneWidget);
    expect(find.text('下周方向'), findsOneWidget);
    final Finder weeklyOptions = find.byWidgetPredicate((Widget widget) {
      final Key? key = widget.key;
      return widget is ChoiceChip &&
          key is ValueKey<String> &&
          key.value.startsWith('weekly-option-');
    });
    expect(weeklyOptions, findsWidgets);

    await tester.tap(weeklyOptions.first);
    await tester.pumpAndSettle();

    expect(find.text('已保存你选择的下周方向。'), findsOneWidget);
  });

  testWidgets('周期报告页可切换到上一完整自然月', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TestHarness().buildApp(
        const MaterialApp(home: WeeklyReportPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('周报'), findsOneWidget);
    await tester.tap(find.text('月报'));
    await tester.pumpAndSettle();

    expect(find.text('本地确定性月报'), findsOneWidget);
    expect(find.text('核心能力变化'), findsOneWidget);
    expect(find.text('身体变化'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('weekly-psych-check-in-card')),
      findsNothing,
    );
  });
}
