import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../plugins/application/plugin_runtime.dart';
import '../../plugins/application/plugin_runtime_provider.dart';
import '../../plugins/core/plugin_descriptor.dart';
import '../../plugins/settings/plugin_settings_controller.dart';
import 'plugin_skills_dialog.dart';

class CapabilitiesPage extends ConsumerWidget {
  const CapabilitiesPage({super.key, this.highlightedFeatureId});

  final String? highlightedFeatureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PluginRuntime runtime = ref.watch(pluginRuntimeProvider);
    final PluginSettingsController controller =
        ref.watch(pluginSettingsControllerProvider);
    final List<PluginDescriptor> descriptors =
        runtime.registry.descriptors.values.toList(growable: false);
    final List<PluginDescriptor> sports =
        _byType(descriptors, PluginType.sport);
    final List<PluginDescriptor> goals = <PluginDescriptor>[
      ..._byType(descriptors, PluginType.goal),
      ..._byType(descriptors, PluginType.support),
    ];
    final List<PluginDescriptor> optional =
        _byType(descriptors, PluginType.feature);
    final List<PluginDescriptor> required = descriptors
        .where((PluginDescriptor item) => item.isRequired)
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    final PluginDescriptor? highlighted = highlightedFeatureId == null
        ? null
        : runtime.registry.descriptors[highlightedFeatureId];

    return Scaffold(
      body: TrainFlowPage(
        title: '运动与功能',
        subtitle: '设置只保存在当前账号的本机数据域，不会同步到云端。关闭功能不会删除历史记录。',
        eyebrow: '我的',
        leading: const TrainMateBackButton(fallbackRoute: AppRoutes.profile),
        children: <Widget>[
          if (highlighted != null)
            TrainFlowCard(
              tone: TrainFlowCardTone.peach,
              child: Text(
                '${highlighted.name}当前未启用或尚未恢复。你可以在下方查看依赖和处理方式；已有记录仍在历史记录中。',
                key: const ValueKey<String>('capability-unavailable-message'),
              ),
            ),
          if (controller.state.recoveryMessage case final String message?)
            _RecoveryCard(
              message: message,
              busy: controller.state.isBusy,
              onRestore: () => _restoreDefaults(context, controller),
            ),
          if (runtime.recoveryFailures.isNotEmpty)
            TrainFlowCard(
              tone: TrainFlowCardTone.peach,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('部分功能需要恢复',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final String message
                      in runtime.recoveryFailures.values.toSet())
                    Text(message),
                  const SizedBox(height: 8),
                  const Text('请重试刚才的操作；账户切换恢复失败时，请返回账号切换页重试。'),
                ],
              ),
            ),
          if (controller.state.operationMessage case final String message?)
            Text(
              message,
              key: const ValueKey<String>('capability-operation-message'),
            ),
          _CapabilitySection(
            title: '运动',
            subtitle: '四项专项运动。主运动、次运动或有效计划仍使用时不能关闭。',
            descriptors: sports,
            runtime: runtime,
            controller: controller,
          ),
          _CapabilitySection(
            title: '目标与支持',
            subtitle: '减脂、综合健身与康复支持。档案或有效计划仍使用时不能关闭。',
            descriptors: goals,
            runtime: runtime,
            controller: controller,
          ),
          _CapabilitySection(
            title: '可选功能',
            subtitle: '关闭后停止新建和编辑；已有计划、训练记录与报告继续保留。',
            descriptors: optional,
            runtime: runtime,
            controller: controller,
          ),
          _CapabilitySection(
            title: '核心常驻',
            subtitle: '身份、安全、存储、导航、历史和数据权利用于保护账号与已有数据，始终保持启用。',
            descriptors: required,
            runtime: runtime,
            controller: controller,
            required: true,
          ),
          TrainFlowCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history),
              title: const Text('历史记录'),
              subtitle: const Text('查看已保存计划版本、训练记录和各类报告。'),
              trailing: const Icon(Icons.chevron_right),
              // 管理页位于主导航之外；切回历史，避免重复压入同一导航容器。
              onTap: () => context.go(AppRoutes.history),
            ),
          ),
        ],
      ),
    );
  }

  List<PluginDescriptor> _byType(
    List<PluginDescriptor> source,
    PluginType type,
  ) {
    final List<PluginDescriptor> result = source
        .where((PluginDescriptor item) => item.type == type && !item.isRequired)
        .toList(growable: false);
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  Future<void> _restoreDefaults(
    BuildContext context,
    PluginSettingsController controller,
  ) async {
    try {
      await controller.restoreDefaults();
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _CapabilitySection extends StatelessWidget {
  const _CapabilitySection({
    required this.title,
    required this.subtitle,
    required this.descriptors,
    required this.runtime,
    required this.controller,
    this.required = false,
  });

  final String title;
  final String subtitle;
  final List<PluginDescriptor> descriptors;
  final PluginRuntime runtime;
  final PluginSettingsController controller;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionTitle(title: title),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(subtitle),
        ),
        for (final PluginDescriptor descriptor in descriptors)
          TrainFlowCard(
            key: ValueKey<String>('capability-${descriptor.id}'),
            child: required
                ? ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_outline),
                    title: Text(descriptor.name),
                    subtitle: const Text('核心能力，始终启用'),
                    trailing: const Text('常驻'),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(descriptor.name),
                        subtitle: Text(descriptor.description),
                        value: runtime.isEnabled(descriptor.id),
                        onChanged:
                            controller.state.isBusy || runtime.isSwitching
                                ? null
                                : (bool value) =>
                                    _setEnabled(context, descriptor, value),
                      ),
                      if (descriptor.skills.isNotEmpty ||
                          descriptor.workflows.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: ValueKey('capability-skills-${descriptor.id}'),
                            icon: const Icon(Icons.menu_book_outlined),
                            label: Text('查看技能（${descriptor.skills.length}）'),
                            onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) =>
                                    PluginSkillsDialog(descriptor: descriptor)),
                          ),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }

  Future<void> _setEnabled(
    BuildContext context,
    PluginDescriptor descriptor,
    bool enabled,
  ) async {
    if (enabled) {
      final List<PluginDescriptor> additions =
          runtime.previewEnable(descriptor.id);
      final List<PluginDescriptor> dependencies = additions
          .where((PluginDescriptor item) => item.id != descriptor.id)
          .toList(growable: false);
      if (dependencies.isNotEmpty) {
        final bool confirmed = await showDialog<bool>(
              context: context,
              builder: (BuildContext context) => AlertDialog(
                title: Text('启用${descriptor.name}'),
                content: Text(
                  '还会同时启用：${dependencies.map((item) => item.name).join('、')}。是否继续？',
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('确认启用'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirmed) return;
      }
    } else {
      final List<String> reasons = runtime.checkDisable(descriptor.id);
      if (reasons.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text('暂时不能关闭${descriptor.name}'),
            content: Text(reasons.join('\n')),
            actions: <Widget>[
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
    }
    try {
      await controller.setEnabled(descriptor.id, enabled);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    required this.message,
    required this.busy,
    required this.onRestore,
  });

  final String message;
  final bool busy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) => TrainFlowCard(
        tone: TrainFlowCardTone.peach,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(message),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey<String>('restore-default-capabilities'),
              onPressed: busy ? null : onRestore,
              child: const Text('恢复默认设置'),
            ),
          ],
        ),
      );
}

void _showError(BuildContext context, Object error) {
  final String message = error is StateError
      ? error.message.toString()
      : '功能设置操作失败，请重试；已有训练数据未被清除。';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
