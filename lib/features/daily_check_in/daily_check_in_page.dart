import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/daily_check_in.dart';
import '../dashboard/training_mvp_controller.dart';

class DailyCheckInPage extends ConsumerWidget {
  const DailyCheckInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final DailyCheckInSummary summary = state.dailyCheckInSummary;

    return TrainFlowPage(
      title: '精简签到',
      subtitle: '用户理解引擎消费端 Mock：默认值来自画像，置信度足够时只问必要项。',
      children: [
        _DailyCheckInSummaryCard(summary: summary, state: state),
        _DailyCheckInPromptCard(summary: summary),
        _DailyCheckInActionCard(summary: summary),
      ],
    );
  }
}

class _DailyCheckInSummaryCard extends StatelessWidget {
  final DailyCheckInSummary summary;
  final TrainingMvpState state;

  const _DailyCheckInSummaryCard({
    required this.summary,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '输入递减',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: summary.modeLabel),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '今天只问',
                  value: summary.questionCountLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '默认值',
                  value: summary.confidenceLabel,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(summary.explanation),
          const SizedBox(height: 8),
          Text(
            summary.sortExplanation,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            state.dailyCheckInStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _DailyCheckInPromptCard extends StatelessWidget {
  final DailyCheckInSummary summary;

  const _DailyCheckInPromptCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日需要确认',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            summary.sortExplanation,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 10),
          for (final DailyCheckInPrompt prompt in summary.prompts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    prompt.required
                        ? Icons.radio_button_checked
                        : Icons.auto_awesome,
                    size: 18,
                    color: prompt.required
                        ? AppColors.primary
                        : AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'P${prompt.priorityRank} ${prompt.label}：${prompt.value} · ${prompt.sourceLabel} · ${prompt.priorityReason}',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DailyCheckInActionCard extends ConsumerWidget {
  final DailyCheckInSummary summary;

  const _DailyCheckInActionCard({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '一键确认',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '确认本身会成为 profile_events 的学习信号；当前先写入本地身体数据列表。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: summary.canUseYesterday
                  ? () {
                      ref
                          .read(trainingMvpProvider.notifier)
                          .confirmDailyCheckInSameAsYesterday();
                    }
                  : null,
              icon: const Icon(Icons.repeat),
              label: const Text('和昨天一样'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ref
                    .read(trainingMvpProvider.notifier)
                    .recordTiredDailyCheckIn();
              },
              icon: const Icon(Icons.battery_saver_outlined),
              label: const Text('今天偏累，建议轻松版'),
            ),
          ),
        ],
      ),
    );
  }
}
