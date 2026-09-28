import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_brand.dart';
import '../../core/constants/app_colors.dart';
import '../../core/design_system/trainmate_primitives.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainmate_showcase_widgets.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/body_data_quality.dart';
import '../../data/models/body_metric.dart';
import '../../services/body_metric_display_service.dart';
import '../../data/models/body_metric_export.dart';
import '../../data/models/body_metric_goal.dart';
import '../../data/models/body_metric_import.dart';
import '../../data/models/body_metric_revision.dart';
import '../../data/models/body_trend_insight.dart';
import '../../data/models/imported_workout.dart';
import '../../plugins/application/plugin_runtime_provider.dart';
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
      layout: TrainFlowPageLayout.report,
      subtitle: '10 秒快录体重、静息心率、HRV、睡眠和疲劳，默认看 7 日趋势，也可切换 30/90 日窗口。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.profile,
      ),
      artwork: const TrainMateIllustration(
        assetPath: 'assets/images/trainmate_data_shield.png',
        semanticLabel: '身体数据授权与保护插画',
        fallback: TrainMateActionCharacter(
          action: TrainMateAction.treePoseBalance,
          backgroundColor: AppColors.primary,
        ),
      ),
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
        const SectionTitle(title: '已保存身体记录'),
        const Text('按记录日期展示，包含历史记录。缺失、沿用或不可用字段显示“无有效记录”；'
            '原始保留值与来源标记可在 JSON 中查看。保存时标签不代表当前状态。'),
        for (final BodyMetric metric in state.bodyMetrics)
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
              const Icon(Icons.route, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'GPX / FIT 导入',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
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
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.activityImport),
              child: const Text('打开导入'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BodyMetricCsvImportCard extends ConsumerStatefulWidget {
  final TrainingMvpState state;

  const _BodyMetricCsvImportCard({required this.state});

  @override
  ConsumerState<_BodyMetricCsvImportCard> createState() =>
      _BodyMetricCsvImportCardState();
}

class _BodyMetricCsvImportCardState extends ConsumerState<_BodyMetricCsvImportCard> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
        text: ref.read(bodyMetricCsvImportTextProvider));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    ref.listen<String>(bodyMetricCsvImportTextProvider, (_, next) {
      // 输入留空后需要连续录入；文本变化不能重新创建输入控件。
      if (_textController.text != next) {
        _textController.value = TextEditingValue(
            text: next, selection: TextSelection.collapsed(offset: next.length));
      }
    });
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
              const Icon(Icons.table_view, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '身体 CSV 导入',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
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
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              _showBodyMetricExample(context, 'CSV 格式样例',
                  sampleBodyMetricCsvImportText);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('查看 CSV 格式样例'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _textController,
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
              onPressed: ref.watch(bodyMetricControllerProvider).isSavingBodyMetrics
                  ? null : () async {
                await _runDataCenterAction(
                  context,
                  () =>
                      ref.read(bodyMetricControllerProvider.notifier).importCsv(
                            ref.read(bodyMetricCsvImportTextProvider),
                          ),
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
                  color: TrainFlowTokens.darkTrainingMuted,
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
                    color: TrainFlowTokens.accent,
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

class _BodyMetricSnapshotCard extends ConsumerStatefulWidget {
  final TrainingMvpState state;

  const _BodyMetricSnapshotCard({required this.state});

  @override
  ConsumerState<_BodyMetricSnapshotCard> createState() =>
      _BodyMetricSnapshotCardState();
}

class _BodyMetricSnapshotCardState extends ConsumerState<_BodyMetricSnapshotCard> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
        text: ref.read(bodyMetricSnapshotTextProvider));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    ref.listen<String>(bodyMetricSnapshotTextProvider, (_, next) {
      // 用户输入保持焦点与光标；只有样例或外部恢复改变文本时才同步。
      if (_textController.text != next) {
        _textController.value = TextEditingValue(
            text: next, selection: TextSelection.collapsed(offset: next.length));
      }
    });
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
                  color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '截图识别 Mock',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: pendingMetric == null ? '待识别' : '待确认'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '先粘贴体脂秤、手表或健康 App 截图中的文字，系统抽取指标；真实 OCR 和相册权限后续再接。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              _showBodyMetricExample(context, '截图文字样例',
                  sampleBodyMetricSnapshotText);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('查看截图文字样例'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _textController,
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
                try {
                  ref
                      .read(bodyMetricControllerProvider.notifier)
                      .recognizeSnapshotText(
                        ref.read(bodyMetricSnapshotTextProvider),
                      );
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('身体数据操作失败：$error')),
                  );
                }
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
                onPressed: ref.watch(bodyMetricControllerProvider).isSavingBodyMetrics
                    ? null : () async {
                  await _runDataCenterAction(
                    context,
                    () => ref
                        .read(bodyMetricControllerProvider.notifier)
                        .confirmPendingMetric(),
                  );
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
                    color: TrainFlowTokens.accent,
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
                      ? TrainFlowTokens.darkTrainingMuted
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
    final bool saving = ref.watch(bodyMetricExportControllerProvider
        .select((value) => value.isSaving));

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '数据出口',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '本地版不上传身体数据。这里提供 JSON/CSV 预览和导出包摘要；登记保存到本机，系统文件保存与分享尚未接入。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const Text('CSV 仅输出各记录的有效指标，空白不代表零；未知来源标为 unknown。'
              'JSON 保留原始值、实际字段及来源标记。mood 为保存时标签，不代表当前状态。'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: saving ? null : () async {
                  final String exportText = state.bodyMetricJsonExport;
                  ref
                      .read(bodyMetricExportTextProvider.notifier)
                      .setValue(exportText);
                  await _runDataCenterAction(
                    context,
                    () => ref
                        .read(bodyMetricExportControllerProvider.notifier)
                        .recordJsonExport(exportText),
                  );
                },
                icon: const Icon(Icons.data_object),
                label: const Text('导出 JSON'),
              ),
              OutlinedButton.icon(
                onPressed: saving ? null : () async {
                  final String exportText = state.bodyMetricCsvExport;
                  ref
                      .read(bodyMetricExportTextProvider.notifier)
                      .setValue(exportText);
                  await _runDataCenterAction(
                    context,
                    () => ref
                        .read(bodyMetricExportControllerProvider.notifier)
                        .recordCsvExport(exportText),
                  );
                },
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('导出 CSV'),
              ),
              OutlinedButton.icon(
                onPressed: saving ? null : () async {
                  final String packageSummary =
                      state.bodyMetricExportPackageSummary;
                  ref
                      .read(bodyMetricExportPackageStatusProvider.notifier)
                      .setValue('导出包摘要预览（登记结果见上方）\n$packageSummary');
                  await _runDataCenterAction(
                    context,
                    () => ref
                        .read(bodyMetricExportControllerProvider.notifier)
                        .recordPackageExport(packageSummary),
                  );
                },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('生成导出包'),
              ),
              OutlinedButton.icon(
                onPressed: saving || state.bodyMetricExportRecords.isEmpty
                    ? null
                    : () async {
                        final operation = ref.read(featureAccessProvider)
                            .beginOperation('core.data_rights');
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
                        await _runDataCenterAction(
                          context,
                          () async {
                            operation.checkActive();
                            await ref
                                .read(bodyMetricExportControllerProvider.notifier)
                                .clear();
                          },
                        );
                      },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('清除导出记录'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final bool? confirmed = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext dialogContext) {
                      return AlertDialog(
                        title: const Text('清除全部身体数据？'),
                        content: Text(
                          '这会删除${AppBrand.displayName} 本地保存的身体记录和修订历史，且无法撤销。'
                          '不会删除 Apple 健康中的原始数据，也不会清除训练记录。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.danger,
                            ),
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
                  await _runDataCenterAction(
                    context,
                    () =>
                        ref.read(bodyMetricControllerProvider.notifier).clear(),
                  );
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
              color: TrainFlowTokens.darkTrainingRaised,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                exportPackageStatus,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TrainFlowTokens.darkTrainingOnSurface,
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
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              state.bodyMetricExportStatusMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
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
    final report = BodyMetricDisplayService().build(metrics: state.bodyMetrics);
    return TrainFlowCard(
      key: const ValueKey('body-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('近 7 日身体记录', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('观察窗口：${report.periodLabel}。均值只包含有记录的自然日，不代表今日状态。'),
          for (final field in BodyMetricDisplayField.values.where(
            (f) => f != BodyMetricDisplayField.fatigue,
          )) ...[
            const SizedBox(height: 12),
            MetricPill(
              label: '${field.label}记录日均值',
              value: report[field].meanLabel,
            ),
            const SizedBox(height: 4),
            Text(
              report[field].evidenceLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
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
                      ?.copyWith(fontWeight: FontWeight.w600),
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
                  color: TrainFlowTokens.accent,
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
              const Icon(Icons.history, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '最近修订',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
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
                  color: TrainFlowTokens.darkTrainingMuted,
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
                    ?.copyWith(fontWeight: FontWeight.w600),
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
                color: TrainFlowTokens.darkTrainingMuted,
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
      key: const ValueKey('body-goals'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_outlined, color: toneColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '指标参考与记录',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(
                label: '参考与积累',
                color: toneColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            report.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
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
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            ToneBadge(
              label: goal.isReference
                  ? '非个人目标'
                  : goal.achieved ? '已累计' : goal.type.label,
              color: color,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!goal.isReference)
          TrainMateProgressBar(
            value: goal.progress,
            color: color,
            trackColor: color.withValues(alpha: 0.12),
            height: 8,
          ),
        const SizedBox(height: 8),
        InfoRow(label: '当前', value: goal.currentLabel),
        InfoRow(label: goal.isReference ? '参考' : '目标', value: goal.targetLabel),
        InfoRow(label: '说明', value: goal.milestoneLabel),
        Text(
          goal.guidance,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TrainFlowTokens.darkTrainingMuted,
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
    if (currentMetric == null) {
      return const TrainFlowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '10 秒快录',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('尚未建立身体数据基线，快捷录入不会显示或预填示例值。请先使用完整截图或 CSV，并确认后再保存。'),
          ],
        ),
      );
    }
    // 兼容默认值、继承值和未知来源不能变成新的手动观测。
    const quickFields = {
      'weightKg': '体重',
      'restingHeartRate': '静息心率',
      'hrvMs': 'HRV',
      'sleepHours': '睡眠',
      'fatigueLevel': '疲劳',
    };
    final missingLabels = quickFields.entries
        .where((entry) => !currentMetric.hasValue(entry.key))
        .map((entry) => entry.value)
        .toList();
    if (missingLabels.isNotEmpty) {
      return TrainFlowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('10 秒快录',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('上次记录的${missingLabels.join('、')}缺少有效数据或来源不明，无法安全预填。'
                '请先用完整截图或 CSV 补全并确认。历史记录保留，不会自动补零或保存默认值。'),
          ],
        ),
      );
    }
    final double weight = ref.watch(bodyMetricWeightProvider);
    final int restingHr = ref.watch(bodyMetricRestingHrProvider);
    final int hrv = ref.watch(bodyMetricHrvProvider);
    final double sleep = ref.watch(bodyMetricSleepProvider);
    final int fatigue = ref.watch(bodyMetricFatigueProvider);
    final DateTime measuredAt = ref.watch(bodyMetricMeasuredAtProvider);
    // 范围只影响控件，包含上次实际值；不截断数值，也不新增健康阈值。
    final weightMin = math.min(60.0, currentMetric.weightKg);
    final weightMax = math.max(90.0, currentMetric.weightKg);
    final sleepMin = math.min(4.0, currentMetric.sleepHours);
    final sleepMax = math.max(9.0, currentMetric.sleepHours);

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '10 秒快录',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '默认预填上次值，日期可补录；异常值先确认再入库。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            '补录日期',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
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
            min: weightMin,
            max: weightMax,
            divisions: weightMin == 60 && weightMax == 90 ? 300 : null,
            suffix: 'kg',
            onChanged: (double value) {
              ref.read(bodyMetricWeightProvider.notifier).setValue(value);
            },
          ),
          _IntSliderLine(
            label: '静息心率',
            value: restingHr,
            min: math.min(45, currentMetric.restingHeartRate),
            max: math.max(85, currentMetric.restingHeartRate),
            suffix: 'bpm',
            onChanged: (int value) {
              ref.read(bodyMetricRestingHrProvider.notifier).setValue(value);
            },
          ),
          _IntSliderLine(
            label: 'HRV',
            value: hrv,
            min: math.min(25, currentMetric.hrvMs),
            max: math.max(85, currentMetric.hrvMs),
            suffix: 'ms',
            onChanged: (int value) {
              ref.read(bodyMetricHrvProvider.notifier).setValue(value);
            },
          ),
          _DoubleSliderLine(
            label: '睡眠',
            value: sleep,
            min: sleepMin,
            max: sleepMax,
            divisions: sleepMin == 4 && sleepMax == 9 ? 50 : null,
            suffix: 'h',
            onChanged: (double value) {
              ref.read(bodyMetricSleepProvider.notifier).setValue(value);
            },
          ),
          _IntSliderLine(
            label: '疲劳',
            value: fatigue,
            min: 0,
            max: 10,
            suffix: '/10',
            onChanged: (int value) {
              ref.read(bodyMetricFatigueProvider.notifier).setValue(value);
            },
          ),
          const SizedBox(height: 10),
          TrainMateButton(
            label: '保存身体数据',
            icon: Icons.save_outlined,
            onPressed: ref.watch(bodyMetricControllerProvider).isSavingBodyMetrics
                ? null : () async {
              await _runDataCenterAction(
                context,
                () => ref
                    .read(bodyMetricControllerProvider.notifier)
                    .saveManualMetric(
                      weightKg: weight,
                      restingHeartRate: restingHr,
                      hrvMs: hrv,
                      sleepHours: sleep,
                      fatigueLevel: fatigue,
                      measuredAt: measuredAt,
                    ),
              );
            },
            expand: true,
          ),
          if (state.pendingBodyMetric?.source == BodyMetricSource.manual) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: ref.watch(bodyMetricControllerProvider).isSavingBodyMetrics
                    ? null : () async {
                  await _runDataCenterAction(
                    context,
                    () => ref
                        .read(bodyMetricControllerProvider.notifier)
                        .confirmPendingMetric(),
                  );
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
                      ? TrainFlowTokens.darkTrainingMuted
                      : AppColors.warningDark,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '上次记录：${currentMetric.measuredDateLabel} · ${currentMetric.weightKg.toStringAsFixed(1)} kg',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final TrainingMvpState state;
  final BodyMetricTrendWindow window;
  const _TrendCard({required this.state, required this.window});

  @override
  Widget build(BuildContext context) {
    final report = BodyMetricDisplayService().build(
      metrics: state.bodyMetrics,
      windowDays: window.days,
    );
    return TrainFlowCard(
      key: const ValueKey('body-trend'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BodyMetricTrendChart(report: report, windowLabel: window.label),
          const SizedBox(height: 16),
          if (report.coveredDays == 0) const Text('本窗口无有效观测，历史记录保留。'),
          for (final field in BodyMetricDisplayField.values)
            _TrendRow(
              label: field.label,
              latest: report[field].latestLabel,
              average: report[field].meanLabel,
              windowLabel: window.label,
              note: report[field].evidenceLabel,
            ),
        ],
      ),
    );
  }
}

class _BodyMetricTrendChart extends StatelessWidget {
  final BodyMetricDisplayReport report;
  final String windowLabel;

  const _BodyMetricTrendChart({
    required this.report,
    required this.windowLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.show_chart, color: TrainFlowTokens.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$windowLabel趋势图表',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            ToneBadge(label: '${report.coveredDays}/${report.days.length} 日'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '观察窗口 ${report.periodLabel}。各线独立缩放，纵向位置不能跨指标比较；空日不连线，不据此判断恢复或风险。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: TrainFlowTokens.darkTrainingMuted,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          width: double.infinity,
          child: CustomPaint(
            key: const ValueKey('body-trend-canvas'),
            painter: _BodyMetricTrendChartPainter(report: report),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _TrendLegendDot(
              label: _rangeLabel(report[BodyMetricDisplayField.weight]),
              color: TrainFlowTokens.accent,
            ),
            _TrendLegendDot(
              label: _rangeLabel(report[BodyMetricDisplayField.hrv]),
              color: AppColors.success,
            ),
            _TrendLegendDot(
              label: _rangeLabel(report[BodyMetricDisplayField.fatigue]),
              color: AppColors.warningDark,
            ),
          ],
        ),
      ],
    );
  }
}

String _rangeLabel(BodyMetricDisplaySeries series) {
  final values = series.values.whereType<double>().toList();
  if (values.isEmpty) return '${series.field.label}：无有效记录';
  return '${series.field.label} ${values.reduce(math.min).toStringAsFixed(1)}–'
      '${values.reduce(math.max).toStringAsFixed(1)} ${series.field.unit}（${series.count} 日）';
}

class _TrendLegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _TrendLegendDot({required this.label, required this.color});

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
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: TrainFlowTokens.darkTrainingMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _BodyMetricTrendChartPainter extends CustomPainter {
  final BodyMetricDisplayReport report;

  const _BodyMetricTrendChartPainter({required this.report});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect chartRect = Rect.fromLTWH(0, 4, size.width, size.height - 28);
    final Paint gridPaint = Paint()
      ..color = AppColors.grayLightish.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    final Paint axisPaint = Paint()
      ..color = TrainFlowTokens.darkTrainingMuted.withValues(alpha: 0.25)
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
      values: report[BodyMetricDisplayField.weight].values,
      color: TrainFlowTokens.accent,
    );
    _drawSeries(
      canvas: canvas,
      chartRect: chartRect,
      values: report[BodyMetricDisplayField.hrv].values,
      color: AppColors.success,
    );
    _drawSeries(
      canvas: canvas,
      chartRect: chartRect,
      values: report[BodyMetricDisplayField.fatigue].values,
      color: AppColors.warningDark,
    );

    _drawDateLabel(
      canvas: canvas,
      offset: Offset(chartRect.left, size.height - 16),
      label: bodyMetricDisplayDate(report.days.first).substring(5),
      textAlign: TextAlign.left,
    );
    _drawDateLabel(
      canvas: canvas,
      offset: Offset(chartRect.right, size.height - 16),
      label: bodyMetricDisplayDate(report.days.last).substring(5),
      textAlign: TextAlign.right,
    );
  }

  void _drawSeries({
    required Canvas canvas,
    required Rect chartRect,
    required Iterable<double?> values,
    required Color color,
  }) {
    final series = values.toList();
    final actual = series.whereType<double>().toList();
    if (actual.isEmpty) {
      return;
    }
    final double minValue = actual.reduce(math.min);
    final double maxValue = actual.reduce(math.max);
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
    bool connected = false;
    for (int index = 0; index < series.length; index += 1) {
      final value = series[index];
      if (value == null) {
        connected = false;
        continue;
      }
      final double x = series.length == 1
          ? chartRect.center.dx
          : chartRect.left + chartRect.width * index / (series.length - 1);
      final double normalized = maxValue == minValue
          ? 0.5
          : (value - minValue) / range;
      final double y = chartRect.bottom - normalized * chartRect.height;
      final Offset point = Offset(x, y);
      if (!connected) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      connected = true;
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
          color: TrainFlowTokens.darkTrainingMuted,
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
    return oldDelegate.report != report;
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
              const Icon(Icons.timeline, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '趋势窗口',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
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
            '按当前自然日查看 7/30/90 日记录；缺失不补零，同日每项取最近有效值。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
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
                    color: TrainFlowTokens.darkTrainingMuted,
                  ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '最近有效值 $latest · $windowLabel记录日均值 $average',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TrainFlowTokens.darkTrainingMuted,
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
              const Icon(Icons.insights, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '趋势洞察',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
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
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            '叠加视图',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
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
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          InfoRow(label: '减脂保护', value: report.fatLossProtectionLabel),
          Text(
            report.fatLossProtectionDetail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
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

  String _value(String field, String value) =>
      metric.hasValue(field) ? value : '无有效记录';

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      key: ValueKey('body-record-${metric.id}'),
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
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const ToneBadge(label: '历史记录'),
            ],
          ),
          const SizedBox(height: 8),
          InfoRow(
              label: '体重',
              value: _value(
                  'weightKg', '${metric.weightKg.toStringAsFixed(1)} kg')),
          InfoRow(
              label: '体脂',
              value: _value('bodyFatPercentage',
                  '${metric.bodyFatPercentage.toStringAsFixed(1)}%')),
          InfoRow(
              label: '静息心率',
              value:
                  _value('restingHeartRate', '${metric.restingHeartRate} bpm')),
          InfoRow(label: 'HRV', value: _value('hrvMs', '${metric.hrvMs} ms')),
          InfoRow(
              label: '睡眠',
              value: _value(
                  'sleepHours', '${metric.sleepHours.toStringAsFixed(1)} h')),
          InfoRow(
              label: '疲劳',
              value: _value('fatigueLevel', '${metric.fatigueLevel}/10')),
          InfoRow(
              label: '酸痛',
              value: _value('sorenessLevel', '${metric.sorenessLevel}/10')),
          if (metric.moodLabel.isNotEmpty) Text('保存时标签：${metric.moodLabel}'),
          Text(
            '${metric.sourceVerified ? metric.source.label : '来源未确认'} · ${metric.note}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
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
  final int? divisions;
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

Future<void> _runDataCenterAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('身体数据操作失败：$error')),
    );
  }
}

// 样例独立只读展示，不进入输入 provider、识别结果或写入仓储。
Future<void> _showBodyMetricExample(
    BuildContext context, String title, String text) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Text('以下为演示数据，仅供查看格式，不会填入表单或保存。'
            '请返回后输入自己的实际记录。\n\n$text'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    ),
  );
}
