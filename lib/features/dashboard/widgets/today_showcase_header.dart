import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/trainflow_tokens.dart';
import '../../../core/widgets/trainmate_action_character.dart';
import '../../../core/widgets/trainmate_showcase_widgets.dart';
import '../../../data/models/workout_day.dart';

/// 今日页只组合已有训练事实；场景中的文案与按钮始终由 Flutter 实时渲染。
class TodayShowcaseHeader extends StatelessWidget {
  const TodayShowcaseHeader({
    super.key,
    required this.athleteName,
    required this.growthLabel,
    required this.growthXp,
    required this.nextLevelXp,
    required this.completionRate,
    required this.readinessScore,
    required this.weeklyConsistencyLabel,
    required this.workout,
    required this.onOpenCoach,
    required this.onStartWorkout,
  });

  final String athleteName;
  final String growthLabel;
  final int growthXp;
  final int nextLevelXp;
  final double completionRate;
  final int? readinessScore;
  final String weeklyConsistencyLabel;
  final WorkoutDay workout;
  final VoidCallback? onOpenCoach;
  final VoidCallback? onStartWorkout;

  @override
  Widget build(BuildContext context) {
    final String safeName = athleteName.trim().isEmpty ? '训练者' : athleteName;
    final int completionPercent = (completionRate.clamp(0, 1) * 100).round();
    final String taskSubtitle =
        '${workout.trainingType.label} · ${workout.estimatedMinutes} 分钟 · '
        '${workout.mainSets.length + workout.accessoryWork.length} 个动作';
    return Semantics(
      key: const ValueKey<String>('today-showcase-header'),
      container: true,
      label: '今日训练，$safeName，$taskSubtitle',
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 360;
          final double metricWidth = compact ? 176 : 204;
          final double firstWidth = compact ? 106 : 124;
          final double secondWidth = compact ? 88 : 104;
          return TrainMateSceneHero(
            style: TrainMateSceneHeroStyle.referenceShowcase,
            referenceBackgroundColor: TrainFlowTokens.purple,
            characterInsets: EdgeInsets.fromLTRB(
              compact ? 180 : 214,
              70,
              compact ? 18 : 20,
              108,
            ),
            sceneAsset:
                'assets/images/immersive_scenes/trainmate_today_training_room.png',
            greeting: '你好，$safeName',
            dateLabel: _dateLabel(DateTime.now()),
            character: const TrainMateActionCharacter(
              action: TrainMateAction.running,
              size: 178,
              backgroundColor: AppColors.transparent,
              style: TrainMateCharacterStyle.flatShowcase,
              semanticLabel: 'CoachMate 正在陪你开始今日训练',
            ),
            taskTitle: workout.title,
            taskSubtitle: taskSubtitle,
            taskIcon: Icons.play_circle_fill_rounded,
            actionTooltip: 'AI 教练',
            onAction: onOpenCoach,
            onTaskTap: onStartWorkout,
            taskProgress: completionRate,
            taskProgressLabel: '今日完成 $completionPercent%',
            taskTrailing: FilledButton(
              onPressed: onStartWorkout,
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 44),
              ),
              child: const Text('开始'),
            ),
            metricOverlay: Positioned(
              key: const ValueKey<String>('today-showcase-metric-capsule'),
              left: 20,
              top: 78,
              child: Semantics(
                label: '今日完成 $completionPercent%，准备度 ${readinessScore ?? '无法评估'}，'
                    '预计 ${workout.estimatedMinutes} 分钟，$weeklyConsistencyLabel，'
                    '$growthLabel，$growthXp/$nextLevelXp XP',
                child: ExcludeSemantics(
                  child: SizedBox(
                    width: metricWidth,
                    height: 68,
                    child: Stack(
                      children: <Widget>[
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: firstWidth,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: TrainFlowTokens.pink,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 8, 18, 8),
                              child: FittedBox(
                                alignment: Alignment.centerLeft,
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      '$completionPercent% 完成',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: TrainFlowTokens.brandDark,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      '预计 ${workout.estimatedMinutes} 分钟',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: TrainFlowTokens.brandDark
                                                .withValues(alpha: 0.78),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 4,
                          bottom: 4,
                          width: secondWidth,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: TrainFlowTokens.showcaseActionSurface,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
                              child: FittedBox(
                                alignment: Alignment.centerLeft,
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      '${readinessScore ?? '无法评估'} 准备度',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            color: TrainFlowTokens.yellow,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      weeklyConsistencyLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: TrainFlowTokens.paper
                                                .withValues(alpha: 0.76),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _dateLabel(DateTime date) =>
      '${date.month} 月 ${date.day} 日 · $weeklyConsistencyLabel';
}
