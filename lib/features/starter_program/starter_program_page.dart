import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/evidence_source.dart';
import '../../data/models/starter_graduation_report.dart';
import '../../data/models/starter_program.dart';
import '../dashboard/training_mvp_controller.dart';

class StarterProgramPage extends ConsumerWidget {
  const StarterProgramPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final StarterProgramDay day = state.activeStarterProgramDay;

    return TrainFlowPage(
      title: '30 天渐进引导',
      subtitle: '新手默认入口：低到不可能失败，每天只增强一点点。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.dailyCheckIn,
      ),
      artwork: const TrainMateActionCharacter(
        action: TrainMateAction.jumpRope,
        backgroundColor: AppColors.primary,
      ),
      children: [
        _StarterProgramSummaryCard(state: state),
        _StarterProgramTodayCard(day: day, state: state),
        _StarterGraduationPreviewCard(state: state),
        _StarterEvidenceCard(sources: day.evidenceSources),
      ],
    );
  }
}

class _StarterProgramSummaryCard extends ConsumerWidget {
  final TrainingMvpState state;

  const _StarterProgramSummaryCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrainFlowCard(
      cornerCharacterAction: TrainMateAction.jumpRope,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_circle, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '新手冷启动',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: state.starterProgramGoal.label),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<StarterProgramGoal>(
            initialValue: state.starterProgramGoal,
            decoration: const InputDecoration(labelText: '引导目标'),
            items: [
              for (final StarterProgramGoal goal in StarterProgramGoal.values)
                DropdownMenuItem<StarterProgramGoal>(
                  value: goal,
                  child: Text(goal.label),
                ),
            ],
            onChanged: (StarterProgramGoal? value) {
              if (value != null) {
                ref.read(trainingMvpProvider.notifier).setStarterProgramGoal(
                      value,
                    );
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '当前进度',
                  value: '第 ${state.starterProgramDayIndex}/30 天',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '累计成长日',
                  value: '${state.starterProgramStreak} 天',
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            state.starterProgramStatusMessage,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _StarterProgramTodayCard extends ConsumerWidget {
  final StarterProgramDay day;
  final TrainingMvpState state;

  const _StarterProgramTodayCard({
    required this.day,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<String> trainingSteps = state.starterProgramRescueMode
        ? [day.rescueVersion]
        : day.trainingSteps;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  day.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: day.dayLabel),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ToneBadge(label: day.weekTheme, color: AppColors.secondary),
              ToneBadge(label: '${day.durationMinutes} 分钟'),
              if (day.isGraduationTest)
                const ToneBadge(label: '毕业测试', color: AppColors.warningDark),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '今天做什么',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final String step in trainingSteps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(step)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          InfoRow(label: '今天照吃', value: day.mealInstruction),
          InfoRow(label: '调坡度', value: day.adjustmentRule),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final StarterProgramFeedback feedback
                  in StarterProgramFeedback.values)
                OutlinedButton(
                  onPressed: () {
                    ref
                        .read(trainingMvpProvider.notifier)
                        .completeStarterProgramDay(feedback);
                  },
                  child: Text(feedback.label),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(trainingMvpProvider.notifier)
                        .useStarterRescueVersion();
                  },
                  icon: const Icon(Icons.local_fire_department_outlined),
                  label: const Text('5 分钟补救版'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(trainingMvpProvider.notifier)
                        .postponeStarterProgramDay();
                  },
                  icon: const Icon(Icons.event_repeat),
                  label: const Text('漏练顺延'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StarterGraduationPreviewCard extends StatelessWidget {
  final TrainingMvpState state;

  const _StarterGraduationPreviewCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final StarterGraduationReport report = state.starterGraduationReport;
    final String buttonLabel = report.readyForFormalPlan ? '查看毕业报告' : '预览毕业报告';

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '毕业报告',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: report.readyForFormalPlan ? '已生成' : '第 30 天生成',
                color: report.readyForFormalPlan
                    ? AppColors.primary
                    : AppColors.warningDark,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            report.transitionSummary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
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
                  label: '心率趋势',
                  value: report.heartRateTrendLabel,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push(AppRoutes.starterGraduation),
              icon: const Icon(Icons.assessment_outlined),
              label: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _StarterEvidenceCard extends StatelessWidget {
  final List<EvidenceSource> sources;

  const _StarterEvidenceCard({required this.sources});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '为什么这样安排',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final EvidenceSource source in sources) ...[
            Text(
              source.citationLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text('原文片段：${source.quote}'),
            const SizedBox(height: 4),
            Text(
              '适用原因：${source.note}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            if (source != sources.last) const Divider(height: 18),
          ],
        ],
      ),
    );
  }
}
