import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../plugins/application/plugin_runtime.dart';
import '../../plugins/application/plugin_runtime_provider.dart';
import '../../plugins/core/plugin_core.dart';
import '../motion_check/running/running_video_pose_gateway.dart';
import 'package:go_router/go_router.dart';

/// 只读声明与本机运行状态；打开详情不联网、不启动业务控制器。
class PluginSkillsDialog extends ConsumerWidget {
  const PluginSkillsDialog({super.key, required this.descriptor});
  final PluginDescriptor descriptor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(pluginRuntimeProvider);
    return AlertDialog(
      title: Text('${descriptor.name}的技能'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('技能随所属插件启停。云端实际版本与可用性在生成请求时校验；训练结果仍需安全审核和用户确认。'),
              for (final workflow in descriptor.workflows) ...[
                const Divider(),
                Text(workflow.label),
                Text(
                    '技能归属：${runtime.registry.descriptors[workflow.ownerPluginId]?.name ?? workflow.ownerPluginId}，共享工具链'),
                Text(!runtime.isWritable(workflow.ownerPluginId)
                    ? '需要启用所属功能'
                    : workflow.ownerPluginId == 'feature.resource_library'
                        ? '可浏览已审核运动资源'
                        : runningVideoPreviewEnabled
                        ? '可在验收入口运行'
                        : '真实视频验收中，正式发行未开放'),
                TextButton(
                    onPressed: () {
                      final owner =
                          runtime.registry.descriptors[workflow.ownerPluginId];
                      if (owner != null) {
                        showDialog<void>(
                            context: context,
                            builder: (_) =>
                                PluginSkillsDialog(descriptor: owner));
                      }
                    },
                    child: const Text('查看工具链技能')),
                if (workflow.ownerPluginId == 'feature.resource_library' && runtime.isWritable(workflow.ownerPluginId))
                  TextButton(onPressed: () { Navigator.of(context).pop(); context.push('/resources'); }, child: const Text('打开运动资源库')),
                if (workflow.ownerPluginId == 'feature.motion_check' && runningVideoPreviewEnabled &&
                    runtime.isWritable(workflow.ownerPluginId) &&
                    runtime.isWritable(descriptor.id))
                  TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push('/motion-check/running');
                      },
                      child: const Text('打开跑姿视频分析')),
              ],
              for (final skill in descriptor.skills) ...[
                const Divider(height: 28),
                Text(skill.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(_status(runtime, skill),
                    key: ValueKey('skill-status-${descriptor.id}-${skill.id}')),
                Text(skill.execution == SkillExecution.local
                    ? '本机运行 · 版本 ${skill.version}'
                    : '云端运行 · 兼容版本 ${skill.version}'),
                Text(skill.purpose),
                Text('输入：${skill.inputs}'),
                Text('输出：${skill.outputs}'),
                Text('不可用时：${skill.fallback}'),
                const SizedBox(height: 6),
                Text('技能标识：${skill.id}',
                    style: Theme.of(context).textTheme.bodySmall),
                if (skill.fragmentKey != null)
                  Text('专项片段：${skill.fragmentKey}',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'))
      ],
    );
  }

  String _status(PluginRuntime runtime, PluginSkillBinding skill) {
    if (!runtime.isEnabled(descriptor.id)) return '所属插件已停用';
    if (!runtime.isWritable(descriptor.id)) return '所属插件正在切换或等待恢复';
    if (descriptor.id == 'feature.motion_check' &&
        !runningVideoPreviewEnabled) {
      return '真实视频验收中，正式发行未开放';
    }
    if (skill.execution == SkillExecution.local) {
      return runtime.registry.readCapability<Object>(skill.capabilityId!) ==
              null
          ? '本地实现尚未就绪'
          : '本地已就绪';
    }
    if (!runtime.isWritable('feature.ai_center') ||
        !runtime.isWritable('feature.training_plan')) {
      return '需要启用 AI 中心和训练计划功能';
    }
    return '云端待请求时校验';
  }
}
