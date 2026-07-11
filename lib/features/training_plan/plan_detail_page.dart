import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/evidence_source.dart';
import '../../data/models/training_plan.dart';
import '../../data/models/training_rule_audit.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/workout_day.dart';
import '../dashboard/training_mvp_controller.dart';

class PlanDetailPage extends ConsumerWidget {
  final String planId;

  const PlanDetailPage({super.key, required this.planId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final TrainingPlan? plan = state.findPlan(planId);

    if (plan == null) {
      return const TrainFlowPage(
        title: '计划不存在',
        children: [
          TrainFlowCard(child: Text('没有找到对应训练计划。')),
        ],
      );
    }

    return TrainFlowPage(
      title: plan.title,
      subtitle: '${plan.sportType.label} · ${plan.level}',
      children: [
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(label: '周期', value: '${plan.durationWeeks} 周'),
              InfoRow(label: '目标', value: plan.goal),
              InfoRow(label: '结构', value: plan.weeklyStructure),
              const SizedBox(height: 8),
              Text(
                plan.description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        _RuleAuditCard(report: state.ruleAuditReportForPlan(plan)),
        const SectionTitle(title: '第 1 周训练日'),
        for (final WorkoutDay day in plan.workoutDays)
          TrainFlowCard(
            onTap: () => context.go(AppRoutes.workoutDetail(plan.id, day.id)),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    'D${day.dayIndex}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        day.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day.trainingType.label} · 决策 ${day.decisionType.label} · ${day.intensity}',
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${day.estimatedMinutes} 分钟'),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () {
                        ref
                            .read(trainingMvpProvider.notifier)
                            .startWorkoutPlayer(workoutDayId: day.id);
                        context.go(AppRoutes.workoutPlayer);
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('开始跟练'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SectionTitle(title: '依据来源'),
        _EvidenceList(sources: plan.evidenceSources),
      ],
    );
  }
}

class _EvidenceList extends StatelessWidget {
  final List<EvidenceSource> sources;

  const _EvidenceList({required this.sources});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final EvidenceSource source in sources) ...[
            Text(
              source.title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${source.author} · ${source.sourceType.label}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              source.citationLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text('原文片段：${source.quote}'),
            const SizedBox(height: 6),
            Text('适用原因：${source.note}'),
            if (source != sources.last) const Divider(height: 22),
          ],
        ],
      ),
    );
  }
}

class _RuleAuditCard extends StatelessWidget {
  final TrainingRuleAuditReport report;

  const _RuleAuditCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '规则引擎校验',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: report.statusLabel,
                color: _auditStatusColor(report),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '训练日',
                  value: '${report.checkedWorkoutCount} 天',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '引用',
                  value: '${report.citationCount} 条',
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '跑步模块',
                  value: '${report.runningModuleCount} 个',
                  color: AppColors.warningDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '最长时长',
                  value: '${report.maxEstimatedMinutes} 分钟',
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final TrainingRuleAuditItem item in report.items) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _auditIcon(item.severity),
                  color: _auditSeverityColor(item.severity),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.title} · ${item.severity.label}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (item != report.items.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

Color _auditStatusColor(TrainingRuleAuditReport report) {
  if (report.failCount > 0) {
    return AppColors.danger;
  }
  if (report.warningCount > 0) {
    return AppColors.warningDark;
  }
  return AppColors.primary;
}

Color _auditSeverityColor(TrainingRuleAuditSeverity severity) {
  switch (severity) {
    case TrainingRuleAuditSeverity.pass:
      return AppColors.primary;
    case TrainingRuleAuditSeverity.warning:
      return AppColors.warningDark;
    case TrainingRuleAuditSeverity.fail:
      return AppColors.danger;
  }
}

IconData _auditIcon(TrainingRuleAuditSeverity severity) {
  switch (severity) {
    case TrainingRuleAuditSeverity.pass:
      return Icons.check_circle_outline;
    case TrainingRuleAuditSeverity.warning:
      return Icons.error_outline;
    case TrainingRuleAuditSeverity.fail:
      return Icons.report_gmailerrorred;
  }
}
