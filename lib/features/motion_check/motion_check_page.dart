import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/ai_artifact.dart';
import '../../data/models/evidence_source.dart';
import '../../data/models/exercise.dart';
import '../../data/models/motion_check.dart';
import '../../data/models/motion_pose.dart';
import '../../services/motion_pose_analysis_service.dart';
import '../dashboard/training_mvp_controller.dart';
import '../ai_center/application/ai_artifact_controller.dart';
import 'application/motion_image_analysis_controller.dart';

class MotionCheckPage extends ConsumerStatefulWidget {
  const MotionCheckPage({super.key});

  @override
  ConsumerState<MotionCheckPage> createState() => _MotionCheckPageState();
}

class _MotionCheckPageState extends ConsumerState<MotionCheckPage> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);

    return TrainFlowPage(
      title: '动作纠错',
      layout: TrainFlowPageLayout.form,
      subtitle: '照片先在设备端提取关键点，确认后才发起云端图片复核。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.exercises,
      ),
      artwork: const TrainMateActionCharacter(
        action: TrainMateAction.squat,
        backgroundColor: AppColors.primary,
      ),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
                value: 0, icon: Icon(Icons.add_a_photo), label: Text('照片识别')),
            ButtonSegment(
                value: 1, icon: Icon(Icons.rule), label: Text('纠错规则')),
            ButtonSegment(
                value: 2, icon: Icon(Icons.history), label: Text('分析记录')),
          ],
          selected: <int>{_section},
          onSelectionChanged: (Set<int> value) =>
              setState(() => _section = value.first),
        ),
        if (_section == 0) ...[
          _MotionPhotoRecognitionCard(rules: state.motionChecks),
          _MotionPipelineCard(state: state),
        ] else if (_section == 1)
          for (final MotionCheckRule rule in state.motionChecks)
            _MotionRuleCard(rule: rule)
        else if (state.motionAnalysisResults.isEmpty)
          const TrainFlowCard(
            cornerCharacterAction: TrainMateAction.squat,
            child: Text('还没有动作分析记录。'),
          )
        else
          for (final MotionAnalysisResult result in state.motionAnalysisResults)
            TrainFlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  InfoRow(label: '评分', value: '${result.score} 分'),
                  InfoRow(label: '风险', value: result.riskLevel.label),
                  InfoRow(label: '来源', value: result.analysisSource),
                ],
              ),
            ),
      ],
    );
  }
}

class _MotionPhotoRecognitionCard extends ConsumerWidget {
  final List<MotionCheckRule> rules;

  const _MotionPhotoRecognitionCard({required this.rules});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MotionImageAnalysisState state =
        ref.watch(motionImageAnalysisControllerProvider);
    final AiArtifactState aiState = ref.watch(aiArtifactControllerProvider);
    final controller = ref.read(motionImageAnalysisControllerProvider.notifier);
    final MotionPoseAnalysis? analysis = state.analysis;
    final AiArtifact? aiArtifact = aiState.latestFor(AiCapability.motion);
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('照片动作识别',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: state.ruleId,
            decoration: const InputDecoration(labelText: '选择纠错动作'),
            items: [
              for (final MotionCheckRule rule in rules)
                DropdownMenuItem(value: rule.id, child: Text(rule.type.label)),
            ],
            onChanged: state.isBusy
                ? null
                : (String? value) {
                    if (value == null) return;
                    controller.selectRule(
                      rules.firstWhere(
                          (MotionCheckRule item) => item.id == value),
                    );
                  },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.isBusy
                      ? null
                      : () => controller.pickAndAnalyze(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('拍照识别'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isBusy
                      ? null
                      : () => controller.pickAndAnalyze(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('从相册选择'),
                ),
              ),
            ],
          ),
          if (state.isBusy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (state.imageBytes != null) ...[
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(state.imageBytes!, fit: BoxFit.contain),
                    if (state.frame != null)
                      CustomPaint(painter: _PoseOverlayPainter(state.frame!)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(state.statusMessage),
          if (analysis != null) ...[
            const Divider(height: 24),
            InfoRow(label: '评分', value: '${analysis.score} 分'),
            InfoRow(label: '风险', value: analysis.riskLevel.label),
            InfoRow(
              label: '置信度',
              value: '${(analysis.confidence * 100).round()}%',
            ),
            for (final MotionPoseMeasurement item in analysis.measurements)
              InfoRow(label: item.label, value: item.valueLabel),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  ref
                      .read(trainingMvpProvider.notifier)
                      .analyzeMotionCheckFromPoseJson(
                        ruleId: state.ruleId!,
                        rawJson: jsonEncode(state.frame!.toJson()),
                      );
                  controller.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('纠错结果已应用到今日训练。')),
                  );
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('应用纠错结果'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: aiState.isBusy || state.imageBytes == null
                    ? null
                    : () async {
                        final bool? confirmed = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext dialogContext) => AlertDialog(
                            title: const Text('提交 AI 图片复核？'),
                            content: const Text(
                              '本次照片会在内存中清理元数据后发送给 AI 进行一次分析，不会保存到本地、云端或日志中。',
                            ),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: const Text('确认提交'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        final AiArtifact? artifact = await ref
                            .read(aiArtifactControllerProvider.notifier)
                            .generateMotion(
                              imageBytes: state.imageBytes!,
                              filename: '${state.ruleId!}.jpg',
                              ruleId: state.ruleId!,
                              localPoseSummary:
                                  '本地评分 ${analysis.score}，风险 ${analysis.riskLevel.label}，${analysis.measurements.map((item) => '${item.label} ${item.valueLabel}').join('；')}',
                            );
                        if (artifact != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('AI Motion 评分卡已生成，请确认后再应用。'),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('提交 AI 图片复核'),
              ),
            ),
            if (aiArtifact?.motionScore != null) ...[
              const SizedBox(height: 12),
              _AiMotionReviewPanel(
                artifact: aiArtifact!,
                ruleId: state.ruleId!,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AiMotionReviewPanel extends ConsumerWidget {
  final AiArtifact artifact;
  final String ruleId;

  const _AiMotionReviewPanel({
    required this.artifact,
    required this.ruleId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AiMotionScore? score = artifact.motionScore;
    if (score == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text(
          'AI Motion 图片复核',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        InfoRow(label: '评分', value: '${score.score} 分'),
        InfoRow(label: '风险', value: _cloudRiskLabel(score.riskLevel)),
        InfoRow(
          label: '置信度',
          value: '${(score.confidence * 100).round()}%',
        ),
        if (score.detectedErrors.isNotEmpty)
          Text('发现：${score.detectedErrors.join('；')}'),
        if (score.corrections.isNotEmpty)
          Text('纠正：${score.corrections.join('；')}'),
        if (score.replacements.isNotEmpty)
          Text('替代：${score.replacements.join('；')}'),
        const SizedBox(height: 6),
        Text(
          score.safetyNote,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TrainFlowTokens.darkTrainingMuted,
              ),
        ),
        if (artifact.warnings.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('提示：${artifact.warnings.join('；')}'),
        ],
        if (artifact.isPending) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final bool? confirmed = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext dialogContext) => AlertDialog(
                    title: const Text('采用 AI Motion 建议？'),
                    content: const Text('确认后会写入本地动作分析记录，并重新计算今日训练。'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('确认采用'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                final AiArtifact? accepted = await ref
                    .read(aiArtifactControllerProvider.notifier)
                    .decide(
                      artifact: artifact,
                      decision: AiArtifactDecision.accepted,
                    );
                if (accepted == null || !context.mounted) return;
                ref
                    .read(trainingMvpProvider.notifier)
                    .applyAiMotionArtifact(artifact: accepted, ruleId: ruleId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('AI Motion 建议已写入今日训练决策。')),
                );
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('确认采用 AI 建议'),
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('该 AI Motion 结果已确认。'),
          ),
      ],
    );
  }
}

String _cloudRiskLabel(String riskLevel) => switch (riskLevel) {
      'low' => '低风险',
      'high' => '高风险',
      _ => '中风险',
    };

class _PoseOverlayPainter extends CustomPainter {
  final MotionPoseFrame frame;

  const _PoseOverlayPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint point = Paint()..color = AppColors.secondary;
    final Paint line = Paint()
      ..color = AppColors.secondary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    Offset? position(MotionPoseLandmarkType type) {
      final item = frame.landmark(type);
      return item == null
          ? null
          : Offset(item.x * size.width, item.y * size.height);
    }

    const connections = <List<MotionPoseLandmarkType>>[
      [
        MotionPoseLandmarkType.leftShoulder,
        MotionPoseLandmarkType.rightShoulder
      ],
      [MotionPoseLandmarkType.leftShoulder, MotionPoseLandmarkType.leftElbow],
      [MotionPoseLandmarkType.leftElbow, MotionPoseLandmarkType.leftWrist],
      [MotionPoseLandmarkType.rightShoulder, MotionPoseLandmarkType.rightElbow],
      [MotionPoseLandmarkType.rightElbow, MotionPoseLandmarkType.rightWrist],
      [MotionPoseLandmarkType.leftShoulder, MotionPoseLandmarkType.leftHip],
      [MotionPoseLandmarkType.rightShoulder, MotionPoseLandmarkType.rightHip],
      [MotionPoseLandmarkType.leftHip, MotionPoseLandmarkType.rightHip],
      [MotionPoseLandmarkType.leftHip, MotionPoseLandmarkType.leftKnee],
      [MotionPoseLandmarkType.leftKnee, MotionPoseLandmarkType.leftAnkle],
      [MotionPoseLandmarkType.rightHip, MotionPoseLandmarkType.rightKnee],
      [MotionPoseLandmarkType.rightKnee, MotionPoseLandmarkType.rightAnkle],
    ];
    for (final pair in connections) {
      final Offset? first = position(pair.first);
      final Offset? second = position(pair.last);
      if (first != null && second != null) canvas.drawLine(first, second, line);
    }
    for (final landmark in frame.landmarks) {
      canvas.drawCircle(
          Offset(landmark.x * size.width, landmark.y * size.height), 5, point);
    }
  }

  @override
  bool shouldRepaint(covariant _PoseOverlayPainter oldDelegate) =>
      oldDelegate.frame != frame;
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
              const Icon(Icons.motion_photos_on, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Motion Vision 管线',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: '${state.motionChecks.length} 项'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '本地规则 Mock：当前模拟图片/视频识别后的结果；另提供结构化关键点几何计算样例，生成角度、风险、置信度和训练决策影响。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            state.motionAnalysisStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
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
                      ?.copyWith(fontWeight: FontWeight.w600),
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
            ToneBadge(label: '已写入今日决策', color: TrainFlowTokens.accent),
          ],
          const SizedBox(height: 8),
          Text(
            rule.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          if (exercise != null) ...[
            const SizedBox(height: 8),
            InfoRow(label: '动作库', value: exercise.name),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    context.push(AppRoutes.exerciseDetail(exercise.id)),
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
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final EvidenceSource source in sources) ...[
          Text(
            source.citationLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text('原文片段：${source.quote}'),
          const SizedBox(height: 4),
          Text(
            '适用原因：${source.note}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
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
