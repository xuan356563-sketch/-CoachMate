import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/emp_system.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainmate_showcase_widgets.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/growth_evidence.dart';
import '../../data/models/growth_timeline.dart';
import '../../data/models/training_metrics.dart';
import '../../services/growth_engine.dart';
import '../../services/growth_timeline_service.dart';
import '../dashboard/training_mvp_controller.dart';
import '../data_center/application/body_metric_controller.dart';
import '../profile/application/user_profile_controller.dart';
import 'application/growth_evidence_controller.dart';
import 'application/run_context_controller.dart';
import 'application/strength_primary_exercise_controller.dart';
import 'application/training_metrics_provider.dart';
import 'ability_progress_overview.dart';

class GrowthEvidencePage extends ConsumerStatefulWidget {
  const GrowthEvidencePage({super.key});

  @override
  ConsumerState<GrowthEvidencePage> createState() => _GrowthEvidencePageState();
}

class _GrowthEvidencePageState extends ConsumerState<GrowthEvidencePage> {
  bool _includeRevoked = false;
  int _visibleCount = 30;
  GrowthTimelineEntryType? _selectedType;

  @override
  Widget build(BuildContext context) {
    final GrowthEvidenceState state =
        ref.watch(growthEvidenceControllerProvider);
    final TrainingMvpState trainingState = ref.watch(trainingMvpProvider);
    ref.watch(bodyMetricControllerProvider);
    final UserProfileState profileState =
        ref.watch(userProfileControllerProvider);
    final List<GrowthTimelineEntry> timeline = GrowthTimelineService().build(
      evidenceEvents: state.events,
      checkIns: ref.read(dailyCheckInRepositoryProvider).getSnapshot().records,
      achievements: trainingState.achievementRecords,
      weeklyReports: trainingState.savedWeeklyReports,
      races: trainingState.races,
      includeRevokedEvidence: _includeRevoked,
    );
    final List<GrowthTimelineEntry> filteredTimeline = _selectedType == null
        ? timeline
        : timeline
            .where(
              (GrowthTimelineEntry entry) => entry.type == _selectedType,
            )
            .toList(growable: false);
    final List<GrowthTimelineEntry> visible =
        filteredTimeline.take(_visibleCount).toList(growable: false);
    final String athleteProfileId = resolveTrainingMetricsAthleteProfileId(
      growthEvidenceAthleteProfileId: state.athleteProfileId,
      profileAthleteProfileId: profileState.profile.id,
    );
    final AsyncValue<List<MetricAggregate>> metrics = ref.watch(
      trainingMetricAggregatesProvider(
        TrainingMetricsQuery(
          athleteProfileId: athleteProfileId,
          includeInvalidated: true,
        ),
      ),
    );
    final AsyncValue<List<RunContextReviewItem>> runContextReviews = ref.watch(
      pendingRunContextReviewsProvider(athleteProfileId),
    );
    final AsyncValue<List<StrengthExerciseOption>> strengthExercises =
        ref.watch(strengthExerciseOptionsProvider(athleteProfileId));

    return TrainFlowPage(
      title: '成长时间线',
      layout: TrainFlowPageLayout.report,
      subtitle: '统一查看训练、健康、签到、成就、周报和正式赛果，并保留证据边界。',
      eyebrow: 'Evidence Timeline',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.dashboard,
      ),
      artwork: const TrainMateIllustration(
        assetPath: 'assets/images/trainmate_growth_scene.png',
        semanticLabel: '训练成长与证据时间线插画',
        fallback: TrainMateActionCharacter(
          action: TrainMateAction.treePoseBalance,
          backgroundColor: AppColors.primary,
        ),
      ),
      children: [
        AbilityProgressOverview(metrics: metrics),
        RunContextReviewCard(
          athleteProfileId: athleteProfileId,
          reviews: runContextReviews,
        ),
        StrengthPrimaryExerciseCard(
          athleteProfileId: athleteProfileId,
          exercises: strengthExercises,
        ),
        GrowthMetricsOverview(metrics: metrics),
        _LevelEvidenceCard(
          levelState: state.levelState,
          events: state.events,
          statusMessage: state.statusMessage,
        ),
        if (state.weeklyReports.isNotEmpty)
          _GrowthWeeklyReportsCard(reports: state.weeklyReports),
        TrainFlowCard(
          child: SwitchListTile.adaptive(
            key: const ValueKey<String>('growth-evidence-revoked-switch'),
            contentPadding: EdgeInsets.zero,
            value: _includeRevoked,
            onChanged: (bool value) {
              setState(() {
                _includeRevoked = value;
                _visibleCount = 30;
              });
            },
            title: const Text('显示已撤销来源'),
            subtitle: const Text('删除来源不会抹去审计痕迹，但不会计入经验或周报。'),
          ),
        ),
        const SectionTitle(title: '统一时间线'),
        _GrowthTimelineFilters(
          selectedType: _selectedType,
          onChanged: (GrowthTimelineEntryType? value) {
            setState(() {
              _selectedType = value;
              _visibleCount = 30;
            });
          },
        ),
        if (visible.isEmpty)
          const _EmptyEvidenceCard()
        else
          for (final GrowthTimelineEntry entry in visible)
            if (entry.evidenceEvent != null)
              _GrowthEvidenceEventCard(event: entry.evidenceEvent!)
            else
              _GrowthTimelineEntryCard(entry: entry),
        if (visible.length < filteredTimeline.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _visibleCount += 30;
                  });
                },
                icon: const Icon(Icons.expand_more),
                label: Text(
                  '加载更多（已显示 ${visible.length}/${filteredTimeline.length}）',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GrowthTimelineFilters extends StatelessWidget {
  const _GrowthTimelineFilters({
    required this.selectedType,
    required this.onChanged,
  });

  final GrowthTimelineEntryType? selectedType;
  final ValueChanged<GrowthTimelineEntryType?> onChanged;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilterChip(
            label: const Text('全部'),
            selected: selectedType == null,
            onSelected: (_) => onChanged(null),
          ),
          for (final GrowthTimelineEntryType type
              in GrowthTimelineEntryType.values)
            FilterChip(
              label: Text(type.label),
              selected: selectedType == type,
              onSelected: (_) => onChanged(type),
            ),
        ],
      ),
    );
  }
}

class _GrowthTimelineEntryCard extends StatelessWidget {
  const _GrowthTimelineEntryCard({required this.entry});

  final GrowthTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final Color color = _timelineColor(entry.type);
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_timelineIcon(entry.type), color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.dateLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TrainFlowTokens.darkTrainingMuted,
                          ),
                    ),
                  ],
                ),
              ),
              ToneBadge(label: entry.type.label, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Text(entry.description),
          const SizedBox(height: 8),
          Text(
            '来源：${entry.sourceLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          if (entry.destination != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.push(
                  _timelineDestinationPath(entry.destination!),
                ),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('查看详情'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

IconData _timelineIcon(GrowthTimelineEntryType type) => switch (type) {
      GrowthTimelineEntryType.training => Icons.fitness_center,
      GrowthTimelineEntryType.health => Icons.monitor_heart_outlined,
      GrowthTimelineEntryType.checkIn => Icons.event_available_outlined,
      GrowthTimelineEntryType.achievement => Icons.emoji_events_outlined,
      GrowthTimelineEntryType.weeklyReport => Icons.summarize_outlined,
      GrowthTimelineEntryType.race => Icons.flag_outlined,
    };

Color _timelineColor(GrowthTimelineEntryType type) => switch (type) {
      GrowthTimelineEntryType.training => AppColors.primary,
      GrowthTimelineEntryType.health => AppColors.success,
      GrowthTimelineEntryType.checkIn => AppColors.secondary,
      GrowthTimelineEntryType.achievement => AppColors.warningDark,
      GrowthTimelineEntryType.weeklyReport => AppColors.primary,
      GrowthTimelineEntryType.race => AppColors.warningDark,
    };

String _timelineDestinationPath(GrowthTimelineDestination destination) =>
    switch (destination) {
      GrowthTimelineDestination.dailyCheckIn => AppRoutes.dailyCheckIn,
      GrowthTimelineDestination.weeklyReport => AppRoutes.weeklyReport,
      GrowthTimelineDestination.racePrep => AppRoutes.races,
    };

class RunContextReviewCard extends ConsumerStatefulWidget {
  const RunContextReviewCard({
    required this.athleteProfileId,
    required this.reviews,
    super.key,
  });

  final String athleteProfileId;
  final AsyncValue<List<RunContextReviewItem>> reviews;

  @override
  ConsumerState<RunContextReviewCard> createState() =>
      _RunContextReviewCardState();
}

class _RunContextReviewCardState extends ConsumerState<RunContextReviewCard> {
  String? _busyWorkoutId;
  String? _actionMessage;

  @override
  Widget build(BuildContext context) {
    return widget.reviews.when(
      loading: () => const SizedBox.shrink(),
      error: (Object error, StackTrace stackTrace) => TrainFlowCard(
        tone: TrainFlowCardTone.peach,
        child: const Text('跑步项目确认记录读取失败；不会自动猜测为公路跑或越野跑。'),
      ),
      data: (List<RunContextReviewItem> values) {
        if (values.isEmpty) return const SizedBox.shrink();
        return TrainFlowCard(
          tone: TrainFlowCardTone.peach,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '确认跑步项目',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'HealthKit 只提供 `.running`。请根据实际路线确认；确认前不会把训练猜成公路跑或越野跑。',
              ),
              const SizedBox(height: 12),
              for (final RunContextReviewItem item in values) ...[
                _RunContextReviewRow(
                  item: item,
                  busy: _busyWorkoutId == item.workoutId,
                  disabled: _busyWorkoutId != null,
                  onConfirm: (String value) => _confirm(item, value),
                ),
                if (item != values.last) const Divider(height: 20),
              ],
              if (_actionMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _actionMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.warningDark,
                      ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirm(RunContextReviewItem item, String runContext) async {
    setState(() {
      _busyWorkoutId = item.workoutId;
      _actionMessage = null;
    });
    try {
      await ref.read(runContextConfirmationServiceProvider).confirm(
            athleteProfileId: widget.athleteProfileId,
            workoutId: item.workoutId,
            runContext: runContext,
          );
      if (!mounted) return;
      setState(() {
        _actionMessage = runContext == 'trail'
            ? '已确认为越野跑，相关指标正在使用新上下文。'
            : '已确认为公路跑，相关指标正在使用新上下文。';
      });
    } on RunContextRecalculationException catch (error) {
      if (!mounted) return;
      setState(() => _actionMessage = error.message);
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _actionMessage = error.message.toString());
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionMessage = '跑步项目确认失败，原有事实和指标未被猜测性修改。');
    } finally {
      ref.invalidate(
        pendingRunContextReviewsProvider(widget.athleteProfileId),
      );
      ref.invalidate(trainingMetricAggregatesProvider);
      ref.invalidate(trainingReportRevisionsProvider);
      ref.invalidate(growthMetricsControllerProvider);
      if (mounted) {
        setState(() => _busyWorkoutId = null);
      }
    }
  }
}

class _RunContextReviewRow extends StatelessWidget {
  const _RunContextReviewRow({
    required this.item,
    required this.busy,
    required this.disabled,
    required this.onConfirm,
  });

  final RunContextReviewItem item;
  final bool busy;
  final bool disabled;
  final ValueChanged<String> onConfirm;

  @override
  Widget build(BuildContext context) {
    final String date =
        '${item.localDate.year}-${item.localDate.month.toString().padLeft(2, '0')}-${item.localDate.day.toString().padLeft(2, '0')}';
    final String distance = item.distanceMeters > 0
        ? '${(item.distanceMeters / 1000).toStringAsFixed(1)} 公里'
        : '距离未提供';
    final String duration = item.durationSeconds > 0
        ? '${(item.durationSeconds / 60).round()} 分钟'
        : '时长未提供';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$date · $distance · $duration'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: disabled ? null : () => onConfirm('road'),
                child: Text(busy ? '正在保存' : '公路跑'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: disabled ? null : () => onConfirm('trail'),
                child: Text(busy ? '正在保存' : '越野跑'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class StrengthPrimaryExerciseCard extends ConsumerStatefulWidget {
  const StrengthPrimaryExerciseCard({
    required this.athleteProfileId,
    required this.exercises,
    super.key,
  });

  final String athleteProfileId;
  final AsyncValue<List<StrengthExerciseOption>> exercises;

  @override
  ConsumerState<StrengthPrimaryExerciseCard> createState() =>
      _StrengthPrimaryExerciseCardState();
}

class _StrengthPrimaryExerciseCardState
    extends ConsumerState<StrengthPrimaryExerciseCard> {
  String? _busyExerciseKey;
  String? _message;

  @override
  Widget build(BuildContext context) {
    return widget.exercises.when(
      loading: () => const SizedBox.shrink(),
      error: (Object error, StackTrace stackTrace) => TrainFlowCard(
        child: const Text('力量动作记录读取失败；不会自动选择主项或生成跨动作结论。'),
      ),
      data: (List<StrengthExerciseOption> values) {
        if (values.isEmpty) return const SizedBox.shrink();
        return TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择力量主项',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                '主项只按同一动作、相近重量区间、e1RM 和可用 RPE 解释；全身总容量只作训练量背景。',
              ),
              const SizedBox(height: 8),
              for (final StrengthExerciseOption option in values)
                SwitchListTile.adaptive(
                  key: ValueKey<String>(
                    'strength-primary-${option.exerciseKey}',
                  ),
                  contentPadding: EdgeInsets.zero,
                  value: option.isActive,
                  onChanged: _busyExerciseKey == null
                      ? (bool value) => _setActive(option, value)
                      : null,
                  title: Text(option.displayName),
                  subtitle: Text(
                    '已记录 ${option.recordedSetCount} 组'
                    '${_busyExerciseKey == option.exerciseKey ? ' · 正在保存' : ''}',
                  ),
                ),
              if (_message != null) ...[
                const SizedBox(height: 6),
                Text(
                  _message!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TrainFlowTokens.darkTrainingMuted,
                      ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _setActive(
    StrengthExerciseOption option,
    bool isActive,
  ) async {
    setState(() {
      _busyExerciseKey = option.exerciseKey;
      _message = null;
    });
    try {
      await ref.read(strengthPrimaryExerciseServiceProvider).setActive(
            athleteProfileId: widget.athleteProfileId,
            exerciseKey: option.exerciseKey,
            displayName: option.displayName,
            isActive: isActive,
          );
      if (!mounted) return;
      setState(() {
        _message = isActive
            ? '已将 ${option.displayName} 设为主项，力量指标已按单动作重算。'
            : '已取消 ${option.displayName} 主项，旧结论已失效。';
      });
    } on StrengthPrimaryExerciseRecalculationException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = '力量主项保存失败：$error');
    } finally {
      ref.invalidate(
        strengthExerciseOptionsProvider(widget.athleteProfileId),
      );
      ref.invalidate(trainingMetricAggregatesProvider);
      ref.invalidate(trainingReportRevisionsProvider);
      ref.invalidate(growthMetricsControllerProvider);
      if (mounted) setState(() => _busyExerciseKey = null);
    }
  }
}

class GrowthMetricsOverview extends StatelessWidget {
  const GrowthMetricsOverview({
    required this.metrics,
    super.key,
  });

  final AsyncValue<List<MetricAggregate>> metrics;

  @override
  Widget build(BuildContext context) {
    return metrics.when(
      loading: () => const Column(
        children: [
          _MetricGroupCard(
            title: '训练适应（L2）',
            emptyMessage: '数据积累中：正在读取本地训练指标。',
          ),
          _MetricGroupCard(
            title: '长期结果（L3）',
            emptyMessage: '数据积累中：正在读取本地长期指标。',
            showBodyDataNotice: true,
          ),
        ],
      ),
      error: (Object error, StackTrace stackTrace) => const Column(
        children: [
          _MetricGroupCard(
            title: '训练适应（L2）',
            emptyMessage: '计算失败：训练指标暂时无法读取。',
          ),
          _MetricGroupCard(
            title: '长期结果（L3）',
            emptyMessage: '计算失败：长期指标暂时无法读取。',
            showBodyDataNotice: true,
          ),
        ],
      ),
      data: (List<MetricAggregate> values) {
        final List<MetricAggregate> l2 = values
            .where((MetricAggregate item) =>
                _l2MetricCodes.contains(item.metricCode))
            .toList();
        final List<MetricAggregate> l3 = values
            .where((MetricAggregate item) =>
                _l3MetricCodes.contains(item.metricCode))
            .toList();
        return Column(
          children: [
            _MetricGroupCard(
              title: '训练适应（L2）',
              metrics: l2,
              emptyMessage: '数据积累中：暂无达到解释门槛的训练采样。无手表也可继续使用计划、打卡和手动录入。',
            ),
            _MetricGroupCard(
              title: '长期结果（L3）',
              metrics: l3,
              emptyMessage: '数据积累中：当前没有可展示的长期指标，不会自动造数。',
              showBodyDataNotice: true,
            ),
          ],
        );
      },
    );
  }
}

class _MetricGroupCard extends StatelessWidget {
  const _MetricGroupCard({
    required this.title,
    required this.emptyMessage,
    this.metrics = const <MetricAggregate>[],
    this.showBodyDataNotice = false,
  });

  final String title;
  final String emptyMessage;
  final List<MetricAggregate> metrics;
  final bool showBodyDataNotice;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      cornerCharacterAction: TrainMateAction.treePoseBalance,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (metrics.isEmpty)
            Text(
              emptyMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
                  ),
            )
          else
            for (final MetricAggregate metric in metrics)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MetricStatusRow(metric: metric),
              ),
          if (showBodyDataNotice) ...[
            const SizedBox(height: 8),
            Text(
              '身体慢变量仅在月报或你主动查看时展示，不会出现在日常首页。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricStatusRow extends StatelessWidget {
  const _MetricStatusRow({required this.metric});

  final MetricAggregate metric;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.grayLightest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _metricStatusColor(metric.status),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _metricDisplayName(metric),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _metricDetail(metric),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TrainFlowTokens.darkTrainingMuted,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ToneBadge(
              label: _metricStatusLabel(metric.status),
              color: _metricStatusColor(metric.status),
            ),
          ],
        ),
      ),
    );
  }
}

const Set<String> _l2MetricCodes = <String>{
  'same_pace_heart_rate',
  'running_efficiency_factor',
  'aerobic_decoupling',
  'strength_e1rm',
  'strength_progress',
  'badminton_consistency',
};

const Set<String> _l3MetricCodes = <String>{
  'body_weight_7d',
  'body_fat_7d',
  'vo2max_monthly',
  'device_best_segment',
  'official_race_pb',
};

String _metricName(String code) => switch (code) {
      'same_pace_heart_rate' => '同配速心率',
      'running_efficiency_factor' => '跑步效率因子',
      'aerobic_decoupling' => '有氧解耦',
      'strength_e1rm' => '主项 e1RM',
      'strength_progress' => '力量进步',
      'badminton_consistency' => '羽毛球训练一致性',
      'body_weight_7d' => '体重 7 日均值',
      'body_fat_7d' => '体脂 7 日均值',
      'vo2max_monthly' => 'VO2max 月度观察',
      'device_best_segment' => '设备记录最佳分段',
      'official_race_pb' => '正式比赛 PB',
      _ => code,
    };

String _metricDisplayName(MetricAggregate metric) {
  final String base = _metricName(metric.metricCode);
  final String exerciseName =
      (metric.metadata['exerciseName'] as String? ?? '').trim();
  return exerciseName.isEmpty ? base : '$base · $exerciseName';
}

String _metricStatusLabel(MetricStatus status) => switch (status) {
      MetricStatus.ready => '可解释',
      MetricStatus.accumulating => '数据积累中',
      MetricStatus.unavailable => '不可用',
      MetricStatus.invalidated => '已失效',
      MetricStatus.failed => '计算失败',
    };

Color _metricStatusColor(MetricStatus status) => switch (status) {
      MetricStatus.ready => AppColors.success,
      MetricStatus.accumulating => AppColors.secondaryDark,
      MetricStatus.unavailable => TrainFlowTokens.darkTrainingMuted,
      MetricStatus.invalidated => AppColors.warningDark,
      MetricStatus.failed => AppColors.danger,
    };

String _metricDetail(MetricAggregate metric) {
  switch (metric.status) {
    case MetricStatus.ready:
      final Object? displayValue = metric.metadata['displayValue'];
      if (displayValue is String && displayValue.isNotEmpty) {
        return displayValue;
      }
      final double? value = metric.value;
      if (value == null) return '已达到解释门槛，等待可展示结果。';
      if (metric.unit == 'ratio') {
        return '${(value * 100).round()}% · ${metric.algorithmVersion}';
      }
      final String unit = metric.unit.isEmpty ? '' : ' ${metric.unit}';
      return '${value.toStringAsFixed(1)}$unit · ${metric.algorithmVersion}';
    case MetricStatus.accumulating:
      return _remainingDataLabel(metric.metadata);
    case MetricStatus.unavailable:
      return '当前来源无法支持该指标，不会使用替代值。';
    case MetricStatus.invalidated:
      return '上游来源已变化，等待重算后再展示结论。';
    case MetricStatus.failed:
      return '本地计算失败，原始记录仍保留。';
  }
}

String _remainingDataLabel(Map<String, Object?> metadata) {
  final Object? minutes = metadata['remainingMinutes'];
  if (minutes is num) return '数据积累中，还需 ${minutes.ceil()} 分钟。';
  final Object? seconds =
      metadata['remainingSeconds'] ?? metadata['remainingDurationSeconds'];
  if (seconds is num) {
    return '数据积累中，还需 ${(seconds / 60).ceil()} 分钟。';
  }
  final Object? samples = metadata['remainingSamples'];
  if (samples is num) return '数据积累中，还需 ${samples.ceil()} 次训练。';
  final Object? days = metadata['remainingDays'];
  if (days is num) return '数据积累中，还需 ${days.ceil()} 个有效日。';
  return '数据积累中，尚未达到解释门槛。';
}

class _LevelEvidenceCard extends StatelessWidget {
  const _LevelEvidenceCard({
    required this.levelState,
    required this.events,
    required this.statusMessage,
  });

  final GrowthLevelState levelState;
  final List<GrowthEvidenceEvent> events;
  final String statusMessage;

  @override
  Widget build(BuildContext context) {
    final GrowthLevelProgress progress = GrowthEngine().buildLevelProgress(
      events: events,
      previous: levelState,
    );
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_outlined,
                  color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '成长等级 ${progress.label}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              EmpBadge(
                label: '峰值 ${levelState.peakXp} XP',
                tone: EmpBadgeTone.yellow,
                icon: Icons.emoji_events_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              EmpProgressRing(
                progress: progress.progress,
                size: 56,
                strokeWidth: 6,
                color: TrainFlowTokens.accent,
                trackColor: TrainFlowTokens.darkTrainingRaised,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '当前有效 XP ${progress.currentXp}/'
                  '${progress.nextLevelXp}。',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '等级只记录已达成峰值，不会因删除或修订而倒退。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            statusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _GrowthWeeklyReportsCard extends StatelessWidget {
  const _GrowthWeeklyReportsCard({required this.reports});

  final List<WeeklyGrowthReport> reports;

  @override
  Widget build(BuildContext context) {
    final WeeklyGrowthReport latest = reports.first;
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_view_week_outlined,
                  color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '周成长报告',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: latest.isLocked ? '已锁定' : '本周可更新'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '训练执行指数',
                  value: latest.trainingExecutionIndexLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '完成率',
                  value: latest.completionRateLabel,
                  color: TrainFlowTokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            latest.recoverySummary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _EmptyEvidenceCard extends StatelessWidget {
  const _EmptyEvidenceCard();

  @override
  Widget build(BuildContext context) {
    return const TrainFlowCard(
      child: EmpEmptyState(
        icon: Icons.auto_awesome_outlined,
        title: '尚未形成成长证据',
        description:
            '完成一次达到 50% 的训练、导入历史活动或保存健康记录后，这里会展示来源、数据完整度和模型贡献。',
      ),
    );
  }
}

class _GrowthEvidenceEventCard extends StatelessWidget {
  const _GrowthEvidenceEventCard({required this.event});

  final GrowthEvidenceEvent event;

  @override
  Widget build(BuildContext context) {
    final Color tone =
        event.isRevoked ? TrainFlowTokens.darkTrainingMuted : AppColors.primary;
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                event.eventType == GrowthEventType.training
                    ? Icons.directions_run_outlined
                    : Icons.favorite_border,
                color: tone,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _eventDateLabel(event),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TrainFlowTokens.darkTrainingMuted,
                          ),
                    ),
                  ],
                ),
              ),
              ToneBadge(
                label: event.isRevoked ? '已撤销' : '${event.confidence.label}置信',
                color: tone,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(event.description),
          if (event.xpComponents.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final GrowthXpComponent component in event.xpComponents)
                  ToneBadge(
                    label: '${component.type.label} +${component.amount}',
                    color: AppColors.success,
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            const ToneBadge(label: '不计成长分', color: TrainFlowTokens.darkTrainingMuted),
          ],
          if (event.impacts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '模型贡献（估计）',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final GrowthImpact impact in event.impacts)
                  ToneBadge(
                    label: '${impact.dimension.label} ${impact.pointsLabel}',
                    color: AppColors.secondaryDark,
                  ),
              ],
            ),
          ],
          if (event.missingData.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '缺少数据：${event.missingData.join('、')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.warningDark,
                  ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '来源 ${event.sourceTable}:${event.sourceId} · 模型 v${event.modelVersion}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }

  String _eventDateLabel(GrowthEvidenceEvent event) {
    final DateTime date = event.occurredOn;
    final DateTime sourceLocal = event.occurredAt
        .toUtc()
        .add(Duration(minutes: event.timeZoneOffsetMinutes));
    final String hour = sourceLocal.hour.toString().padLeft(2, '0');
    final String minute = sourceLocal.minute.toString().padLeft(2, '0');
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} $hour:$minute · ${event.eventType.label}';
  }
}
