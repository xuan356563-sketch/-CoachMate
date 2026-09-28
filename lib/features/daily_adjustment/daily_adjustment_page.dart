import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/daily_adjustment.dart';
import '../../data/models/workout_day.dart';
import '../dashboard/training_mvp_controller.dart';
import '../pet/application/pet_controller.dart';
import 'application/daily_adjustment_controller.dart';
import 'application/daily_course_adjustment.dart';

class DailyAdjustmentPage extends ConsumerWidget {
  const DailyAdjustmentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final DailyAdjustmentDecision decision = state.dailyAdjustmentDecision;
    final TrainMateAction characterAction = switch (decision.decisionType) {
      TrainingDecisionType.normal => TrainMateAction.highKnees,
      TrainingDecisionType.deload => TrainMateAction.sideLungeStretch,
      TrainingDecisionType.technique => TrainMateAction.squat,
      TrainingDecisionType.recovery ||
      TrainingDecisionType.rest =>
        TrainMateAction.seatedMeditation,
    };

    return TrainFlowPage(
      title: '每日调整',
      layout: TrainFlowPageLayout.form,
      subtitle: '把身体状态和现实约束合并，给出今天是否正常、降级、恢复、技术或休息。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.dashboard,
      ),
      artwork: TrainMateActionCharacter(
        action: characterAction,
        backgroundColor: AppColors.primary,
      ),
      children: [
        TrainFlowCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('准备度 ${state.readinessValueLabel} · 工程估算'),
            const SizedBox(height: 8),
            Text(state.readinessEvidence.explanation),
            TextButton(onPressed: () => context.push(AppRoutes.dataCenter),
                child: const Text('查看和补充身体记录')),
            FilledButton(onPressed: () async {
              try {
                await ref.read(dailyAdjustmentControllerProvider.notifier).confirmTodayStatus();
                if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已确认今日状态；计划未改变。'))); }
              } catch (_) {
                if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('状态确认未保存，请重试。'))); }
              }
            }, child: const Text('确认已核对今日状态记录')),
          ]),
        ),
        _DecisionSummaryCard(
          decision: decision,
          state: state,
          characterAction: characterAction,
        ),
        _RealityConstraintCard(state: state),
        _AdjustmentStepsCard(decision: decision),
        _ApplyAdjustmentCard(state: state),
      ],
    );
  }
}

class _DecisionSummaryCard extends StatelessWidget {
  final DailyAdjustmentDecision decision;
  final TrainingMvpState state;
  final TrainMateAction characterAction;

  const _DecisionSummaryCard({
    required this.decision,
    required this.state,
    required this.characterAction,
  });

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      cornerCharacterAction: characterAction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今日重算结果',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(
                label: decision.decisionLabel,
                color: _decisionColor(decision.decisionType),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '五类决策',
                  value: decision.decisionTypeLabel,
                  color: _decisionColor(decision.decisionType),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '建议时长',
                  value: '${decision.adjustedMinutes} 分钟',
                  color: TrainFlowTokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoRow(label: '原计划', value: state.todayWorkout.title),
          InfoRow(label: '今日变化', value: decision.planChangeSummary),
          InfoRow(label: '判断原因', value: decision.reason),
        ],
      ),
    );
  }
}

class _RealityConstraintCard extends ConsumerWidget {
  final TrainingMvpState state;

  const _RealityConstraintCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DailyAdjustmentController controller =
        ref.read(dailyAdjustmentControllerProvider.notifier);

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '现实约束',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _ConstraintGroup(
            title: '可用时间',
            children: [
              _ChoiceButton(
                label: '20 分钟',
                selected: state.dailyAvailableMinutesOverride == 20,
                onPressed: () => controller.setDailyAvailableMinutes(20),
              ),
              _ChoiceButton(
                label: '30 分钟',
                selected: state.dailyAvailableMinutesOverride == 30,
                onPressed: () => controller.setDailyAvailableMinutes(30),
              ),
              _ChoiceButton(
                label: '40 分钟',
                selected: state.dailyAvailableMinutesOverride == 40,
                onPressed: () => controller.setDailyAvailableMinutes(40),
              ),
              _ChoiceButton(
                label: '60 分钟',
                selected: state.dailyAvailableMinutesOverride == 60,
                onPressed: () => controller.setDailyAvailableMinutes(60),
              ),
            ],
          ),
          _ConstraintGroup(
            title: '工作压力',
            children: [
              _ChoiceButton(
                label: WorkStressLevel.normal.label,
                selected: state.dailyWorkStress == WorkStressLevel.normal,
                onPressed: () =>
                    controller.setDailyWorkStress(WorkStressLevel.normal),
              ),
              _ChoiceButton(
                label: WorkStressLevel.high.label,
                selected: state.dailyWorkStress == WorkStressLevel.high,
                onPressed: () =>
                    controller.setDailyWorkStress(WorkStressLevel.high),
              ),
              _ChoiceButton(
                label: WorkStressLevel.extreme.label,
                selected: state.dailyWorkStress == WorkStressLevel.extreme,
                onPressed: () =>
                    controller.setDailyWorkStress(WorkStressLevel.extreme),
              ),
            ],
          ),
          _ConstraintGroup(
            title: '场地器械',
            children: [
              _ChoiceButton(
                label: TrainingEnvironment.gym.label,
                selected:
                    state.dailyTrainingEnvironment == TrainingEnvironment.gym,
                onPressed: () => controller
                    .setDailyTrainingEnvironment(TrainingEnvironment.gym),
              ),
              _ChoiceButton(
                label: TrainingEnvironment.home.label,
                selected:
                    state.dailyTrainingEnvironment == TrainingEnvironment.home,
                onPressed: () => controller
                    .setDailyTrainingEnvironment(TrainingEnvironment.home),
              ),
              _ChoiceButton(
                label: TrainingEnvironment.outdoor.label,
                selected: state.dailyTrainingEnvironment ==
                    TrainingEnvironment.outdoor,
                onPressed: () => controller
                    .setDailyTrainingEnvironment(TrainingEnvironment.outdoor),
              ),
              _ChoiceButton(
                label: TrainingEnvironment.noEquipment.label,
                selected: state.dailyTrainingEnvironment ==
                    TrainingEnvironment.noEquipment,
                onPressed: () => controller.setDailyTrainingEnvironment(
                  TrainingEnvironment.noEquipment,
                ),
              ),
            ],
          ),
          _ConstraintGroup(
            title: '天气状态',
            children: [
              _ChoiceButton(
                label: WeatherCondition.good.label,
                selected: state.dailyWeather == WeatherCondition.good,
                onPressed: () =>
                    controller.setDailyWeather(WeatherCondition.good),
              ),
              _ChoiceButton(
                label: WeatherCondition.hot.label,
                selected: state.dailyWeather == WeatherCondition.hot,
                onPressed: () =>
                    controller.setDailyWeather(WeatherCondition.hot),
              ),
              _ChoiceButton(
                label: WeatherCondition.rain.label,
                selected: state.dailyWeather == WeatherCondition.rain,
                onPressed: () =>
                    controller.setDailyWeather(WeatherCondition.rain),
              ),
              _ChoiceButton(
                label: WeatherCondition.poorAir.label,
                selected: state.dailyWeather == WeatherCondition.poorAir,
                onPressed: () =>
                    controller.setDailyWeather(WeatherCondition.poorAir),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConstraintGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ConstraintGroup({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: children,
          ),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Future<void> Function() onPressed;

  const _ChoiceButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    void run() {
      unawaited(_runDailyAdjustmentAction(context, onPressed));
    }

    if (selected) {
      return FilledButton(
        onPressed: run,
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: run,
      child: Text(label),
    );
  }
}

class _AdjustmentStepsCard extends StatelessWidget {
  final DailyAdjustmentDecision decision;

  const _AdjustmentStepsCard({required this.decision});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '调整动作',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final String badge in decision.constraintBadges)
                ToneBadge(label: badge, color: TrainFlowTokens.accent),
            ],
          ),
          const SizedBox(height: 12),
          for (final String adjustment in decision.adjustments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: TrainFlowTokens.accent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(adjustment)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ApplyAdjustmentCard extends ConsumerWidget {
  final TrainingMvpState state;

  const _ApplyAdjustmentCard({
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applied = appliedDailyCourseFor(state, state.todayWorkout.id);
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '应用结果',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            applied == null
                ? state.dailyAdjustmentStatusMessage
                : '当前课程已应用确认调整：${applied.originalEstimatedMinutes} → ${applied.adjustedEstimatedMinutes} 分钟。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: () => context.push(AppRoutes.plans), child: const Text('进入计划调整')),
          if (dailyCourseApplyEnabled)
            OutlinedButton.icon(
              onPressed: () => _previewCourseAdjustment(context, ref),
              icon: const Icon(Icons.preview_outlined),
              label: const Text('查看可执行课程差异'),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                try {
                  await ref
                      .read(dailyAdjustmentControllerProvider.notifier)
                      .applyDailyAdjustmentDecision(
                        state.dailyAdjustmentDecision,
                      );
                  await ref.read(petControllerProvider.notifier).refreshToday();
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('记录今日建议失败：$error')),
                  );
                }
              },
              icon: const Icon(Icons.task_alt),
              label: const Text('记录今日建议'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _previewCourseAdjustment(BuildContext context, WidgetRef ref) async {
  try {
    final service = ref.read(dailyCourseAdjustmentProvider);
    final preview = service.preview();
    final candidate = preview.candidate;
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(candidate == null ? '当前仅有建议' : '确认课程调整'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(preview.reason),
          const SizedBox(height: 12),
          Text('原课程：${preview.original.estimatedMinutes} 分钟 · ${preview.original.intensity}'),
          if (candidate != null) ...[
            Text('原主训练：${preview.original.mainSets.join('；')}'),
            Text('原辅助训练：${preview.original.accessoryWork.isEmpty ? '无' : preview.original.accessoryWork.join('；')}'),
            const SizedBox(height: 12),
            Text('调整后：${candidate.estimatedMinutes} 分钟 · ${candidate.intensity}'),
            Text('调整后主训练：${candidate.mainSets.join('；')}'),
            Text('调整后辅助训练：${candidate.accessoryWork.isEmpty ? '无' : candidate.accessoryWork.join('；')}'),
            const Text('准备与冷身保留；确认后才保存。'),
          ] else const Text('可记录当前建议，或进入计划页面使用已有调整流程。'),
        ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
        if (candidate != null) FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('确认应用')),
      ],
    ));
    if (confirmed != true || !context.mounted) return;
    await service.confirm(preview);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('课程调整已保存并应用到跟练，可在核心历史查看。')));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('课程调整未完成：$error')));
  }
}

Future<void> _runDailyAdjustmentAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('保存每日调整失败：$error')),
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
      return TrainFlowTokens.darkTrainingMuted;
  }
}
