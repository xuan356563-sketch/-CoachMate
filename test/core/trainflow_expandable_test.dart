import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/core/widgets/trainflow_widgets.dart';

void main() {
  testWidgets('折叠组件默认不构建详情并可切换展开状态', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrainFlowExpandable(
              key: ValueKey<String>('test-expandable'),
              title: '训练详情',
              summary: '五步训练摘要',
              child: Text('完整训练内容'),
            ),
          ),
        ),
      );

      expect(find.text('完整训练内容'), findsNothing);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('训练详情，五步训练摘要'),
        ),
        matchesSemantics(
          label: '训练详情，五步训练摘要',
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: false,
        ),
      );

      await tester.tap(find.text('训练详情'));
      await tester.pumpAndSettle();

      expect(find.text('完整训练内容'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('训练详情，五步训练摘要'),
        ),
        matchesSemantics(
          label: '训练详情，五步训练摘要',
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: true,
        ),
      );

      await tester.tap(find.text('训练详情'));
      await tester.pumpAndSettle();
      expect(find.text('完整训练内容'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('系统关闭动画时折叠状态立即切换', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: TrainFlowExpandable(
              title: '教练说明',
              summary: '两行摘要',
              child: Text('完整说明'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('教练说明'));
    await tester.pump();

    expect(find.text('完整说明'), findsOneWidget);
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).duration,
      Duration.zero,
    );
    expect(find.byType(AnimatedSize), findsNothing);
  });

  testWidgets('不可点击卡片不会合并内部折叠按钮的语义', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrainFlowCard(
              child: Column(
                children: [
                  Text('成长经验 0/500'),
                  TrainFlowExpandable(
                    title: '查看详情',
                    summary: '今日任务 0/3',
                    child: Text('计算依据'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final Finder expandable = find.bySemanticsLabel(
        '查看详情，今日任务 0/3',
      );
      expect(expandable, findsOneWidget);
      expect(
        tester.getSemantics(expandable),
        matchesSemantics(
          label: '查看详情，今日任务 0/3',
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: false,
        ),
      );

      await tester.tap(expandable);
      await tester.pumpAndSettle();
      expect(find.text('计算依据'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
