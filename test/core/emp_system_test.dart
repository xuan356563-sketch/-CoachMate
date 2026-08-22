import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/core/theme/trainflow_tokens.dart';
import 'package:trainflow_ai/core/widgets/emp_system.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          backgroundColor: TrainFlowTokens.darkTrainingSurface,
          body: Center(child: child),
        ),
      );

  testWidgets('EmpStatPanel 展示大数字/单位/副值与分段进度', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      const EmpStatPanel(
        value: '26480',
        unit: '步',
        secondary: '39%',
        timer: '01:15:16',
        progress: 0.39,
      ),
    ));

    expect(find.text('26480'), findsOneWidget);
    expect(find.text('步'), findsOneWidget);
    expect(find.text('39%  ·  01:15:16'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // 语义标签汇总数值与单位。
    final SemanticsNode node = tester.getSemantics(
      find.byType(EmpStatPanel),
    );
    expect(node.label, contains('26480'));
    expect(node.label, contains('步'));
  });

  testWidgets('EmpProgressRing 显示进度与语义值', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      const EmpProgressRing(progress: 0.5, label: '50%'),
    ));

    expect(find.text('50%'), findsOneWidget);
    final SemanticsNode node = tester.getSemantics(
      find.byType(EmpProgressRing),
    );
    expect(node.label, contains('50%'));
    expect(node.value, '50');
  });

  testWidgets('EmpEmptyState 展示标题/说明/操作按钮', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      EmpEmptyState(
        title: '还没有挑战',
        description: '完成一次训练后会出现。',
        actionLabel: '去训练',
        onAction: () {},
      ),
    ));

    expect(find.text('还没有挑战'), findsOneWidget);
    expect(find.text('完成一次训练后会出现。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '去训练'), findsOneWidget);
  });

  testWidgets('EmpBadge 多色语义：品牌深底白字 / 黄底深字', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      const Column(
        children: <Widget>[
          EmpBadge(label: '进行中', tone: EmpBadgeTone.brand),
          EmpBadge(label: '已完赛', tone: EmpBadgeTone.mint),
        ],
      ),
    ));

    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('已完赛'), findsOneWidget);
    // 品牌徽章：深紫底 + 白字；薄荷绿徽章：薄荷绿底 + 深字。
    expect(find.text('进行中'), findsOneWidget);
  });

  testWidgets('EmpIllustrationCard 展示标题/副标题与动作按钮', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(
      EmpIllustrationCard(
        title: '下一场挑战',
        subtitle: '距比赛 3 天',
        actionLabel: '查看排期',
        onAction: () {},
      ),
    ));

    expect(find.text('下一场挑战'), findsOneWidget);
    expect(find.text('距比赛 3 天'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '查看排期'), findsOneWidget);
  });

  testWidgets('EmpSkeleton 在减少动效下静态且不报错', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: wrap(const EmpSkeleton(width: 120, height: 16)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
