import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/trainmate_visual_mode.dart';
import '../../core/theme/trainflow_tokens.dart';
import '../../core/widgets/flow_mascot.dart';
import '../../core/widgets/trainmate_showcase_widgets.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/training_metrics.dart';
import '../../data/models/plan_revision_proposal.dart';
import '../../data/models/workout_day.dart';
import '../../data/models/training_schedule.dart';
import '../../services/four_week_plan_generator.dart';
import '../dashboard/training_mvp_controller.dart';
import '../guided_workout/data/guided_workout_catalog_loader.dart';
import '../guided_workout/domain/guided_workout_course.dart';
import '../guided_workout/presentation/guided_workout_pages.dart';
import '../profile/application/training_schedule_controller.dart';
import 'application/adjustment_proposal_controller.dart';
import 'application/four_week_plan_controller.dart';
import 'application/plan_revision_controller.dart';

FlowMascotSpec selectPlanMascotSpec({
  required bool hasPlans,
  required bool hasAvailability,
  required bool hasScheduledWorkouts,
  required bool hasProposedAdjustment,
  required bool hasConfirmedAdjustment,
}) {
  if (hasProposedAdjustment) {
    return const FlowMascotSpec(
      action: FlowMascotAction.pointSuggestion,
      expression: FlowMascotExpression.focused,
      semanticLabel: 'Flow 训练伙伴指向待确认的负荷调整建议',
      durationMilliseconds: 460,
    );
  }
  if (hasConfirmedAdjustment ||
      (hasPlans && hasAvailability && hasScheduledWorkouts)) {
    return const FlowMascotSpec(
      action: FlowMascotAction.nodCheck,
      expression: FlowMascotExpression.happy,
      semanticLabel: 'Flow 训练伙伴点头确认训练日程',
      durationMilliseconds: 420,
      motionCycles: 2,
    );
  }
  return const FlowMascotSpec(
    action: FlowMascotAction.thinkCalendar,
    expression: FlowMascotExpression.curious,
    semanticLabel: 'Flow 训练伙伴正在思考训练日历',
    durationMilliseconds: 580,
  );
}

class PlanListPage extends ConsumerWidget {
  const PlanListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final TrainingScheduleState schedule =
        ref.watch(trainingScheduleControllerProvider);
    final FourWeekPlanState fourWeekPlan =
        ref.watch(fourWeekPlanControllerProvider);
    final AsyncValue<AdjustmentProposalState> adjustmentProposals =
        ref.watch(acwrAdjustmentProposalControllerProvider);
    final AsyncValue<GuidedWorkoutCatalog> guidedWorkoutCatalog =
        ref.watch(guidedWorkoutCatalogProvider);
    final List<AdjustmentProposal> proposals = switch (adjustmentProposals) {
      AsyncData<AdjustmentProposalState>(:final value) => value.proposals,
      _ => const <AdjustmentProposal>[],
    };
    final FlowMascotSpec mascotSpec = selectPlanMascotSpec(
      hasPlans: state.plans.isNotEmpty,
      hasAvailability: schedule.availability.isNotEmpty,
      hasScheduledWorkouts: schedule.workouts.isNotEmpty,
      hasProposedAdjustment: proposals.any(
        (AdjustmentProposal proposal) =>
            proposal.status == AdjustmentProposalStatus.proposed,
      ),
      hasConfirmedAdjustment: proposals.any(
        (AdjustmentProposal proposal) =>
            proposal.status == AdjustmentProposalStatus.confirmed,
      ),
    );

    final ScheduledWorkout? nextWorkout = schedule.workouts.isEmpty
        ? null
        : (List<ScheduledWorkout>.of(schedule.workouts)
              ..sort((ScheduledWorkout a, ScheduledWorkout b) =>
                  a.scheduledDate.compareTo(b.scheduledDate)))
            .first;
    final String planTitle =
        state.plans.isEmpty ? '还没有训练计划' : state.plans.first.title;
    final String scheduleSubtitle = nextWorkout == null
        ? '尚未安排训练日 · 点击生成并确认计划'
        : '${nextWorkout.scheduledDate.month} 月 ${nextWorkout.scheduledDate.day} 日 · ${nextWorkout.timeLabel} · ${nextWorkout.allocatedMinutes} 分钟';

    return TrainMateImmersiveHubPage(
      mode: TrainMateVisualMode.darkTraining,
      hero: KeyedSubtree(
        key: const ValueKey<String>('plans-showcase-header'),
        child: TrainMateSceneHero(
          sceneAsset:
              'assets/images/immersive_scenes/trainmate_plan_studio.png',
          greeting:
              '你好，${state.profile.name.trim().isEmpty ? '训练者' : state.profile.name}',
          dateLabel: '${DateTime.now().month} 月 ${DateTime.now().day} 日 · 本周节奏',
          character: TrainMateIllustration(
            assetPath: 'assets/images/trainmate_plans_showcase.png',
            semanticLabel: '训练计划人物插画',
            fallback: FloatingFlowMascot(size: 156, spec: mascotSpec),
          ),
          taskTitle: planTitle,
          taskSubtitle: scheduleSubtitle,
          taskIcon: Icons.calendar_month_rounded,
          actionTooltip: '生成训练计划',
          onAction: () => context.push(AppRoutes.planGenerate),
          onTaskTap: () => context.push(AppRoutes.planGenerate),
          taskProgress: schedule.workouts.isEmpty
              ? 0
              : (schedule.workouts.length / state.profile.weeklyTrainingDays)
                  .clamp(0, 1),
          taskProgressLabel: '本周已排期 ${schedule.workouts.length} 次',
        ),
      ),
      children: [
        TrainMateStatusStrip(
          semanticLabel: '计划状态',
          onTap: () => context.push(AppRoutes.planGenerate),
          metrics: <TrainMateStatusMetric>[
            TrainMateStatusMetric(
                label: '计划',
                value: '${state.plans.length} 个',
                icon: Icons.calendar_month_outlined),
            TrainMateStatusMetric(
                label: '已排期',
                value: '${schedule.workouts.length} 次',
                icon: Icons.schedule_outlined,
                color: AppColors.secondaryLight),
            TrainMateStatusMetric(
                label: '周期',
                value: fourWeekPlan.currentPhase.label,
                icon: Icons.timelapse_outlined),
          ],
        ),
        const SizedBox(height: 20),
        TrainMateOverviewGrid(
          first: _PlanOverviewTile(
              label: '本周节奏',
              value: '${schedule.workouts.length} 次',
              icon: Icons.date_range_outlined),
          second: _PlanOverviewTile(
              label: '四周阶段',
              value: '当前 ${fourWeekPlan.currentPhase.label}',
              icon: Icons.auto_graph_outlined),
          trend: _PlanOverviewTile(
              label: '更新状态',
              value: fourWeekPlan.executionLocked
                  ? '执行已锁定'
                  : (fourWeekPlan.updateAvailable ? '有待确认更新' : '计划保持稳定'),
              icon: Icons.sync_outlined,
              wide: true),
        ),
        const SizedBox(height: 20),
        TrainFlowCard(
          tone: TrainFlowCardTone.peach,
          cornerCharacterAction:
              trainMateActionForFlowMascot(mascotSpec.action),
          onTap: () => context.push(AppRoutes.planGenerate),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '生成新的四周计划',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (fourWeekPlan.executionLocked)
                    const ToneBadge(label: '执行已锁定')
                  else if (fourWeekPlan.updateAvailable)
                    const ToneBadge(label: '需要更新'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                fourWeekPlan.executionLocked
                    ? '${fourWeekPlan.executionLockReason ?? '筛查状态无效。'}已切换本地安全计划；请进入统一入口处理。'
                    : fourWeekPlan.updateAvailable
                        ? '档案、赛事或 Skill 版本已变化，当前计划不会自动替换；请进入统一入口重新生成并确认。'
                        : '由已审核 Skill 生成结构化处方，本地安全审计通过并确认后才会激活。',
              ),
              const SizedBox(height: 10),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('开始生成'),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ],
          ),
        ),
        Semantics(
          key: const ValueKey<String>('race-prep-entry'),
          container: true,
          button: true,
          child: TrainFlowCard(
            onTap: () => context.push(AppRoutes.races),
            child: Row(
              children: [
                const Icon(
                  Icons.emoji_events_outlined,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '比赛备战',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '导入赛事并查看备赛阶段、倒计时和赛后成绩。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
        _AcwrAdjustmentProposalSection(state: adjustmentProposals),
        const _PlanRevisionSection(),
        guidedWorkoutCatalog.when(
          data: (GuidedWorkoutCatalog catalog) => GuidedWorkoutCourseSection(
            courses: catalog.courses,
            onSelected: (String id) =>
                context.push(AppRoutes.guidedWorkoutDetail(id)),
          ),
          loading: () => const SizedBox.shrink(),
          error: (Object error, StackTrace stackTrace) => TrainFlowCard(
            child: Text('跳绳跟练课程暂时无法读取：$error'),
          ),
        ),
        if (state.plans.isNotEmpty) ...[
          const SectionTitle(title: '本周训练节奏'),
          _ScheduledWeekCard(schedule: schedule),
          _WeekRhythmCard(
            days: state.plans.first.workoutDays
                .where((WorkoutDay day) => day.weekIndex == 1)
                .toList(),
          ),
          const SectionTitle(title: '4 周阶段'),
          _FourWeekOverview(state: fourWeekPlan),
          const SectionTitle(title: '训练方案'),
        ],
        for (int index = 0; index < state.plans.length; index++)
          TrainFlowCard(
            tone:
                index == 0 ? TrainFlowCardTone.peach : TrainFlowCardTone.paper,
            onTap: () => context.push(
              AppRoutes.planDetail(state.plans[index].id),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.plans[index].title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    ToneBadge(label: '${state.plans[index].durationWeeks} 周'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  state.plans[index].description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 12),
                InfoRow(label: '目标', value: state.plans[index].goal),
                InfoRow(
                  label: '周结构',
                  value: state.plans[index].weeklyStructure,
                ),
                const SizedBox(height: 8),
                _WorkoutPreview(
                  days: state.plans[index].workoutDays.take(4).toList(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PlanOverviewTile extends StatelessWidget {
  const _PlanOverviewTile(
      {required this.label,
      required this.value,
      required this.icon,
      this.wide = false});
  final String label;
  final String value;
  final IconData icon;
  final bool wide;
  @override
  Widget build(BuildContext context) => TrainFlowCard(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: wide ? 108 : 132),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: TrainFlowTokens.accent),
              const SizedBox(height: 14),
              TrainMateMetricValue(value: value, label: label),
            ],
          ),
        ),
      );
}

class _PlanRevisionSection extends ConsumerStatefulWidget {
  const _PlanRevisionSection();

  @override
  ConsumerState<_PlanRevisionSection> createState() =>
      _PlanRevisionSectionState();
}

class _PlanRevisionSectionState extends ConsumerState<_PlanRevisionSection> {
  @override
  Widget build(BuildContext context) {
    final PlanRevisionState revision =
        ref.watch(planRevisionControllerProvider);
    final trigger = revision.triggerSnapshot;
    final bool hasTrigger = trigger?.shouldSuggest ?? false;
    return TrainFlowCard(
      tone: TrainFlowCardTone.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '剩余周期重排',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text('系统会从实际日程与训练日志自动计算；只有结构性变化才建议云端重排，并且确认后才生效。'),
          const SizedBox(height: 12),
          if (trigger != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                MetricPill(
                    label: '已完成', value: '${trigger.completedSessions} 次'),
                MetricPill(label: '已漏练', value: '${trigger.missedSessions} 次'),
                MetricPill(
                    label: '日程变化', value: '${trigger.changedScheduleDays} 天'),
                MetricPill(
                  label: '器械',
                  value: trigger.equipmentChanged ? '有变化' : '无变化',
                ),
              ],
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !hasTrigger ||
                      revision.isBusy ||
                      (trigger?.localSafetyOnly ?? false)
                  ? null
                  : () => ref
                      .read(planRevisionControllerProvider.notifier)
                      .propose(),
              icon: const Icon(Icons.compare_arrows),
              label: Text(revision.isBusy ? '处理中…' : '生成重排差异'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            revision.statusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          if (revision.proposal != null) ...<Widget>[
            const Divider(height: 24),
            for (final PlanRevisionDifference difference
                in revision.proposal!.differences)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '第 ${difference.sessionIndex + 1} 节：'
                  '${difference.beforeTrainingType} '
                  '${difference.beforeDurationMinutes} 分钟 → '
                  '${difference.afterTrainingType} '
                  '${difference.afterDurationMinutes} 分钟',
                ),
              ),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: revision.isBusy
                        ? null
                        : () => ref
                            .read(planRevisionControllerProvider.notifier)
                            .reject(),
                    child: const Text('拒绝'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: revision.isBusy
                        ? null
                        : () => ref
                            .read(planRevisionControllerProvider.notifier)
                            .confirm(),
                    child: const Text('确认并激活'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AcwrAdjustmentProposalSection extends ConsumerWidget {
  const _AcwrAdjustmentProposalSection({required this.state});

  final AsyncValue<AdjustmentProposalState> state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return state.when(
      loading: () => const SizedBox.shrink(),
      error: (Object _, StackTrace __) => TrainFlowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('负荷调整建议暂时无法读取。'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () =>
                  ref.invalidate(acwrAdjustmentProposalControllerProvider),
              child: const Text('重新读取'),
            ),
          ],
        ),
      ),
      data: (AdjustmentProposalState value) {
        if (value.proposals.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(title: '待确认的负荷调整'),
            for (final AdjustmentProposal proposal in value.proposals.take(3))
              _AdjustmentProposalCard(proposal: proposal),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                value.statusMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AdjustmentProposalCard extends ConsumerWidget {
  const _AdjustmentProposalCard({required this.proposal});

  final AdjustmentProposal proposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool canApply =
        proposal.workoutDayId != null || proposal.workoutChanges.isNotEmpty;
    return TrainFlowCard(
      tone: proposal.status == AdjustmentProposalStatus.proposed
          ? TrainFlowCardTone.peach
          : TrainFlowCardTone.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  proposal.workoutTitle,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: _proposalStatusLabel(proposal.status)),
            ],
          ),
          const SizedBox(height: 8),
          Text(proposal.explanation),
          const SizedBox(height: 10),
          InfoRow(
            label: '触发依据',
            value:
                '${proposal.triggerMetricCode} · ${proposal.triggerAlgorithmVersion}',
          ),
          InfoRow(
            label: '差异预览',
            value: '${proposal.originalMinutes} → '
                '${proposal.adjustedMinutes} 分钟；'
                '${proposal.originalIntensity} → ${proposal.adjustedIntensity}',
          ),
          if (proposal.workoutChanges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '将按以下不可变快照一次性应用；任一训练日已变化都会停止整组修改：',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 6),
            for (final AdjustmentProposalWorkoutChange change
                in proposal.workoutChanges)
              Text(
                '· ${change.workoutTitle}：${change.originalMinutes} → '
                '${change.adjustedMinutes} 分钟',
              ),
          ],
          if (proposal.status == AdjustmentProposalStatus.proposed) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: canApply
                        ? () {
                            ref
                                .read(
                                  acwrAdjustmentProposalControllerProvider
                                      .notifier,
                                )
                                .confirm(proposal.id);
                          }
                        : null,
                    child: Text(canApply ? '确认应用' : '建议暂不可执行'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    ref
                        .read(
                          acwrAdjustmentProposalControllerProvider.notifier,
                        )
                        .reject(proposal.id);
                  },
                  child: const Text('不采用'),
                ),
              ],
            ),
          ],
          if (proposal.status == AdjustmentProposalStatus.confirmed) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                ref
                    .read(
                      acwrAdjustmentProposalControllerProvider.notifier,
                    )
                    .undo(proposal.id);
              },
              icon: const Icon(Icons.undo),
              label: const Text('撤销本次调整'),
            ),
          ],
        ],
      ),
    );
  }
}

String _proposalStatusLabel(AdjustmentProposalStatus status) {
  return switch (status) {
    AdjustmentProposalStatus.proposed => '待确认',
    AdjustmentProposalStatus.confirmed => '已应用',
    AdjustmentProposalStatus.rejected => '已拒绝',
    AdjustmentProposalStatus.undone => '已撤销',
  };
}

class _FourWeekOverview extends StatelessWidget {
  const _FourWeekOverview({required this.state});

  final FourWeekPlanState state;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.statusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          for (final GeneratedPlanWeek week in state.generation.weeks)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ToneBadge(label: week.phase.label),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '第 ${week.weekIndex} 周 · ${week.workouts.length} 练',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          week.focus,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
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

class _ScheduledWeekCard extends StatelessWidget {
  final TrainingScheduleState schedule;

  const _ScheduledWeekCard({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final DateTime end = now.add(const Duration(days: 7));
    final List<ScheduledWorkout> workouts = schedule.workouts
        .where((item) =>
            !item.scheduledDate
                .isBefore(DateTime(now.year, now.month, now.day)) &&
            item.scheduledDate.isBefore(end))
        .toList();
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '按可用时间自动安排',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (workouts.isEmpty)
            const Text('本周尚无排期，请到“我的 > 训练日程”添加可训练时间。')
          else
            for (final ScheduledWorkout workout in workouts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InfoRow(
                  label:
                      '${workout.scheduledDate.month}/${workout.scheduledDate.day}',
                  value:
                      '${workout.timeLabel} · ${workout.allocatedMinutes} 分钟 · ${workout.version.label}',
                ),
              ),
        ],
      ),
    );
  }
}

class _WeekRhythmCard extends StatelessWidget {
  final List<WorkoutDay> days;

  const _WeekRhythmCard({required this.days});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int index = 0; index < 7; index++)
            Expanded(
              child: _WeekDayMarker(
                index: index,
                day: index < days.length ? days[index] : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekDayMarker extends StatelessWidget {
  final int index;
  final WorkoutDay? day;

  const _WeekDayMarker({required this.index, required this.day});

  @override
  Widget build(BuildContext context) {
    final bool hasWorkout = day != null;
    return Tooltip(
      message: day?.title ?? '恢复或机动日',
      child: Column(
        children: [
          Text(
            'D${index + 1}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: hasWorkout ? AppColors.primary : AppColors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 1.5),
            ),
            child: Icon(
              hasWorkout ? Icons.fitness_center : Icons.hotel_outlined,
              size: 16,
              color: hasWorkout ? AppColors.secondary : AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            day?.trainingType.label ?? '恢复',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                  fontSize: 9,
                ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutPreview extends StatelessWidget {
  final List<WorkoutDay> days;

  const _WorkoutPreview({required this.days});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final WorkoutDay day in days)
          ToneBadge(
            label:
                'D${day.dayIndex} ${day.trainingType.label}/${day.decisionType.label}',
            color: AppColors.secondary,
          ),
      ],
    );
  }
}
