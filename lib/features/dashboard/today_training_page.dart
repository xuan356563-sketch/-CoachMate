import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/body_metric.dart';
import '../../data/models/daily_adjustment.dart';
import '../../data/models/daily_check_in.dart';
import '../../data/models/evidence_source.dart';
import '../../data/models/meal_guide.dart';
import '../../data/models/motion_check.dart';
import '../../data/models/pain_log.dart';
import '../../data/models/race.dart';
import '../../data/models/starter_program.dart';
import '../../data/models/training_load_curve.dart';
import '../../data/models/training_reminder.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/workout_day.dart';
import 'training_mvp_controller.dart';

class TodayTrainingPage extends ConsumerWidget {
  const TodayTrainingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final WorkoutDay todayWorkout = state.todayWorkout;

    return TrainFlowPage(
      title: '今日训练',
      subtitle: 'TrainFlow AI / AI 训练决策辅助系统',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '照吃卡',
            onPressed: () => context.go(AppRoutes.mealGuide),
            icon: const Icon(Icons.restaurant_menu),
          ),
          IconButton(
            tooltip: '记录疼痛',
            onPressed: () => context.go(AppRoutes.rehab),
            icon: const Icon(Icons.health_and_safety_outlined),
          ),
          IconButton(
            tooltip: 'AI 教练',
            onPressed: () => context.go(AppRoutes.aiCoach),
            icon: const Icon(Icons.auto_awesome),
          ),
          IconButton(
            tooltip: '提醒',
            onPressed: () => context.go(AppRoutes.reminders),
            icon: const Icon(Icons.notifications_active_outlined),
          ),
        ],
      ),
      children: [
        if (!state.profileCompleted) const _OnboardingPromptCard(),
        _MorningReportCard(state: state),
        _WorkerProfileStrategyCard(state: state),
        _ReminderPreviewCard(state: state),
        _DailyCheckInPreviewCard(state: state),
        const _RehabEntryCard(),
        if (state.latestPainLog != null)
          _PainRiskCard(painLog: state.latestPainLog!),
        _ReadinessCard(state: state),
        _RecoveryCountdownCard(state: state),
        _DailyAdjustmentPreviewCard(state: state),
        _TrainingStatusTrendCard(state: state),
        _StarterProgramPreviewCard(
            day: state.activeStarterProgramDay, state: state),
        _DataCenterPreviewCard(metric: state.latestBodyMetric, state: state),
        _MealGuidePreviewCard(guide: state.activeMealGuide),
        _MotionCheckPreviewCard(state: state),
        _RacePrepPreviewCard(race: state.featuredRace),
        const SectionTitle(title: '今日训练内容'),
        _WorkoutSummaryCard(workout: todayWorkout),
        const _FeedbackCard(),
        const SectionTitle(title: 'AI 教练建议 Mock'),
        _CoachAdviceCard(advice: state.coachAdvices),
        const SectionTitle(title: '训练依据'),
        _EvidenceSourceCard(sources: todayWorkout.evidenceSources),
      ],
    );
  }
}

class _MorningReportCard extends StatelessWidget {
  final TrainingMvpState state;

  const _MorningReportCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final BodyMetric? metric = state.latestBodyMetric;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wb_sunny_outlined, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '晨间报告',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: state.readinessLabel),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '昨晚睡眠',
                  value: metric == null
                      ? '未记录'
                      : '${metric.sleepHours.toStringAsFixed(1)} h',
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: 'HRV',
                  value: metric == null ? '未记录' : '${metric.hrvMs} ms',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoRow(label: '今日安排', value: state.todayWorkout.title),
          InfoRow(label: '一句话建议', value: state.morningReportAdvice),
        ],
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

class _ReminderPreviewCard extends StatelessWidget {
  final TrainingMvpState state;

  const _ReminderPreviewCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final TrainingReminder? nextReminder = state.nextTrainingReminder;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '主动提醒',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: state.remindersEnabled ? '本地 Mock' : '已暂停',
                color: state.remindersEnabled
                    ? AppColors.primary
                    : AppColors.warningDark,
              ),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(label: '下一条', value: state.reminderSummaryLabel),
          if (nextReminder != null) ...[
            const SizedBox(height: 4),
            Text(
              nextReminder.reason,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.reminders),
              child: const Text('打开提醒'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyCheckInPreviewCard extends StatelessWidget {
  final TrainingMvpState state;

  const _DailyCheckInPreviewCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final DailyCheckInSummary summary = state.dailyCheckInSummary;

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
              ToneBadge(label: summary.modeLabel),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(label: '今天只问', value: summary.questionCountLabel),
          Text(
            summary.explanation,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            summary.sortExplanation,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.dailyCheckIn),
              child: const Text('打开签到'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecoveryCountdownCard extends StatelessWidget {
  final TrainingMvpState state;

  const _RecoveryCountdownCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final bool hasLog = state.latestLog != null;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_bottom, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '恢复倒计时',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: state.recoveryCountdownLabel,
                color: hasLog ? AppColors.secondary : AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '距下次高强度课',
                  value: state.recoveryCountdownLabel,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '建议恢复',
                  value: '${state.recommendedRecoveryHours} 小时',
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            state.recoveryAdvice,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
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
              onPressed: () => context.go(AppRoutes.dailyAdjustment),
              child: const Text('打开调整'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainingStatusTrendCard extends StatelessWidget {
  final TrainingMvpState state;

  const _TrainingStatusTrendCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final double acute = state.acuteLoadScore;
    final double chronic = state.chronicLoadScore;
    final double acuteRatio = (acute / chronic).clamp(0.0, 1.4).toDouble();
    final double chronicRatio = (chronic / 520).clamp(0.0, 1.0).toDouble();
    final List<TrainingLoadCurvePoint> curvePoints =
        state.trainingLoadCurvePoints;
    final TrainingLoadCurvePoint? latestLoadPoint =
        curvePoints.isEmpty ? null : curvePoints.last;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '训练状态趋势',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: state.trainingStatusLabel),
            ],
          ),
          const SizedBox(height: 12),
          _LoadBar(
            label: 'ATL 急性负荷',
            value: acuteRatio / 1.4,
            score: acute.round(),
            color: AppColors.warning,
          ),
          const SizedBox(height: 10),
          _LoadBar(
            label: 'CTL 慢性体能',
            value: chronicRatio,
            score: chronic.round(),
            color: AppColors.primary,
          ),
          if (curvePoints.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'CTL / ATL / TSB 训练负荷曲线',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '当前 TSB ${latestLoadPoint!.tsbScore.round()} · 日负荷 ${latestLoadPoint.dailyLoadScore.round()}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            _LoadCurveChart(points: curvePoints),
            const SizedBox(height: 8),
            const _LoadCurveLegend(),
          ],
          const SizedBox(height: 12),
          Text(
            state.trainingStatusReason,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _LoadBar extends StatelessWidget {
  final String label;
  final double value;
  final int score;
  final Color color;

  const _LoadBar({
    required this.label,
    required this.value,
    required this.score,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '$score',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: value,
          minHeight: 8,
          color: color,
          backgroundColor: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
      ],
    );
  }
}

class _LoadCurveChart extends StatelessWidget {
  final List<TrainingLoadCurvePoint> points;

  const _LoadCurveChart({required this.points});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: CustomPaint(
        painter: _LoadCurvePainter(points: points),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 100),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  points.first.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                Text(
                  points.last.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadCurveLegend extends StatelessWidget {
  const _LoadCurveLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _LegendDot(label: 'CTL', color: AppColors.primary),
        SizedBox(width: 14),
        _LegendDot(label: 'ATL', color: AppColors.warning),
        SizedBox(width: 14),
        _LegendDot(label: 'TSB', color: AppColors.secondary),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendDot({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _LoadCurvePainter extends CustomPainter {
  final List<TrainingLoadCurvePoint> points;

  const _LoadCurvePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    final double chartHeight = size.height - 22;
    for (final double ratio in <double>[0, 0.5, 1]) {
      final double y = chartHeight * ratio;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final List<double> allValues = [
      for (final TrainingLoadCurvePoint point in points) ...[
        point.ctlScore,
        point.atlScore,
        point.tsbScore,
      ],
    ];
    final double minValue =
        allValues.reduce((double a, double b) => a < b ? a : b);
    final double maxValue =
        allValues.reduce((double a, double b) => a > b ? a : b);

    _drawLine(
      canvas: canvas,
      size: Size(size.width, chartHeight),
      color: AppColors.primary,
      values:
          points.map((TrainingLoadCurvePoint point) => point.ctlScore).toList(),
      minValue: minValue,
      maxValue: maxValue,
    );
    _drawLine(
      canvas: canvas,
      size: Size(size.width, chartHeight),
      color: AppColors.warning,
      values:
          points.map((TrainingLoadCurvePoint point) => point.atlScore).toList(),
      minValue: minValue,
      maxValue: maxValue,
    );
    _drawLine(
      canvas: canvas,
      size: Size(size.width, chartHeight),
      color: AppColors.secondary,
      values:
          points.map((TrainingLoadCurvePoint point) => point.tsbScore).toList(),
      minValue: minValue,
      maxValue: maxValue,
    );
  }

  void _drawLine({
    required Canvas canvas,
    required Size size,
    required Color color,
    required List<double> values,
    required double minValue,
    required double maxValue,
  }) {
    if (values.isEmpty) {
      return;
    }
    final double range =
        (maxValue - minValue).abs() < 1 ? 1 : maxValue - minValue;
    final Path path = Path();
    for (int i = 0; i < values.length; i += 1) {
      final double x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final double normalized = (values[i] - minValue) / range;
      final double y = size.height - normalized * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = color);
    }
    final Paint linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _LoadCurvePainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

class _StarterProgramPreviewCard extends StatelessWidget {
  final StarterProgramDay day;
  final TrainingMvpState state;

  const _StarterProgramPreviewCard({
    required this.day,
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
              const Icon(Icons.flag_circle, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '30 天渐进引导',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: day.dayLabel),
            ],
          ),
          const SizedBox(height: 10),
          Text(
              '${day.title} · ${day.durationMinutes} 分钟 · 连续 ${state.starterProgramStreak} 天'),
          const SizedBox(height: 8),
          Text(
            '今天只做一屏：做什么 + 怎么吃；太累可切 5 分钟补救版。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.starterProgram),
              child: const Text('打开引导'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataCenterPreviewCard extends StatelessWidget {
  final BodyMetric? metric;
  final TrainingMvpState state;

  const _DataCenterPreviewCard({
    required this.metric,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final BodyMetric? latestMetric = metric;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '身体数据',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: '7 日趋势'),
            ],
          ),
          const SizedBox(height: 10),
          if (latestMetric == null)
            const Text('还没有身体数据，先完成一次 10 秒快录。')
          else
            Text(
              '${latestMetric.measuredDateLabel} · 体重 ${latestMetric.weightKg.toStringAsFixed(1)} kg · HRV ${latestMetric.hrvMs} ms · 睡眠 ${latestMetric.sleepHours.toStringAsFixed(1)} h',
            ),
          const SizedBox(height: 8),
          Text(
            '7 日均值：体重 ${state.averageWeight7d.toStringAsFixed(1)} kg，静息心率 ${state.averageRestingHr7d.round()} bpm。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.dataCenter),
              child: const Text('查看身体数据'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RacePrepPreviewCard extends StatelessWidget {
  final RacePlan race;

  const _RacePrepPreviewCard({required this.race});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '比赛备战',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: race.type.label),
            ],
          ),
          const SizedBox(height: 10),
          Text('${race.name} · ${race.currentPhase} · ${race.raceDateLabel}'),
          const SizedBox(height: 8),
          Text(
            '已接入周期反推、赛前减量、装备建议、比赛策略和成绩预测 Mock。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.races),
              child: const Text('查看比赛备战'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MotionCheckPreviewCard extends StatelessWidget {
  final TrainingMvpState state;

  const _MotionCheckPreviewCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final MotionCheckRule rule = state.featuredMotionCheck;
    final MotionAnalysisResult? result = state.latestMotionAnalysisResult;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.motion_photos_on, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '动作纠错',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: '${rule.score} 分'),
            ],
          ),
          const SizedBox(height: 10),
          if (result == null)
            Text('8 个核心动作规则已接入，今日先从${rule.type.label}纠错开始。')
          else
            Text(
              '最近分析：${result.type.label} · ${result.riskLevel.label} · ${result.suggestedImpact.label}',
            ),
          const SizedBox(height: 8),
          Text(
            result == null
                ? '当前为本地规则 Mock，不做真实视频识别。'
                : '动作质量风险已进入每日调整，训练会按 Body Engine 解释更保守地处理。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.motionCheck),
              child: const Text('查看纠错'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MealGuidePreviewCard extends StatelessWidget {
  final MealGuide guide;

  const _MealGuidePreviewCard({required this.guide});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_menu, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今日照吃卡',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: guide.scenario.label),
            ],
          ),
          const SizedBox(height: 10),
          Text(guide.instruction),
          const SizedBox(height: 8),
          Text(
            guide.formula,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.mealGuide),
              child: const Text('查看照吃指令'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RehabEntryCard extends StatelessWidget {
  const _RehabEntryCard();

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Row(
        children: [
          const Icon(Icons.health_and_safety_outlined,
              color: AppColors.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('康复记录：记录疼痛后今日训练会自动降级'),
          ),
          TextButton(
            onPressed: () => context.go(AppRoutes.rehab),
            child: const Text('记录疼痛'),
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
                        .read(trainingMvpProvider.notifier)
                        .saveProfile(state.profile);
                  },
                  child: const Text('使用当前资料'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => context.go(AppRoutes.onboarding),
                child: const Text('调整'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  final TrainingMvpState state;

  const _ReadinessCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final Color color = readinessColor(state.readinessScore);

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  state.readinessLabel,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: '${state.readinessScore} 分', color: color),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '今日时长',
                  value: '${state.todayWorkout.estimatedMinutes} 分钟',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '目标强度',
                  value: state.todayWorkout.intensity,
                  color: AppColors.secondary,
                ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrainFlowCard(
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
          _FiveStepFlow(workout: workout),
          const SizedBox(height: 12),
          InfoRow(label: '热身补充', value: workout.warmupSteps.join(' / ')),
          InfoRow(label: '主训练', value: workout.mainSets.join(' / ')),
          InfoRow(
            label: '辅助',
            value: workout.accessoryWork.isEmpty
                ? '无需额外辅助'
                : workout.accessoryWork.join(' / '),
          ),
          InfoRow(label: '冷身', value: workout.cooldownSteps.join(' / ')),
          const SizedBox(height: 8),
          Text(
            workout.coachNotes,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () {
                ref.read(trainingMvpProvider.notifier).startWorkoutPlayer();
                context.go(AppRoutes.workoutPlayer);
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始跟练'),
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
        Text(
          '今日训练五步',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
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

class _FeedbackCard extends ConsumerWidget {
  const _FeedbackCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int rpe = ref.watch(feedbackRpeProvider);
    final bool completed = ref.watch(feedbackCompletedProvider);

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '训练完成记录',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('今天已完成训练'),
            value: completed,
            onChanged: (bool value) {
              ref.read(feedbackCompletedProvider.notifier).setValue(value);
            },
          ),
          Row(
            children: [
              const Text('体感强度'),
              Expanded(
                child: Slider(
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '$rpe',
                  value: rpe.toDouble(),
                  onChanged: (double value) {
                    ref
                        .read(feedbackRpeProvider.notifier)
                        .setValue(value.round());
                  },
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '$rpe',
                  textAlign: TextAlign.end,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                ref.read(trainingMvpProvider.notifier).saveTodayLog(
                      completed: completed,
                      rpe: rpe,
                      userNote: completed ? '按计划完成' : '未完成，等待调整',
                    );
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('保存今日反馈'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceSourceCard extends StatelessWidget {
  final List<EvidenceSource> sources;

  const _EvidenceSourceCard({required this.sources});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final EvidenceSource source in sources) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    source.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                ToneBadge(
                  label: source.sourceType.label,
                  color: AppColors.secondary,
                ),
              ],
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
            const SizedBox(height: 4),
            Text(
              '适用原因：${source.note}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            if (source != sources.last) const Divider(height: 22),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.knowledge),
              child: const Text('查看书库'),
            ),
          ),
        ],
      ),
    );
  }
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
    return TrainFlowCard(
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
    );
  }
}
