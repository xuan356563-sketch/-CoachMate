import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/first_run_onboarding/presentation/first_run_pages.dart';

void main() {
  testWidgets('Android只显示浏览模式，不显示iOS购买操作', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: MembershipWelcomePage()),
        ),
      );

      expect(find.text('暂不订阅，进入浏览模式'), findsOneWidget);
      expect(find.text('恢复购买'), findsNothing);
      expect(find.text('管理订阅'), findsNothing);
      expect(find.textContaining('以App Store 实际价格/月订阅'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS显示恢复购买与管理订阅入口', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: MembershipWelcomePage()),
        ),
      );

      expect(find.text('恢复购买'), findsOneWidget);
      expect(find.text('管理订阅'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
