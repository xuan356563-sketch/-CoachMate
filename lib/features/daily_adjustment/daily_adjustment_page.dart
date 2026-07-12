import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/daily_adjustment.dart';
import '../../data/models/workout_day.dart';
import '../dashboard/training_mvp_controller.dart';
import 'application/daily_adjustment_controller.dart';

class DailyAdjustmentPage extends ConsumerWidget {
  const DailyAdjustmentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final DailyAdjustmentDecision decision = state.dailyAdjustmentDecision;

    return TrainFlowPage(
      title: '每日调整',
      subtitle: '把身体状态和现实约束合并，给出今天是否正常、降级、恢复、技术或休息。',
      children: [
        _DecisionSummaryCard(decision: decision, state: state),
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

  const _DecisionSummaryCard({
    required this.decision,
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
              const Icon(Icons.tune, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今日重算结果',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
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
                  label: '调整后时长',
                  value: '${decision.adjustedMinutes} 分钟',
                  color: AppColors.secondary,
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
                ?.copyWith(fontWeight: FontWeight.w800),
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
                ?.copyWith(fontWeight: FontWeight.w800),
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
  final VoidCallback onPressed;

  const _ChoiceButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return FilledButton(
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
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
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final String badge in decision.constraintBadges)
                ToneBadge(label: badge, color: AppColors.secondary),
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
                    color: AppColors.primary,
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
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '应用结果',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            state.dailyAdjustmentStatusMessage,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                ref
                    .read(dailyAdjustmentControllerProvider.notifier)
                    .applyDailyAdjustmentDecision(
                        state.dailyAdjustmentDecision);
              },
              icon: const Icon(Icons.task_alt),
              label: const Text('应用今日调整'),
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
