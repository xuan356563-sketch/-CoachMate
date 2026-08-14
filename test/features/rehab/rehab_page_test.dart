import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/rehab/rehab_page.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('康复页首屏显示专属医疗边界且不重复通用免责', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(
            InMemoryLocalStorageService(),
          ),
        ],
        child: const MaterialApp(home: RehabPage()),
      ),
    );
    await tester.pump();

    final Finder card =
        find.byKey(const ValueKey<String>('rehab-medical-boundary-card'));
    expect(card, findsOneWidget);
    expect(tester.getTopLeft(card).dy, lessThan(852));
    expect(find.textContaining('不用于诊断、治疗'), findsOneWidget);
    expect(find.textContaining('保守提醒阈值，不是医学诊断标准'), findsOneWidget);
    expect(find.textContaining('免责声明：本系统提供训练建议'), findsNothing);
  });
}
