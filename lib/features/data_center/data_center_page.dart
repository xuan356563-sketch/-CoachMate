import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/body_data_quality.dart';
import '../../data/models/body_metric.dart';
import '../../data/models/body_metric_export.dart';
import '../../data/models/body_metric_goal.dart';
import '../../data/models/body_metric_import.dart';
import '../../data/models/body_metric_revision.dart';
import '../../data/models/body_trend_insight.dart';
import '../../data/models/imported_workout.dart';
import 'application/body_metric_controller.dart';
import 'application/body_metric_export_controller.dart';
import '../dashboard/training_mvp_controller.dart';

class DataCenterPage extends ConsumerWidget {
  const DataCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final BodyMetricTrendWindow trendWindow =
        ref.watch(bodyMetricTrendWindowProvider);

    return TrainFlowPage(
      title: '身体数据',
      subtitle: '10 秒快录体重、静息心率、HRV、睡眠和疲劳，默认看 7 日趋势，也可切换 30/90 日窗口。',
      children: [
        _BodyMetricSummaryCard(state: state),
        _BodyDataQualityCard(report: state.bodyDataQualityReport),
        _BodyMetricRevisionCard(revisions: state.bodyMetricRevisions),
        _BodyMetricGoalCard(report: state.bodyMetricGoalReport),
        _QuickBodyMetricCard(state: state),
        _BodyMetricSnapshotCard(state: state),
        _BodyMetricCsvImportCard(state: state),
        _ActivityImportPreviewCard(state: state),
        _BodyMetricExportCard(state: state),
        SectionTitle(title: '${trendWindow.label}趋势'),
        _TrendWindowSelectorCard(selectedWindow: trendWindow),
        _TrendCard(state: state, window: trendWindow),
        _BodyTrendInsightCard(
          report: state.bodyTrendInsightReportForWindow(trendWindow),
        ),
        const SectionTitle(title: '最近记录'),
        for (final BodyMetric metric in state.recentBodyMetrics)
          _BodyMetricLogCard(metric: metric),
      ],
    );
  }
}

class _ActivityImportPreviewCard extends StatelessWidget {
  final TrainingMvpState state;

  const _ActivityImportPreviewCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final ImportedWorkout? workout = state.latestImportedWorkout;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'GPX / FIT 导入',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: workout == null ? '待导入' : workout.source.label),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            workout == null
                ? '导入手表训练文件，把配速、心率和爬升写入 workout_logs。'
                : '${workout.summary} · 已写入 workout_logs',
          ),
          const SizedBox(height: 8),
          Text(
            '当前先支持 GPX 文本和 FIT 摘要粘贴；真实文件选择器后续再接。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.activityImport),
              child: const Text('打开导入'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BodyMetricCsvImportCard extends ConsumerWidget {
  final TrainingMvpState state;

  const _BodyMetricCsvImportCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String importText = ref.watch(bodyMetricCsvImportTextProvider);
    final BodyMetricImportResult? latestResult =
        state.bodyMetricImportResults.isEmpty
            ? null
            : state.bodyMetricImportResults.first;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.table_view, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '身体 CSV 导入',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: latestResult == null ? '待导入' : latestResult.sourceLabel,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '粘贴 Apple 健康、手表或表格导出的身体数据 CSV，写入 body_metrics 后会刷新质量、趋势和指标目标。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              ref.read(bodyMetricCsvImportTextProvider.notifier).useSample();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('使用 CSV 样例'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey<String>(importText),
            initialValue: importText,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '身体数据 CSV',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (String value) {
              ref
                  .read(bodyMetricCsvImportTextProvider.notifier)
                  .setValue(value);
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                ref.read(bodyMetricControllerProvider.notifier).importCsv(
                      ref.read(bodyMetricCsvImportTextProvider),
                    );
              },
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('导入身体数据 CSV'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            state.bodyMetricImportStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          if (latestResult != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MetricPill(
                    label: '导入记录',
                    value: '${latestResult.importedCount} 条',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricPill(
                    label: '日期范围',
                    value: latestResult.dateRangeLabel,
                    color: AppColors.secondary,
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

class _BodyMetricSnapshotCard extends ConsumerWidget {
  final TrainingMvpState state;

  const _BodyMetricSnapshotCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String snapshotText = ref.watch(bodyMetricSnapshotTextProvider);
    final BodyMetric? pendingMetric =
        state.pendingBodyMetric?.source == BodyMetricSource.screenshot
            ? state.pendingBodyMetric
            : null;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.document_scanner_outlined,
                  color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '截图识别 Mock',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: pendingMetric == null ? '待识别' : '待确认'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '先粘贴体脂秤、手表或健康 App 截图中的文字，系统抽取指标；真实 OCR 和相册权限后续再接。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              ref.read(bodyMetricSnapshotTextProvider.notifier).useSample();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('使用截图样例'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey<String>(snapshotText),
            initialValue: snapshotText,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '截图文字',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (String value) {
              ref.read(bodyMetricSnapshotTextProvider.notifier).setValue(value);
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                ref
                    .read(bodyMetricControllerProvider.notifier)
                    .recognizeSnapshotText(
                      ref.read(bodyMetricSnapshotTextProvider),
                    );
              },
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('识别截图文字'),
            ),
          ),
          if (pendingMetric != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ref
                      .read(bodyMetricControllerProvider.notifier)
                      .confirmPendingMetric();
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('确认写入截图识别数据'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: MetricPill(
                    label: '体重',
                    value: '${pendingMetric.weightKg.toStringAsFixed(1)} kg',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricPill(
                    label: '静息心率',
                    value: '${pendingMetric.restingHeartRate} bpm',
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            state.bodyMetricSnapshotStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: pendingMetric == null
                      ? AppColors.textSecondary
                      : AppColors.warningDark,
                ),
          ),
        ],
      ),
    );
  }
}

class _BodyMetricExportCard extends ConsumerWidget {
  final TrainingMvpState state;

  const _BodyMetricExportCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String exportText = ref.watch(bodyMetricExportTextProvider);
    final String exportPackageStatus =
        ref.watch(bodyMetricExportPackageStatusProvider);

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '数据出口',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '本地版不上传身体数据。这里先提供 JSON/CSV 预览、本地导出包摘要和一键清除，后续再接系统保存、分享与数据库。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () {
                  final String exportText = state.bodyMetricJsonExport;
                  ref
                      .read(bodyMetricExportTextProvider.notifier)
                      .setValue(exportText);
                  ref
                      .read(bodyMetricExportControllerProvider.notifier)
                      .recordJsonExport(exportText);
                },
                icon: const Icon(Icons.data_object),
                label: const Text('导出 JSON'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final String exportText = state.bodyMetricCsvExport;
                  ref
                      .read(bodyMetricExportTextProvider.notifier)
                      .setValue(exportText);
                  ref
                      .read(bodyMetricExportControllerProvider.notifier)
                      .recordCsvExport(exportText);
                },
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('导出 CSV'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final String packageSummary =
                      state.bodyMetricExportPackageSummary;
                  ref
                      .read(bodyMetricExportPackageStatusProvider.notifier)
                      .setValue(packageSummary);
                  ref
                      .read(bodyMetricExportControllerProvider.notifier)
                      .recordPackageExport(packageSummary);
                },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('生成导出包'),
              ),
              OutlinedButton.icon(
                onPressed: state.bodyMetricExportRecords.isEmpty
                    ? null
                    : () async {
                        final bool? confirmed = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext dialogContext) {
                            return AlertDialog(
                              title: const Text('清除本地导出记录？'),
                              content: const Text(
                                '此操作会删除本地 JSON、CSV 和导出包摘要记录；不会删除身体数据或当前导出预览。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(true),
                                  child: const Text('确认清除'),
                                ),
                              ],
                            );
                          },
                        );
                        if (confirmed != true || !context.mounted) {
                          return;
                        }
                        ref
                            .read(bodyMetricExportControllerProvider.notifier)
                            .clear();
                      },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('清除导出记录'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(bodyMetricControllerProvider.notifier).clear();
                  ref
                      .read(bodyMetricExportTextProvider.notifier)
                      .setValue('身体数据已清除，当前记录 0 条。');
                  ref
                      .read(bodyMetricExportPackageStatusProvider.notifier)
                      .setValue('身体数据已清除，导出包需重新生成。');
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('清除身体数据'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BodyMetricExportHistoryCard(state: state),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primaryLightest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                exportPackageStatus,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                    ),
              ),
            ),
          ),
          if (exportText.isNotEmpty) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.grayLightest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  exportText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BodyMetricExportHistoryCard extends StatelessWidget {
  final TrainingMvpState state;

  const _BodyMetricExportHistoryCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final BodyMetricExportRecord? latestRecord =
        state.latestBodyMetricExportRecord;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.grayLightest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本地导出记录',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              state.bodyMetricExportStatusMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            if (latestRecord != null) ...[
              const SizedBox(height: 8),
              InfoRow(label: '最近格式', value: latestRecord.format.label),
              InfoRow(label: '文件名', value: latestRecord.fileName),
              InfoRow(
                label: '范围',
                value:
                    '${latestRecord.metricCount} 条 · ${latestRecord.sizeLabel}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BodyMetricSummaryCard extends StatelessWidget {
  final TrainingMvpState state;

  const _BodyMetricSummaryCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final BodyMetric? latestMetric = state.latestBodyMetric;

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
                  '今日身体状态',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (latestMetric != null)
                ToneBadge(label: latestMetric.source.label),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '体重 7 日均值',
                  value: '${state.averageWeight7d.toStringAsFixed(1)} kg',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '静息心率',
                  value: '${state.averageRestingHr7d.round()} bpm',
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: 'HRV 7 日均值',
                  value: '${state.averageHrv7d.round()} ms',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '睡眠 7 日均值',
                  value: '${state.averageSleep7d.toStringAsFixed(1)} h',
                  color: AppColors.warningDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            latestMetric == null
                ? '还没有身体数据，先完成一次快录。'
                : '${latestMetric.measuredDateLabel} · ${latestMetric.moodLabel} · ${latestMetric.note}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _BodyDataQualityCard extends StatelessWidget {
  final BodyDataQualityReport report;

  const _BodyDataQualityCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final Color toneColor = switch (report.statusLabel) {
      '需复核' => AppColors.danger,
      '可用但需确认' => AppColors.warningDark,
      _ => AppColors.primary,
    };

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined, color: toneColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '数据质量',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: report.statusLabel, color: toneColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '质量分',
                  value: report.qualityScoreLabel,
                  color: toneColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '记录数',
                  value: '${report.recordCount} 条',
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoRow(label: '覆盖率', value: report.coverageLabel),
          InfoRow(label: '来源口径', value: report.sourceLabel),
          InfoRow(label: '修订留痕', value: report.revisionPolicyLabel),
          const SizedBox(height: 8),
          for (final BodyDataQualityIssue issue in report.issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ToneBadge(
                    label: issue.severity.label,
                    color: _severityColor(issue.severity),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${issue.title}：${issue.description}'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _severityColor(BodyDataQualitySeverity severity) {
    switch (severity) {
      case BodyDataQualitySeverity.info:
        return AppColors.secondary;
      case BodyDataQualitySeverity.warning:
        return AppColors.warningDark;
      case BodyDataQualitySeverity.risk:
        return AppColors.danger;
    }
  }
}

class _BodyMetricRevisionCard extends StatelessWidget {
  final List<BodyMetricRevision> revisions;

  const _BodyMetricRevisionCard({required this.revisions});

  @override
  Widget build(BuildContext context) {
    final List<BodyMetricRevision> recentRevisions = revisions.take(3).toList();

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '最近修订',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: '${revisions.length} 条留痕'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            revisions.isEmpty
                ? '暂无修订记录；同日覆盖身体数据时会保留旧值、新值、来源和原因。'
                : '同日覆盖已保留旧值、新值、来源和原因，供预测对账和数据复核使用。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          if (recentRevisions.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final BodyMetricRevision revision in recentRevisions) ...[
              _BodyMetricRevisionLine(revision: revision),
              if (revision != recentRevisions.last) const Divider(height: 20),
            ],
          ],
        ],
      ),
    );
  }
}

class _BodyMetricRevisionLine extends StatelessWidget {
  final BodyMetricRevision revision;

  const _BodyMetricRevisionLine({required this.revision});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                revision.measuredDateLabel,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            ToneBadge(label: revision.revisedMetric.source.label),
          ],
        ),
        const SizedBox(height: 8),
        InfoRow(label: '体重', value: revision.weightChangeLabel),
        InfoRow(label: '静息心率', value: revision.restingHrChangeLabel),
        InfoRow(label: '来源', value: revision.sourceChangeLabel),
        InfoRow(label: '原因', value: revision.reason),
        Text(
          '修订时间：${revision.revisedAtLabel}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _BodyMetricGoalCard extends StatelessWidget {
  final BodyMetricGoalReport report;

  const _BodyMetricGoalCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final Color toneColor =
        report.hasProtectionWarning ? AppColors.warningDark : AppColors.primary;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_outlined, color: toneColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '指标目标',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: '${report.achievedCount}/${report.goals.length} 达成',
                color: toneColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            report.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          for (final BodyMetricGoal goal in report.goals) ...[
            _GoalProgressLine(goal: goal),
            if (goal != report.goals.last) const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          Text(
            report.protectionMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: toneColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _GoalProgressLine extends StatelessWidget {
  final BodyMetricGoal goal;

  const _GoalProgressLine({required this.goal});

  @override
  Widget build(BuildContext context) {
    final Color color = goal.needsProtection
        ? AppColors.warningDark
        : goal.achieved
            ? AppColors.success
            : AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                goal.title,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            ToneBadge(
              label: goal.achieved ? '已达成' : goal.type.label,
              color: color,
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: goal.progress,
          minHeight: 8,
          color: color,
          backgroundColor: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        const SizedBox(height: 8),
        InfoRow(label: '当前', value: goal.currentLabel),
        InfoRow(label: '目标', value: goal.targetLabel),
        InfoRow(label: '里程碑', value: goal.milestoneLabel),
        Text(
          goal.guidance,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _QuickBodyMetricCard extends ConsumerWidget {
  final TrainingMvpState state;

  const _QuickBodyMetricCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BodyMetric? currentMetric = state.latestBodyMetric;
    final double weight = ref.watch(bodyMetricWeightProvider);
    final int restingHr = ref.watch(bodyMetricRestingHrProvider);
    final int hrv = ref.watch(bodyMetricHrvProvider);
    final double sleep = ref.watch(bodyMetricSleepProvider);
    final int fatigue = ref.watch(bodyMetricFatigueProvider);
    final DateTime measuredAt = ref.watch(bodyMetricMeasuredAtProvider);

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '10 秒快录',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '默认预填上次值，日期可补录；异常值先确认再入库。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            '补录日期',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('今天'),
                selected: _isSameDate(measuredAt, DateTime.now()),
                onSelected: (_) {
                  ref.read(bodyMetricMeasuredAtProvider.notifier).useToday();
                },
              ),
              ChoiceChip(
                label: const Text('昨天补录'),
                selected: _isSameDate(
                  measuredAt,
                  DateTime.now().subtract(const Duration(days: 1)),
                ),
                onSelected: (_) {
                  ref
                      .read(bodyMetricMeasuredAtProvider.notifier)
                      .useYesterday();
                },
              ),
              ChoiceChip(
                label: const Text('前天补录'),
                selected: _isSameDate(
                  measuredAt,
                  DateTime.now().subtract(const Duration(days: 2)),
                ),
                onSelected: (_) {
                  ref
                      .read(bodyMetricMeasuredAtProvider.notifier)
                      .useTwoDaysAgo();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DoubleSliderLine(
            label: '体重',
            value: weight,
            min: 60,
            max: 90,
            divisions: 300,
            suffix: 'kg',
            onChanged: (double value) {
              ref.read(bodyMetricWeightProvider.notifier).setValue(value);
            },
          ),
          _IntSliderLine(
            label: '静息心率',
            value: restingHr,
            min: 45,
            max: 85,
            suffix: 'bpm',
            onChanged: (int value) {
              ref.read(bodyMetricRestingHrProvider.notifier).setValue(value);
            },
          ),
          _IntSliderLine(
            label: 'HRV',
            value: hrv,
            min: 25,
            max: 85,
            suffix: 'ms',
            onChanged: (int value) {
              ref.read(bodyMetricHrvProvider.notifier).setValue(value);
            },
          ),
          _DoubleSliderLine(
            label: '睡眠',
            value: sleep,
            min: 4,
            max: 9,
            divisions: 50,
            suffix: 'h',
            onChanged: (double value) {
              ref.read(bodyMetricSleepProvider.notifier).setValue(value);
            },
          ),
          _IntSliderLine(
            label: '疲劳',
            value: fatigue,
            min: 1,
            max: 10,
            suffix: '/10',
            onChanged: (int value) {
              ref.read(bodyMetricFatigueProvider.notifier).setValue(value);
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                ref
                    .read(bodyMetricControllerProvider.notifier)
                    .saveManualMetric(
                      weightKg: weight,
                      restingHeartRate: restingHr,
                      hrvMs: hrv,
                      sleepHours: sleep,
                      fatigueLevel: fatigue,
                      measuredAt: measuredAt,
                    );
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存身体数据'),
            ),
          ),
          if (state.pendingBodyMetric?.source == BodyMetricSource.manual) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ref
                      .read(bodyMetricControllerProvider.notifier)
                      .confirmPendingMetric();
                },
                icon: const Icon(Icons.warning_amber_outlined),
                label: const Text('确认保存异常值'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            state.bodyMetricManualStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: state.pendingBodyMetric == null
                      ? AppColors.textSecondary
                      : AppColors.warningDark,
                ),
          ),
          if (currentMetric != null) ...[
            const SizedBox(height: 8),
            Text(
              '上次记录：${currentMetric.measuredDateLabel} · ${currentMetric.weightKg.toStringAsFixed(1)} kg',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final TrainingMvpState state;
  final BodyMetricTrendWindow window;

  const _TrendCard({
    required this.state,
    required this.window,
  });

  @override
  Widget build(BuildContext context) {
    final List<BodyMetric> windowMetrics = state.bodyMetricsForWindow(window);
    final BodyMetric? latestMetric =
        windowMetrics.isEmpty ? null : windowMetrics.first;
    if (latestMetric == null) {
      return const TrainFlowCard(child: Text('暂无趋势数据。'));
    }
    final List<_BodyMetricTrendPoint> trendPoints = windowMetrics.reversed
        .map(
          (BodyMetric metric) => _BodyMetricTrendPoint(
            dateLabel: metric.measuredDateLabel.substring(5),
            weightKg: metric.weightKg,
            hrvMs: metric.hrvMs,
            fatigueLevel: metric.fatigueLevel,
          ),
        )
        .toList();

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BodyMetricTrendChart(
            points: trendPoints,
            windowLabel: window.label,
          ),
          const SizedBox(height: 16),
          _TrendRow(
            label: '体重',
            latest: '${latestMetric.weightKg.toStringAsFixed(1)} kg',
            average:
                '${state.averageWeightForWindow(window).toStringAsFixed(1)} kg',
            windowLabel: window.label,
            note: '看 ${window.label}均值，不放大单日波动',
          ),
          _TrendRow(
            label: '静息心率',
            latest: '${latestMetric.restingHeartRate} bpm',
            average: '${state.averageRestingHrForWindow(window).round()} bpm',
            windowLabel: window.label,
            note: '偏离均值过多时需要复核',
          ),
          _TrendRow(
            label: 'HRV',
            latest: '${latestMetric.hrvMs} ms',
            average: '${state.averageHrvForWindow(window).round()} ms',
            windowLabel: window.label,
            note: '连续下降时优先恢复',
          ),
          _TrendRow(
            label: '疲劳',
            latest: '${latestMetric.fatigueLevel}/10',
            average:
                '${state.averageFatigueForWindow(window).toStringAsFixed(1)}/10',
            windowLabel: window.label,
            note: '进入今日准备度计算',
          ),
        ],
      ),
    );
  }
}

class _BodyMetricTrendPoint {
  final String dateLabel;
  final double weightKg;
  final int hrvMs;
  final int fatigueLevel;

  const _BodyMetricTrendPoint({
    required this.dateLabel,
    required this.weightKg,
    required this.hrvMs,
    required this.fatigueLevel,
  });
}

class _BodyMetricTrendChart extends StatelessWidget {
  final List<_BodyMetricTrendPoint> points;
  final String windowLabel;

  const _BodyMetricTrendChart({
    required this.points,
    required this.windowLabel,
  });

  @override
  Widget build(BuildContext context) {
    final String rangeLabel = points.length < 2
        ? points.first.dateLabel
        : '${points.first.dateLabel} - ${points.last.dateLabel}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.show_chart, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$windowLabel趋势图表',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            ToneBadge(label: '${points.length} 条'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '真实窗口数据 $rangeLabel，体重看下降方向，HRV 看恢复弹性，疲劳看风险抬升。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          width: double.infinity,
          child: CustomPaint(
            painter: _BodyMetricTrendChartPainter(points: points),
          ),
        ),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _TrendLegendDot(label: '体重线', color: AppColors.primary),
            _TrendLegendDot(label: 'HRV线', color: AppColors.success),
            _TrendLegendDot(label: '疲劳线', color: AppColors.warningDark),
          ],
        ),
      ],
    );
  }
}

class _TrendLegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _TrendLegendDot({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox(width: 8, height: 8),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _BodyMetricTrendChartPainter extends CustomPainter {
  final List<_BodyMetricTrendPoint> points;

  const _BodyMetricTrendChartPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect chartRect = Rect.fromLTWH(0, 4, size.width, size.height - 28);
    final Paint gridPaint = Paint()
      ..color = AppColors.grayLightish.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    final Paint axisPaint = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.25)
      ..strokeWidth = 1;

    for (int i = 0; i <= 3; i += 1) {
      final double y = chartRect.top + chartRect.height * i / 3;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }
    canvas.drawLine(chartRect.bottomLeft, chartRect.bottomRight, axisPaint);

    _drawSeries(
      canvas: canvas,
      chartRect: chartRect,
      values: points.map((_BodyMetricTrendPoint point) => point.weightKg),
      color: AppColors.primary,
    );
    _drawSeries(
      canvas: canvas,
      chartRect: chartRect,
      values:
          points.map((_BodyMetricTrendPoint point) => point.hrvMs.toDouble()),
      color: AppColors.success,
    );
    _drawSeries(
      canvas: canvas,
      chartRect: chartRect,
      values: points
          .map((_BodyMetricTrendPoint point) => point.fatigueLevel.toDouble()),
      color: AppColors.warningDark,
    );

    _drawDateLabel(
      canvas: canvas,
      offset: Offset(chartRect.left, size.height - 16),
      label: points.first.dateLabel,
      textAlign: TextAlign.left,
    );
    _drawDateLabel(
      canvas: canvas,
      offset: Offset(chartRect.right, size.height - 16),
      label: points.last.dateLabel,
      textAlign: TextAlign.right,
    );
  }

  void _drawSeries({
    required Canvas canvas,
    required Rect chartRect,
    required Iterable<double> values,
    required Color color,
  }) {
    final List<double> series = values.toList();
    if (series.isEmpty) {
      return;
    }
    final double minValue = series.reduce(math.min);
    final double maxValue = series.reduce(math.max);
    final double range = math.max(maxValue - minValue, 1);
    final Paint linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.4;
    final Paint dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final Path path = Path();

    for (int index = 0; index < series.length; index += 1) {
      final double x = series.length == 1
          ? chartRect.center.dx
          : chartRect.left + chartRect.width * index / (series.length - 1);
      final double normalized = (series[index] - minValue) / range;
      final double y = chartRect.bottom - normalized * chartRect.height;
      final Offset point = Offset(x, y);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawCircle(point, 3.5, dotPaint);
    }
    canvas.drawPath(path, linePaint);
  }

  void _drawDateLabel({
    required Canvas canvas,
    required Offset offset,
    required String label,
    required TextAlign textAlign,
  }) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
    )..layout();
    final double dx = textAlign == TextAlign.right
        ? offset.dx - textPainter.width
        : offset.dx;
    textPainter.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _BodyMetricTrendChartPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

class _TrendWindowSelectorCard extends ConsumerWidget {
  final BodyMetricTrendWindow selectedWindow;

  const _TrendWindowSelectorCard({required this.selectedWindow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '趋势窗口',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: selectedWindow.label),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final BodyMetricTrendWindow window
                  in BodyMetricTrendWindow.values)
                ChoiceChip(
                  label: Text(window.label),
                  selected: selectedWindow == window,
                  onSelected: (_) {
                    ref
                        .read(bodyMetricTrendWindowProvider.notifier)
                        .setWindow(window);
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '7 日看短期波动，30/90 日看更稳定的体重、恢复和疲劳方向。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _TrendRow extends StatelessWidget {
  final String label;
  final String latest;
  final String average;
  final String windowLabel;
  final String note;

  const _TrendRow({
    required this.label,
    required this.latest,
    required this.average,
    required this.windowLabel,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '最新 $latest · $windowLabel均值 $average',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

class _BodyTrendInsightCard extends StatelessWidget {
  final BodyTrendInsightReport report;

  const _BodyTrendInsightCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '趋势洞察',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: report.windowLabel),
            ],
          ),
          const SizedBox(height: 12),
          InfoRow(label: '体重趋势', value: report.weightTrendLabel),
          Text(
            report.weightTrendDetail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            '叠加视图',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final BodyTrendOverlay overlay in report.overlays)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('· ${overlay.title}：${overlay.description}'),
            ),
          const SizedBox(height: 8),
          InfoRow(label: '里程碑', value: report.milestoneLabel),
          Text(
            report.milestoneDetail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          InfoRow(label: '减脂保护', value: report.fatLossProtectionLabel),
          Text(
            report.fatLossProtectionDetail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _BodyMetricLogCard extends StatelessWidget {
  final BodyMetric metric;

  const _BodyMetricLogCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  metric.measuredDateLabel,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: metric.moodLabel),
            ],
          ),
          const SizedBox(height: 8),
          InfoRow(
              label: '体重', value: '${metric.weightKg.toStringAsFixed(1)} kg'),
          InfoRow(
              label: '体脂',
              value: '${metric.bodyFatPercentage.toStringAsFixed(1)}%'),
          InfoRow(label: '静息心率', value: '${metric.restingHeartRate} bpm'),
          InfoRow(label: 'HRV', value: '${metric.hrvMs} ms'),
          InfoRow(
              label: '睡眠', value: '${metric.sleepHours.toStringAsFixed(1)} h'),
          InfoRow(label: '疲劳', value: '${metric.fatigueLevel}/10'),
          Text(
            '${metric.source.label} · ${metric.note}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _DoubleSliderLine extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  const _DoubleSliderLine({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final String formattedValue = value.toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label：$formattedValue $suffix'),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          label: formattedValue,
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _IntSliderLine extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  const _IntSliderLine({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label：$value $suffix'),
        Slider(
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: '$value',
          value: value.toDouble(),
          onChanged: (double nextValue) {
            onChanged(nextValue.round());
          },
        ),
      ],
    );
  }
}

bool _isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
