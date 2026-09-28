import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_profile.dart';
import '../core/plugin_core.dart';
import 'plugin_runtime_provider.dart';

/// 只展示当前计划实际运动的已注册贡献，不为全部运动重复生成报告。
class SportContributionLabel extends ConsumerWidget {
  const SportContributionLabel(
      {super.key, required this.sport, this.report = false});
  final MainSport sport;
  final bool report;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(pluginRuntimeProvider);
    final display = runtime.sportDirectory.displayFor(sport);
    if (display == null) return const SizedBox.shrink();
    final labels = runtime.contributions.where((item) => report
        ? item is ReportContribution &&
            item.id == display.weeklyReport.id &&
            item.reportId == display.weeklyReport.reportId
        : item is CardContribution &&
            item.id == display.workout.id &&
            item.slot == display.workout.slot);
    if (labels.isEmpty) return const SizedBox.shrink();
    return Align(
        alignment: Alignment.centerLeft,
        child: Chip(label: Text(labels.single.label)));
  }
}
