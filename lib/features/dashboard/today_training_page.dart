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
import '../../data/local/trainmate_structured_database_gateway.dart';
import '../../data/models/daily_adjustment.dart';
import '../../data/models/body_metric.dart';
import '../../data/models/growth_evidence.dart';
import '../../data/models/pain_log.dart';
import '../../data/models/training_log.dart';
import '../../data/models/training_metrics.dart';
import '../../data/models/training_schedule.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/workout_day.dart';
import '../../services/growth_engine.dart';
import '../growth/application/growth_evidence_controller.dart';
import '../growth/application/local_training_fact_sync.dart';
import '../growth/application/training_metrics_projection_service.dart';
import '../growth/application/training_metrics_provider.dart';
import '../growth/ability_progress_overview.dart';
import '../profile/application/training_schedule_controller.dart';
import '../rhythm/application/body_rhythm_controller.dart';
import '../profile/application/user_profile_controller.dart';
import '../training_log/presentation/training_record_editor.dart';
import 'training_mvp_controller.dart';
import 'widgets/today_showcase_header.dart';

FlowMascotSpec selectTodayMascotSpec({
  required bool profileCompleted,
  required TrainingDecisionType decisionType,
  required bool shouldDeloadTraining,
  required bool isSynchronizing,
  required int completedTaskCount,
  required int totalTaskCount,
}) {
  if (!profileCompleted) {
    return const FlowMascotSpec(
      action: FlowMascotAction.beckon,
      expression: FlowMascotExpression.wink,
      semanticLabel: 'Flow 训练伙伴邀请你完成基础资料',
      durationMilliseconds: 520,
    );
  }
  if (shouldDeloadTraining ||
      decisionType == TrainingDecisionType.deload ||
      decisionType == TrainingDecisionType.recovery ||
      decisionType == TrainingDecisionType.rest) {
    return const FlowMascotSpec(
      action: FlowMascotAction.meditate,
      expression: FlowMascotExpression.closed,
      semanticLabel: 'Flow 训练伙伴提醒今天优先恢复',
      durationMilliseconds: 620,
    );
  }
  if (isSynchronizing) {
    return const FlowMascotSpec(
      action: FlowMascotAction.scan,
      expression: FlowMascotExpression.focused,
      semanticLabel: 'Flow 训练伙伴正在核对训练记录',
      durationMilliseconds: 560,
    );
  }
  if (totalTaskCount > 0 && completedTaskCount >= totalTaskCount) {
    return const FlowMascotSpec(
      action: FlowMascotAction.celebrate,
      expression: FlowMascotExpression.happy,
      semanticLabel: 'Flow 训练伙伴庆祝今日任务完成',
      durationMilliseconds: 460,
      motionCycles: 2,
    );
  }
  return const FlowMascotSpec(
    action: FlowMascotAction.jog,
    expression: FlowMascotExpression.wink,
    semanticLabel: 'Flow 训练伙伴陪你开始今日慢跑',
    durationMilliseconds: 480,
    motionCycles: 2,
  );
}

class TodayTrainingPage extends ConsumerStatefulWidget {
  const TodayTrainingPage({super.key});

  @override
  ConsumerState<TodayTrainingPage> createState() => _TodayTrainingPageState();
}

class _TodayTrainingPageState extends ConsumerState<TodayTrainingPage> {
  String? _pendingReceiptEventId;

  void _startWorkoutFromShowcase() {
    final bool started =
        ref.read(trainingMvpProvider.notifier).startWorkoutPlayer();
    if (started) {
      context.push(AppRoutes.workoutPlayer);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ref.read(trainingMvpProvider).workoutPlayerStatusMessage,
        ),
      ),
    );
  }

  void _scheduleGrowthReceipt(TrainingGrowthReceipt receipt) {
    final String eventId = receipt.event.eventId;
    if (_pendingReceiptEventId == eventId) return;
    _pendingReceiptEventId = eventId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingReceiptEventId != eventId) return;
      final String incompleteLabel =
          receipt.event.missingData.isEmpty ? '' : ' · 数据不完整';
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            '+${receipt.awardedXp} 成长分 · ${receipt.message}'
            '$incompleteLabel',
          ),
          action: SnackBarAction(
            label: '查看证据',
            onPressed: () => context.push(AppRoutes.growthEvidence),
          ),
        ),
      );
      ref
          .read(growthEvidenceControllerProvider.notifier)
          .acknowledgeLatestReceipt(eventId);
      _pendingReceiptEventId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final WorkoutDay todayWorkout = state.todayWorkout;
    final GrowthEvidenceState growthState =
        ref.watch(growthEvidenceControllerProvider);
    if (growthState.latestReceipt != null) {
      _scheduleGrowthReceipt(growthState.latestReceipt!);
    }
    final GrowthDashboard growthDashboard = GrowthEngine().buildDashboard(
      events: growthState.events,
      levelState: growthState.levelState,
      todayWorkout: todayWorkout,
      logs: state.logs,
      races: state.races,
    );
    final FlowMascotSpec mascotSpec = selectTodayMascotSpec(
      profileCompleted: state.profileCompleted,
      decisionType: todayWorkout.decisionType,
      shouldDeloadTraining: state.latestPainLog?.shouldDeloadTraining == true,
      isSynchronizing: growthState.isSynchronizing,
      completedTaskCount: growthDashboard.completedTaskCount,
      totalTaskCount: growthDashboard.totalTaskCount,
    );
    final DateTime now = DateTime.now();
    final TrainingMetricsQuery metricsQuery = TrainingMetricsQuery(
      athleteProfileId: state.profile.id,
      period: MetricPeriod.week,
      periodStart: _weekStart(now),
    );
    final AsyncValue<List<MetricAggregate>> metricsAsync =
        ref.watch(trainingMetricAggregatesProvider(metricsQuery));
    final AsyncValue<List<MetricAggregate>> historicalMetricsAsync = ref.watch(
      trainingMetricAggregatesProvider(
        TrainingMetricsQuery(
          athleteProfileId: state.profile.id,
          includeInvalidated: true,
        ),
      ),
    );
    final List<MetricAggregate> metrics = metricsAsync.when(
      data: (List<MetricAggregate> value) => value,
      error: (Object error, StackTrace stackTrace) => const <MetricAggregate>[],
      loading: () => const <MetricAggregate>[],
    );
    final TrainingScheduleState scheduleState =
        ref.watch(trainingScheduleControllerProvider);
    final DateTime weekStart = _weekStart(now);
    final DateTime weekEnd = weekStart.add(const Duration(days: 7));
    final List<ScheduledWorkout> scheduledWeekWorkouts = scheduleState.workouts
        .where((ScheduledWorkout item) =>
            !item.scheduledDate.isBefore(weekStart) &&
            item.scheduledDate.isBefore(weekEnd))
        .toList(growable: false);
    final AsyncValue<L1ScheduledResultReadState> l1ResultsAsync = ref.watch(
      l1ScheduledResultReadProvider(
        L1ScheduledResultQuery(
          athleteProfileId: state.profile.id,
          startLocalDate: weekStart,
          endExclusiveLocalDate: weekEnd,
        ),
      ),
    );
    final TrainingMetricsProjectionService projectionService =
        ref.watch(trainingMetricsProjectionServiceProvider);
    final L1DashboardProjection l1Projection = l1ResultsAsync.when(
      data: (L1ScheduledResultReadState value) => projectionService.project(
        logs: state.logs,
        scheduledTodayWorkout: state.scheduledTodayWorkout,
        scheduledWeekWorkouts: scheduledWeekWorkouts,
        metrics: metrics,
        now: now,
        persistedScheduledResults: value.results
            .map((StructuredScheduledWorkoutResult item) =>
                item.toDomainResult())
            .toList(growable: false),
        source: switch (value.source) {
          L1ScheduledResultReadSource.structured =>
            L1ProjectionSource.structured,
          L1ScheduledResultReadSource.compatibilityUnavailable =>
            L1ProjectionSource.compatibilityUnavailable,
          L1ScheduledResultReadSource.compatibilityFailed =>
            L1ProjectionSource.compatibilityFailed,
        },
      ),
      error: (Object error, StackTrace stackTrace) => projectionService.project(
        logs: state.logs,
        scheduledTodayWorkout: state.scheduledTodayWorkout,
        scheduledWeekWorkouts: scheduledWeekWorkouts,
        metrics: metrics,
        now: now,
        source: L1ProjectionSource.compatibilityFailed,
      ),
      loading: () => projectionService.project(
        logs: state.logs,
        scheduledTodayWorkout: state.scheduledTodayWorkout,
        scheduledWeekWorkouts: scheduledWeekWorkouts,
        metrics: metrics,
        now: now,
        source: L1ProjectionSource.structuredLoading,
      ),
    );
    final AsyncValue<BodyRhythmState> rhythmAsync =
        ref.watch(bodyRhythmControllerProvider);

    final BodyMetric? latestMetric = state.latestBodyMetric;
    final String completionLabel =
        '${(growthDashboard.completionRate.clamp(0, 1) * 100).round()}%';

    return TrainMateImmersiveHubPage(
      mode: TrainMateVisualMode.darkTraining,
      hero: TodayShowcaseHeader(
        athleteName: state.profile.name,
        growthLabel: growthDashboard.level.label,
        growthXp: growthDashboard.level.currentXp,
        nextLevelXp: growthDashboard.level.nextLevelXp,
        completionRate: growthDashboard.completionRate,
        weeklyConsistencyLabel: l1Projection.weeklyConsistencyLabel,
        workout: todayWorkout,
        onOpenCoach: () => context.go(AppRoutes.aiCenter),
        onStartWorkout: _startWorkoutFromShowcase,
      ),
      children: [
        TrainMateStatusStrip(
          semanticLabel: '今日最新状态，点击进入签到',
          onTap: () => context.push(AppRoutes.dailyCheckIn),
          metrics: <TrainMateStatusMetric>[
            TrainMateStatusMetric(
              label: '睡眠',
              value: latestMetric == null
                  ? '待记录'
                  : '${latestMetric.sleepHours.toStringAsFixed(1)}h',
              icon: Icons.bedtime_outlined,
              color: AppColors.primaryLightest,
            ),
            TrainMateStatusMetric(
              label: '准备度',
              value: '${state.readinessScore}',
              icon: Icons.bolt_outlined,
              color: AppColors.secondaryLight,
            ),
            TrainMateStatusMetric(
              label: '疲劳',
              value: latestMetric == null
                  ? '待记录'
                  : '${latestMetric.fatigueLevel}/10',
              icon: Icons.battery_alert_outlined,
              color: AppColors.background,
            ),
            TrainMateStatusMetric(
              label: '酸痛',
              value: latestMetric == null
                  ? '待记录'
                  : '${latestMetric.sorenessLevel}/10',
              icon: Icons.accessibility_new_outlined,
              color: AppColors.primaryLightest,
            ),
            TrainMateStatusMetric(
              label: '心情',
              value: latestMetric?.moodLabel.isNotEmpty == true
                  ? latestMetric!.moodLabel
                  : '待记录',
              icon: Icons.sentiment_satisfied_alt_outlined,
              color: AppColors.secondaryLight,
            ),
          ],
        ),
        const SizedBox(height: 20),
        TrainMateOverviewGrid(
          first: _TodayOverviewCard(
            icon: Icons.favorite_outline,
            label: '训练准备度',
            value: '${state.readinessScore}',
            detail: state.readinessLabel,
          ),
          second: _TodayOverviewCard(
            icon: Icons.calendar_today_outlined,
            label: '本周一致性',
            value: l1Projection.weeklyConsistencyLabel,
            detail: '$completionLabel 完成',
          ),
          trend: _TodayOverviewCard(
            icon: Icons.insights_outlined,
            label: '恢复与训练记录',
            value: latestMetric == null
                ? '暂无身体数据'
                : 'HRV ${latestMetric.hrvMs} · 睡眠 ${latestMetric.sleepHours.toStringAsFixed(1)}h',
            detail: latestMetric == null
                ? '完成签到后会在这里显示最新真实状态。'
                : '最近状态来自 ${latestMetric.source.label} · ${latestMetric.measuredDateLabel}',
            wide: true,
          ),
        ),
        const SizedBox(height: 20),
        if (!state.profileCompleted) const _OnboardingPromptCard(),
        AbilityProgressOverview(
          metrics: historicalMetricsAsync,
          compact: true,
          onTap: () => context.push(AppRoutes.growthEvidence),
        ),
        _TodayGrowthCard(
          dashboard: growthDashboard,
          projection: l1Projection,
          isSynchronizing: growthState.isSynchronizing,
          statusMessage: growthState.statusMessage,
          mascotAction: mascotSpec.action,
          rhythm: rhythmAsync,
        ),
        const SectionTitle(title: '今日状态与签到'),
        const _DailyCheckInPreviewCard(),
        if (state.latestPainLog != null)
          _PainRiskCard(painLog: state.latestPainLog!),
        const SectionTitle(title: '今日训练内容'),
        _WorkerProfileStrategyCard(state: state),
        _DailyAdjustmentPreviewCard(state: state),
        _WorkoutSummaryCard(workout: todayWorkout),
        const SectionTitle(title: '训练完成记录'),
        _TrainingRecordEntryCard(workout: todayWorkout),
        _RecentTrainingRecordsCard(logs: state.logs),
        const SectionTitle(title: 'AI 教练建议（本地规则）'),
        _CoachAdviceCard(advice: state.coachAdvices),
      ],
    );
  }
}

class _TodayOverviewCard extends StatelessWidget {
  const _TodayOverviewCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: wide ? 118 : 142),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Icon(icon, color: TrainFlowTokens.accent),
            const SizedBox(height: 10),
            TrainMateMetricValue(value: value, label: label),
            const SizedBox(height: 3),
            Text(detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: TrainMateVisualScope.muted(context))),
          ],
        ),
      ),
    );
  }
}

class _TrainingRecordEntryCard extends StatelessWidget {
  const _TrainingRecordEntryCard({required this.workout});

  final WorkoutDay workout;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.edit_calendar_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '记录今日训练',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '记录计划内训练或额外运动，保存后更新成长证据。',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey<String>('today-training-record-entry'),
              onPressed: () => showTrainingRecordEditor(
                context: context,
                workout: workout,
              ),
              icon: const Icon(Icons.add),
              label: const Text('记录今日训练'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayGrowthCard extends StatelessWidget {
  const _TodayGrowthCard({
    required this.dashboard,
    required this.projection,
    required this.isSynchronizing,
    required this.statusMessage,
    required this.mascotAction,
    required this.rhythm,
  });

  final GrowthDashboard dashboard;
  final L1DashboardProjection projection;
  final bool isSynchronizing;
  final String statusMessage;
  final FlowMascotAction mascotAction;
  final AsyncValue<BodyRhythmState> rhythm;

  @override
  Widget build(BuildContext context) {
    final String dayLabel = dashboard.growthDay == null
        ? '成长基线待建立'
        : '累计成长日 ${dashboard.growthDay}';
    return TrainFlowCard(
      key: const ValueKey<String>('today-growth-card'),
      tone: TrainFlowCardTone.peach,
      cornerCharacterAction: trainMateActionForFlowMascot(mascotAction),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RhythmCompactEntry(
            rhythm: rhythm,
            growthLabel: '$dayLabel · ${dashboard.level.label}',
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: dashboard.level.progress,
            minHeight: 8,
            color: AppColors.primary,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 8),
          Text(
            '成长经验 ${dashboard.level.currentXp}/${dashboard.level.nextLevelXp}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'L1 训练执行',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          InfoRow(
            label: '本周一致性',
            value: projection.weeklyConsistencyLabel,
          ),
          InfoRow(
            label: '今日训练判定',
            value: projection.todayDecisionLabel,
          ),
          InfoRow(
            label: '负荷状态',
            value: projection.loadStateLabel.replaceFirst('负荷状态：', ''),
          ),
          const SizedBox(height: 8),
          TrainFlowExpandable(
            key: const ValueKey<String>(
              'today-growth-details-expandable',
            ),
            title: '查看详情',
            summary:
                '今日任务 ${dashboard.completedTaskCount}/${dashboard.totalTaskCount} · ${dashboard.raceCountdownLabel}',
            summaryMaxLines: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dashboard.raceCountdownLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 10),
                for (final GrowthTask task in dashboard.tasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      children: [
                        Icon(
                          task.completed
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: task.completed
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(task.title)),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  isSynchronizing ? '正在核对真实记录…' : statusMessage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '计算依据：${projection.calculationBasis}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => context.push(AppRoutes.growthEvidence),
                    icon: const Icon(Icons.timeline_outlined),
                    label: const Text('查看成长证据'),
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

class _RhythmCompactEntry extends StatelessWidget {
  const _RhythmCompactEntry({
    required this.rhythm,
    required this.growthLabel,
  });

  final AsyncValue<BodyRhythmState> rhythm;
  final String growthLabel;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String subtitle;
    final String trailing;
    switch (rhythm) {
      case AsyncData<BodyRhythmState>(:final value):
        final snapshot = value.snapshot;
        if (!snapshot.hasBaseline) {
          title = '身体节奏基线积累中';
          subtitle = '已有 ${snapshot.sufficientFactorCount}/4 项长期数据';
        } else if (snapshot.stateAge == null) {
          title = '近期节奏 ${snapshot.speed.toStringAsFixed(1)}×';
          subtitle = '填写生日后显示状态年龄';
        } else {
          title = '状态年龄 ${snapshot.stateAge!.toStringAsFixed(1)}';
          subtitle = '${snapshot.paceLabel} · 每周更新一次';
        }
        trailing = '${snapshot.speed.toStringAsFixed(1)}×';
      case AsyncError<BodyRhythmState>():
        title = '身体节奏暂未更新';
        subtitle = '点击查看数据状态';
        trailing = '--';
      default:
        title = '正在核对身体节奏';
        subtitle = '读取近 30 天长期趋势';
        trailing = '…';
    }
    return Semantics(
      button: true,
      label: '$title，$subtitle，点击查看身体节奏详情',
      child: InkWell(
        key: const ValueKey<String>('today-growth-rhythm-entry'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(AppRoutes.rhythmDetail),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.monitor_heart_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '$subtitle · $growthLabel',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkerProfileStrategyCard extends StatelessWidget {
  final TrainingMvpState state;

  const _WorkerProfileStrategyCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final UserProfile profile = state.profile;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.work_outline, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今天按你的现实约束安排',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: profile.workerProfileType.label),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(label: '作息', value: profile.workScheduleType.label),
          InfoRow(label: '器械条件', value: profile.equipmentAccessType.label),
          Text(
            profile.workerProfileType.strategy,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _DailyCheckInPreviewCard extends StatelessWidget {
  const _DailyCheckInPreviewCard();

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
                  '今日签到',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '打开后再填写今天的主观状态；首页不展示身体慢变量或推断结论。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.dailyCheckIn),
              child: const Text('打开签到'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyAdjustmentPreviewCard extends StatelessWidget {
  final TrainingMvpState state;

  const _DailyAdjustmentPreviewCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final DailyAdjustmentDecision decision = state.dailyAdjustmentDecision;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '每日调整',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: decision.decisionLabel,
                color: _decisionColor(decision.decisionType),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(
            label: '现实约束',
            value:
                '${state.dailyAvailableMinutesOverride} 分钟 · ${state.dailyWorkStress.label} · ${state.dailyTrainingEnvironment.label} · ${state.dailyWeather.label}',
          ),
          InfoRow(
            label: '今日变化',
            value: decision.planChangeSummary,
          ),
          const SizedBox(height: 8),
          Text(
            state.dailyAdjustmentStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.dailyAdjustment),
              child: const Text('打开调整'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PainRiskCard extends StatelessWidget {
  final PainLog painLog;

  const _PainRiskCard({required this.painLog});

  @override
  Widget build(BuildContext context) {
    final bool isRedLine = painLog.requiresMedicalAttention;

    return TrainFlowCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isRedLine ? Icons.warning_amber_rounded : Icons.healing_outlined,
            color: isRedLine ? AppColors.danger : AppColors.warningDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRedLine ? '停止相关训练并就医' : '今日训练已自动降级',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${painLog.bodyPart}疼痛 ${painLog.painLevel}/10 · ${painLog.timing.label}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
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

class _OnboardingPromptCard extends ConsumerWidget {
  const _OnboardingPromptCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);

    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_ind, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '首次进入请填写基础资料',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '当前先使用本地 Mock 档案生成训练建议，后续可以接真实问卷和存储。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final MainSport sport in state.profile.mainSports)
                ToneBadge(label: sport.label),
              ToneBadge(label: state.profile.workScheduleType.label),
              ToneBadge(label: state.profile.equipmentAccessType.label),
              ToneBadge(label: state.profile.workerProfileType.label),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    ref
                        .read(userProfileControllerProvider.notifier)
                        .save(state.profile);
                  },
                  child: const Text('使用当前资料'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => context.push(AppRoutes.onboarding),
                child: const Text('调整'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkoutSummaryCard extends ConsumerWidget {
  final WorkoutDay workout;

  const _WorkoutSummaryCard({required this.workout});

  void _startPlayer(BuildContext context, WidgetRef ref) {
    final bool started =
        ref.read(trainingMvpProvider.notifier).startWorkoutPlayer();
    if (started) {
      context.push(AppRoutes.workoutPlayer);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ref.read(trainingMvpProvider).workoutPlayerStatusMessage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  workout.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: workout.trainingType.label),
              const SizedBox(width: 8),
              ToneBadge(
                label: '决策 ${workout.decisionType.label}',
                color: _decisionColor(workout.decisionType),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey<String>('today-workout-start-button'),
              onPressed: () => _startPlayer(context, ref),
              icon: const Icon(Icons.play_arrow),
              label: Text(
                '开始跟练 · 约 ${workout.estimatedMinutes} 分钟',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TrainFlowExpandable(
            key: const ValueKey<String>(
              'today-workout-five-step-expandable',
            ),
            title: '今日训练五步',
            summary: '泡沫轴 / 拉伸 / 激活 / 正式 / 放松 · ${workout.estimatedMinutes} 分钟',
            child: _FiveStepFlow(workout: workout),
          ),
          const SizedBox(height: 12),
          InfoRow(label: '热身补充', value: workout.warmupSteps.join(' / ')),
          InfoRow(
            label: '辅助',
            value: workout.accessoryWork.isEmpty
                ? '无需额外辅助'
                : workout.accessoryWork.join(' / '),
          ),
          const SizedBox(height: 8),
          TrainFlowExpandable(
            key: const ValueKey<String>(
              'today-workout-coach-notes-expandable',
            ),
            title: '教练说明',
            summary: workout.coachNotes,
            summaryMaxLines: 2,
            child: Text(
              key: const ValueKey<String>('today-workout-coach-notes-full'),
              workout.coachNotes,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiveStepFlow extends StatelessWidget {
  final WorkoutDay workout;

  const _FiveStepFlow({required this.workout});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepLine(index: 1, title: '泡沫轴放松', items: workout.foamRollingSteps),
        _StepLine(index: 2, title: '动态拉伸', items: workout.dynamicStretchSteps),
        _StepLine(index: 3, title: '激活动作', items: workout.activationSteps),
        _StepLine(index: 4, title: '正式训练', items: workout.mainSets),
        _StepLine(index: 5, title: '训练后放松与反馈', items: workout.cooldownSteps),
        const SizedBox(height: 6),
        Text(
          '以上流程总时长计入 ${workout.estimatedMinutes} 分钟训练预算。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final int index;
  final String title;
  final List<String> items;

  const _StepLine({
    required this.index,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final String value = items.isEmpty ? '今日无需安排' : items.join(' / ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primaryLightest,
            child: Text(
              '$index',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: '$title：',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTrainingRecordsCard extends StatelessWidget {
  final List<TrainingLog> logs;

  const _RecentTrainingRecordsCard({required this.logs});

  @override
  Widget build(BuildContext context) {
    final List<TrainingLog> recentLogs =
        logs.where((TrainingLog log) => log.isSessionRecord).toList()
          ..sort(
            (TrainingLog first, TrainingLog second) =>
                second.createdAt.compareTo(first.createdAt),
          );
    final List<TrainingLog> visibleLogs = recentLogs.take(3).toList();

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '最近训练记录',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (visibleLogs.isEmpty)
            Text(
              '还没有完整训练记录，完成今日训练后会显示在这里。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            )
          else
            for (int index = 0; index < visibleLogs.length; index += 1) ...[
              _TrainingLogRow(log: visibleLogs[index]),
              if (index < visibleLogs.length - 1) const Divider(height: 24),
            ],
        ],
      ),
    );
  }
}

class _TrainingLogRow extends StatelessWidget {
  final TrainingLog log;

  const _TrainingLogRow({required this.log});

  @override
  Widget build(BuildContext context) {
    final String note = log.userNote?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _trainingLogDateLabel(log.createdAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            ToneBadge(
              label: _trainingLogCompletionLabel(log),
              color: _trainingLogStatusColor(log),
            ),
            const SizedBox(width: 8),
            ToneBadge(label: 'RPE ${log.rpe}'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          log.isSessionReview
              ? log.sessionReviewSummary
              : note.isEmpty
                  ? '无备注'
                  : note,
        ),
        if (log.isSessionReview && note.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            note,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ],
    );
  }
}

String _trainingLogDateLabel(DateTime value) {
  final String month = value.month.toString().padLeft(2, '0');
  final String day = value.day.toString().padLeft(2, '0');
  final String hour = value.hour.toString().padLeft(2, '0');
  final String minute = value.minute.toString().padLeft(2, '0');
  return '$month月$day日 $hour:$minute';
}

String _trainingLogCompletionLabel(TrainingLog log) {
  if (log.isSessionReview) {
    return '${log.normalizedCompletionPercentage}% 完成';
  }
  return log.completed ? '已完成' : '未完成';
}

Color _trainingLogStatusColor(TrainingLog log) {
  if (log.completed || log.normalizedCompletionPercentage >= 80) {
    return AppColors.primary;
  }
  if (log.normalizedCompletionPercentage > 0) {
    return AppColors.warningDark;
  }
  return AppColors.textSecondary;
}

DateTime _weekStart(DateTime value) {
  final DateTime date = DateTime(value.year, value.month, value.day);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

Color _decisionColor(TrainingDecisionType decisionType) {
  switch (decisionType) {
    case TrainingDecisionType.normal:
      return AppColors.primary;
    case TrainingDecisionType.deload:
      return AppColors.warningDark;
    case TrainingDecisionType.recovery:
      return AppColors.success;
    case TrainingDecisionType.technique:
      return AppColors.secondary;
    case TrainingDecisionType.rest:
      return AppColors.textSecondary;
  }
}

class _CoachAdviceCard extends StatelessWidget {
  final List<String> advice;

  const _CoachAdviceCard({required this.advice});

  @override
  Widget build(BuildContext context) {
    if (advice.isEmpty) {
      return const TrainFlowCard(
        child: Text('暂无建议，完成签到或训练后再来查看。'),
      );
    }
    return TrainFlowCard(
      child: TrainFlowExpandable(
        key: const ValueKey<String>('today-coach-advice-expandable'),
        title: '建议详情',
        summary: '共 ${advice.length} 条建议',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final String item in advice) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.bolt,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
              if (item != advice.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
