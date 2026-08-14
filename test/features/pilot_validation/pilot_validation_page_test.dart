import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/pilot_validation/pilot_validation_page.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('内测页新增匿名测试者并只记录结构化三档状态', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(
            InMemoryLocalStorageService(),
          ),
        ],
        child: const MaterialApp(home: PilotValidationPage()),
      ),
    );
    await tester.pump();

    expect(find.text('复制，人工发送'), findsOneWidget);
    expect(find.textContaining('不做医疗诊断'), findsOneWidget);
    await tester.tap(find.text('新增匿名测试者'));
    await tester.pumpAndSettle();

    expect(find.textContaining('T01'), findsWidgets);
    final Finder progress = find.byKey(
      const ValueKey<String>('pilot-participant-progress-card'),
    );
    await tester.scrollUntilVisible(
      progress,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(progress, findsOneWidget);
    expect(find.text('确认 14 天承诺'), findsOneWidget);
    expect(find.text('押金档（只记线下状态）'), findsOneWidget);
    expect(find.text('第 14 天付费档决定'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
