import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/pilot_validation.dart';
import 'application/pilot_validation_service.dart';

class PilotValidationPage extends ConsumerStatefulWidget {
  const PilotValidationPage({super.key});

  @override
  ConsumerState<PilotValidationPage> createState() =>
      _PilotValidationPageState();
}

class _PilotValidationPageState extends ConsumerState<PilotValidationPage> {
  late final PilotValidationService _service;
  List<PilotParticipantRecord> _participants = const <PilotParticipantRecord>[];
  PilotScenario _newScenario = PilotScenario.raceRunning;
  String? _selectedId;

  static const String invitationMessage =
      '我在做一个 AI 训练工具，想每天免费帮你安排训练 7 天，你只需要每晚发我一句今天的状态。'
      '只记录安排训练所需的最少信息，不做医疗诊断，你随时可以退出。';

  @override
  void initState() {
    super.initState();
    _service = ref.read(pilotValidationServiceProvider);
    _refresh();
  }

  PilotParticipantRecord? get _selected {
    final String? id = _selectedId;
    if (id == null) return null;
    for (final PilotParticipantRecord item in _participants) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _refresh([String? preferredId]) {
    final List<PilotParticipantRecord> values = _service.listParticipants();
    setState(() {
      _participants = values;
      _selectedId = preferredId ??
          (values.any((PilotParticipantRecord item) => item.id == _selectedId)
              ? _selectedId
              : (values.isEmpty ? null : values.first.id));
    });
  }

  Future<void> _addParticipant() async {
    try {
      final PilotParticipantRecord created = await _service.addParticipant(
        scenario: _newScenario,
        startedOn: DateTime.now(),
      );
      _refresh(created.id);
    } on StateError catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _save(PilotParticipantRecord participant) async {
    try {
      await _service.save(participant);
      _refresh(participant.id);
    } on StateError catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _markCheckIn() async {
    final PilotParticipantRecord? participant = _selected;
    if (participant == null) return;
    try {
      await _service.markCheckIn(participant.id, DateTime.now());
      _refresh(participant.id);
    } on StateError catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _markFeedback() async {
    final PilotParticipantRecord? participant = _selected;
    if (participant == null) return;
    try {
      await _service.markFeedback(participant.id, DateTime.now());
      _refresh(participant.id);
    } on StateError catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _copyInvitation() async {
    await Clipboard.setData(const ClipboardData(text: invitationMessage));
    if (mounted) _showMessage('邀请文案已复制，请由你人工选择接收者并发送。');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PilotParticipantRecord? participant = _selected;
    return TrainFlowPage(
      title: '假设卡内测',
      subtitle: '只记录匿名履约结果，不保存微信原文、身份或支付凭证。',
      eyebrow: '7–14 天人肉私教验证',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.profile,
      ),
      artwork: const TrainMateActionCharacter(
        action: TrainMateAction.pointingGuide,
        backgroundColor: AppColors.primary,
      ),
      children: [
        _InvitationCard(onCopy: _copyInvitation),
        _CohortCard(
          participants: _participants,
          selectedId: _selectedId,
          newScenario: _newScenario,
          onScenarioChanged: (PilotScenario value) {
            setState(() => _newScenario = value);
          },
          onAdd: _participants.length >= 5 ? null : _addParticipant,
          onSelected: (String id) => setState(() => _selectedId = id),
        ),
        if (participant != null)
          _ParticipantProgressCard(
            participant: participant,
            onCommitmentAccepted: participant.commitmentAccepted
                ? null
                : () => _save(
                      participant.copyWith(
                        commitmentAcceptedAt: DateTime.now(),
                      ),
                    ),
            onCheckIn: _markCheckIn,
            onFeedback: _markFeedback,
            onDepositChanged: (PilotDepositStatus value) =>
                _save(participant.copyWith(depositStatus: value)),
            onContinuationChanged: (PilotContinuationDecision value) => _save(
              participant.copyWith(continuationDecision: value),
            ),
          ),
        const _PrivacyBoundaryCard(),
      ],
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({required this.onCopy});

  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今晚第一条微信',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const SelectableText(_PilotValidationPageState.invitationMessage),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined),
              label: const Text('复制，人工发送'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CohortCard extends StatelessWidget {
  const _CohortCard({
    required this.participants,
    required this.selectedId,
    required this.newScenario,
    required this.onScenarioChanged,
    required this.onAdd,
    required this.onSelected,
  });

  final List<PilotParticipantRecord> participants;
  final String? selectedId;
  final PilotScenario newScenario;
  final ValueChanged<PilotScenario> onScenarioChanged;
  final VoidCallback? onAdd;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '首批匿名测试者（${participants.length}/5）',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SegmentedButton<PilotScenario>(
            segments: [
              for (final PilotScenario value in PilotScenario.values)
                ButtonSegment<PilotScenario>(
                  value: value,
                  label: Text(value.label),
                ),
            ],
            selected: <PilotScenario>{newScenario},
            onSelectionChanged: (Set<PilotScenario> values) =>
                onScenarioChanged(values.first),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('新增匿名测试者'),
            ),
          ),
          if (participants.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final PilotParticipantRecord item in participants)
                  ChoiceChip(
                    label: Text('${item.alias} · ${item.scenario.label}'),
                    selected: item.id == selectedId,
                    onSelected: (_) => onSelected(item.id),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ParticipantProgressCard extends StatelessWidget {
  const _ParticipantProgressCard({
    required this.participant,
    required this.onCommitmentAccepted,
    required this.onCheckIn,
    required this.onFeedback,
    required this.onDepositChanged,
    required this.onContinuationChanged,
  });

  final PilotParticipantRecord participant;
  final VoidCallback? onCommitmentAccepted;
  final VoidCallback onCheckIn;
  final VoidCallback onFeedback;
  final ValueChanged<PilotDepositStatus> onDepositChanged;
  final ValueChanged<PilotContinuationDecision> onContinuationChanged;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      key: const ValueKey<String>('pilot-participant-progress-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${participant.alias} · ${participant.scenario.label}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ToneBadge(
                label: participant.commitmentAccepted ? '承诺档已确认' : '待确认承诺',
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('每晚最少信息：睡眠、疲劳、明日可用时间、疼痛。'),
          const SizedBox(height: 6),
          const Text('次日晚反馈：是否执行、体感 1–5、计划/判断/依据哪项最有价值。'),
          const SizedBox(height: 12),
          InfoRow(label: '状态已收集', value: '${participant.checkInCount}/14 天'),
          InfoRow(label: '次日反馈已收集', value: '${participant.feedbackCount}/14 天'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: onCommitmentAccepted,
                child: Text(
                  participant.commitmentAccepted ? '承诺档已确认' : '确认 14 天承诺',
                ),
              ),
              OutlinedButton(
                onPressed: onCheckIn,
                child: const Text('今日状态已收集'),
              ),
              OutlinedButton(
                onPressed: onFeedback,
                child: const Text('次日反馈已收集'),
              ),
            ],
          ),
          const Divider(height: 28),
          DropdownButtonFormField<PilotDepositStatus>(
            initialValue: participant.depositStatus,
            decoration: const InputDecoration(labelText: '押金档（只记线下状态）'),
            items: [
              for (final PilotDepositStatus value in PilotDepositStatus.values)
                DropdownMenuItem<PilotDepositStatus>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (PilotDepositStatus? value) {
              if (value != null) onDepositChanged(value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PilotContinuationDecision>(
            initialValue: participant.continuationDecision,
            decoration: const InputDecoration(labelText: '第 14 天付费档决定'),
            items: [
              for (final PilotContinuationDecision value
                  in PilotContinuationDecision.values)
                DropdownMenuItem<PilotContinuationDecision>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (PilotContinuationDecision? value) {
              if (value != null) onContinuationChanged(value);
            },
          ),
        ],
      ),
    );
  }
}

class _PrivacyBoundaryCard extends StatelessWidget {
  const _PrivacyBoundaryCard();

  @override
  Widget build(BuildContext context) {
    return const TrainFlowCard(
      child: Text(
        '隐私边界：这里只保存 T01–T05、场景、履约日期和线下状态。'
        '不要粘贴姓名、微信聊天、伤病描述、手机号、收款账号或支付凭证。',
      ),
    );
  }
}
