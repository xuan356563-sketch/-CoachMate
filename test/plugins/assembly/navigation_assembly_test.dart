import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/app/navigation/main_shell.dart';
import 'package:trainflow_ai/app/navigation/trainmate_bottom_navigation_v2.dart';
import 'package:trainflow_ai/plugins/application/sport_contribution_label.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';

void main() {
  testWidgets('导航数量变化且选中下标不变时重置胶囊，点击使用当前列表', (tester) async {
    var selected = -1;
    Widget nav(List<int> indices) => MaterialApp(
        home: Scaffold(
            bottomNavigationBar: TrainMateBottomNavigationV2(
                items: [for (final i in indices) bottomNavItems[i]],
                selectedIndex: 1,
                animationDuration: const Duration(milliseconds: 300),
                onDestinationSelected: (i) => selected = i)));
    await tester.pumpWidget(nav([0, 1, 2, 3, 4]));
    await tester.pumpWidget(nav([1, 4]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('计划'), findsNothing);
    await tester.tap(find.byKey(const Key('bottom-nav-item-0')));
    expect(selected, 0);
    await tester.pumpWidget(nav([1, 2, 4]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('伙伴'), findsOneWidget);
  });
  testWidgets('跟练与周报只消费当前运动注册贡献，停用后撤下', (tester) async {
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    await tester.pumpWidget(ProviderScope(
        overrides: [pluginRuntimeProvider.overrideWith((ref) => runtime)],
        child: const MaterialApp(
            home: Scaffold(
                body: Column(children: [
          SportContributionLabel(sport: MainSport.marathon),
          SportContributionLabel(sport: MainSport.marathon, report: true),
        ])))));
    expect(find.text('马拉松跟练'), findsOneWidget);
    expect(find.text('马拉松周报'), findsOneWidget);
    await runtime.disable('sport.marathon');
    await tester.pump();
    expect(find.text('马拉松跟练'), findsNothing);
    expect(find.text('马拉松周报'), findsNothing);
    await runtime.registry.shutdown();
  });
}
