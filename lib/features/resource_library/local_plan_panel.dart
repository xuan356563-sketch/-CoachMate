import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/seed/seed_exercises.dart';
import '../../plugins/application/plugin_runtime_provider.dart';
import '../../plugins/features/resource_library_plugin.dart';
import 'local_plan_controller.dart';
import 'resource_catalog.dart';

class LocalPlanPanel extends ConsumerWidget {
  const LocalPlanPanel({super.key, required this.resource});
  final TrainingPlanResource resource;
  Future<bool> _confirm(
          BuildContext context, String title, String body) async =>
      await showDialog<bool>(
          context: context,
          builder: (ctx) =>
              AlertDialog(title: Text(title), content: Text(body), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('确认'))
              ])) ??
      false;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(localPlanControllerProvider);
    final runtime = ref.watch(pluginRuntimeProvider);
    final writable = runtime.isWritable('feature.training_plan') &&
        runtime.isWritable(ResourceLibraryPlugin.id) &&
        runtime.isWritable(resource.ownerPluginId);
    final draft =
        state.draft?.resourceRef.id == resource.ref.id ? state.draft : null;
    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(children: [
        TextButton(
            onPressed: () => context.push('/onboarding'),
            child: const Text('核对个人档案')),
        TextButton(
            onPressed: () => context.push('/plans/generate'),
            child: const Text('训练前检查'))
      ]),
      if (!writable) const Text('请先启用训练计划、资源库与对应运动。'),
      FilledButton(
          onPressed: !writable || state.busy
              ? null
              : () async {
                  final prior = state.draft;
                  if (prior != null &&
                      !await _confirm(
                          context, '替换已有本地草稿？', '新的候选计划将替换本机待确认草稿，当前有效计划保持不变。')) {
                    return;
                  }
                  if (!context.mounted) return;
                  await run(() => ref
                      .read(localPlanControllerProvider.notifier)
                      .createLocalDraft(resource.ref.id,
                          replaceDraftId: prior?.id));
                },
          child: Text(state.busy ? '正在处理' : '生成本地待确认计划')),
      if (state.message.isNotEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(state.message)),
      if (draft != null) ...[
        Text(draft.plan.title, style: Theme.of(context).textTheme.titleLarge),
        Text(draft.plan.description),
        Text(draft.plan.weeklyStructure),
        Text(
            '审核：${draft.auditSummary.passCount} 项通过，${draft.auditSummary.warningCount} 项提醒，${draft.auditSummary.failCount} 项阻断'),
        for (final message in [
          ...draft.auditSummary.blockingReasons,
          ...draft.warnings
        ])
          Text(message),
        for (final day in draft.plan.workoutDays)
          ExpansionTile(
              key: ValueKey('${draft.id}-${day.id}'),
              title: Text(
                  '第 ${day.weekIndex} 周 · 第 ${day.dayIndex} 天 · ${day.title}'),
              subtitle: Text('${day.estimatedMinutes} 分钟 · ${day.intensity}'),
              children: [
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in {
                            '放松': day.foamRollingSteps,
                            '动态伸展': day.dynamicStretchSteps,
                            '激活': day.activationSteps,
                            '热身': day.warmupSteps,
                            '主训练': day.mainSets,
                            '辅助': day.accessoryWork,
                            '冷身': day.cooldownSteps
                          }.entries)
                            if (entry.value.isNotEmpty)
                              Text('${entry.key}：${entry.value.join('；')}'),
                          for (final link in day.workoutExercises)
                            Text(
                                '${seedExercises.where((e) => e.id == link.exerciseId).firstOrNull?.name ?? link.exerciseId} · ${link.plannedSetCount} 组 · ${link.repetitionsPerSet} 次 · ${link.plannedWeightOrIntensity}'),
                          Text(day.coachNotes),
                        ]))
              ]),
        Text('来源：${draft.resourceRef.id} · ${draft.resourceRef.version}'),
        FilledButton(
            onPressed:
                !writable || state.busy || !draft.auditSummary.canActivate
                    ? null
                    : () async {
                        if (!await _confirm(context, '确认启用这份计划？',
                            '启用后将替换当前有效计划，并保留现有版本历史。请确认已查看课程与审核提示。')) {
                          return;
                        }
                        if (!context.mounted) return;
                        await run(() => ref
                            .read(localPlanControllerProvider.notifier)
                            .activateLocalDraft(draft.id));
                      },
            child: const Text('确认并启用计划')),
      ],
      if (state.activated)
        TextButton(
            onPressed: () => context.push('/plans'),
            child: const Text('查看当前计划')),
    ]);
  }
}
