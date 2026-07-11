import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/weekly_report.dart';
import '../../data/models/weekly_report_export.dart';
import '../dashboard/training_mvp_controller.dart';

class WeeklyReportPage extends ConsumerWidget {
  const WeeklyReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final WeeklyReport report = state.weeklyReport;
    final String exportText = ref.watch(weeklyReportExportTextProvider);
    final String imageExportStatus =
        ref.watch(weeklyReportImageExportStatusProvider);

    return TrainFlowPage(
      title: '自动周报',
      subtitle: '训练周报 Agent Mock：完成率、负荷趋势、决策回顾和下周重点。',
      children: [
        _WeeklyReportSummaryCard(report: report),
        _WeeklyReportInsightCard(report: report),
        _WeeklyReportFocusCard(report: report),
        _WeeklyReportExportCard(
          state: state,
          report: report,
          exportText: exportText,
          imageExportStatus: imageExportStatus,
        ),
      ],
    );
  }
}

class _WeeklyReportSummaryCard extends StatelessWidget {
  final WeeklyReport report;

  const _WeeklyReportSummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.summarize, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '自动周报 Agent Mock',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: report.weekLabel),
            ],
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
                  label: '负荷趋势',
                  value: report.loadTrendLabel,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: report.completionRate,
            minHeight: 8,
            color: AppColors.primary,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 10),
          Text(
            '本周完成 ${report.completedWorkouts}/${report.plannedWorkouts} 次计划训练。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyReportInsightCard extends StatelessWidget {
  final WeeklyReport report;

  const _WeeklyReportInsightCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '决策命中回顾',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(report.decisionReview),
          const SizedBox(height: 12),
          Text(
            '恢复建议',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(report.recoverySummary),
          const SizedBox(height: 12),
          Text(
            '本周亮点',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final String item in report.highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('· $item'),
            ),
        ],
      ),
    );
  }
}

class _WeeklyReportFocusCard extends StatelessWidget {
  final WeeklyReport report;

  const _WeeklyReportFocusCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '下周重点',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < report.nextWeekFocus.length; i += 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.primaryLightest,
                    child: Text(
                      '${i + 1}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(report.nextWeekFocus[i])),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WeeklyReportExportCard extends ConsumerWidget {
  final TrainingMvpState state;
  final WeeklyReport report;
  final String exportText;
  final String imageExportStatus;

  const _WeeklyReportExportCard({
    required this.state,
    required this.report,
    required this.exportText,
    required this.imageExportStatus,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.ios_share, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '周报导出',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: 'Markdown + PNG'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '上方周报可导出 Markdown；下方分享卡可在本地生成 PNG 图片字节，也可先保存到本地周报归档，后续再接系统分享和保存到相册。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          _WeeklyReportImagePreview(report: report),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                final String markdown = report.markdown;
                ref
                    .read(weeklyReportExportTextProvider.notifier)
                    .setValue(markdown);
                ref
                    .read(trainingMvpProvider.notifier)
                    .recordWeeklyReportMarkdownExport(markdown);
              },
              icon: const Icon(Icons.description_outlined),
              label: const Text('导出 Markdown'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ref
                    .read(trainingMvpProvider.notifier)
                    .saveCurrentWeeklyReport();
              },
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('保存到本地归档'),
            ),
          ),
          const SizedBox(height: 10),
          _SavedWeeklyReportArchiveCard(state: state),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await _exportImagePreview(ref);
              },
              icon: const Icon(Icons.image_outlined),
              label: const Text('生成图片卡片'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            imageExportStatus,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 10),
          _WeeklyReportExportHistoryCard(state: state),
          if (exportText.isNotEmpty) ...[
            const SizedBox(height: 12),
            SelectableText(exportText),
          ],
        ],
      ),
    );
  }

  Future<void> _exportImagePreview(WidgetRef ref) async {
    try {
      final Uint8List bytes = await _buildWeeklyReportPng(report);
      final int byteCount = bytes.length;
      if (byteCount == 0) {
        ref
            .read(weeklyReportImageExportStatusProvider.notifier)
            .setValue('图片卡片生成失败：PNG 字节为空。');
        return;
      }
      final double kb = byteCount / 1024;
      ref
          .read(trainingMvpProvider.notifier)
          .recordWeeklyReportPngExport(byteCount);
      ref.read(weeklyReportImageExportStatusProvider.notifier).setValue(
            '图片卡片已生成：PNG ${kb.toStringAsFixed(1)} KB，可接系统分享。',
          );
    } catch (_) {
      ref
          .read(weeklyReportImageExportStatusProvider.notifier)
          .setValue('图片卡片生成失败：请重新打开周报后再试。');
    }
  }
}

class _WeeklyReportExportHistoryCard extends StatelessWidget {
  final TrainingMvpState state;

  const _WeeklyReportExportHistoryCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final WeeklyReportExportRecord? latestRecord =
        state.latestWeeklyReportExportRecord;

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
              state.weeklyReportExportStatusMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            if (latestRecord != null) ...[
              const SizedBox(height: 8),
              InfoRow(label: '最近格式', value: latestRecord.format.label),
              InfoRow(label: '文件名', value: latestRecord.fileName),
              InfoRow(
                label: '大小',
                value: '${latestRecord.sizeLabel} · ${latestRecord.weekLabel}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SavedWeeklyReportArchiveCard extends StatelessWidget {
  final TrainingMvpState state;

  const _SavedWeeklyReportArchiveCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final WeeklyReport? latestSavedReport = state.savedWeeklyReports.isEmpty
        ? null
        : state.savedWeeklyReports.first;

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
              '本地周报归档',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              state.weeklyReportSaveStatusMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            if (latestSavedReport != null) ...[
              const SizedBox(height: 8),
              InfoRow(label: '最近保存', value: latestSavedReport.weekLabel),
              InfoRow(
                label: '完成率',
                value: latestSavedReport.completionRateLabel,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<Uint8List> _buildWeeklyReportPng(WeeklyReport report) async {
  const double width = 1080;
  const double height = 1080;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);

  canvas.drawRect(
    const Rect.fromLTWH(0, 0, width, height),
    Paint()..color = AppColors.primaryLightest,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(54, 54, width - 108, height - 108),
      const Radius.circular(42),
    ),
    Paint()..color = Colors.white,
  );

  _drawImageText(
    canvas,
    'TrainFlow AI 周报',
    const Offset(96, 104),
    fontSize: 58,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
    maxWidth: 760,
  );
  _drawImageText(
    canvas,
    report.weekLabel,
    const Offset(96, 178),
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
    maxWidth: 720,
  );

  _drawMetricBlock(
    canvas,
    rect: const Rect.fromLTWH(96, 260, 410, 160),
    label: '完成率',
    value: report.completionRateLabel,
    color: AppColors.primary,
  );
  _drawMetricBlock(
    canvas,
    rect: const Rect.fromLTWH(574, 260, 410, 160),
    label: '负荷趋势',
    value: report.loadTrendLabel,
    color: AppColors.secondary,
  );

  final Rect progressTrack = const Rect.fromLTWH(96, 474, 888, 28);
  canvas.drawRRect(
    RRect.fromRectAndRadius(progressTrack, const Radius.circular(14)),
    Paint()..color = AppColors.primary.withValues(alpha: 0.12),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(
        progressTrack.left,
        progressTrack.top,
        progressTrack.width * report.completionRate.clamp(0, 1),
        progressTrack.height,
      ),
      const Radius.circular(14),
    ),
    Paint()..color = AppColors.primary,
  );

  _drawSectionText(
    canvas,
    title: '恢复建议',
    body: report.recoverySummary,
    top: 570,
  );
  _drawSectionText(
    canvas,
    title: '下周重点',
    body: report.nextWeekFocus.first,
    top: 760,
  );
  _drawImageText(
    canvas,
    '本地生成 · 数据归用户所有',
    const Offset(96, 982),
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    maxWidth: 888,
  );

  final ui.Image image =
      await recorder.endRecording().toImage(width.toInt(), height.toInt());
  final ByteData? byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return byteData?.buffer.asUint8List() ?? Uint8List(0);
}

void _drawMetricBlock(
  Canvas canvas, {
  required Rect rect,
  required String label,
  required String value,
  required Color color,
}) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(28)),
    Paint()..color = color.withValues(alpha: 0.1),
  );
  _drawImageText(
    canvas,
    label,
    Offset(rect.left + 28, rect.top + 26),
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    maxWidth: rect.width - 56,
  );
  _drawImageText(
    canvas,
    value,
    Offset(rect.left + 28, rect.top + 76),
    fontSize: 46,
    fontWeight: FontWeight.w900,
    color: color,
    maxWidth: rect.width - 56,
  );
}

void _drawSectionText(
  Canvas canvas, {
  required String title,
  required String body,
  required double top,
}) {
  _drawImageText(
    canvas,
    title,
    Offset(96, top),
    fontSize: 34,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
    maxWidth: 888,
  );
  _drawImageText(
    canvas,
    body,
    Offset(96, top + 52),
    fontSize: 34,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    maxWidth: 888,
    maxLines: 3,
  );
}

void _drawImageText(
  Canvas canvas,
  String text,
  Offset offset, {
  required double fontSize,
  required FontWeight fontWeight,
  required Color color,
  required double maxWidth,
  int maxLines = 1,
}) {
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    ),
    maxLines: maxLines,
    ellipsis: '...',
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  painter.paint(canvas, offset);
}

class _WeeklyReportImagePreview extends StatelessWidget {
  final WeeklyReport report;

  const _WeeklyReportImagePreview({required this.report});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primaryLightest,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_graph, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'TrainFlow AI 周报卡片',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                ToneBadge(label: report.weekLabel),
              ],
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
                const SizedBox(width: 8),
                Expanded(
                  child: MetricPill(
                    label: '负荷趋势',
                    value: report.loadTrendLabel,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              report.recoverySummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              report.nextWeekFocus.first,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
