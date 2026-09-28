import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/formal_ai_plan.dart';
import '../../data/models/starter_graduation_report.dart';
import '../dashboard/training_mvp_controller.dart';

class StarterGraduationPage extends ConsumerWidget {
  const StarterGraduationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final StarterGraduationReport report = state.starterGraduationReport;

    return TrainFlowPage(
      title: '30 天毕业报告',
      layout: TrainFlowPageLayout.report,
      subtitle: '第 30 天结束后，用完成率、心率变化和主观感受趋势衔接正式 AI 个性化周期。',
      animateChildren: true,
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.starterProgram,
      ),
      artwork: const TrainMateActionCharacter(
        action: TrainMateAction.jumpingJack,
        backgroundColor: AppColors.primary,
      ),
      children: [
        _GraduationSummaryCard(report: report, state: state),
        _AbilityAssessmentCard(report: report),
        _HeartRateTrendCard(report: report),
        _SubjectiveTrendCard(report: report),
        _FormalPlanTransitionCard(report: report, state: state),
      ],
    );
  }
}

class _GraduationSummaryCard extends StatelessWidget {
  final StarterGraduationReport report;
  final TrainingMvpState state;

  const _GraduationSummaryCard({
    required this.report,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      cornerCharacterAction: TrainMateAction.jumpingJack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '毕业评估',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(
                label: report.readyForFormalPlan ? '可切换' : '预览中',
                color: report.readyForFormalPlan
                    ? AppColors.primary
                    : AppColors.warningDark,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '完成率',
                  value: report.completionRateLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '完成天数',
                  value: '${report.completedDays}/${report.totalDays}',
                  color: TrainFlowTokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: report.completionRate,
            minHeight: 8,
            color: TrainFlowTokens.accent,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 10),
          Text(
            '目标：${report.goalLabel} · 当前第 ${state.starterProgramDayIndex}/30 天 · 生成于 ${report.generatedDateLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _AbilityAssessmentCard extends StatelessWidget {
  final StarterGraduationReport report;

  const _AbilityAssessmentCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '能力评估',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(report.abilitySummary),
          const SizedBox(height: 12),
          InfoRow(
              label: '准备度',
              value: '${report.readinessScore ?? '无法评估'} · ${report.readinessLabel}'),
        ],
      ),
    );
  }
}

class _HeartRateTrendCard extends StatelessWidget {
  final StarterGraduationReport report;

  const _HeartRateTrendCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_outline, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '心率变化',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: report.heartRateTrendLabel),
            ],
          ),
          const SizedBox(height: 10),
          Text(report.heartRateTrendDetail),
        ],
      ),
    );
  }
}

class _SubjectiveTrendCard extends StatelessWidget {
  final StarterGraduationReport report;

  const _SubjectiveTrendCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt_outlined,
                  color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '主观感受趋势',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: report.subjectiveTrendLabel),
            ],
          ),
          const SizedBox(height: 10),
          Text(report.subjectiveTrendDetail),
        ],
      ),
    );
  }
}

class _FormalPlanTransitionCard extends ConsumerWidget {
  final StarterGraduationReport report;
  final TrainingMvpState state;

  const _FormalPlanTransitionCard({
    required this.report,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '正式 AI 计划衔接',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: state.formalPlanUnlocked ? '已切换' : '待切换'),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(label: '推荐周期', value: report.recommendedNextPlan),
          const SizedBox(height: 4),
          Text(report.transitionSummary),
          const SizedBox(height: 10),
          Text(
            state.formalPlanStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          if (state.formalAiPlan != null) ...[
            const SizedBox(height: 12),
            _FormalAiPlanGeneratedCard(plan: state.formalAiPlan!),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: report.readyForFormalPlan
                      ? () {
                          ref
                              .read(trainingMvpProvider.notifier)
                              .unlockFormalAiPlanFromGraduation();
                        }
                      : null,
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('切换正式 AI 计划'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.go(AppRoutes.plans),
                  icon: const Icon(Icons.list_alt),
                  label: const Text('查看计划'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormalAiPlanGeneratedCard extends StatelessWidget {
  final FormalAiPlan plan;

  const _FormalAiPlanGeneratedCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TrainFlowTokens.darkTrainingRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已生成正式周期',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            InfoRow(label: '周期名称', value: plan.title),
            InfoRow(label: '周期长度', value: plan.durationLabel),
            InfoRow(label: '训练结构', value: plan.weeklyStructure),
            InfoRow(label: '渐进规则', value: plan.progressionRule),
            InfoRow(label: '安全规则', value: plan.safetyRule),
            const SizedBox(height: 8),
            Text(
              '4 周重点',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final String focus in plan.weeklyFocus)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('· $focus'),
              ),
          ],
        ),
      ),
    );
  }
}
