import 'local_plan_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/user_profile.dart';
import '../../plugins/application/plugin_runtime_provider.dart';
import '../../plugins/features/resource_library_plugin.dart';
import 'resource_catalog.dart';
import 'resource_library_controller.dart';
import 'assessment_record.dart';

class ResourceLibraryPage extends ConsumerStatefulWidget {
  const ResourceLibraryPage({super.key});
  @override
  ConsumerState<ResourceLibraryPage> createState() =>
      _ResourceLibraryPageState();
}

class _ResourceLibraryPageState extends ConsumerState<ResourceLibraryPage> {
  MainSport? _sport;
  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(resourceCatalogProvider);
    if (catalog == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('运动资源库')),
          body: const Center(child: Text('请先启用运动资源库。')));
    }
    final items = catalog.list(sport: _sport);
    return Scaffold(
        appBar: AppBar(title: const Text('运动资源库')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('基础评估记录训练事实；计划模板由现有运动策略生成，审核后由你确认启用。'),
          Wrap(spacing: 8, children: [
            ChoiceChip(
                label: const Text('全部'),
                selected: _sport == null,
                onSelected: (_) => setState(() => _sport = null)),
            for (final sport in [
              MainSport.marathon,
              MainSport.trailRunning,
              MainSport.strength,
              MainSport.hyrox
            ])
              ChoiceChip(
                  label: Text(sport.label),
                  selected: _sport == sport,
                  onSelected: (_) => setState(() => _sport = sport))
          ]),
          for (final assessment in [true, false]) ...[
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(assessment ? '基础评估' : '训练计划',
                    style: Theme.of(context).textTheme.titleLarge)),
            for (final resource
                in items.where((r) => (r is AssessmentGuide) == assessment))
              Card(
                  child: ListTile(
                      title: Text(resource.title),
                      subtitle: Text(resource.scope),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          context.push('/resources/${resource.ref.id}'))),
          ],
          TextButton(
              onPressed: () => context.push('/history/assessments'),
              child: const Text('查看评估历史')),
        ]));
  }
}

class ResourceDetailPage extends ConsumerWidget {
  const ResourceDetailPage({super.key, required this.resourceId});
  final String resourceId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SportResource resource;
    try {
      resource =
          (ref.watch(resourceCatalogProvider) ?? (throw StateError('资源库已停用')))
              .require(resourceId);
    } catch (_) {
      return Scaffold(
          appBar: AppBar(title: const Text('资源详情')),
          body: const Center(child: Text('资源不存在、尚未审核或已停用。')));
    }
    final runtime = ref.watch(pluginRuntimeProvider);
    final writable = runtime.isWritable(ResourceLibraryPlugin.id) &&
        runtime.isWritable(resource.ownerPluginId);
    return Scaffold(
        appBar: AppBar(title: Text(resource.title)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(resource.scope),
          const SizedBox(height: 12),
          Text('来源：${resource.source}'),
          Text('版本：${resource.ref.version} · 内部内容已审核'),
          for (final instruction in resource.instructions)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(instruction)),
          Wrap(children: [
            if (runtime.isWritable('feature.exercise_library'))
              TextButton(
                  onPressed: () => context.push('/exercises'),
                  child: const Text('相关动作库')),
            if (runtime.isWritable('feature.knowledge_library'))
              TextButton(
                  onPressed: () => context.push('/knowledge'),
                  child: const Text('知识来源'))
          ]),
          if (!writable) const Text('请先在运动与功能中启用资源库及对应运动。'),
          if (resource is AssessmentGuide && writable)
            AssessmentForm(
                key: ValueKey(
                    resource.ref.fingerprint + runtime.accountEpoch.toString()),
                guide: resource),
          if (resource is AssessmentGuide && writable)
            AssessmentRecordsList(resourceId: resource.ref.id),
          if (resource is TrainingPlanResource)
            LocalPlanPanel(resource: resource),
        ]));
  }
}

class AssessmentRecordsList extends ConsumerWidget {
  const AssessmentRecordsList({super.key, required this.resourceId});
  final String resourceId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(assessmentControllerProvider);
    List<AssessmentRecord> records;
    try {
      records = ref
          .watch(assessmentRecordRepositoryProvider)
          .list()
          .where((r) => r.resourceRef.id == resourceId)
          .toList();
    } catch (_) {
      return const Text('历史记录格式不受支持，请先复核本机数据。');
    }
    return Column(children: [
      for (final record in records)
        ListTile(
            title: Text('已保存：${record.assessedAt.toString().substring(0, 10)}'),
            trailing: IconButton(
                tooltip: '删除这份评估',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                              title: const Text('删除这份评估？'),
                              content: const Text('只删除选中的评估记录。'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('取消')),
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('删除'))
                              ]));
                  if (confirmed != true || !context.mounted) return;
                  try {
                    await ref
                        .read(assessmentControllerProvider.notifier)
                        .delete(record);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('删除未完成：$e')));
                    }
                  }
                }))
    ]);
  }
}

class AssessmentForm extends ConsumerStatefulWidget {
  const AssessmentForm({super.key, required this.guide});
  final AssessmentGuide guide;
  @override
  ConsumerState<AssessmentForm> createState() => _AssessmentFormState();
}

class _AssessmentFormState extends ConsumerState<AssessmentForm> {
  final _values = <String, String>{};
  DateTime _date = DateTime.now();
  AssessmentRecord? _preview;
  bool _busy = false, _saved = false;
  String? _error;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextButton(
            onPressed: _busy || _preview != null
                ? null
                : () async {
                    final date = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now());
                    if (mounted && date != null) setState(() => _date = date);
                  },
            child: Text('评估日期：${_date.toString().substring(0, 10)}')),
        if (_preview == null) ...[
          for (final field in widget.guide.fields)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                    key: ValueKey(field.id),
                    decoration: InputDecoration(
                        labelText: field.label +
                            (field.unit.isEmpty ? '' : '（${field.unit}）'),
                        hintText: '未知可留空'),
                    keyboardType: field.numeric
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    onChanged: (v) => _values[field.id] = v)),
          FilledButton(
              onPressed: () {
                try {
                  final service = ref
                      .read(pluginRuntimeProvider)
                      .registry
                      .readCapability<AssessmentService>(
                          ResourceLibraryPlugin.assessment);
                  if (service == null) throw StateError('评估技能不可用');
                  final record = service.record(
                      guide: widget.guide,
                      id: newResourceRecordId(),
                      assessedAt: _date,
                      values: _values);
                  setState(() {
                    _preview = record;
                    _error = null;
                  });
                } catch (e) {
                  setState(() => _error = e.toString());
                }
              },
              child: const Text('查看事实汇总')),
        ] else ...[
          AssessmentRecordView(record: _preview!),
          FilledButton(
              onPressed: _busy || _saved
                  ? null
                  : () async {
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      try {
                        await ref
                            .read(assessmentControllerProvider.notifier)
                            .save(_preview!);
                        if (mounted) setState(() => _saved = true);
                      } catch (e) {
                        if (mounted) {
                          setState(() => _error = '保存未完成，可保留结果重试：$e');
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: Text(_saved
                  ? '已保存'
                  : _busy
                      ? '正在保存'
                      : '保存评估记录')),
          TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _preview = null;
                        _saved = false;
                        _values.clear();
                      }),
              child: const Text('重新填写一份')),
        ],
        if (_error != null) Text(_error!),
      ]);
}

class AssessmentRecordView extends StatelessWidget {
  const AssessmentRecordView({super.key, required this.record});
  final AssessmentRecord record;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('手动记录 · 事实汇总，不代表能力等级'),
        Text(record.assessedAt.toString().substring(0, 10)),
        for (final field in record.fields)
          if (record.values[field.id]?.isNotEmpty ?? false)
            Text(
                '${field.label}：${record.values[field.id]!}${field.unit.isEmpty ? '' : ' ${field.unit}'}'),
        Text('记录来源版本：${record.resourceRef.version}'),
      ]));
}
