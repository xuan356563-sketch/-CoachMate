import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../plugins/history/core_history.dart';
import '../../plugins/application/plugin_runtime_provider.dart';
import '../motion_check/running/running_form_assessment_service.dart';
import '../motion_check/running/running_report_view.dart';

/// 历史入口不创建视频控制器，不依赖动作插件启用状态。
class RunningHistoryPage extends ConsumerWidget {
  const RunningHistoryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(pluginRuntimeProvider.select((r) => r.accountEpoch));
    List<RunningFormReport> reports;
    try {
      reports = ref.watch(coreHistoryProvider).listRunningReports();
    } catch (_) {
      return Scaffold(
          appBar: AppBar(title: const Text('跑姿报告历史')),
          body: const Center(child: Text('无法读取报告，账号可能已变化或本地格式不受支持；请重新打开。')));
    }
    return Scaffold(
        appBar: AppBar(title: const Text('跑姿报告历史')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('仅读取本机结构化报告，原视频未保存。'),
          if (reports.isEmpty) const Text('还没有已保存的跑姿报告。'),
          for (final report in reports)
            ExpansionTile(
                key: ValueKey(report.id),
                title: Text(
                    '${report.createdAt.toLocal().toString().substring(0, 16)} · ${report.side}'),
                children: [RunningReportView(report: report)]),
        ]));
  }
}
