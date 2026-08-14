import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/core/widgets/trainmate_showcase_widgets.dart';
import 'package:trainflow_ai/core/widgets/trainflow_widgets.dart';
import 'package:trainflow_ai/features/companion/application/coach_memory_controller.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';

class CoachMemoryPage extends ConsumerWidget {
  const CoachMemoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CoachMemoryState> value =
        ref.watch(coachMemoryControllerProvider);
    return TrainFlowPage(
      title: '记忆与来源',
      subtitle: '训练事实不进入这里；长期记忆必须可追溯、可控制、可忘记。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.companion,
      ),
      includeDisclaimer: false,
      children: <Widget>[
        value.when(
          loading: () => const TrainMateStatePanel(
            title: '正在读取记忆',
            message: '只读取本机 Coach 记忆库。',
            icon: Icons.memory_outlined,
          ),
          error: (_, __) => const TrainMateStatePanel(
            title: '记忆暂不可用',
            message: '读取失败，既有记忆没有被修改。',
            icon: Icons.error_outline,
          ),
          data: (CoachMemoryState state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TrainFlowCard(
                tone: TrainFlowCardTone.outline,
                child: Text(state.statusMessage),
              ),
              const SizedBox(height: 12),
              TrainFlowCard(
                tone: TrainFlowCardTone.outline,
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: state.cloudProjectionConsented,
                  title: const Text('Coach 云投影'),
                  subtitle: const Text(
                    '默认关闭。开启后仍需逐条允许，只同步最小结构化投影和已确认记忆。',
                  ),
                  onChanged: (bool granted) =>
                      _setCloudConsent(context, ref, granted),
                ),
              ),
              const SizedBox(height: 12),
              if (state.memories.isEmpty)
                const TrainFlowCard(child: Text('暂无可管理的关系记忆。'))
              else
                for (final CoachMemoryV1 memory in state.memories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _MemoryCard(
                      memory: memory,
                      cloudProjectionConsented: state.cloudProjectionConsented,
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _setCloudConsent(
    BuildContext context,
    WidgetRef ref,
    bool granted,
  ) async {
    try {
      await ref
          .read(coachMemoryControllerProvider.notifier)
          .setCloudProjectionConsent(granted);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Coach 云投影设置失败：$error')),
      );
    }
  }
}

class _MemoryCard extends ConsumerWidget {
  const _MemoryCard({
    required this.memory,
    required this.cloudProjectionConsented,
  });

  final CoachMemoryV1 memory;
  final bool cloudProjectionConsented;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool deleted = memory.status == CoachMemoryStatus.deleted;
    final bool superseded = memory.status == CoachMemoryStatus.superseded;
    final bool active = memory.status == CoachMemoryStatus.active;
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  deleted ? '已删除记忆墓碑' : memory.displayText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Chip(label: Text(_statusLabel(memory.status))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_categoryLabel(memory.category)} · 置信度 '
            '${(memory.confidenceBps / 100).toStringAsFixed(0)}% · '
            '${_validityLabel(memory)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!deleted) ...<Widget>[
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('为什么记得'),
              subtitle: Text(
                memory.sources.isEmpty
                    ? '没有可用来源'
                    : '共 ${memory.sources.length} 个来源',
              ),
              children: <Widget>[
                for (final CoachSourceRef source in memory.sources)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link_outlined),
                    title: Text(source.summaryKey ?? '本机结构化来源'),
                    subtitle: Text(
                      '${source.sourceKind} · '
                      '${source.observedAt.toLocal()}\n'
                      '摘要 ${source.sourceDigest.substring(0, 12)}…',
                    ),
                  ),
              ],
            ),
            if (active)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: memory.mayMention,
                title: const Text('允许搭子明确提及'),
                subtitle: const Text('关闭后仍可用于已授权的选择，但回复中不会直接说出。'),
                onChanged: (bool value) => ref
                    .read(coachMemoryControllerProvider.notifier)
                    .setMayMention(memory.memoryId, value),
              ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: memory.syncAllowed,
              title: const Text('允许 Coach 云投影'),
              subtitle: Text(
                cloudProjectionConsented
                    ? '只同步这条已确认记忆的最小结构化投影。'
                    : '请先开启上方独立同意项。',
              ),
              onChanged: active && cloudProjectionConsented
                  ? (bool value) => ref
                      .read(coachMemoryControllerProvider.notifier)
                      .setSyncAllowed(memory.memoryId, value)
                  : null,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (!active && !superseded)
                  FilledButton(
                    onPressed: () => ref
                        .read(coachMemoryControllerProvider.notifier)
                        .confirm(memory.memoryId),
                    child: const Text('确认使用'),
                  ),
                if (active)
                  OutlinedButton(
                    onPressed: () => _correct(context, ref),
                    child: const Text('纠正'),
                  ),
                if (!superseded)
                  TextButton(
                    onPressed: () => _forget(context, ref),
                    child: const Text('忘记'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _correct(BuildContext context, WidgetRef ref) async {
    final TextEditingController controller =
        TextEditingController(text: memory.displayText);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('纠正这条记忆'),
        content: TextField(
          controller: controller,
          maxLength: 240,
          autofocus: true,
          decoration: const InputDecoration(labelText: '正确内容'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('确认纠正'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim() == memory.displayText) return;
    await ref.read(coachMemoryControllerProvider.notifier).correct(
          memoryId: memory.memoryId,
          replacement: result,
        );
  }

  Future<void> _forget(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('确认忘记？'),
        content: const Text('确认后立即停止使用正文，只保留 30 天不含内容的删除墓碑。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认忘记'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(coachMemoryControllerProvider.notifier)
        .forget(memory.memoryId);
  }
}

String _statusLabel(CoachMemoryStatus status) => switch (status) {
      CoachMemoryStatus.candidate => '待确认',
      CoachMemoryStatus.readyForReview => '待复核',
      CoachMemoryStatus.active => '使用中',
      CoachMemoryStatus.superseded => '已废止',
      CoachMemoryStatus.deleted => '已删除',
      CoachMemoryStatus.expired => '已过期',
    };

String _categoryLabel(CoachMemoryCategory category) => switch (category) {
      CoachMemoryCategory.preference => '偏好',
      CoachMemoryCategory.obstacle => '训练障碍',
      CoachMemoryCategory.effectiveStrategy => '有效策略',
      CoachMemoryCategory.ritual => '陪伴仪式',
      CoachMemoryCategory.boundary => '用户边界',
      CoachMemoryCategory.milestone => '里程碑',
    };

String _validityLabel(CoachMemoryV1 memory) {
  if (memory.validityPolicy == CoachMemoryValidityPolicy.untilRevoked) {
    return '撤销前有效';
  }
  final DateTime? until = memory.validUntil?.toLocal();
  if (until == null) return '有效期缺失';
  return '有效至 ${until.year}-${until.month.toString().padLeft(2, '0')}-'
      '${until.day.toString().padLeft(2, '0')}';
}
