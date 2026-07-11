import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/evidence_source.dart';
import '../../data/models/exercise.dart';
import '../../data/models/motion_check.dart';
import '../../services/motion_pose_analysis_service.dart';
import '../dashboard/training_mvp_controller.dart';

class MotionCheckPage extends ConsumerWidget {
  const MotionCheckPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);

    return TrainFlowPage(
      title: '动作纠错',
      subtitle: '先用本地规则模拟 Motion Vision → Body Engine → 决策输入。',
      children: [
        _MotionPipelineCard(state: state),
        for (final MotionCheckRule rule in state.motionChecks)
          _MotionRuleCard(rule: rule),
      ],
    );
  }
}

Future<void> _showPoseJsonImportDialog({
  required BuildContext context,
  required WidgetRef ref,
  required MotionCheckRule rule,
}) async {
  final TextEditingController controller = TextEditingController();
  final String? rawJson = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('导入结构化关键点'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            minLines: 7,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: '关键点 JSON',
              hintText: '粘贴本地姿态模型输出的 poseFrame 或 landmarks JSON',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.text = jsonEncode(
                MotionPoseAnalysisService.sampleFrameFor(rule.type).toJson(),
              );
            },
            child: const Text('填入样例'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('导入并分析'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  if (rawJson == null || rawJson.isEmpty) {
    return;
  }
  ref.read(trainingMvpProvider.notifier).analyzeMotionCheckFromPoseJson(
        ruleId: rule.id,
        rawJson: rawJson,
      );
}

class _MotionPipelineCard extends StatelessWidget {
  final TrainingMvpState state;

  const _MotionPipelineCard({required this.state});

  @override
  Widget build(BuildContext context) {
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
                  'Motion Vision 管线',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: '${state.motionChecks.length} 项'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '本地规则 Mock：当前模拟图片/视频识别后的结果；另提供结构化关键点几何计算样例，生成角度、风险、置信度和训练决策影响。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            state.motionAnalysisStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          if (result != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MetricPill(
                    label: '最近分析',
                    value: result.type.label,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricPill(
                    label: '决策影响',
                    value: result.suggestedImpact.label,
                    color: _riskColor(result.riskLevel),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            InfoRow(label: 'Body Engine', value: result.bodyEngineSummary),
            InfoRow(label: '动作质量风险', value: result.decisionImpact),
            InfoRow(label: '分析来源', value: result.analysisSource),
            if (result.analysisConfidence > 0)
              InfoRow(
                label: '计算置信度',
                value: '${(result.analysisConfidence * 100).round()}%',
              ),
            if (result.angleMetrics.isNotEmpty)
              InfoRow(label: '角度计算', value: result.angleMetrics.join(' / ')),
          ],
        ],
      ),
    );
  }
}

class _MotionRuleCard extends ConsumerWidget {
  final MotionCheckRule rule;

  const _MotionRuleCard({required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final MotionAnalysisResult? latest = state.latestMotionAnalysisResult;
    final bool isLatest = latest?.sourceRuleId == rule.id;
    final Exercise? exercise =
        rule.exerciseId == null ? null : state.findExercise(rule.exerciseId!);

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rule.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: '${rule.score} 分'),
              const SizedBox(width: 8),
              ToneBadge(
                label: rule.riskLevel.label,
                color: _riskColor(rule.riskLevel),
              ),
            ],
          ),
          if (isLatest) ...[
            const SizedBox(height: 8),
            ToneBadge(label: '已写入今日决策', color: AppColors.secondary),
          ],
          const SizedBox(height: 8),
          Text(
            rule.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          if (exercise != null) ...[
            const SizedBox(height: 8),
            InfoRow(label: '动作库', value: exercise.name),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    context.go(AppRoutes.exerciseDetail(exercise.id)),
                icon: const Icon(Icons.open_in_new),
                label: const Text('查看动作安全提示'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          InfoRow(label: '观察角度', value: rule.targetAngles.join(' / ')),
          InfoRow(label: '主要问题', value: rule.commonIssues.join(' / ')),
          InfoRow(label: '纠正建议', value: rule.correctionCues.join(' / ')),
          InfoRow(label: '退阶动作', value: rule.regressions.join(' / ')),
          InfoRow(label: '拍摄建议', value: rule.nextCaptureTips.join(' / ')),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                ref
                    .read(trainingMvpProvider.notifier)
                    .analyzeMotionCheck(rule.id);
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('模拟上传分析'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ref
                    .read(trainingMvpProvider.notifier)
                    .analyzeMotionCheckWithPose(rule.id);
              },
              icon: const Icon(Icons.straighten),
              label: const Text('计算关键点样例'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showPoseJsonImportDialog(
                context: context,
                ref: ref,
                rule: rule,
              ),
              icon: const Icon(Icons.data_object),
              label: const Text('导入关键点数据'),
            ),
          ),
          const SizedBox(height: 8),
          _MotionEvidenceBlock(sources: rule.evidenceSources),
        ],
      ),
    );
  }
}

class _MotionEvidenceBlock extends StatelessWidget {
  final List<EvidenceSource> sources;

  const _MotionEvidenceBlock({required this.sources});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '依据来源',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final EvidenceSource source in sources) ...[
          Text(
            source.citationLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text('原文片段：${source.quote}'),
          const SizedBox(height: 4),
          Text(
            '适用原因：${source.note}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          if (source != sources.last) const Divider(height: 18),
        ],
      ],
    );
  }
}

Color _riskColor(MotionRiskLevel riskLevel) {
  switch (riskLevel) {
    case MotionRiskLevel.low:
      return AppColors.success;
    case MotionRiskLevel.medium:
      return AppColors.warningDark;
    case MotionRiskLevel.high:
      return AppColors.danger;
  }
}
