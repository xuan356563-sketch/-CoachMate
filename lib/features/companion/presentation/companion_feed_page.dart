import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/core/constants/app_colors.dart';
import 'package:trainflow_ai/core/theme/trainmate_visual_mode.dart';
import 'package:trainflow_ai/core/theme/trainflow_tokens.dart';
import 'package:trainflow_ai/core/widgets/trainmate_branding.dart';
import 'package:trainflow_ai/core/widgets/trainmate_showcase_widgets.dart';
import 'package:trainflow_ai/core/widgets/trainflow_widgets.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/features/companion/application/companion_controller.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';
import 'package:trainflow_ai/features/companion/domain/companion_models.dart';
import 'package:trainflow_ai/features/pet/presentation/pet_first_egg_page.dart';
import 'package:trainflow_ai/features/pet/presentation/illustrated_pet_renderer.dart';
import 'package:trainflow_ai/features/pet/presentation/pet_labels.dart';

class CompanionFeedPage extends ConsumerStatefulWidget {
  const CompanionFeedPage({super.key, this.initialMessageId});

  /// 本地通知仅能定位本机已保存的消息，不能携带训练或健康原始数据。
  final String? initialMessageId;

  @override
  ConsumerState<CompanionFeedPage> createState() => _CompanionFeedPageState();
}

class _CompanionFeedPageState extends ConsumerState<CompanionFeedPage> {
  bool _markedRead = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<CompanionFeedState> asyncState =
        ref.watch(companionControllerProvider);
    return asyncState.when(
      loading: () => const _CompanionHubStatePage(
        title: '正在唤醒衡衡狸',
        message: '只在本机读取已有训练、活动与恢复事实。',
        icon: Icons.pets_outlined,
      ),
      error: (_, __) => const _CompanionUnavailable(
        message: '搭子状态读取失败，训练与健康数据没有被改动。',
      ),
      data: (CompanionFeedState value) {
        if (value.status == CompanionFeedStatus.needsFirstEgg) {
          return const PetFirstEggPage(asMainTab: true);
        }
        if (value.status != CompanionFeedStatus.ready) {
          return _CompanionUnavailable(message: value.statusMessage);
        }
        if (!_markedRead) {
          _markedRead = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(companionControllerProvider.notifier).markAllRead();
          });
        }
        return _ReadyCompanionFeed(
          state: value,
          highlightedMessageId: widget.initialMessageId,
        );
      },
    );
  }
}

class _ReadyCompanionFeed extends ConsumerWidget {
  const _ReadyCompanionFeed({
    required this.state,
    this.highlightedMessageId,
  });

  final CompanionFeedState state;
  final String? highlightedMessageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PetCompanion pet = state.pet!;
    final CompanionMessage? latestMessage =
        state.messages.isEmpty ? null : state.messages.last;
    return TrainMateImmersiveHubPage(
      includeDisclaimer: false,
      mode: TrainMateVisualMode.darkTraining,
      hero: TrainMateSceneHero(
        sceneAsset:
            'assets/images/immersive_scenes/trainmate_companion_room.png',
        greeting: '你好，${state.displayName}',
        dateLabel: state.relationshipState!.label,
        character: IllustratedPetRenderer(
          species: pet.species,
          stage: pet.stage,
          mood: pet.mood,
          size: 164,
          semanticLabel: '${state.displayName}的衡衡狸形象',
        ),
        taskTitle: latestMessage == null ? '今天它安静陪着' : '衡衡狸的最新消息',
        taskSubtitle: latestMessage?.body ?? '没有可靠事实时，少说一句。',
        taskIcon: Icons.pets_outlined,
        actionTooltip: '记忆与来源',
        onAction: () => context.push(AppRoutes.companionMemories),
        onTaskTap: () => context.push(AppRoutes.companionArchive),
        taskTrailing: IconButton(
          tooltip: '搭子设置',
          onPressed: () => _showSettings(context, ref, state),
          icon: Icon(
            Icons.tune_outlined,
            color: TrainMateVisualScope.foreground(context),
          ),
        ),
      ),
      children: <Widget>[
        TrainMateStatusStrip(
          semanticLabel: '伙伴状态',
          onTap: () => context.push(AppRoutes.companionArchive),
          metrics: <TrainMateStatusMetric>[
            TrainMateStatusMetric(
                label: '关系',
                value: state.relationshipState!.label,
                icon: Icons.favorite_outline),
            TrainMateStatusMetric(
                label: '消息',
                value: '${state.messages.length} 条',
                icon: Icons.chat_bubble_outline,
                color: TrainFlowTokens.accent),
            TrainMateStatusMetric(
                label: '教练',
                value: state.coachAvailable ? '可用' : '未开启',
                icon: Icons.smart_toy_outlined),
          ],
        ),
        const SizedBox(height: 20),
        _CompanionRelationshipCard(
          pet: pet,
          relationshipState: state.relationshipState!,
          statusMessage: state.statusMessage,
        ),
        const SizedBox(height: 12),
        if (state.messages.isEmpty)
          TrainFlowCard(
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.nightlight_round,
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '今天它安静陪着。没有可靠事实时，少说一句。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          )
        else
          ...state.messages
              .toList(growable: false)
              .reversed
              .map((CompanionMessage message) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Align(
                      alignment:
                          message.messageRole == CompanionMessageRole.user
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: CompanionMessageCard(
                          key: ValueKey<String>(
                              'companion-message-${message.messageId}'),
                          message: message,
                          highlighted:
                              message.messageId == highlightedMessageId,
                          onAction: (CompanionAction action) async {
                            if (action.kind == CompanionActionKind.dismiss) {
                              await ref
                                  .read(companionControllerProvider.notifier)
                                  .dismissToday(message: message);
                              return;
                            }
                            final String? route = action.route;
                            if (route != null && context.mounted) {
                              context.push(route);
                            }
                          },
                        ),
                      ),
                    ),
                  )),
        const SizedBox(height: 4),
        _CoachComposer(enabled: state.coachAvailable),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => context.push(AppRoutes.companionArchive),
          icon: const Icon(Icons.auto_stories_outlined),
          label: const Text('查看成长档案'),
        ),
      ],
    );
  }
}

class CompanionMessageCard extends StatelessWidget {
  const CompanionMessageCard({
    super.key,
    required this.message,
    required this.onAction,
    this.highlighted = false,
  });

  final CompanionMessage message;
  final ValueChanged<CompanionAction> onAction;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.messageRole == CompanionMessageRole.user;
    return Semantics(
      label: '${isUser ? '我的' : '衡衡狸'}消息：${message.body}',
      child: TrainFlowCard(
        tone: highlighted || isUser
            ? TrainFlowCardTone.peach
            : TrainFlowCardTone.paper,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(message.body, style: Theme.of(context).textTheme.titleMedium),
            if (message.isConversation && !isUser) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.phonelink_lock_outlined, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    message.verificationState ==
                            CoachVerificationState.dualVerified
                        ? '双端已核验'
                        : '仅本机',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            if (message.facts.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: message.facts
                    .map((CompanionFact fact) => _FactChip(fact: fact))
                    .toList(growable: false),
              ),
            ],
            if (message.actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: message.actions
                    .map((CompanionAction action) =>
                        action.kind == CompanionActionKind.primary
                            ? FilledButton(
                                onPressed: () => onAction(action),
                                child: Text(action.label),
                              )
                            : OutlinedButton(
                                onPressed: () => onAction(action),
                                child: Text(action.label),
                              ))
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.fact});

  final CompanionFact fact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${fact.label}：${fact.value}${fact.isDerived ? '，推算' : ''}',
      button: fact.sourceDigest != null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: fact.sourceDigest == null
            ? null
            : () => _showFactSource(context, fact),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: TrainMateVisualScope.isDark(context)
                ? TrainFlowTokens.darkTrainingRaised
                : AppColors.primaryLightest,
            borderRadius: BorderRadius.circular(
              TrainFlowTokens.mainTabControlRadius,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${fact.label} ${fact.value}${fact.isDerived ? ' · 推算' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (fact.sourceDigest != null) ...<Widget>[
                const SizedBox(width: 4),
                const Icon(Icons.info_outline, size: 15),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachComposer extends ConsumerStatefulWidget {
  const _CoachComposer({required this.enabled});

  final bool enabled;

  @override
  ConsumerState<_CoachComposer> createState() => _CoachComposerState();
}

class _CoachComposerState extends ConsumerState<_CoachComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      tone: TrainFlowCardTone.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _controller,
            enabled: widget.enabled && !_sending,
            minLines: 1,
            maxLines: 4,
            maxLength: 500,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              labelText: '和衡衡狸说说',
              hintText: '例如：今天练什么？或“记住：我喜欢先热身”',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.enabled
                      ? '消息只保存在本机；训练建议只读取结构化事实。'
                      : 'Coach 本地存储尚未就绪，暂不能发送。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilledButton.icon(
                onPressed: widget.enabled && !_sending ? _send : null,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: const Text('发送'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final String text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(companionControllerProvider.notifier)
          .sendUserMessage(text);
      if (mounted) _controller.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

Future<void> _showFactSource(
  BuildContext context,
  CompanionFact fact,
) {
  final String digest = fact.sourceDigest ?? '';
  return showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('事实来源', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(fact.sourceSummary ?? '本机结构化记录'),
            const SizedBox(height: 8),
            Text('来源编号：${fact.sourceLocalId ?? '未提供'}'),
            Text('观察时间：${fact.observedAt?.toLocal() ?? '未提供'}'),
            Text(
                '内容摘要：${digest.isEmpty ? '未提供' : '${digest.substring(0, 12)}…'}'),
            const SizedBox(height: 8),
            const Text('这里不展示原始健康样本、完整对话或自由文本证据。'),
          ],
        ),
      ),
    ),
  );
}

class _CompanionUnavailable extends StatelessWidget {
  const _CompanionUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _CompanionHubStatePage(
      title: '衡衡狸暂时不可用',
      message: message,
      icon: Icons.pets_outlined,
    );
  }
}

class _CompanionHubStatePage extends StatelessWidget {
  const _CompanionHubStatePage({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TrainMateImmersiveHubPage(
      includeDisclaimer: false,
      mode: TrainMateVisualMode.darkTraining,
      hero: TrainMateSceneHero(
        sceneAsset:
            'assets/images/immersive_scenes/trainmate_companion_room.png',
        greeting: '你好，训练者',
        dateLabel: '运动搭子',
        character: TrainMateBrandmark(size: 128),
        taskTitle: title,
        taskSubtitle: message,
        taskIcon: icon,
      ),
      children: <Widget>[
        TrainMateStatePanel(
          title: title,
          message: message,
          icon: icon,
        ),
      ],
    );
  }
}

class _CompanionRelationshipCard extends StatelessWidget {
  const _CompanionRelationshipCard({
    required this.pet,
    required this.relationshipState,
    required this.statusMessage,
  });

  final PetCompanion pet;
  final RelationshipState relationshipState;
  final String statusMessage;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.favorite_outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '陪伴状态',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: relationshipState.label),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${petStageLabel(pet.stage)} · ${petMoodLabel(pet.mood)}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            statusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showSettings(
  BuildContext context,
  WidgetRef ref,
  CompanionFeedState state,
) async {
  final CompanionRelationship relationship = state.relationship!;
  final TextEditingController nameController = TextEditingController(
      text: relationship.companionName ?? state.displayName);
  DisturbTier tier = relationship.disturbTier;
  bool notifications = relationship.notificationsEnabled;
  bool details = relationship.notificationDetailEnabled;
  final Set<CompanionBoundaryTopic> boundaries =
      Set<CompanionBoundaryTopic>.from(relationship.boundaries);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setSheetState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('搭子设置', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  maxLength: 12,
                  decoration: const InputDecoration(labelText: '衡衡狸名称'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<DisturbTier>(
                  initialValue: tier,
                  decoration: const InputDecoration(labelText: '主动陪伴频率'),
                  items: DisturbTier.values
                      .map((DisturbTier item) => DropdownMenuItem(
                            value: item,
                            child: Text(_disturbTierLabel(item)),
                          ))
                      .toList(growable: false),
                  onChanged: (DisturbTier? value) {
                    if (value != null) setSheetState(() => tier = value);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: notifications,
                  title: const Text('接收搭子系统通知'),
                  subtitle: const Text('默认关闭；开启时才会请求系统通知权限。'),
                  onChanged: (bool value) =>
                      setSheetState(() => notifications = value),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: details,
                  title: const Text('通知里显示详细内容'),
                  subtitle: const Text('打开后，通知内容会显示在锁屏上，可能被旁人看到。'),
                  onChanged: (bool value) =>
                      setSheetState(() => details = value),
                ),
                const SizedBox(height: 8),
                Text('不想被提起的事', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '外貌评价始终关闭；疼痛 ≥7 分的安全提示不受此设置影响。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                ...<CompanionBoundaryTopic>[
                  CompanionBoundaryTopic.weight,
                  CompanionBoundaryTopic.bodyComposition,
                  CompanionBoundaryTopic.pain,
                  CompanionBoundaryTopic.diet,
                  CompanionBoundaryTopic.sleep,
                  CompanionBoundaryTopic.comparison,
                ].map((CompanionBoundaryTopic topic) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: boundaries.contains(topic),
                      title: Text(_boundaryLabel(topic)),
                      onChanged: (bool? value) => setSheetState(() {
                        if (value == true) {
                          boundaries.add(topic);
                        } else {
                          boundaries.remove(topic);
                        }
                      }),
                    )),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await ref
                          .read(companionControllerProvider.notifier)
                          .updatePreferences(
                            companionName: nameController.text.trim(),
                            disturbTier: tier,
                            notificationsEnabled: notifications,
                            notificationDetailEnabled: details,
                            boundaries: boundaries,
                          );
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    child: const Text('保存本机设置'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  nameController.dispose();
}

String _disturbTierLabel(DisturbTier value) => switch (value) {
      DisturbTier.less => '少一点',
      DisturbTier.normal => '普通',
      DisturbTier.more => '多一点',
      DisturbTier.silent => '静默',
    };

String _boundaryLabel(CompanionBoundaryTopic value) => switch (value) {
      CompanionBoundaryTopic.weight => '体重',
      CompanionBoundaryTopic.bodyComposition => '体脂和围度',
      CompanionBoundaryTopic.appearance => '外貌评价',
      CompanionBoundaryTopic.pain => '疼痛',
      CompanionBoundaryTopic.diet => '饮食',
      CompanionBoundaryTopic.sleep => '睡眠',
      CompanionBoundaryTopic.comparison => '历史对比',
    };
