import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/core/design_system/trainmate_cards.dart';
import 'package:trainflow_ai/core/design_system/trainmate_date_selector.dart';
import 'package:trainflow_ai/core/design_system/trainmate_design_showcase.dart';
import 'package:trainflow_ai/core/design_system/trainmate_primitives.dart';
import 'package:trainflow_ai/core/design_system/trainmate_states.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('TrainMateButton', () {
    testWidgets('渲染标签并在点击时触发回调', (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(_wrap(
        TrainMateButton(label: '开始', onPressed: () => tapped = true),
      ));
      expect(find.text('开始'), findsOneWidget);
      await tester.tap(find.text('开始'));
      expect(tapped, isTrue);
    });

    testWidgets('禁用状态不触发回调', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const TrainMateButton(label: '禁用', onPressed: null)));
      final FilledButton button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('loading 状态渲染进度指示器并禁用', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        TrainMateButton(label: '加载', loading: true, onPressed: () {}),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final FilledButton button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  group('TrainMateIconButton', () {
    testWidgets('带可访问名称', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const TrainMateIconButton(icon: Icons.search, tooltip: '搜索'),
      ));
      expect(find.byTooltip('搜索'), findsOneWidget);
    });
  });

  group('TrainMateBadge', () {
    testWidgets('StreakBadge 显示连续天数', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const TrainMateStreakBadge(days: 7)));
      expect(find.text('连续 7 天'), findsOneWidget);
    });

    testWidgets('LevelBadge 显示等级', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const TrainMateLevelBadge(level: 12)));
      expect(find.text('Lv.12'), findsOneWidget);
    });

    testWidgets('RewardBadge 显示奖励文案', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const TrainMateRewardBadge(label: '+50 积分')));
      expect(find.text('+50 积分'), findsOneWidget);
    });
  });

  group('TrainMateProgressRing / Bar', () {
    testWidgets('环形进度带语义值', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const TrainMateProgressRing(value: 0.42, semanticLabel: '完成度'),
      ));
      expect(find.byType(TrainMateProgressRing), findsOneWidget);
      final Semantics semantics = tester.widget<Semantics>(
        find.descendant(
          of: find.byType(TrainMateProgressRing),
          matching: find.byType(Semantics),
        ).first,
      );
      expect(semantics.properties.label, '完成度');
    });

    testWidgets('线性进度条渲染', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const TrainMateProgressBar(value: 0.62)));
      expect(find.byType(TrainMateProgressBar), findsOneWidget);
    });
  });

  group('TrainMateStatCard', () {
    testWidgets('渲染数值与单位', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const TrainMateStatCard(
        label: '今日时长',
        value: '42',
        unit: '分钟',
        icon: Icons.timer_outlined,
      )));
      expect(find.text('42'), findsOneWidget);
      expect(find.text('分钟'), findsOneWidget);
      expect(find.text('今日时长'), findsOneWidget);
    });

    testWidgets('loading 状态渲染骨架屏', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const TrainMateStatCard(
        label: '今日时长',
        value: '--',
        icon: Icons.timer_outlined,
        loading: true,
      )));
      expect(find.byType(TrainMateSkeleton), findsWidgets);
      expect(find.text('今日时长'), findsNothing);
    });
  });

  group('TrainMateChallengeCard', () {
    testWidgets('进行中状态显示「继续挑战」', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(TrainMateChallengeCard(
        title: '30 天晨跑挑战',
        subtitle: '每天 20 分钟',
        status: TrainMateChallengeStatus.active,
        progress: 0.4,
        icon: Icons.directions_run_rounded,
      )));
      expect(find.text('继续挑战'), findsOneWidget);
    });

    testWidgets('已过期状态按钮禁用', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(TrainMateChallengeCard(
        title: '过期挑战',
        subtitle: '活动已结束',
        status: TrainMateChallengeStatus.expired,
        progress: 0.5,
        icon: Icons.directions_bike_rounded,
      )));
      expect(find.text('已结束'), findsOneWidget);
      final FilledButton button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('锁定状态按钮禁用', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(TrainMateChallengeCard(
        title: '锁定挑战',
        subtitle: '需解锁',
        status: TrainMateChallengeStatus.locked,
        progress: 0,
        icon: Icons.lock_outline_rounded,
      )));
      expect(find.text('解锁条件'), findsOneWidget);
      final FilledButton button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('可参加状态点击触发操作', (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(_wrap(TrainMateChallengeCard(
        title: '新挑战',
        subtitle: '快来参加',
        status: TrainMateChallengeStatus.available,
        progress: 0,
        icon: Icons.directions_run_rounded,
        onAction: () => tapped = true,
      )));
      await tester.tap(find.text('立即参加'));
      expect(tapped, isTrue);
    });
  });

  group('TrainMateSkeleton', () {
    testWidgets('骨架屏块渲染', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const TrainMateSkeleton(height: 16)));
      expect(find.byType(TrainMateSkeleton), findsOneWidget);
    });

    testWidgets('骨架屏列表行渲染', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const TrainMateSkeletonListTile()));
      expect(find.byType(TrainMateSkeletonListTile), findsOneWidget);
    });
  });

  group('TrainMateEmptyState / ErrorState', () {
    testWidgets('空状态渲染标题与操作', (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(_wrap(TrainMateEmptyState(
        title: '还没有参加挑战',
        message: '挑选一个喜欢的目标。',
        actionLabel: '浏览挑战',
        onAction: () => tapped = true,
      )));
      expect(find.text('还没有参加挑战'), findsOneWidget);
      await tester.tap(find.text('浏览挑战'));
      expect(tapped, isTrue);
    });

    testWidgets('错误状态重试触发回调', (WidgetTester tester) async {
      bool retried = false;
      await tester.pumpWidget(_wrap(TrainMateErrorState(
        message: '网络失败',
        onRetry: () => retried = true,
      )));
      expect(find.text('加载失败'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, isTrue);
    });
  });

  group('TrainMateToast', () {
    testWidgets('渲染提示文案', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const TrainMateToast(message: '已保存', tone: TrainMateToastTone.success),
      ));
      expect(find.text('已保存'), findsOneWidget);
    });
  });

  group('TrainMateDateSelector', () {
    testWidgets('渲染日期并触发选择回调', (WidgetTester tester) async {
      final DateTime now = DateTime.now();
      final DateTime day = DateTime(now.year, now.month, now.day);
      DateTime? picked;
      await tester.pumpWidget(_wrap(TrainMateDateSelector(
        dates: List<DateTime>.generate(5, (int i) => day.add(Duration(days: i))),
        selected: day,
        onChanged: (DateTime d) => picked = d,
      )));
      expect(find.text('今'), findsOneWidget);
      // 点击第二天（day+1）。
      await tester.tap(find.text('${day.add(const Duration(days: 1)).day}').first);
      expect(picked, day.add(const Duration(days: 1)));
    });
  });

  group('TrainMateDesignShowcase', () {
    testWidgets('完整组件示例页可渲染', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: TrainMateDesignShowcase()));
      await tester.pump();
      expect(find.byType(TrainMateDesignShowcase), findsOneWidget);
      expect(find.text('TrainMate 基础组件'), findsOneWidget);
    });
  });
}
