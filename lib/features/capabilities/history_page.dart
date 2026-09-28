import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/generated_training_plan.dart';
import '../../data/models/exercise_training_profile.dart';
import '../../data/models/growth_evidence.dart';
import '../../data/models/training_log.dart';
import '../../data/models/training_metrics.dart';
import '../../data/models/training_plan.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/weekly_report.dart';
import '../../data/models/workout_day.dart';
import '../../features/profile/application/health_sync_controller.dart';
import '../../plugins/history/core_history.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  static const int _growthPageSize = 30;

  DateTime _selectedDate = DateTime.now();
  Future<_AsyncHistory>? _asyncHistory;
  final List<WeeklyGrowthReport> _additionalGrowthReports =
      <WeeklyGrowthReport>[];
  bool? _hasMoreGrowthReports;
  bool _isLoadingMoreGrowthReports = false;
  String? _growthPageError;
  int _growthRequestEpoch = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _asyncHistory ??= _loadAsyncHistory();
  }

  Future<_AsyncHistory> _loadAsyncHistory() async {
    final CoreHistory history = ref.read(coreHistoryProvider);
    final String athleteProfileId = ref.read(healthSyncAthleteIdProvider);
    final DateTime weekStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day - (_selectedDate.weekday - 1),
    );
    final DateTime monthStart =
        DateTime(_selectedDate.year, _selectedDate.month);
    final List<dynamic> values = await Future.wait<dynamic>(<Future<dynamic>>[
      history.listGrowthReports(
        athleteProfileId: athleteProfileId,
        limit: _growthPageSize,
        offset: 0,
      ),
      history.listReportRevisions(
        athleteProfileId: athleteProfileId,
        period: MetricPeriod.week,
        periodStart: weekStart,
      ),
      history.listReportRevisions(
        athleteProfileId: athleteProfileId,
        period: MetricPeriod.month,
        periodStart: monthStart,
      ),
    ]);
    return _AsyncHistory(
      growthReports: values[0] as List<WeeklyGrowthReport>,
      weeklyRevisions: values[1] as List<ReportRevision>,
      monthlyRevisions: values[2] as List<ReportRevision>,
    );
  }

  @override
  Widget build(BuildContext context) {
    final CoreHistory history = ref.watch(coreHistoryProvider);
    final GeneratedTrainingPlanHistory planHistory = history.getPlanHistory();
    final TrainingPlan? legacyPlan = history.getLegacyPlan();
    final List<TrainingLog> logs = history.listLogs();
    final List<WeeklyReport> weeklyReports = history.listWeeklyReports();
    final bool includeLegacyPlan = legacyPlan != null &&
        !planHistory.versions.any(
          (GeneratedPlanVersion version) => version.plan.id == legacyPlan.id,
        );

    return TrainFlowPage(
      title: '历史记录',
      subtitle: '这里仅读取已经保存的内容，不会生成计划、补算报告或修改记录。',
      eyebrow: '核心历史',
      leading: const TrainMateBackButton(fallbackRoute: AppRoutes.profile),
      children: <Widget>[
        TextButton.icon(onPressed: () => context.push('/history/assessments'), icon: const Icon(Icons.fact_check_outlined), label: const Text('基础评估历史')),
        TextButton.icon(onPressed: () => context.push('/history/running'),
          icon: const Icon(Icons.directions_run), label: const Text('跑姿报告历史')),
        for (final adjustment in history.listCourseAdjustments())
          TrainFlowCard(key: ValueKey('history-course-${adjustment.id}'), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('已确认课程调整 · ${adjustment.workoutTitle}'),
              Text('${adjustment.originalEstimatedMinutes} → ${adjustment.adjustedEstimatedMinutes} 分钟 · ${adjustment.adjustedIntensity}'),
              Text(adjustment.workoutSnapshot!.mainSets.join('；')),
              Text('${adjustment.adjustedAtLabel} · ${adjustment.reason}'),
              const Text('这是当时确认的课程快照，当前计划变化后不自动沿用。'),
            ])),
        const SectionTitle(title: '已保存计划版本'),
        if (planHistory.versions.isEmpty && !includeLegacyPlan)
          const _EmptyHistoryCard(message: '还没有已保存的计划版本。'),
        for (final GeneratedPlanVersion version
            in planHistory.versions.reversed)
          TrainFlowCard(
            key: ValueKey<String>('history-plan-${version.id}'),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(version.plan.title),
              subtitle: Text(
                '${_date(version.activatedAt)} · ${version.plan.sportType.label} · ${version.plan.workoutDays.length} 个训练日',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.historyPlan(version.id)),
            ),
          ),
        if (includeLegacyPlan) _LegacyPlanCard(plan: legacyPlan),
        const SectionTitle(title: '训练记录'),
        if (logs.isEmpty)
          const _EmptyHistoryCard(message: '还没有训练记录。')
        else
          for (final TrainingLog log in logs.reversed)
            _TrainingLogCard(log: log),
        const SectionTitle(title: '兼容周报'),
        if (weeklyReports.isEmpty)
          const _EmptyHistoryCard(message: '还没有兼容周报。')
        else
          for (final WeeklyReport report in weeklyReports)
            _WeeklyReportCard(report: report),
        const SectionTitle(title: '成长与结构化报告'),
        TrainFlowCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.date_range_outlined),
            title: const Text('选择要查看的周/月'),
            subtitle: Text(_date(_selectedDate)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickDate,
          ),
        ),
        FutureBuilder<_AsyncHistory>(
          future: _asyncHistory,
          builder:
              (BuildContext context, AsyncSnapshot<_AsyncHistory> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const TrainFlowCard(
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return TrainFlowCard(
                tone: TrainFlowCardTone.peach,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_historyError(snapshot.error!)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('重新读取'),
                    ),
                  ],
                ),
              );
            }
            final _AsyncHistory value = snapshot.requireData;
            final List<WeeklyGrowthReport> growthReports = <WeeklyGrowthReport>[
              ...value.growthReports,
              ..._additionalGrowthReports,
            ];
            final bool hasMoreGrowthReports = _hasMoreGrowthReports ??
                value.growthReports.length == _growthPageSize;
            return Column(
              children: <Widget>[
                if (growthReports.isEmpty)
                  const _EmptyHistoryCard(message: '还没有成长周报。')
                else
                  for (final WeeklyGrowthReport report in growthReports)
                    _GrowthReportCard(report: report),
                if (_growthPageError != null)
                  TrainFlowCard(
                    tone: TrainFlowCardTone.peach,
                    child: Text(_growthPageError!),
                  ),
                if (hasMoreGrowthReports)
                  TextButton(
                    key: const ValueKey<String>('history-growth-load-more'),
                    onPressed: _isLoadingMoreGrowthReports
                        ? null
                        : () => _loadMoreGrowthReports(value),
                    child: Text(
                        _isLoadingMoreGrowthReports ? '正在读取更多记录…' : '加载更多成长周报'),
                  ),
                if (value.weeklyRevisions.isEmpty &&
                    value.monthlyRevisions.isEmpty)
                  const _EmptyHistoryCard(message: '所选日期没有结构化周报或月报修订。'),
                for (final ReportRevision revision in <ReportRevision>[
                  ...value.weeklyRevisions,
                  ...value.monthlyRevisions,
                ])
                  _ReportRevisionCard(revision: revision),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '选择历史报告日期',
      cancelText: '取消',
      confirmText: '查看',
    );
    if (selected == null) return;
    setState(() {
      _selectedDate = selected;
      _resetAsyncHistory();
    });
  }

  Future<void> _loadMoreGrowthReports(_AsyncHistory firstPage) async {
    if (_isLoadingMoreGrowthReports) return;
    final int requestEpoch = ++_growthRequestEpoch;
    final CoreHistory history = ref.read(coreHistoryProvider);
    final String athleteProfileId = ref.read(healthSyncAthleteIdProvider);
    setState(() {
      _isLoadingMoreGrowthReports = true;
      _growthPageError = null;
    });
    try {
      final List<WeeklyGrowthReport> page = await history.listGrowthReports(
        athleteProfileId: athleteProfileId,
        limit: _growthPageSize,
        offset:
            firstPage.growthReports.length + _additionalGrowthReports.length,
      );
      if (!mounted || requestEpoch != _growthRequestEpoch) return;
      setState(() {
        _additionalGrowthReports.addAll(page);
        _hasMoreGrowthReports = page.length == _growthPageSize;
        _isLoadingMoreGrowthReports = false;
      });
    } catch (error) {
      if (!mounted || requestEpoch != _growthRequestEpoch) return;
      setState(() {
        _growthPageError = _historyError(error);
        _isLoadingMoreGrowthReports = false;
      });
    }
  }

  void _resetAsyncHistory() {
    _growthRequestEpoch++;
    _additionalGrowthReports.clear();
    _hasMoreGrowthReports = null;
    _isLoadingMoreGrowthReports = false;
    _growthPageError = null;
    _asyncHistory = _loadAsyncHistory();
  }

  void _reload() => setState(_resetAsyncHistory);
}

class HistoryPlanDetailPage extends ConsumerWidget {
  const HistoryPlanDetailPage({super.key, required this.versionId});

  final String versionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GeneratedPlanVersion? version =
        ref.watch(coreHistoryProvider).getPlanVersion(versionId);
    if (version == null) {
      return TrainFlowPage(
        title: '计划版本不可用',
        subtitle: '该计划版本可能来自另一个账号数据域，请返回历史记录重新选择。',
        leading: const TrainMateBackButton(fallbackRoute: AppRoutes.history),
        children: <Widget>[
          FilledButton(
            onPressed: () => context.go(AppRoutes.history),
            child: const Text('返回历史记录'),
          ),
        ],
      );
    }
    final TrainingPlan plan = version.plan;
    return TrainFlowPage(
      title: plan.title,
      subtitle:
          '${plan.sportType.label} · ${plan.durationWeeks} 周 · ${_date(version.activatedAt)}',
      eyebrow: '已保存计划版本',
      leading: const TrainMateBackButton(fallbackRoute: AppRoutes.history),
      children: <Widget>[
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(plan.description),
              const SizedBox(height: 8),
              Text('目标：${plan.goal}'),
              Text('周结构：${plan.weeklyStructure}'),
              const SizedBox(height: 8),
              const Text('只读版本，不能从这里激活、回退或开始训练。'),
            ],
          ),
        ),
        for (final WorkoutDay workout in plan.workoutDays)
          _WorkoutSnapshotCard(workout: workout),
      ],
    );
  }
}

class _WorkoutSnapshotCard extends StatelessWidget {
  const _WorkoutSnapshotCard({required this.workout});
  final WorkoutDay workout;

  @override
  Widget build(BuildContext context) => TrainFlowCard(
        key: ValueKey<String>('history-workout-${workout.id}'),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(workout.title),
          subtitle: Text(
            '第 ${workout.weekIndex + 1} 周 · ${workout.estimatedMinutes} 分钟 · ${workout.intensity}',
          ),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            for (final String item in <String>[
              ...workout.warmupSteps,
              ...workout.mainSets,
              ...workout.accessoryWork,
              ...workout.cooldownSteps,
            ])
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.circle, size: 7),
                title: Text(item),
              ),
            if (workout.coachNotes.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('教练提示：${workout.coachNotes}'),
              ),
          ],
        ),
      );
}

class _TrainingLogCard extends StatelessWidget {
  const _TrainingLogCard({required this.log});
  final TrainingLog log;

  @override
  Widget build(BuildContext context) => TrainFlowCard(
        key: ValueKey<String>('history-log-${log.id}'),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(log.kind == TrainingLogKind.playerStep
              ? (log.completed ? '已完成跟练步骤' : '未完成跟练步骤')
              : (log.completed ? '已完成训练' : '未完成训练')),
          subtitle: Text('${_date(log.date)} · RPE ${log.rpe}'),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(log.sessionReviewSummary),
            ),
            if (log.userNote?.isNotEmpty == true)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('备注：${log.userNote}'),
              ),
            if (log.painNote?.isNotEmpty == true)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('疼痛记录：${log.painNote}'),
              ),
          ],
        ),
      );
}

class _WeeklyReportCard extends StatelessWidget {
  const _WeeklyReportCard({required this.report});
  final WeeklyReport report;

  String get _savedDirection {
    final selectedId = report.selectedOptionId;
    if (selectedId == null || selectedId.isEmpty) return '未保存下周方向选择。';
    final selected = report.options.where((option) => option.id == selectedId).toList();
    if (selected.length != 1 || selected.single.label.trim().isEmpty) {
      return '原方向选择无法匹配保存的选项，未自动替换。';
    }
    return '已保存方向：${selected.single.label}';
  }

  @override
  Widget build(BuildContext context) => TrainFlowCard(
        key: ValueKey<String>('history-weekly-${report.id}'),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(report.weekLabel),
          subtitle: Text(
              '完成率 ${report.completionRateLabel} · ${report.loadTrendLabel}'),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('生成日期：${report.generatedDateLabel}'),
                const Text('以下为保存时的报告，只读展示，不重新计算或应用计划。'),
                const SizedBox(height: 12),
                const Text('原报告摘要', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(report.decisionReview),
                Text(report.recoverySummary),
                if (report.goalSummary.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('保存时的目标', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(report.goalSummary),
                ],
                const SizedBox(height: 12),
                const Text('事实依据', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(report.realityObservation.isEmpty
                    ? '此报告未保存事实依据，不重新推断。' : report.realityObservation),
                for (final exposure in report.dimensionExposure)
                  Text('${exposure.dimension.label}：实际记录 ${exposure.completedSessions} 次，计划 ${exposure.plannedSessions} 次'),
                const SizedBox(height: 12),
                const Text('手动复盘', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(report.recoveryEvidenceAvailable == true
                    ? '保存时状态标签：${report.psychRiskLabel}'
                    : '状态依据未记录或不足，无法评估。'),
                if (report.psychCheckIn case final checkIn?) ...[
                  Text('训练动机：${checkIn.motivation == null ? '未填写' : '${checkIn.motivation}/5'}'),
                  Text('感知压力：${checkIn.perceivedStress == null ? '未填写' : '${checkIn.perceivedStress}/5'}'),
                  Text('恢复感：${checkIn.recoveryFeel == null ? '未填写' : '${checkIn.recoveryFeel}/5'}'),
                  if (checkIn.weekNote?.isNotEmpty == true)
                    Text('备注：${checkIn.weekNote}'),
                ] else
                  const Text('此报告未保存手动复盘。'),
                if (report.highlights.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('原报告亮点', style: TextStyle(fontWeight: FontWeight.w600)),
                  for (final item in report.highlights) Text(item),
                ],
                const SizedBox(height: 12),
                const Text('下周方向记录', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final item in report.nextWeekFocus) Text(item),
                for (final option in report.options) Text('当时可选：${option.label}'),
                Text(_savedDirection),
                const Text('方向选择仅为复盘记录，不表示计划已调整。'),
                if (report.reflectionQuestion.isNotEmpty) Text(report.reflectionQuestion),
              ],
            ),
          ],
        ),
      );
}

class _GrowthReportCard extends StatelessWidget {
  const _GrowthReportCard({required this.report});
  final WeeklyGrowthReport report;

  @override
  Widget build(BuildContext context) => TrainFlowCard(
        key: ValueKey<String>('history-growth-${report.id}'),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('成长周报 · ${_date(report.weekStartsOn)}'),
          subtitle: Text(
            '完成率 ${report.completionRateLabel} · 执行指标 ${report.trainingExecutionIndexLabel}\n${report.recoverySummary}',
          ),
          isThreeLine: true,
        ),
      );
}

class _ReportRevisionCard extends StatelessWidget {
  const _ReportRevisionCard({required this.revision});
  final ReportRevision revision;

  @override
  Widget build(BuildContext context) => TrainFlowCard(
        key: ValueKey<String>('history-revision-${revision.id}'),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
            '${revision.period == MetricPeriod.month ? '月报' : '周报'}修订 ${revision.revision}',
          ),
          subtitle: Text(_date(revision.periodStart)),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            Align(
                alignment: Alignment.centerLeft,
                child: Text(revision.narrative)),
          ],
        ),
      );
}

class _LegacyPlanCard extends StatelessWidget {
  const _LegacyPlanCard({required this.plan});
  final TrainingPlan plan;

  @override
  Widget build(BuildContext context) => TrainFlowCard(
        key: ValueKey<String>('history-legacy-plan-${plan.id}'),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(plan.title),
          subtitle: Text(
              '兼容计划 · ${plan.sportType.label} · ${plan.workoutDays.length} 个训练日'),
          children: <Widget>[
            for (final WorkoutDay workout in plan.workoutDays)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(workout.title),
                subtitle: Text(
                    '${workout.estimatedMinutes} 分钟 · ${workout.intensity}'),
              ),
          ],
        ),
      );
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => TrainFlowCard(child: Text(message));
}

class _AsyncHistory {
  const _AsyncHistory({
    required this.growthReports,
    required this.weeklyRevisions,
    required this.monthlyRevisions,
  });

  final List<WeeklyGrowthReport> growthReports;
  final List<ReportRevision> weeklyRevisions;
  final List<ReportRevision> monthlyRevisions;
}

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _historyError(Object error) {
  if (error is StateError) return error.message.toString();
  return '历史记录读取失败，请重试。';
}
