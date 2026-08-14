import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/profile/profile_page.dart';

import '../../support/test_harness.dart';

void main() {
  testWidgets('Apple 健康按训练分析身体三阶段说明用途并避免宣称已授权', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TestHarness().buildApp(
        const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, '同步训练记录'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, '读取进步分析数据'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, '开启身体追踪'),
      findsOneWidget,
    );
    expect(find.textContaining('训练、距离和能量'), findsOneWidget);
    expect(find.textContaining('心率、静息心率、HRV、VO2max 和路线'), findsOneWidget);
    expect(find.textContaining('体重和体脂'), findsOneWidget);
    expect(find.text('删除本地健康数据'), findsOneWidget);
    expect(find.text('已授权'), findsNothing);
    expect(find.text('邮箱账号'), findsOneWidget);
    expect(
      find.text('t***@example.com · 训练数据保留在本机'),
      findsOneWidget,
    );
  });
}
