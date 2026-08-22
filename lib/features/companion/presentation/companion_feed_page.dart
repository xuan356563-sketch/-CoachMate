import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/core/constants/app_colors.dart';
import 'package:trainflow_ai/core/theme/trainmate_visual_mode.dart';
import 'package:trainflow_ai/core/widgets/coach_mate_orb.dart';
import 'package:trainflow_ai/core/widgets/trainmate_branding.dart';
import 'package:trainflow_ai/core/widgets/trainmate_showcase_widgets.dart';
import 'package:trainflow_ai/core/widgets/trainflow_widgets.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/features/companion/application/companion_controller.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';
import 'package:trainflow_ai/features/companion/domain/companion_models.dart';
import 'package:trainflow_ai/features/pet/presentation/pet_first_egg_page.dart';
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
        title: '正在唤醒袋小满',
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
    final bool empty = state.messages.isEmpty;
    return TrainMateVisualScope(
      mode: TrainMateVisualMode.darkTraining,
      child: Theme(
        data: TrainMateVisualScope.darkHubTheme(context),
        child: ColoredBox(
          color: TrainFlowTokens.darkTrainingSurface,
          child: SafeArea(
            child: Column(
              children: <Widget>[
                _CompanionTopBar(
                  displayName: state.displayName,
                  relationshipLabel: state.relationshipState!.label,
                  onSettings: () => _showSettings(context, ref, state),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      TrainFlowTokens.mainTabPageGutter,
                      4,
                      TrainFlowTokens.mainTabPageGutter,
                      12,
                    ),
                    children: <Widget>[
                      if (empty)
                        _CompanionWelcome(
                          displayName: state.displayName,
                          relationshipLabel: state.relationshipState!.label,
                          statusMessage: state.statusMessage,
                          stageLabel: petStageLabel(pet.stage),
                          moodLabel: petMoodLabel(pet.mood),
                          coachAvailable: state.coachAvailable,
                        )
                      else
                        ...state.messages
                            .toList(growable: false)
                            .reversed
                            .map((CompanionMessage message) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Align(
                                    alignment: message.messageRole ==
                                            CompanionMessageRole.user
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 520),
                                      child: CompanionMessageCard(
                                        key: ValueKey<String>(
                                          'companion-message-'
                                          '${message.messageId}',
                                        ),
                                        message: message,
                                        highlighted: message.messageId ==
                                            highlightedMessageId,
                                        onAction:
                                            (CompanionAction action) async {
                                          if (action.kind ==
                                              CompanionActionKind.dismiss) {
                                            await ref
                                                .read(companionControllerProvider
                                                    .notifier)
                                                .dismissToday(
                                                  message: message,
                                                );
                                            return;
                                          }
                                          final String? route = action.route;
                                          if (route != null &&
                                              context.mounted) {
                                            context.push(route);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                )),
                    ],
                  ),
                ),
                _CoachComposer(
                  enabled: state.coachAvailable,
                  companionName: state.displayName,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 聊天式顶部条：搭子设置 + 关系状态 + 记忆入口。
class _CompanionTopBar extends StatelessWidget {
  const _CompanionTopBar({
    required this.displayName,
    required this.relationshipLabel,
    required this.onSettings,
  });

  final String displayName;
  final String relationshipLabel;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '搭子设置',
            onPressed: onSettings,
            icon: Icon(
              Icons.tune_outlined,
              color: TrainFlowTokens.darkTrainingOnSurface,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '$displayName · $relationshipLabel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
                  ),
            ),
          ),
          TextButton.icon(
            onPressed: () => context.push(AppRoutes.companionMemories),
            icon: const Icon(Icons.auto_stories_outlined, size: 18),
            label: const Text('记忆'),
          ),
        ],
      ),
    );
  }
}

/// 参考图欢迎页形态：大球体头像 + 问候 + 渐变标题 + 状态标签。
class _CompanionWelcome extends StatelessWidget {
  const _CompanionWelcome({
    required this.displayName,
    required this.relationshipLabel,
    required this.statusMessage,
    required this.stageLabel,
    required this.moodLabel,
    required this.coachAvailable,
  });

  final String displayName;
  final String relationshipLabel;
  final String statusMessage;
  final String stageLabel;
  final String moodLabel;
  final bool coachAvailable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        children: <Widget>[
          const CoachMateOrb(size: 140, active: true, phase: 0.3),
          const SizedBox(height: 28),
          Text(
            '你好，$displayName',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingOnSurface,
                ),
          ),
          const SizedBox(height: 6),
          const _WelcomeGradientText('我能帮你什么？'),
          const SizedBox(height: 14),
          Text(
            statusMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: <Widget>[
              ToneBadge(label: relationshipLabel),
              ToneBadge(label: stageLabel),
              ToneBadge(label: moodLabel),
              ToneBadge(label: coachAvailable ? 'AI 教练可用' : 'AI 教练未开启'),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () => context.push(AppRoutes.companionMemories),
                icon: const Icon(Icons.auto_stories_outlined),
                label: const Text('记忆与来源'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => context.push(AppRoutes.companionArchive),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('成长档案'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 渐变强调标题（品牌渐变：蜜桃 → 荧光绿）。
class _WelcomeGradientText extends StatelessWidget {
  const _WelcomeGradientText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) => const LinearGradient(
        colors: <Color>[Color(0xFFF083C6), Color(0xFF6C3DF4)],
      ).createShader(bounds),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
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
      label: '${isUser ? '我的' : '伙伴'}消息：${message.body}',
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
  const _CoachComposer({
    required this.enabled,
    required this.companionName,
  });

  final bool enabled;
  final String companionName;

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
            decoration: InputDecoration(
              labelText: '和${widget.companionName}说说',
              hintText: '今天练什么？或“记住：我喜欢先热身”',
              suffixIcon: IconButton(
                tooltip: '语音输入',
                onPressed: widget.enabled && !_sending
                    ? _requestVoice
                    : null,
                icon: const Icon(Icons.mic_outlined),
              ),
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

  void _requestVoice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('语音输入即将上线，先用文字聊聊吧。')),
    );
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
      title: '袋小满暂时不可用',
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
        character: const TrainMateBrandCharacter(size: 128),
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
                  decoration: const InputDecoration(labelText: '伙伴名称'),
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
