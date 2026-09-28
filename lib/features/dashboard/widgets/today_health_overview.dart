import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/trainflow_tokens.dart';
import '../../../data/models/body_metric.dart';
import '../../../data/models/daily_activity_summary.dart';
import '../../../data/models/daily_check_in_record.dart';
import '../../../data/models/health_snapshot.dart';

/// 今日健康概览只聚合已经同步或已确认的数据，不补造缺失指标。
class TodayHealthOverviewData {
  const TodayHealthOverviewData({
    required this.activitySummaries,
    required this.latestActivity,
    required this.checkInStreak,
    required this.sleepHours,
    required this.restingHeartRate,
    required this.hrvMs,
    required this.activityStatusMessage,
    this.recoveryEvidence = '来源待确认。',
  });

  final List<DailyActivitySummary> activitySummaries;
  final DailyActivitySummary? latestActivity;
  final CheckInStreakState checkInStreak;
  final double? sleepHours;
  final int? restingHeartRate;
  final int? hrvMs;
  final String activityStatusMessage;
  final String recoveryEvidence;

  factory TodayHealthOverviewData.fromSources({
    required List<DailyActivitySummary> activitySummaries,
    required List<HealthSnapshot> healthSnapshots,
    required BodyMetric? latestBodyMetric,
    required CheckInStreakState checkInStreak,
    required String activityStatusMessage,
    required DateTime now,
  }) {
    final List<DailyActivitySummary> orderedActivities =
        List<DailyActivitySummary>.from(activitySummaries)
          ..sort(
            (DailyActivitySummary left, DailyActivitySummary right) =>
                right.localDate.compareTo(left.localDate),
          );
    final DateTime localNow = now.toLocal();
    final String recoveryDate = _dateKey(localNow);
    final List<HealthSnapshot> orderedSnapshots = healthSnapshots
        .where((item) =>
            _dateKey(item.date.toLocal()) == recoveryDate &&
            item.syncedAt.millisecondsSinceEpoch > 0 &&
            !item.syncedAt.isBefore(item.date) &&
            !item.syncedAt.isAfter(now))
        .toList()
      ..sort(
        (HealthSnapshot left, HealthSnapshot right) =>
            right.syncedAt.compareTo(left.syncedAt),
      );
    // 先选最近摘要再校验字段，不从旧同步结果补回已缺失的观测。
    final HealthSnapshot? latestSnapshot =
        orderedSnapshots.isEmpty ? null : orderedSnapshots.first;
    final bool verifiedSnapshot = latestSnapshot != null &&
        latestSnapshot.sourceLineageVersion >= 2 &&
        latestSnapshot.sourceIds.any((id) => id.trim().isNotEmpty);
    final bool currentBody = latestBodyMetric != null &&
        latestBodyMetric.measuredAt.millisecondsSinceEpoch > 0 &&
        !latestBodyMetric.measuredAt.isAfter(now) &&
        _dateKey(latestBodyMetric.measuredAt.toLocal()) == recoveryDate;
    final List<String> evidence = <String>[];
    num? recoveryValue(String field, String label, num? health, num? body) {
      if (verifiedSnapshot && health != null && health.isFinite && health > 0) {
        evidence.add('$label：$recoveryDate · Apple 健康摘要');
        return health;
      }
      if (currentBody && latestBodyMetric.hasValue(field)) {
        evidence.add('$label：$recoveryDate · ${latestBodyMetric.source.label}');
        return body;
      }
      evidence.add('$label：今日无可用记录');
      return null;
    }

    final double? sleep = recoveryValue('sleepHours', '睡眠',
            latestSnapshot?.sleepHours, latestBodyMetric?.sleepHours)
        ?.toDouble();
    final int? heart = recoveryValue(
            'restingHeartRate',
            '静息心率',
            latestSnapshot?.restingHeartRate,
            latestBodyMetric?.restingHeartRate)
        ?.toInt();
    final int? hrv = recoveryValue(
            'hrvMs', 'HRV', latestSnapshot?.hrvMs, latestBodyMetric?.hrvMs)
        ?.toInt();

    final String todayKey = _dateKey(now);
    DailyActivitySummary? todayActivity;
    for (final DailyActivitySummary activity in orderedActivities) {
      if (activity.localDate == todayKey) {
        todayActivity = activity;
        break;
      }
    }

    return TodayHealthOverviewData(
      activitySummaries: List<DailyActivitySummary>.unmodifiable(
        orderedActivities,
      ),
      latestActivity: todayActivity,
      checkInStreak: checkInStreak,
      sleepHours: sleep,
      restingHeartRate: heart,
      hrvMs: hrv,
      activityStatusMessage: activityStatusMessage,
      recoveryEvidence: '${evidence.join('\n')}\n'
          '仅展示当日可用字段；旧日、来源未确认或无效字段不作为今日观测。记录不等于今日状态已确认。',
    );
  }

  List<double?> weekValuesFor(DailyActivityField field, DateTime now) {
    final Map<String, DailyActivitySummary> summariesByDate =
        <String, DailyActivitySummary>{
      for (final DailyActivitySummary item in activitySummaries)
        item.localDate: item,
    };
    final DateTime today = DateTime(now.year, now.month, now.day);
    return List<double?>.generate(7, (int index) {
      final DateTime date = today.subtract(Duration(days: 6 - index));
      final DailyActivitySummary? item = summariesByDate[_dateKey(date)];
      return switch (field) {
        DailyActivityField.steps => item?.steps?.toDouble(),
        DailyActivityField.activeEnergyKcal => item?.activeEnergyKcal,
        DailyActivityField.exerciseMinutes => item?.exerciseMinutes?.toDouble(),
        DailyActivityField.standHours => item?.standHours?.toDouble(),
        _ => null,
      };
    });
  }
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// 参考健康仪表盘的紧凑信息结构，所有卡片均指向已有确认或同步流程。
class TodayHealthOverview extends StatelessWidget {
  const TodayHealthOverview({
    super.key,
    required this.data,
    required this.now,
    required this.onOpenActivitySettings,
    required this.onOpenCheckIn,
    this.darkCanvas = false,
  });

  final TodayHealthOverviewData data;
  final DateTime now;
  final VoidCallback? onOpenActivitySettings;
  final VoidCallback? onOpenCheckIn;
  final bool darkCanvas;

  @override
  Widget build(BuildContext context) {
    final DailyActivitySummary? latest = data.latestActivity;
    final String activityStatusMessage =
        latest == null && data.activitySummaries.isNotEmpty
            ? '今日活动摘要待同步；历史活动仅用于近 7 日趋势。'
            : data.activityStatusMessage;
    final _MetricDefinition steps = _MetricDefinition(
      id: 'steps',
      title: '步数',
      icon: Icons.directions_walk_rounded,
      value: latest?.steps,
      goal: latest?.stepGoal,
      unit: '步',
      color: TrainFlowTokens.blue,
      trend: data.weekValuesFor(DailyActivityField.steps, now),
    );
    final _MetricDefinition energy = _MetricDefinition(
      id: 'energy',
      title: '活动能量',
      icon: Icons.local_fire_department_rounded,
      value: latest?.activeEnergyKcal,
      goal: latest?.activeEnergyGoalKcal,
      unit: '千卡',
      color: TrainFlowTokens.coral,
      trend: data.weekValuesFor(DailyActivityField.activeEnergyKcal, now),
    );
    final _MetricDefinition exercise = _MetricDefinition(
      id: 'exercise',
      title: '锻炼',
      icon: Icons.timer_outlined,
      value: latest?.exerciseMinutes,
      goal: latest?.exerciseGoalMinutes,
      unit: '分钟',
      color: TrainFlowTokens.purple,
      trend: data.weekValuesFor(DailyActivityField.exerciseMinutes, now),
    );
    final _MetricDefinition stand = _MetricDefinition(
      id: 'stand',
      title: '站立',
      icon: Icons.accessibility_new_rounded,
      value: latest?.standHours,
      goal: latest?.standGoalHours,
      unit: '小时',
      color: TrainFlowTokens.mint,
      trend: data.weekValuesFor(DailyActivityField.standHours, now),
    );

    return Semantics(
      container: true,
      label: '健康概览与习惯追踪',
      child: Column(
        key: const ValueKey<String>('today-health-overview'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeading(
            title: '习惯追踪',
            darkCanvas: darkCanvas,
            trailing: _StreakPill(days: data.checkInStreak.currentStreak),
          ),
          const SizedBox(height: 12),
          _HabitSummaryCard(
            streak: data.checkInStreak,
            onTap: onOpenCheckIn,
          ),
          const SizedBox(height: 16),
          _SectionHeading(
            title: '健康概览',
            darkCanvas: darkCanvas,
            trailing: TextButton.icon(
              key: const ValueKey<String>('today-health-open-settings'),
              onPressed: onOpenActivitySettings,
              icon: const Icon(Icons.sync_rounded, size: 17),
              label: const Text('同步与目标'),
              style: darkCanvas
                  ? TextButton.styleFrom(
                      foregroundColor: TrainFlowTokens.yellow,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          _ActivityStatusBanner(
            message: activityStatusMessage,
            hasActivity: latest != null,
            onTap: onOpenActivitySettings,
          ),
          const SizedBox(height: 12),
          _ResponsiveMetricGrid(
            children: <Widget>[
              _StepProgressCard(metric: steps, onTap: onOpenActivitySettings),
              _MetricCard(metric: energy, onTap: onOpenActivitySettings),
              _MetricCard(metric: exercise, onTap: onOpenActivitySettings),
              _MetricCard(metric: stand, onTap: onOpenActivitySettings),
            ],
          ),
          const SizedBox(height: 12),
          _RecoveryCard(
            sleepHours: data.sleepHours,
            restingHeartRate: data.restingHeartRate,
            hrvMs: data.hrvMs,
            evidence: data.recoveryEvidence,
            onTap: onOpenCheckIn,
          ),
          const SizedBox(height: 12),
          _ActivityTrendCard(
            steps: steps,
            energy: energy,
            onTap: onOpenActivitySettings,
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.trailing,
    required this.darkCanvas,
  });

  final String title;
  final Widget trailing;
  final bool darkCanvas;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: darkCanvas
                        ? TrainFlowTokens.paper
                        : TrainFlowTokens.brandDark,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          trailing,
        ],
      );
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: TrainFlowTokens.purpleSoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            days > 0 ? '连续 $days 天' : '等待首次记录',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: TrainFlowTokens.brandDark,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      );
}

class _HabitSummaryCard extends StatelessWidget {
  const _HabitSummaryCard({required this.streak, required this.onTap});

  final CheckInStreakState streak;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool hasRecord = streak.totalCheckInDays > 0;
    return _TappableSurface(
      key: const ValueKey<String>('today-habit-summary-card'),
      semanticLabel: hasRecord
          ? '已连续记录 ${streak.currentStreak} 天，点击进入今日签到'
          : '尚未完成今日记录，点击进入今日签到',
      onTap: onTap,
      color: TrainFlowTokens.paper,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            _IconTile(
              icon: hasRecord ? Icons.auto_awesome_rounded : Icons.edit_note,
              color: TrainFlowTokens.yellow,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    hasRecord ? '今日节奏已开始' : '完成今天的状态记录',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: TrainFlowTokens.brandDark,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasRecord
                        ? '累计 ${streak.totalCheckInDays} 天 · 最长 ${streak.longestStreak} 天'
                        : '记录睡眠、疲劳与心情，形成真实训练节奏。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TrainFlowTokens.darkTrainingMuted,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded,
                color: TrainFlowTokens.brandDark),
          ],
        ),
      ),
    );
  }
}

class _ActivityStatusBanner extends StatelessWidget {
  const _ActivityStatusBanner({
    required this.message,
    required this.hasActivity,
    required this.onTap,
  });

  final String message;
  final bool hasActivity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _TappableSurface(
        key: const ValueKey<String>('today-health-status-banner'),
        semanticLabel: '活动数据状态：$message，点击打开同步与目标设置',
        onTap: onTap,
        color: hasActivity
            ? TrainFlowTokens.purpleSoft
            : TrainFlowTokens.peachLight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(
                hasActivity
                    ? Icons.verified_outlined
                    : Icons.cloud_sync_outlined,
                size: 18,
                color: TrainFlowTokens.brandDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TrainFlowTokens.brandDark,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: TrainFlowTokens.brandDark),
            ],
          ),
        ),
      );
}

class _ResponsiveMetricGrid extends StatelessWidget {
  const _ResponsiveMetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool singleColumn = constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.35;
          if (singleColumn) {
            return Column(
              children: <Widget>[
                for (int index = 0; index < children.length; index += 1) ...[
                  children[index],
                  if (index != children.length - 1) const SizedBox(height: 12),
                ],
              ],
            );
          }
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              for (final Widget child in children)
                SizedBox(width: (constraints.maxWidth - 12) / 2, child: child),
            ],
          );
        },
      );
}

class _MetricDefinition {
  const _MetricDefinition({
    required this.id,
    required this.title,
    required this.icon,
    required this.value,
    required this.goal,
    required this.unit,
    required this.color,
    required this.trend,
  });

  final String id;
  final String title;
  final IconData icon;
  final num? value;
  final num? goal;
  final String unit;
  final Color color;
  final List<double?> trend;

  bool get hasValue => value != null;
  bool get hasGoal => goal != null && goal! > 0;
  double? get progress => hasValue && hasGoal
      ? (value!.toDouble() / goal!.toDouble()).clamp(0.0, 1.0)
      : null;

  String get valueLabel => hasValue ? _formatNumber(value!) : '待同步';
  String get goalLabel => hasGoal ? '/ ${_formatNumber(goal!)} $unit' : '暂无目标';
}

class _StepProgressCard extends StatelessWidget {
  const _StepProgressCard({required this.metric, required this.onTap});

  final _MetricDefinition metric;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _TappableSurface(
        key: const ValueKey<String>('today-health-steps-card'),
        semanticLabel:
            '步数 ${metric.valueLabel} ${metric.unit}，${metric.goalLabel}，点击打开同步与目标设置',
        onTap: onTap,
        color: TrainFlowTokens.paper,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              _ProgressArc(
                progress: metric.progress,
                color: metric.color,
                icon: metric.icon,
              ),
              const SizedBox(width: 12),
              Expanded(child: _MetricText(metric: metric)),
            ],
          ),
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, required this.onTap});

  final _MetricDefinition metric;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _TappableSurface(
        key: ValueKey<String>('today-health-${metric.id}-card'),
        semanticLabel:
            '${metric.title} ${metric.valueLabel} ${metric.unit}，${metric.goalLabel}，点击打开同步与目标设置',
        onTap: onTap,
        color: TrainFlowTokens.paper,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _IconTile(icon: metric.icon, color: metric.color, compact: true),
              const SizedBox(height: 13),
              _MetricText(metric: metric),
              const SizedBox(height: 9),
              _MiniBars(values: metric.trend, color: metric.color),
            ],
          ),
        ),
      );
}

class _MetricText extends StatelessWidget {
  const _MetricText({required this.metric});

  final _MetricDefinition metric;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            metric.title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: metric.valueLabel,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: TrainFlowTokens.brandDark,
                        fontSize: metric.hasValue ? 27 : 18,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                ),
                if (metric.hasValue)
                  TextSpan(
                    text: ' ${metric.unit}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: TrainFlowTokens.darkTrainingMuted,
                        ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            metric.goalLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      );
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    required this.sleepHours,
    required this.restingHeartRate,
    required this.hrvMs,
    required this.evidence,
    required this.onTap,
  });

  final double? sleepHours;
  final int? restingHeartRate;
  final int? hrvMs;
  final String evidence;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String sleep =
        sleepHours == null ? '暂无数据' : '${sleepHours!.toStringAsFixed(1)} 小时';
    final String heart =
        restingHeartRate == null ? '暂无数据' : '$restingHeartRate 次/分';
    final String hrv = hrvMs == null ? '暂无数据' : '$hrvMs ms';
    return _TappableSurface(
      key: const ValueKey<String>('today-health-recovery-card'),
      semanticLabel: '睡眠与恢复，睡眠 $sleep，静息心率 $heart，HRV $hrv，$evidence，点击进入今日签到',
      onTap: onTap,
      color: TrainFlowTokens.showcaseActionSurface,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const _IconTile(
                  icon: Icons.bedtime_outlined,
                  color: TrainFlowTokens.blue,
                  compact: true,
                ),
                const SizedBox(width: 10),
                Text(
                  '睡眠与恢复',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: TrainFlowTokens.paper,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward_rounded,
                    color: TrainFlowTokens.paper),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: <Widget>[
                _RecoveryValue(label: '睡眠', value: sleep),
                _RecoveryValue(label: '静息心率', value: heart),
                _RecoveryValue(label: 'HRV', value: hrv),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '$evidence\n睡眠阶段需由数据来源提供，当前不展示估算分期。',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: TrainFlowTokens.paper.withValues(alpha: 0.66),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryValue extends StatelessWidget {
  const _RecoveryValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: TrainFlowTokens.paper,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: TrainFlowTokens.paper.withValues(alpha: 0.68),
                ),
          ),
        ],
      );
}

class _ActivityTrendCard extends StatelessWidget {
  const _ActivityTrendCard({
    required this.steps,
    required this.energy,
    required this.onTap,
  });

  final _MetricDefinition steps;
  final _MetricDefinition energy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool hasTrend = steps.trend.any((double? item) => item != null) ||
        energy.trend.any((double? item) => item != null);
    return _TappableSurface(
      key: const ValueKey<String>('today-health-trend-card'),
      semanticLabel:
          hasTrend ? '近七日活动趋势，点击打开同步与目标设置' : '近七日活动趋势暂无数据，点击打开同步与目标设置',
      onTap: onTap,
      color: TrainFlowTokens.paper,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const _IconTile(
                  icon: Icons.show_chart_rounded,
                  color: TrainFlowTokens.purple,
                  compact: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '近 7 日活动趋势',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: TrainFlowTokens.brandDark,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Text(
                  hasTrend ? '真实数据' : '待同步',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: TrainFlowTokens.darkTrainingMuted,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 86,
              child: CustomPaint(
                painter: _ActivityTrendPainter(
                  steps: steps.trend,
                  energy: energy.trend,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 7),
            const Row(
              children: <Widget>[
                _Legend(color: TrainFlowTokens.blue, label: '步数'),
                SizedBox(width: 14),
                _Legend(color: TrainFlowTokens.coral, label: '活动能量'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: const SizedBox.square(dimension: 7),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      );
}

class _TappableSurface extends StatelessWidget {
  const _TappableSurface({
    super.key,
    required this.semanticLabel,
    required this.onTap,
    required this.color,
    required this.child,
  });

  final String semanticLabel;
  final VoidCallback? onTap;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semanticLabel,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: child,
          ),
        ),
      );
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double size = compact ? 34 : 44;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(compact ? 11 : 14),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, color: color, size: compact ? 19 : 24),
      ),
    );
  }
}

class _ProgressArc extends StatelessWidget {
  const _ProgressArc({
    required this.progress,
    required this.color,
    required this.icon,
  });

  final double? progress;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 66,
        child: CustomPaint(
          painter: _ProgressArcPainter(
            progress: progress,
            color: color,
            icon: icon,
            textDirection: Directionality.of(context),
          ),
        ),
      );
}

class _ProgressArcPainter extends CustomPainter {
  const _ProgressArcPainter({
    required this.progress,
    required this.color,
    required this.icon,
    required this.textDirection,
  });

  final double? progress;
  final Color color;
  final IconData icon;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    const double stroke = 6;
    final Rect rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final Paint track = Paint()
      ..color = TrainFlowTokens.border
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(rect, -math.pi * .78, math.pi * 1.56, false, track);
    if (progress != null) {
      final Paint active = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke;
      canvas.drawArc(
        rect,
        -math.pi * .78,
        math.pi * 1.56 * progress!.clamp(0, 1),
        false,
        active,
      );
    }
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: color,
          fontSize: 24,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressArcPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.icon != icon;
}

class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.values, required this.color});

  final List<double?> values;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 22,
        child: CustomPaint(
          painter: _MiniBarsPainter(values: values, color: color),
          child: const SizedBox.expand(),
        ),
      );
}

class _MiniBarsPainter extends CustomPainter {
  const _MiniBarsPainter({required this.values, required this.color});

  final List<double?> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final List<double> present = values.whereType<double>().toList();
    final double maximum =
        present.isEmpty ? 1 : math.max(present.reduce(math.max), 1);
    final double barWidth = size.width / math.max(values.length * 1.65, 1);
    for (int index = 0; index < values.length; index += 1) {
      final double? value = values[index];
      final double x = index * barWidth * 1.65;
      if (value == null) {
        final Paint missing = Paint()
          ..color = TrainFlowTokens.border.withValues(alpha: 0.9)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2;
        canvas.drawLine(
          Offset(x + barWidth * 0.25, size.height - 2),
          Offset(x + barWidth * 0.75, size.height - 2),
          missing,
        );
        continue;
      }
      final double ratio = (value / maximum).clamp(.16, 1);
      final double height = size.height * ratio;
      final Rect rect = Rect.fromLTWH(
        x,
        size.height - height,
        barWidth,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniBarsPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _ActivityTrendPainter extends CustomPainter {
  const _ActivityTrendPainter({required this.steps, required this.energy});

  final List<double?> steps;
  final List<double?> energy;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..color = TrainFlowTokens.border
      ..strokeWidth = 1;
    for (int index = 0; index < 3; index += 1) {
      final double y = size.height * (0.18 + index * .34);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    _drawSeries(canvas, size, steps, TrainFlowTokens.blue);
    _drawSeries(canvas, size, energy, TrainFlowTokens.coral);
  }

  void _drawSeries(
      Canvas canvas, Size size, List<double?> values, Color color) {
    final List<double> present = values.whereType<double>().toList();
    if (present.isEmpty) return;
    final double maxValue = math.max(present.reduce(math.max), 1);
    final Path path = Path();
    bool started = false;
    for (int index = 0; index < values.length; index += 1) {
      final double? value = values[index];
      if (value == null) {
        started = false;
        continue;
      }
      final double x = values.length == 1
          ? size.width / 2
          : index / (values.length - 1) * size.width;
      final double y = size.height -
          8 -
          (value / maxValue).clamp(0.0, 1.0) * (size.height - 18);
      if (started) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        started = true;
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _ActivityTrendPainter oldDelegate) =>
      oldDelegate.steps != steps || oldDelegate.energy != energy;
}

String _formatNumber(num value) {
  if (value is int || value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}
