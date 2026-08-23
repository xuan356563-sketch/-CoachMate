import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/user_insight.dart';
import '../../data/models/user_trust_review.dart';
import '../dashboard/training_mvp_controller.dart';

class UserInsightPage extends ConsumerWidget {
  const UserInsightPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);

    return TrainFlowPage(
      title: '用户画像',
      layout: TrainFlowPageLayout.report,
      subtitle: '越用越懂、越用越简单、越用越相信。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.profile,
      ),
      artwork: const TrainMateActionCharacter(
        action: TrainMateAction.seatedMeditation,
        backgroundColor: AppColors.primary,
      ),
      children: [
        _InsightSummaryCard(state: state),
        _TrustReviewCard(report: state.userTrustReviewReport),
        const SectionTitle(title: '画像结论'),
        for (final UserProfileInsight insight in state.userProfileInsights)
          _InsightCard(insight: insight),
        const SectionTitle(title: '学习信号 profile_events'),
        for (final ProfileEvent event in state.profileEvents.take(8))
          _ProfileEventCard(event: event),
        const SectionTitle(title: '预测对账 prediction_logs'),
        for (final PredictionLog prediction in state.predictionLogs)
          _PredictionCard(prediction: prediction),
      ],
    );
  }
}

class _InsightSummaryCard extends ConsumerWidget {
  final TrainingMvpState state;

  const _InsightSummaryCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserInsightTableState tableState = state.userInsightTableState;
    final UserInsightWeeklyTask? latestTask = tableState.latestWeeklyTask;

    return TrainFlowCard(
      cornerCharacterAction: TrainMateAction.seatedMeditation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '透明画像',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: state.userInsightSummaryLabel),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '学习信号',
                  value: '${state.profileEvents.length} 条',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '预测记录',
                  value: '${state.predictionLogs.length} 条',
                  color: TrainFlowTokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          MetricPill(
            label: '到期回填',
            value: state.predictionBackfillSummaryLabel,
            color: AppColors.success,
          ),
          const SizedBox(height: 12),
          Text(
            state.userInsightStatusMessage,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.grayLightest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.table_chart_outlined,
                        color: TrainFlowTokens.darkTrainingMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '本地画像三表',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      ToneBadge(
                        label: state.userInsightTableSummaryLabel,
                        color: TrainFlowTokens.darkTrainingMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: MetricPill(
                          label: 'profile_events',
                          value: '${tableState.profileEvents.length} 行',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MetricPill(
                          label: 'user_profiles',
                          value: '${tableState.userProfiles.length} 行',
                          color: TrainFlowTokens.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: MetricPill(
                          label: 'prediction_logs',
                          value: '${tableState.predictionLogs.length} 行',
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MetricPill(
                          label: '周度任务',
                          value: '${tableState.weeklyTasks.length} 次',
                          color: AppColors.warningDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    latestTask == null
                        ? '尚未生成周度画像任务；当前页面展示的是实时派生结果。'
                        : '最近任务：${state.userInsightWeeklyTaskLabel}，${latestTask.statusLabel}。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TrainFlowTokens.darkTrainingMuted,
                        ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => ref
                          .read(trainingMvpProvider.notifier)
                          .generateWeeklyUserInsightTask(),
                      icon: const Icon(Icons.task_alt),
                      label: const Text('生成周度画像任务'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('本地自用版：画像不上传；置信度不足时只给保守策略。'),
        ],
      ),
    );
  }
}

class _TrustReviewCard extends StatelessWidget {
  final UserTrustReviewReport report;

  const _TrustReviewCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined,
                  color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '信任回顾',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: '本地透明'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '预测准确率',
                  value: report.predictionAccuracyLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '不确定性',
                  value: report.uncertaintyLabel,
                  color: TrainFlowTokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(report.predictionAccuracyDetail),
          const SizedBox(height: 8),
          Text(
            report.uncertaintyDetail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          InfoRow(label: '数据主权', value: report.dataOwnershipLabel),
          Text(
            report.dataOwnershipDetail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            '兑现回顾',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final TrustReviewItem item in report.reviewItems.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child:
                  Text('· ${item.title}：${item.detail}（${item.evidenceLabel}）'),
            ),
        ],
      ),
    );
  }
}

class _InsightCard extends ConsumerWidget {
  final UserProfileInsight insight;

  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color color = _dimensionColor(insight.dimension);

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_graph, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  insight.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: insight.dimension.label, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Text(insight.conclusion),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '置信度',
                  value: insight.confidenceLabel,
                  color: insight.lowConfidence ? AppColors.warningDark : color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '证据数',
                  value: '${insight.evidenceLabels.length} 条',
                  color: TrainFlowTokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '证据：${insight.evidenceLabels.join(' / ')}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '保守策略：${insight.conservativeAction}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () {
                ref
                    .read(trainingMvpProvider.notifier)
                    .markInsightNeedsCorrection(insight);
              },
              icon: const Icon(Icons.edit_note),
              label: const Text('标记不准'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileEventCard extends StatelessWidget {
  final ProfileEvent event;

  const _ProfileEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: TrainFlowTokens.darkTrainingRaised,
            child: Text(event.dateLabel),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    ToneBadge(label: event.type.label),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  event.detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TrainFlowTokens.darkTrainingMuted,
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

class _PredictionCard extends StatelessWidget {
  final PredictionLog prediction;

  const _PredictionCard({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final Color color = switch (prediction.status) {
      PredictionStatus.hit => AppColors.success,
      PredictionStatus.missed => AppColors.warningDark,
      PredictionStatus.pending => AppColors.secondary,
    };

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  prediction.predictionType,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: prediction.status.label, color: color),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(label: '预测值', value: prediction.predictedValue),
          InfoRow(label: '到期', value: prediction.dueDateLabel),
          InfoRow(label: '回填状态', value: prediction.settlementLabel),
          InfoRow(label: '实际值', value: prediction.actualValue ?? '等待回填'),
        ],
      ),
    );
  }
}

Color _dimensionColor(UserInsightDimension dimension) {
  switch (dimension) {
    case UserInsightDimension.basic:
      return AppColors.primary;
    case UserInsightDimension.behavior:
      return AppColors.secondary;
    case UserInsightDimension.physiology:
      return AppColors.warningDark;
    case UserInsightDimension.preference:
      return AppColors.success;
  }
}
