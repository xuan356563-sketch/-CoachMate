import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainmate_showcase_widgets.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/growth_evidence.dart';
import '../../data/models/exercise_training_profile.dart';
import '../../data/models/monthly_summary.dart';
import '../../data/models/training_log.dart';
import '../../data/models/training_metrics.dart';
import '../../data/models/weekly_report.dart';
import '../../data/models/weekly_psych_check_in.dart';
import '../../services/local_report_generation_coordinator.dart';
import '../dashboard/training_mvp_controller.dart';
import '../growth/application/growth_evidence_controller.dart';
import '../growth/application/training_metrics_provider.dart';
import '../profile/application/health_sync_controller.dart';

enum _ReportPeriodView { week, month }

class WeeklyReportPage extends ConsumerStatefulWidget {
  const WeeklyReportPage({super.key});

  @override
  ConsumerState<WeeklyReportPage> createState() => _WeeklyReportPageState();
}

class _WeeklyReportPageState extends ConsumerState<WeeklyReportPage> {
  _ReportPeriodView _selectedPeriod = _ReportPeriodView.week;

  @override
  Widget build(BuildContext context) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final GrowthEvidenceState growthState =
        ref.watch(growthEvidenceControllerProvider);
    final DateTime weekStart = growthWeekStart(DateTime.now()).subtract(
      const Duration(days: 7),
    );
    final DateTime currentMonthStart =
        DateTime(DateTime.now().year, DateTime.now().month);
    final DateTime monthStart =
        DateTime(currentMonthStart.year, currentMonthStart.month - 1);
    final String athleteProfileId = resolveTrainingMetricsAthleteProfileId(
      growthEvidenceAthleteProfileId: growthState.athleteProfileId,
      profileAthleteProfileId: state.profile.id,
    );
    final bool showingMonth = _selectedPeriod == _ReportPeriodView.month;
    final TrainingReportQuery reportQuery = TrainingReportQuery(
      athleteProfileId: athleteProfileId,
      period: showingMonth ? MetricPeriod.month : MetricPeriod.week,
      periodStart: showingMonth ? monthStart : weekStart,
    );
    final AsyncValue<List<ReportRevision>> reportRevisions =
        ref.watch(trainingReportRevisionsProvider(reportQuery));

    return TrainFlowPage(
      title: '最近结束周期报告',
      layout: TrainFlowPageLayout.report,
      subtitle: '只为已结束周期生成本地确定性修订，不依赖云端定时任务。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.profile,
      ),
      artwork: const TrainMateIllustration(
        assetPath: 'assets/images/trainmate_growth_scene.png',
        semanticLabel: '周期报告与训练成长插画',
        fallback: TrainMateActionCharacter(
          action: TrainMateAction.plank,
          backgroundColor: AppColors.primary,
        ),
      ),
      children: [
        SegmentedButton<_ReportPeriodView>(
          key: const ValueKey<String>('report-period-selector'),
          segments: const <ButtonSegment<_ReportPeriodView>>[
            ButtonSegment<_ReportPeriodView>(
              value: _ReportPeriodView.week,
              label: Text('周报'),
              icon: Icon(Icons.calendar_view_week_outlined),
            ),
            ButtonSegment<_ReportPeriodView>(
              value: _ReportPeriodView.month,
              label: Text('月报'),
              icon: Icon(Icons.calendar_month_outlined),
            ),
          ],
          selected: <_ReportPeriodView>{_selectedPeriod},
          onSelectionChanged: (Set<_ReportPeriodView> value) {
            setState(() => _selectedPeriod = value.single);
          },
        ),
        LocalReportRevisionCard(
          reports: reportRevisions,
          reportTitle: showingMonth ? '本地确定性月报' : '本地确定性周报',
          emptyMessage: showingMonth ? '上一完整自然月的数据仍在积累，达到门槛后会生成不可变月报修订。' : null,
          onGenerate: () async {
            final bool generated = await LocalReportGenerationCoordinator(
              repository: ref.read(trainingMetricsRepositoryProvider),
              metricsPipeline: ref.read(healthSyncMetricsPipelineProvider),
              monthlySummaryLoader: ref.read(monthlySummaryLoaderProvider),
            ).ensureClosedPeriod(
              athleteProfileId: athleteProfileId,
              period: showingMonth ? MetricPeriod.month : MetricPeriod.week,
              periodStart: showingMonth ? monthStart : weekStart,
            );
            ref.invalidate(trainingReportRevisionsProvider(reportQuery));
            return generated;
          },
        ),
        if (showingMonth)
          _MonthlySummaryCard(
            reports: reportRevisions,
            monthStart: monthStart,
          )
        else ...[
          _GrowthWeeklyReportCard(
            state: state,
            growthState: growthState,
            weekStart: weekStart,
          ),
          _PsychologyWeeklyCheckInCard(state: state),
          _LockedGrowthReportsCard(growthState: growthState),
        ],
      ],
    );
  }
}

class _MonthlySummaryCard extends StatelessWidget {
  const _MonthlySummaryCard({
    required this.reports,
    required this.monthStart,
  });

  final AsyncValue<List<ReportRevision>> reports;
  final DateTime monthStart;

  @override
  Widget build(BuildContext context) {
    return reports.when(
      data: (List<ReportRevision> values) {
        final MonthlySummary? summary =
            values.isEmpty ? null : values.first.monthlySummarySnapshot;
        return TrainFlowCard(
          key: const ValueKey<String>('monthly-summary-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${monthStart.year} 年 ${monthStart.month} 月总结',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text('仅统计已结束的完整自然月；不会自动修改训练计划。'),
              const SizedBox(height: 18),
              Text(
                '核心能力变化',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (summary == null)
                const Text('训练执行、耐力 / 专项、力量和恢复数据仍在积累。')
              else
                for (final MonthlyDimensionSummary dimension
                    in summary.dimensions)
                  _MonthlyDimensionRow(dimension: dimension),
              if (summary != null &&
                  summary.trainingDimensionExposure.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  '五维训练暴露',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                _TrainingDimensionRadar(
                  exposure: summary.trainingDimensionExposure,
                ),
              ],
              const SizedBox(height: 18),
              Text(
                '身体变化',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (summary == null)
                const Text('体重、体脂、静息心率、HRV、睡眠和疲劳仍在积累有效日。')
              else
                for (final MonthlyMetricChange change in summary.bodyChanges)
                  _MonthlyMetricRow(change: change),
              const SizedBox(height: 8),
              Text(
                '体重和体脂只描述变化，不判断好坏；其余结论使用固定阈值，不能替代医疗判断。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              if (summary != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push(AppRoutes.planGenerate),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('基于月报生成下个四周计划'),
                  ),
                ),
                const SizedBox(height: 6),
                const Text('只进入待确认草稿流程，不会自动替换当前计划。'),
              ],
            ],
          ),
        );
      },
      error: (Object error, StackTrace stackTrace) => const TrainFlowCard(
        child: Text('月度总结读取失败；本地历史数据未被修改。'),
      ),
      loading: () => const TrainFlowCard(
        child: Text('正在读取月度总结。'),
      ),
    );
  }
}

class _MonthlyDimensionRow extends StatelessWidget {
  const _MonthlyDimensionRow({required this.dimension});

  final MonthlyDimensionSummary dimension;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dimension.dimension.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ToneBadge(label: dimension.state.label),
            ],
          ),
          const SizedBox(height: 4),
          for (final MonthlyMetricChange change in dimension.metrics)
            _MonthlyMetricRow(change: change, compact: true),
        ],
      ),
    );
  }
}

class _MonthlyMetricRow extends StatelessWidget {
  const _MonthlyMetricRow({
    required this.change,
    this.compact = false,
  });

  final MonthlyMetricChange change;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextStyle? detailStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            );
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${change.label}  ${_currentValueLabel(change)}',
                  style: compact
                      ? detailStyle
                      : const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (!compact) ToneBadge(label: change.state.label),
            ],
          ),
          const SizedBox(height: 2),
          Text(_changeDetail(change), style: detailStyle),
        ],
      ),
    );
  }
}

String _currentValueLabel(MonthlyMetricChange change) {
  final double? value = change.currentValue;
  if (value == null) return '数据积累中';
  if (change.code == 'completionRate') {
    return '${(value * 100).round()}%';
  }
  return '${value.toStringAsFixed(_decimalPlaces(change))} ${change.unit}';
}

String _changeDetail(MonthlyMetricChange change) {
  if (change.state == MonthlyChangeState.accumulating) return change.reason;
  final String month = _deltaLabel(
    change.monthOverMonthDelta,
    change,
    prefix: '月环比',
  );
  final String within = _deltaLabel(
    change.withinMonthDelta,
    change,
    prefix: '月内',
  );
  return '$month · $within';
}

String _deltaLabel(
  double? delta,
  MonthlyMetricChange change, {
  required String prefix,
}) {
  if (delta == null) return '$prefix：样本不足';
  final double display = change.code == 'completionRate' ? delta * 100 : delta;
  final String sign = display > 0 ? '+' : '';
  final String unit = change.code == 'completionRate' ? '个百分点' : change.unit;
  return '$prefix：$sign${display.toStringAsFixed(_decimalPlaces(change))} $unit';
}

int _decimalPlaces(MonthlyMetricChange change) {
  return change.code == 'weight' ||
          change.code == 'bodyFat' ||
          change.code == 'sleep' ||
          change.code == 'completionRate'
      ? 1
      : 0;
}

class _PsychologyWeeklyCheckInCard extends ConsumerStatefulWidget {
  const _PsychologyWeeklyCheckInCard({required this.state});

  final TrainingMvpState state;

  @override
  ConsumerState<_PsychologyWeeklyCheckInCard> createState() =>
      _PsychologyWeeklyCheckInCardState();
}

class _PsychologyWeeklyCheckInCardState
    extends ConsumerState<_PsychologyWeeklyCheckInCard> {
  final TextEditingController _noteController = TextEditingController();
  int? _motivation;
  int? _stress;
  int? _recovery;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WeeklyReport? report = widget.state.savedWeeklyReports.isEmpty
        ? null
        : widget.state.savedWeeklyReports.first;
    return TrainFlowCard(
      key: const ValueKey<String>('weekly-psych-check-in-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt_outlined,
                  color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '本周状态复盘',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (report != null) ToneBadge(label: report.psychRiskLevel.label),
            ],
          ),
          const SizedBox(height: 8),
          const Text('三项均可跳过；未选择会保存为未采集，不会自动填中间值。'),
          const SizedBox(height: 14),
          _FivePointSelector(
            label: '训练动机',
            value: _motivation,
            onChanged: (int? value) => setState(() => _motivation = value),
          ),
          _FivePointSelector(
            label: '感知压力',
            value: _stress,
            onChanged: (int? value) => setState(() => _stress = value),
          ),
          _FivePointSelector(
            label: '恢复感',
            value: _recovery,
            onChanged: (int? value) => setState(() => _recovery = value),
          ),
          TextField(
            key: const ValueKey<String>('weekly-psych-note'),
            controller: _noteController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: '本周备注（可选）'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey<String>('weekly-psych-save'),
              onPressed: _save,
              child: const Text('保存本周状态并生成教练周报'),
            ),
          ),
          if (report != null) ...[
            const SizedBox(height: 16),
            Text(report.goalSummary),
            const SizedBox(height: 6),
            Text(report.realityObservation),
            if (report.dimensionExposure.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final TrainingDimensionExposure exposure
                      in report.dimensionExposure)
                    ToneBadge(
                      label:
                          '${exposure.dimension.label} ${exposure.completedSessions}/${exposure.plannedSessions}',
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '下周方向',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final WeeklyReportOption option in report.options)
                  ChoiceChip(
                    key: ValueKey<String>('weekly-option-${option.id}'),
                    label: Text(option.label),
                    selected: report.selectedOptionId == option.id,
                    onSelected: (_) {
                      ref
                          .read(trainingMvpProvider.notifier)
                          .selectWeeklyReportOption(
                            reportId: report.id,
                            optionId: option.id,
                          );
                    },
                  ),
              ],
            ),
            Text(report.reflectionQuestion),
          ],
          const SizedBox(height: 8),
          Text(
            widget.state.weeklyReportSaveStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  void _save() {
    ref.read(trainingMvpProvider.notifier).savePsychologyWeeklyReport(
          psychCheckIn: WeeklyPsychCheckIn(
            motivation: _motivation,
            perceivedStress: _stress,
            recoveryFeel: _recovery,
            weekNote: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          ),
        );
  }
}

class _TrainingDimensionRadar extends StatelessWidget {
  const _TrainingDimensionRadar({required this.exposure});

  final List<TrainingDimensionExposure> exposure;

  @override
  Widget build(BuildContext context) {
    final bool hasPlan = exposure
        .any((TrainingDimensionExposure item) => item.plannedSessions > 0);
    if (!hasPlan) return const Text('五维计划暴露仍在积累。');
    return Column(
      children: <Widget>[
        SizedBox(
          width: 190,
          height: 190,
          child: CustomPaint(
            painter: _TrainingDimensionRadarPainter(exposure),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final TrainingDimensionExposure item in exposure)
              ToneBadge(
                label:
                    '${item.dimension.label} ${item.completedSessions}/${item.plannedSessions}',
              ),
          ],
        ),
      ],
    );
  }
}

class _TrainingDimensionRadarPainter extends CustomPainter {
  const _TrainingDimensionRadarPainter(this.exposure);

  final List<TrainingDimensionExposure> exposure;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = math.min(size.width, size.height) * 0.38;
    final Paint grid = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final Paint fill = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;
    final Paint stroke = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final int count = TrainingDimension.values.length;

    List<Offset> points(double Function(int index) scaleFor) => <Offset>[
          for (int index = 0; index < count; index += 1)
            Offset(
              center.dx +
                  math.cos(-math.pi / 2 + index * math.pi * 2 / count) *
                      radius *
                      scaleFor(index),
              center.dy +
                  math.sin(-math.pi / 2 + index * math.pi * 2 / count) *
                      radius *
                      scaleFor(index),
            ),
        ];

    Path polygon(List<Offset> values) {
      final Path path = Path()..moveTo(values.first.dx, values.first.dy);
      for (final Offset point in values.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      return path..close();
    }

    for (final double scale in <double>[0.25, 0.5, 0.75, 1]) {
      canvas.drawPath(polygon(points((int _) => scale)), grid);
    }
    final Map<TrainingDimension, TrainingDimensionExposure> byDimension =
        <TrainingDimension, TrainingDimensionExposure>{
      for (final TrainingDimensionExposure item in exposure)
        item.dimension: item,
    };
    final List<Offset> actual = points((int index) {
      final TrainingDimensionExposure? item =
          byDimension[TrainingDimension.values[index]];
      if (item == null || item.plannedSessions <= 0) return 0;
      return (item.completedSessions / item.plannedSessions).clamp(0, 1);
    });
    canvas
      ..drawPath(polygon(actual), fill)
      ..drawPath(polygon(actual), stroke);
  }

  @override
  bool shouldRepaint(covariant _TrainingDimensionRadarPainter oldDelegate) {
    return oldDelegate.exposure != exposure;
  }
}

class _FivePointSelector extends StatelessWidget {
  const _FivePointSelector({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (int score = 1; score <= 5; score += 1)
                ChoiceChip(
                  label: Text('$score'),
                  selected: value == score,
                  onSelected: (bool selected) =>
                      onChanged(selected ? score : null),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class LocalReportRevisionCard extends StatefulWidget {
  const LocalReportRevisionCard({
    required this.reports,
    this.onGenerate,
    this.reportTitle = '本地确定性周报',
    this.emptyMessage,
    super.key,
  });

  final AsyncValue<List<ReportRevision>> reports;
  final Future<bool> Function()? onGenerate;
  final String reportTitle;
  final String? emptyMessage;

  @override
  State<LocalReportRevisionCard> createState() =>
      _LocalReportRevisionCardState();
}

class _LocalReportRevisionCardState extends State<LocalReportRevisionCard> {
  bool _isGenerating = false;
  String? _actionMessage;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.reportTitle,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              widget.reports.when(
                data: (List<ReportRevision> value) => ToneBadge(
                  label: value.isEmpty ? '数据积累中' : '修订 ${value.first.revision}',
                ),
                error: (Object error, StackTrace stackTrace) =>
                    const ToneBadge(label: '读取失败'),
                loading: () => const ToneBadge(label: '读取中'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          widget.reports.when(
            data: (List<ReportRevision> value) {
              if (value.isEmpty) {
                return Text(
                  widget.emptyMessage ?? '数据积累中：结构化指标尚未形成，旧周报仅作为兼容摘要展示。',
                );
              }
              final ReportRevision latest = value.first;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(latest.narrative),
                  const SizedBox(height: 8),
                  Text(
                    '${latest.algorithmVersion} · ${latest.metricIds.length} 项输入指标 · 历史修订 ${value.length} 份',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              );
            },
            error: (Object error, StackTrace stackTrace) => const Text(
              '本地报告读取失败，兼容摘要仍可查看；不会请求网络生成报告。',
            ),
            loading: () => const Text('正在读取本地报告修订。'),
          ),
          if (widget.onGenerate != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isGenerating ? null : _generate,
                icon: const Icon(Icons.add_chart_outlined),
                label: Text(_isGenerating ? '正在生成' : '生成新的本地修订'),
              ),
            ),
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
          const SizedBox(height: 8),
          Text(
            '叙事由设备内固定中文模板生成，不调用云端模型，也不覆盖历史修订。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    final Future<bool> Function()? action = widget.onGenerate;
    if (action == null) return;
    setState(() {
      _isGenerating = true;
      _actionMessage = null;
    });
    try {
      final bool generated = await action();
      if (!mounted) return;
      setState(() {
        _actionMessage = generated ? '新的本地报告修订已生成。' : '当前指标未变，已保留现有修订，未重复生成。';
      });
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _actionMessage = error.message.toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _actionMessage = '本地报告生成失败，指标和历史修订均未改变。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }
}

class _GrowthWeeklyReportCard extends StatelessWidget {
  const _GrowthWeeklyReportCard({
    required this.state,
    required this.growthState,
    required this.weekStart,
  });

  final TrainingMvpState state;
  final GrowthEvidenceState growthState;
  final DateTime weekStart;

  @override
  Widget build(BuildContext context) {
    final String currentWeekKey = growthDateKey(weekStart);
    WeeklyGrowthReport? report;
    for (final WeeklyGrowthReport item in growthState.weeklyReports) {
      if (item.weekKey == currentWeekKey) {
        report = item;
        break;
      }
    }
    final int effectiveTrainingDays = _effectiveTrainingDayCount(
      state.logs,
      weekStart,
    );

    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.query_stats_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '兼容训练执行摘要',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              ToneBadge(
                label: report == null
                    ? '数据积累中'
                    : report.isLocked
                        ? '旧报告只读'
                        : '兼容视图',
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (report == null)
            Text(
              '旧周报模型当前没有可展示记录；新的本地报告将以不可变修订保存。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            )
          else
            WeeklyGrowthCompatibilitySummary(
              report: report,
              effectiveTrainingDays: effectiveTrainingDays,
            ),
        ],
      ),
    );
  }
}

class WeeklyGrowthCompatibilitySummary extends StatelessWidget {
  const WeeklyGrowthCompatibilitySummary({
    required this.report,
    required this.effectiveTrainingDays,
    super.key,
  });

  final WeeklyGrowthReport report;
  final int effectiveTrainingDays;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: MetricPill(
                label: '训练执行指数',
                value: report.trainingExecutionIndexLabel,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricPill(
                label: '完成率',
                value: report.completionRateLabel,
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        InfoRow(
          label: '本周有效训练日',
          value: '$effectiveTrainingDays 天',
        ),
        InfoRow(
          label: '跑量',
          value: '${report.runningDistanceKm.toStringAsFixed(1)} km',
        ),
        InfoRow(label: '力量训练', value: '${report.strengthSessionCount} 次'),
        Text(
          '${report.recoverySummary} 已具备 ${report.availableIndexDimensions} 个兼容维度；少于 2 个维度时显示“数据不足”。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          '这是旧 WeeklyGrowthReport 的只读兼容摘要；新的本地报告使用不可变修订，不覆盖历史内容。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _LockedGrowthReportsCard extends StatelessWidget {
  const _LockedGrowthReportsCard({
    required this.growthState,
  });

  final GrowthEvidenceState growthState;

  @override
  Widget build(BuildContext context) {
    final List<WeeklyGrowthReport> reports = growthState.weeklyReports
        .where((WeeklyGrowthReport item) => item.isLocked)
        .take(3)
        .toList();
    if (reports.isEmpty) return const SizedBox.shrink();
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '旧周报兼容记录',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '以下记录只用于兼容查看。新的本地报告会创建修订，不会覆盖历史内容。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 10),
          for (final WeeklyGrowthReport report in reports) ...[
            Text(
              '${report.weekKey} · 训练执行指数 ${report.trainingExecutionIndexLabel}',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

int _effectiveTrainingDayCount(
  List<TrainingLog> logs,
  DateTime weekStart,
) {
  final DateTime weekEnd = weekStart.add(const Duration(days: 7));
  final Set<String> days = <String>{};
  for (final TrainingLog log in logs) {
    if (!log.isSessionRecord || log.normalizedCompletionPercentage < 50) {
      continue;
    }
    if (log.date.isBefore(weekStart) || !log.date.isBefore(weekEnd)) continue;
    days.add('${log.date.year}-${log.date.month}-${log.date.day}');
  }
  return days.length;
}
