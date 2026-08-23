import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/ai_chat.dart';
import '../../data/models/body_metric.dart';
import '../../data/models/health_snapshot.dart';
import '../../data/models/training_schedule.dart';
import '../../data/models/user_profile.dart';
import '../auth/application/auth_controller.dart';
import '../dashboard/training_mvp_controller.dart';
import '../data_center/application/body_metric_controller.dart';
import '../profile/application/health_sync_controller.dart';
import '../training_plan/application/four_week_plan_controller.dart';
import 'application/ai_chat_controller.dart';
import 'application/chat_privacy_router.dart';
import 'application/voice_input_gateway.dart';

final voiceInputGatewayProvider = Provider<VoiceInputGateway>(
  (Ref ref) => createVoiceInputGateway(),
);

class AiChatConversation extends ConsumerWidget {
  const AiChatConversation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AiChatState chat = ref.watch(aiChatControllerProvider);
    final AiLocalStatusSnapshot local = _localStatus(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '本机对话',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (chat.sessions.length > 1)
              PopupMenuButton<String>(
                tooltip: '打开本机对话记录',
                onSelected:
                    ref.read(aiChatControllerProvider.notifier).selectSession,
                itemBuilder: (BuildContext context) => chat.sessions
                    .map(
                      (AiChatSession session) => PopupMenuItem<String>(
                        value: session.id,
                        child: Text(
                          _sessionLabel(session),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                icon: const Icon(Icons.history),
              ),
            IconButton(
              tooltip: '新建对话',
              onPressed: chat.isSending
                  ? null
                  : ref.read(aiChatControllerProvider.notifier).startNewSession,
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
        ),
        _LocalStatusCards(snapshot: local),
        const SizedBox(height: 12),
        Text(
          chat.statusMessage,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TrainFlowTokens.darkTrainingMuted,
              ),
        ),
        const SizedBox(height: 8),
        if (chat.session.messages.isEmpty)
          const TrainFlowCard(
            tone: TrainFlowCardTone.peach,
            child: Text('可以问今天练什么、动作重点或计划安排。身体状态会留在本机处理。'),
          )
        else
          for (final AiChatMessage message in chat.session.messages)
            _MessageBubble(message: message),
        if (chat.isSending)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: LinearProgressIndicator(),
          ),
        if (chat.suggestedActions.isNotEmpty)
          _SuggestedActions(actions: chat.suggestedActions),
        const SizedBox(height: 8),
      ],
    );
  }
}

class AiChatComposer extends ConsumerStatefulWidget {
  const AiChatComposer({super.key});

  @override
  ConsumerState<AiChatComposer> createState() => _AiChatComposerState();
}

class _AiChatComposerState extends ConsumerState<AiChatComposer>
    with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  late final VoiceInputGateway _voice;
  bool _listening = false;
  String? _voiceMessage;

  @override
  void initState() {
    super.initState();
    _voice = ref.read(voiceInputGatewayProvider);
    ref.listenManual(authControllerProvider, (_, __) {
      unawaited(_cancelVoice());
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_cancelVoice());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_voice.cancelListening());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AiChatState chat = ref.watch(aiChatControllerProvider);
    return Material(
      elevation: 10,
      color: AppColors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_voiceMessage != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _voiceMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TrainFlowTokens.darkTrainingMuted,
                      ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('ai-chat-input'),
                    controller: _controller,
                    enabled: !chat.isSending,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 600,
                    decoration: const InputDecoration(
                      hintText: '输入训练问题',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_voice.isSupported) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    key: const ValueKey<String>('ai-chat-voice'),
                    tooltip: _listening ? '停止语音输入' : '开始语音输入',
                    onPressed: chat.isSending ? null : _toggleVoice,
                    icon: Icon(_listening ? Icons.stop : Icons.mic_none),
                  ),
                ],
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const ValueKey<String>('ai-chat-send'),
                  tooltip: '发送',
                  onPressed: chat.isSending ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleVoice() async {
    try {
      if (!_listening) {
        await _voice.startListening();
        if (!mounted) return;
        setState(() {
          _listening = true;
          _voiceMessage = '正在本机识别，点击停止后可编辑文字。';
        });
        return;
      }
      final String transcript = await _voice.stopListening();
      if (!mounted) return;
      setState(() {
        _listening = false;
        _voiceMessage =
            transcript.trim().isEmpty ? '没有识别到文字，请重试或直接输入。' : '识别完成，请核对文字后再发送。';
        if (transcript.trim().isNotEmpty) {
          _controller.text = transcript.trim();
          _controller.selection = TextSelection.collapsed(
            offset: _controller.text.length,
          );
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _voiceMessage = '语音识别暂不可用，请检查麦克风与语音识别权限。';
      });
    }
  }

  Future<void> _cancelVoice() async {
    if (!_listening) return;
    await _voice.cancelListening();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _voiceMessage = '语音输入已停止，未发送任何内容。';
    });
  }

  Future<void> _send() async {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_listening) {
      await _cancelVoice();
    }
    final TrainingMvpState training = ref.read(trainingMvpProvider);
    _controller.clear();
    await ref.read(aiChatControllerProvider.notifier).send(
          text: text,
          localStatus: _localStatus(ref, listen: false),
          context: AiChatContext(
            goal: training.todayWorkout.title,
            sports: training.profile.mainSports
                .map((item) => item.label)
                .toList(growable: false),
            availableMinutes: training.dailyAvailableMinutesOverride,
            scheduledMinutes: training.scheduledTodayWorkout?.allocatedMinutes,
            scheduledPeriod: training.scheduledTodayWorkout?.period.label,
          ),
        );
  }
}

class _LocalStatusCards extends StatelessWidget {
  const _LocalStatusCards({required this.snapshot});

  final AiLocalStatusSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      tone: TrainFlowCardTone.outline,
      child: Column(
        children: [
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('今日训练'),
            subtitle: Text(snapshot.todayWorkoutTitle),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(snapshot.todayWorkoutSummary),
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('当前计划'),
            subtitle: Text(snapshot.activePlanTitle),
            children: const [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('AI 只能提出建议，正式计划需在计划生成器中确认。'),
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('身体状态 · 仅本机'),
            subtitle: Text(
              snapshot.bodyFacts.isEmpty
                  ? '暂无可用记录'
                  : snapshot.bodyFacts.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  snapshot.bodyFacts.isEmpty
                      ? '没有可展示的数据，系统不会用零值补齐。'
                      : snapshot.bodyFacts.join('\n'),
                ),
              ),
              if (snapshot.bodyUpdatedAt != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '更新时间：${_dateTimeLabel(snapshot.bodyUpdatedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TrainFlowTokens.darkTrainingMuted,
                        ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AiChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == AiChatMessageRole.user;
    final bool isLocal = message.role == AiChatMessageRole.local;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 310),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.primary
              : isLocal
                  ? AppColors.secondary.withValues(alpha: 0.15)
                  : AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isLocal
                ? AppColors.secondary
                : TrainFlowTokens.darkTrainingMuted.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLocal)
              const Text(
                '本机状态',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            Text(
              message.content,
              style: TextStyle(color: isUser ? AppColors.white : null),
            ),
            if (message.status == AiChatMessageStatus.failed)
              const Text(
                '发送失败，请重新输入后发送。',
                style: TextStyle(color: AppColors.danger),
              ),
          ],
        ),
      ),
    );
  }
}

class _SuggestedActions extends StatelessWidget {
  const _SuggestedActions({required this.actions});

  final List<String> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final String action in actions)
          ActionChip(
            label: Text(switch (action) {
              'view_today_workout' => '查看今日训练',
              'view_active_plan' => '查看当前计划',
              'open_plan_generator' => '打开计划生成器',
              _ => '查看建议',
            }),
            onPressed: () => context.push(switch (action) {
              'view_active_plan' => AppRoutes.plans,
              'open_plan_generator' => AppRoutes.planGenerate,
              _ => AppRoutes.dashboard,
            }),
          ),
      ],
    );
  }
}

AiLocalStatusSnapshot _localStatus(
  WidgetRef ref, {
  bool listen = true,
}) {
  final TrainingMvpState training =
      listen ? ref.watch(trainingMvpProvider) : ref.read(trainingMvpProvider);
  final BodyMetric? body = listen
      ? ref.watch(bodyMetricControllerProvider).latestMetric
      : ref.read(bodyMetricControllerProvider).latestMetric;
  final HealthSnapshot? health = listen
      ? ref.watch(healthSyncControllerProvider).value?.latest
      : ref.read(healthSyncControllerProvider).value?.latest;
  final planState = listen
      ? ref.watch(fourWeekPlanControllerProvider)
      : ref.read(fourWeekPlanControllerProvider);
  final String activePlan = planState.activeVersionId == null
      ? '暂无已确认的正式 AI 计划'
      : planState.activePlan.title;
  final DateTime now = DateTime.now();
  final bool bodyIsToday = body != null && _sameDay(body.measuredAt, now);
  final bool healthIsToday = health != null && _sameDay(health.date, now);
  final List<String> facts = <String>[];

  final double? sleep = bodyIsToday && body.sleepHours > 0
      ? body.sleepHours
      : healthIsToday
          ? health.sleepHours
          : null;
  final int? restingHeartRate = bodyIsToday && body.restingHeartRate > 0
      ? body.restingHeartRate
      : healthIsToday
          ? health.restingHeartRate
          : null;
  final int? hrv = bodyIsToday && body.hrvMs > 0
      ? body.hrvMs
      : healthIsToday
          ? health.hrvMs
          : null;
  final double? weight = bodyIsToday && body.weightKg > 0
      ? body.weightKg
      : healthIsToday
          ? health.weightKg
          : null;
  final double? bodyFat = bodyIsToday && body.bodyFatPercentage > 0
      ? body.bodyFatPercentage
      : healthIsToday
          ? health.bodyFatPercentage
          : null;
  if (sleep != null) facts.add('睡眠 ${sleep.toStringAsFixed(1)} 小时');
  if (restingHeartRate != null) facts.add('静息心率 $restingHeartRate 次/分');
  if (hrv != null) facts.add('HRV $hrv 毫秒');
  if (weight != null) facts.add('体重 ${weight.toStringAsFixed(1)} kg');
  if (bodyFat != null) {
    facts.add('体脂 ${bodyFat.toStringAsFixed(1)}%');
  }
  if (bodyIsToday && body.fatigueLevel > 0) {
    facts.add('疲劳 ${body.fatigueLevel}/10');
  }
  final int pain = training.latestPainLog?.painLevel ?? 0;
  if (pain > 0) facts.add('疼痛 $pain/10');

  return AiLocalStatusSnapshot(
    todayWorkoutTitle: training.todayWorkout.title,
    todayWorkoutSummary:
        '${training.dailyAvailableMinutesOverride} 分钟 · ${training.dailyAdjustmentDecision.decisionLabel}',
    activePlanTitle: activePlan,
    bodyFacts: facts,
    bodyUpdatedAt: bodyIsToday
        ? body.measuredAt
        : healthIsToday
            ? health.syncedAt
            : null,
  );
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _sessionLabel(AiChatSession session) {
  for (final AiChatMessage message in session.messages) {
    if (message.role == AiChatMessageRole.user) {
      return message.content;
    }
  }
  return '新对话';
}

String _dateTimeLabel(DateTime value) => '${value.month}月${value.day}日 '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
