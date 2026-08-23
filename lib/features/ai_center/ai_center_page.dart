import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainmate_showcase_widgets.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/ai_artifact.dart';
import '../../data/models/training_schedule.dart';
import '../../data/models/user_profile.dart';
import '../daily_adjustment/application/daily_adjustment_controller.dart';
import '../dashboard/training_mvp_controller.dart';
import 'application/ai_artifact_controller.dart';

class AiCenterPage extends ConsumerStatefulWidget {
  const AiCenterPage({super.key});

  @override
  ConsumerState<AiCenterPage> createState() => _AiCenterPageState();
}

class _AiCenterPageState extends ConsumerState<AiCenterPage> {
  int _section = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(aiArtifactControllerProvider.notifier).sync());
    });
  }

  @override
  Widget build(BuildContext context) {
    final TrainingMvpState training = ref.watch(trainingMvpProvider);
    final AiArtifactState aiState = ref.watch(aiArtifactControllerProvider);
    final TrainMateAction characterAction = switch (_section) {
      0 => TrainMateAction.pointingGuide,
      1 => TrainMateAction.squat,
      _ => TrainMateAction.seatedMeditation,
    };

    return TrainMateShowcasePage(
      showcase: TrainMateShowcaseEntrance(
        child: KeyedSubtree(
          key: const ValueKey<String>('ai-showcase-header'),
          child: TrainMateHubHeader(
            title: 'AI 中心',
            subtitle: '生成的是训练卡片，确认后才会影响本地训练；伙伴对话已统一到“伙伴”。',
            eyebrow: 'AI FIRST · 用户掌控',
            semanticLabel: 'AI 中心概览，所有建议确认后才生效',
            artwork: TrainMateIllustration(
              assetPath: 'assets/images/trainmate_ai_showcase.png',
              semanticLabel: 'AI 训练指导插画',
              fallback: TrainMateActionCharacter(
                action: characterAction,
                backgroundColor: TrainFlowTokens.darkTrainingRaised,
              ),
            ),
            metrics: <Widget>[
              TrainMateHubMetric(
                label: '当前',
                value: const <String>['训练卡', '动作卡', '恢复卡'][_section],
                icon: Icons.auto_awesome,
              ),
              TrainMateHubMetric(
                label: '状态',
                value: aiState.isBusy ? '处理中' : '可使用',
                icon: Icons.sync,
                tone: TrainFlowCardTone.peach,
              ),
              const TrainMateHubMetric(
                label: '生效方式',
                value: '确认后',
                icon: Icons.verified_user_outlined,
              ),
            ],
            action: Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: aiState.isBusy
                    ? null
                    : () =>
                        ref.read(aiArtifactControllerProvider.notifier).sync(),
                icon: const Icon(Icons.sync),
                label: const Text('同步 AI 卡片'),
              ),
            ),
          ),
        ),
      ),
      children: [
        SegmentedButton<int>(
          segments: const <ButtonSegment<int>>[
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.calendar_month_outlined),
              label: Text('训练'),
            ),
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.accessibility_new),
              label: Text('动作'),
            ),
            ButtonSegment(
              value: 2,
              icon: Icon(Icons.favorite_border),
              label: Text('恢复'),
            ),
          ],
          selected: <int>{_section},
          onSelectionChanged: aiState.isBusy
              ? null
              : (Set<int> values) => setState(() => _section = values.first),
        ),
        TrainFlowCard(
          tone: TrainFlowCardTone.outline,
          cornerCharacterAction: characterAction,
          child: Text(aiState.statusMessage),
        ),
        if (_section == 0)
          ..._trainerChildren(context, aiState)
        else if (_section == 1)
          ..._motionChildren(context, aiState)
        else if (_section == 2)
          ..._recoveryChildren(context, training, aiState),
      ],
    );
  }

  List<Widget> _trainerChildren(
    BuildContext context,
    AiArtifactState aiState,
  ) {
    final AiArtifact? artifact = aiState.latestForArtifactType(
      AiCapability.trainer,
      'trainer_plan_v1',
    );
    return <Widget>[
      TrainFlowCard(
        tone: TrainFlowCardTone.peach,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Skill 四周计划',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('完成官方筛查后生成预览；本地编译、安全审计和你的确认缺一不可。'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push(AppRoutes.planGenerate),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('生成四周训练计划'),
              ),
            ),
          ],
        ),
      ),
      const SectionTitle(title: '历史 AI Trainer 摘要'),
      if (artifact == null)
        const TrainFlowCard(child: Text('还没有旧版 AI Trainer 摘要。'))
      else
        _TrainerArtifactCard(
          artifact: artifact,
          onRefresh: null,
          onAccept: artifact.isPending
              ? () => _acceptTrainerArtifact(artifact)
              : null,
          onReject: artifact.isPending ? () => _rejectArtifact(artifact) : null,
        ),
    ];
  }

  List<Widget> _motionChildren(
    BuildContext context,
    AiArtifactState aiState,
  ) {
    final AiArtifact? artifact = aiState.latestFor(AiCapability.motion);
    return <Widget>[
      const SectionTitle(title: '图片动作分析'),
      TrainFlowCard(
        tone: TrainFlowCardTone.peach,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Motion',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('先在动作纠错中选择照片。每次上传前都要单独确认，照片不会保存到本地或云端。'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push(AppRoutes.motionCheck),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('前往动作纠错'),
              ),
            ),
          ],
        ),
      ),
      if (artifact == null)
        const TrainFlowCard(child: Text('还没有 AI Motion 评分卡。'))
      else
        _MotionArtifactCard(artifact: artifact),
    ];
  }

  List<Widget> _recoveryChildren(
    BuildContext context,
    TrainingMvpState training,
    AiArtifactState aiState,
  ) {
    final AiArtifact? artifact = aiState.latestFor(AiCapability.recovery);
    return <Widget>[
      const SectionTitle(title: '恢复建议'),
      TrainFlowCard(
        tone: TrainFlowCardTone.peach,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Recovery',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '健康、疼痛、准备度和成长指标只在本机计算；云端 AI 仅接收训练目标与时间约束。',
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    aiState.isBusy ? null : () => _generateRecovery(training),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('生成恢复仪表盘'),
              ),
            ),
          ],
        ),
      ),
      if (artifact == null)
        const TrainFlowCard(child: Text('还没有 AI Recovery 建议。'))
      else
        _RecoveryArtifactCard(
          artifact: artifact,
          onAccept: artifact.isPending
              ? () => _acceptRecoveryArtifact(artifact)
              : null,
          onReject: artifact.isPending ? () => _rejectArtifact(artifact) : null,
        ),
    ];
  }

  Future<void> _generateRecovery(
    TrainingMvpState training,
  ) async {
    await ref.read(aiArtifactControllerProvider.notifier).generateText(
          capability: AiCapability.recovery,
          prompt: '请基于当前状态生成今天的恢复建议。',
          context: _contextFor(training),
        );
  }

  Future<void> _acceptTrainerArtifact(AiArtifact artifact) async {
    if (!await _confirm(
      title: '保存旧版 AI Trainer 摘要？',
      content: '旧版卡片只作为建议摘要保存，不会激活计划或改变正式计划状态。',
    )) {
      return;
    }
    await ref.read(aiArtifactControllerProvider.notifier).decide(
          artifact: artifact,
          decision: AiArtifactDecision.accepted,
        );
  }

  Future<void> _acceptRecoveryArtifact(AiArtifact artifact) async {
    if (!await _confirm(
      title: '采用今日恢复建议？',
      content: '只会更新今天的恢复提示，本地疼痛和安全规则始终优先。',
    )) {
      return;
    }
    final AiArtifact? accepted =
        await ref.read(aiArtifactControllerProvider.notifier).decide(
              artifact: artifact,
              decision: AiArtifactDecision.accepted,
            );
    final AiRecoveryDashboard? dashboard = accepted?.recoveryDashboard;
    if (dashboard != null && mounted) {
      ref
          .read(dailyAdjustmentControllerProvider.notifier)
          .applyAiRecoveryRecommendation(dashboard.recommendedAction);
    }
  }

  Future<void> _rejectArtifact(AiArtifact artifact) async {
    await ref.read(aiArtifactControllerProvider.notifier).decide(
          artifact: artifact,
          decision: AiArtifactDecision.rejected,
        );
  }

  Future<bool> _confirm({
    required String title,
    required String content,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
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
    return confirmed ?? false;
  }

  AiGenerationContext _contextFor(TrainingMvpState training) {
    return AiGenerationContext(
      goal: training.todayWorkout.title,
      sports: training.profile.mainSports.map((item) => item.label).toList(),
      availableMinutes: training.dailyAvailableMinutesOverride,
      scheduledMinutes: training.scheduledTodayWorkout?.allocatedMinutes,
      scheduledPeriod: training.scheduledTodayWorkout?.period.label,
      readinessScore: training.readinessScore,
      dailyDecision: training.dailyAdjustmentDecision.decisionLabel,
      painLevel: training.latestPainLog?.painLevel ?? 0,
    );
  }
}

class _TrainerArtifactCard extends StatelessWidget {
  final AiArtifact artifact;
  final VoidCallback? onRefresh;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const _TrainerArtifactCard({
    required this.artifact,
    this.onRefresh,
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final AiTrainerPlan? plan = artifact.trainerPlan;
    if (plan == null) return const SizedBox.shrink();
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plan.cycleLabel,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: artifact.isPending ? '待确认' : '已确认'),
            ],
          ),
          const SizedBox(height: 10),
          Text(plan.weeklyStructure),
          const Divider(height: 24),
          for (final AiTrainerWorkoutCard card in plan.workoutCards) ...[
            Text(card.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                '${card.durationMinutes} 分钟 · ${card.intensity} · ${card.focus.join(' / ')}'),
            Text(card.safetyNote,
                style: const TextStyle(color: TrainFlowTokens.darkTrainingMuted)),
            const SizedBox(height: 10),
          ],
          if (plan.safetyNotes.isNotEmpty)
            Text('安全提示：${plan.safetyNotes.join('；')}',
                style: const TextStyle(color: TrainFlowTokens.darkTrainingMuted)),
          _Warnings(warnings: artifact.warnings),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('重新生成'),
              ),
              if (onReject != null)
                TextButton(onPressed: onReject, child: const Text('不采用')),
              if (onAccept != null)
                FilledButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('确认采用'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecoveryArtifactCard extends StatelessWidget {
  final AiArtifact artifact;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const _RecoveryArtifactCard({
    required this.artifact,
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final AiRecoveryDashboard? dashboard = artifact.recoveryDashboard;
    if (dashboard == null) return const SizedBox.shrink();
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_border, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text('非健康计划适配预览 ${dashboard.readinessScore} 分',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              ToneBadge(label: artifact.isPending ? '待确认' : '已确认'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '仅根据目标、运动项目与可用时间生成，不是身体恢复或生理测量。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 10),
          Text(dashboard.recommendedAction),
          const SizedBox(height: 10),
          Text('影响因素：${dashboard.factors.join('；')}'),
          const SizedBox(height: 6),
          Text('今天执行：${dashboard.todayTasks.join('；')}'),
          if (dashboard.redFlags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('注意：${dashboard.redFlags.join('；')}',
                style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 6),
          Text(dashboard.safetyNote,
              style: const TextStyle(color: TrainFlowTokens.darkTrainingMuted)),
          _Warnings(warnings: artifact.warnings),
          if (onAccept != null || onReject != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (onReject != null)
                  TextButton(onPressed: onReject, child: const Text('不采用')),
                if (onAccept != null)
                  FilledButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('确认今日建议'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MotionArtifactCard extends StatelessWidget {
  final AiArtifact artifact;

  const _MotionArtifactCard({required this.artifact});

  @override
  Widget build(BuildContext context) {
    final AiMotionScore? score = artifact.motionScore;
    if (score == null) return const SizedBox.shrink();
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AI Motion 评分 ${score.score} 分',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          InfoRow(label: '风险', value: _motionRiskLabel(score.riskLevel)),
          InfoRow(label: '置信度', value: '${(score.confidence * 100).round()}%'),
          if (score.detectedErrors.isNotEmpty)
            Text('发现：${score.detectedErrors.join('；')}'),
          if (score.corrections.isNotEmpty)
            Text('纠正：${score.corrections.join('；')}'),
          if (score.replacements.isNotEmpty)
            Text('替代：${score.replacements.join('；')}'),
          const SizedBox(height: 6),
          Text(score.safetyNote,
              style: const TextStyle(color: TrainFlowTokens.darkTrainingMuted)),
          _Warnings(warnings: artifact.warnings),
        ],
      ),
    );
  }
}

class _Warnings extends StatelessWidget {
  final List<String> warnings;

  const _Warnings({required this.warnings});

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text('提示：${warnings.join('；')}',
          style: const TextStyle(color: AppColors.warningDark)),
    );
  }
}

String _motionRiskLabel(String value) => switch (value) {
      'low' => '低风险',
      'high' => '高风险',
      _ => '中风险',
    };
