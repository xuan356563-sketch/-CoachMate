import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/pain_log.dart';
import '../dashboard/training_mvp_controller.dart';

final rehabPainLevelProvider = NotifierProvider<RehabPainLevelController, int>(
  RehabPainLevelController.new,
);

final rehabBodyPartProvider = NotifierProvider<RehabBodyPartController, String>(
  RehabBodyPartController.new,
);

final rehabTimingProvider = NotifierProvider<RehabTimingController, PainTiming>(
  RehabTimingController.new,
);

class RehabPainLevelController extends Notifier<int> {
  @override
  int build() {
    return 4;
  }

  void setValue(int value) {
    state = value;
  }
}

class RehabBodyPartController extends Notifier<String> {
  @override
  String build() {
    return '膝盖';
  }

  void setValue(String value) {
    state = value;
  }
}

class RehabTimingController extends Notifier<PainTiming> {
  @override
  PainTiming build() {
    return PainTiming.duringTraining;
  }

  void setValue(PainTiming value) {
    state = value;
  }
}

class RehabPage extends ConsumerWidget {
  const RehabPage({super.key});

  static const List<String> _bodyParts = [
    '膝盖',
    '跟腱/小腿',
    '足底',
    '髋',
    '腰背',
    '肩颈',
    '其他',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final int painLevel = ref.watch(rehabPainLevelProvider);
    final String bodyPart = ref.watch(rehabBodyPartProvider);
    final PainTiming timing = ref.watch(rehabTimingProvider);

    return TrainFlowPage(
      title: '康复记录',
      layout: TrainFlowPageLayout.form,
      subtitle: '记录疼痛后，今日训练会自动降级；疼痛 ≥7 强制提示就医。',
      includeDisclaimer: false,
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.profile,
      ),
      artwork: const TrainMateActionCharacter(
        action: TrainMateAction.seatedForwardFold,
        backgroundColor: AppColors.primary,
      ),
      children: [
        const _RehabMedicalBoundaryCard(),
        _CurrentRiskCard(state: state),
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '疼痛记录表单',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: bodyPart,
                decoration: const InputDecoration(labelText: '疼痛部位'),
                items: [
                  for (final String part in _bodyParts)
                    DropdownMenuItem<String>(
                      value: part,
                      child: Text(part),
                    ),
                ],
                onChanged: (String? value) {
                  if (value != null) {
                    ref.read(rehabBodyPartProvider.notifier).setValue(value);
                  }
                },
              ),
              const SizedBox(height: 14),
              Text('疼痛等级：$painLevel / 10'),
              Slider(
                min: 0,
                max: 10,
                divisions: 10,
                label: '$painLevel',
                value: painLevel.toDouble(),
                onChanged: (double value) {
                  ref
                      .read(rehabPainLevelProvider.notifier)
                      .setValue(value.round());
                },
              ),
              DropdownButtonFormField<PainTiming>(
                initialValue: timing,
                decoration: const InputDecoration(labelText: '出现时机'),
                items: [
                  for (final PainTiming item in PainTiming.values)
                    DropdownMenuItem<PainTiming>(
                      value: item,
                      child: Text(item.label),
                    ),
                ],
                onChanged: (PainTiming? value) {
                  if (value != null) {
                    ref.read(rehabTimingProvider.notifier).setValue(value);
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        ref.read(trainingMvpProvider.notifier).savePainLog(
                              bodyPart: bodyPart,
                              painLevel: painLevel,
                              timing: timing,
                              note: '康复页手动记录',
                            );
                      },
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text('保存疼痛记录'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref.read(trainingMvpProvider.notifier).savePainLog(
                          bodyPart: '膝盖',
                          painLevel: 7,
                          timing: PainTiming.duringTraining,
                          note: '红线测试记录',
                        );
                  },
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('记录疼痛 7 分'),
                ),
              ),
            ],
          ),
        ),
        const SectionTitle(title: '疼痛记录'),
        if (state.painLogs.isEmpty)
          TrainFlowCard(
            cornerCharacterAction: TrainMateAction.seatedForwardFold,
            child: Text(
              '还没有疼痛记录。记录后，今日训练和 AI 教练建议会立即更新。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          )
        else
          for (final PainLog painLog in state.painLogs)
            _PainLogCard(painLog: painLog),
      ],
    );
  }
}

class _RehabMedicalBoundaryCard extends StatelessWidget {
  const _RehabMedicalBoundaryCard();

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      key: const ValueKey<String>('rehab-medical-boundary-card'),
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.medical_information_outlined,
                  color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '医疗边界与就医提示',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '这里用于记录疼痛并调整训练，不用于诊断、治疗或替代医生/物理治疗师。'
            '出现剧烈或持续加重疼痛、无法负重或活动、明显肿胀、麻木或无力，'
            '或胸痛、呼吸困难等情况，请立即停止训练并及时就医；紧急症状请联系当地急救。',
          ),
          const SizedBox(height: 8),
          Text(
            '应用中的“疼痛 ≥7 分或持续超过 14 天”是保守提醒阈值，不是医学诊断标准。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _CurrentRiskCard extends StatelessWidget {
  final TrainingMvpState state;

  const _CurrentRiskCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final PainLog? painLog = state.latestPainLog;
    if (painLog == null) {
      return const TrainFlowCard(
        child: Text('当前没有结构化疼痛记录，今日训练按原计划执行。'),
      );
    }

    final bool isRedLine = painLog.requiresMedicalAttention;
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isRedLine ? '疼痛红线已触发' : '训练已自动降级',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: '${painLog.painLevel}/10',
                color: isRedLine ? AppColors.danger : AppColors.warningDark,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isRedLine
                ? '${painLog.medicalAttentionReason}，请停止相关训练并就医。'
                : '${painLog.bodyPart}疼痛 ${painLog.painLevel} 分，今日训练切换为恢复课。',
          ),
        ],
      ),
    );
  }
}

class _PainLogCard extends StatelessWidget {
  final PainLog painLog;

  const _PainLogCard({required this.painLog});

  @override
  Widget build(BuildContext context) {
    final bool isRedLine = painLog.requiresMedicalAttention;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  painLog.bodyPart,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: isRedLine ? '就医红线' : '降级参考',
                color: isRedLine ? AppColors.danger : AppColors.warningDark,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('疼痛 ${painLog.painLevel}/10 · ${painLog.timing.label}'),
          if (painLog.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              painLog.note,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
