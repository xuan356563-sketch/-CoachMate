import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/application/sport_contribution_label.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/sports/marathon_plugin.dart';
import 'package:trainflow_ai/plugins/sports/sport_display_capabilities.dart';
import 'package:trainflow_ai/plugins/sports/sport_plan_strategy.dart';

void main() {
  testWidgets('跟练和周报读取类型化展示声明，并随实际能力撤回', (tester) async {
    final strategy = _DeclaredDisplayMarathon();
    final runtime = PluginRuntime(
        PluginRegistry(plugins: [MarathonPlugin(strategy: strategy)]));
    await runtime.initialize();
    await tester.pumpWidget(ProviderScope(
      overrides: [pluginRuntimeProvider.overrideWith((ref) => runtime)],
      child: MaterialApp(
          home: Scaffold(
              body: Column(children: [
        SportContributionLabel(sport: strategy.definition.sport),
        SportContributionLabel(sport: strategy.definition.sport, report: true),
      ]))),
    ));
    expect(find.text('马拉松节奏跟练'), findsOneWidget);
    expect(find.text('马拉松训练回顾'), findsOneWidget);
    await runtime.disable('sport.marathon');
    await tester.pump();
    expect(find.text('马拉松节奏跟练'), findsNothing);
    expect(find.text('马拉松训练回顾'), findsNothing);
    await runtime.shutdown();
  });
}

class _DeclaredDisplayMarathon extends MarathonPlanStrategy {
  @override
  SportDefinition get definition {
    final original = super.definition;
    return SportDefinition(
      sport: original.sport,
      pluginRef: original.pluginRef,
      cloudSupported: original.cloudSupported,
      specialtyDisplaySupported: original.specialtyDisplaySupported,
      display: const SportDisplayCapabilities(
        workout: CardContribution(
            id: 'sport.marathon.guided_session',
            label: '马拉松节奏跟练',
            slot: 'workout_player'),
        weeklyReport: ReportContribution(
            id: 'sport.marathon.summary',
            label: '马拉松训练回顾',
            reportId: 'weekly_report'),
      ),
    );
  }
}
