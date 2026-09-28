import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../plugins/history/core_history.dart';
import '../../plugins/application/plugin_runtime_provider.dart';
import '../resource_library/assessment_record.dart';
import '../resource_library/resource_library_page.dart';

class AssessmentHistoryPage extends ConsumerWidget {
  const AssessmentHistoryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(pluginRuntimeProvider.select((r) => r.accountEpoch));
    List<AssessmentRecord> records;
    try {
      records = ref.watch(coreHistoryProvider).listAssessments();
    } catch (_) {
      return Scaffold(
          appBar: AppBar(title: const Text('基础评估历史')),
          body: const Center(child: Text('无法读取评估记录，请重新打开；原始数据已保留。')));
    }
    return Scaffold(
        appBar: AppBar(title: const Text('基础评估历史')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('仅查看已保存的手动评估，资源停用不影响历史读取。'),
          if (records.isEmpty) const Text('还没有已保存的评估记录。'),
          for (final record in records)
            ExpansionTile(
                key: ValueKey(record.id),
                title: Text(record.title),
                subtitle: Text(record.assessedAt.toString().substring(0, 10)),
                children: [AssessmentRecordView(record: record)]),
        ]));
  }
}
