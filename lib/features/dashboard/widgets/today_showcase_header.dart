import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
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
  final String weeklyConsistencyLabel;
  final WorkoutDay workout;
  final VoidCallback onOpenCoach;
  final VoidCallback onStartWorkout;

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
      child: Stack(
        children: <Widget>[
          TrainMateSceneHero(
            sceneAsset:
                'assets/images/immersive_scenes/trainmate_today_training_room.png',
            greeting: '你好，$safeName',
            dateLabel: _dateLabel(DateTime.now()),
            character: const TrainMateActionCharacter(
              action: TrainMateAction.running,
              size: 178,
              backgroundColor: AppColors.transparent,
              semanticLabel: 'Flow 正在陪你开始今日训练',
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
          ),
          Positioned(
            key: const ValueKey<String>('today-showcase-metric-capsule'),
            left: 20,
            top: 72,
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A28),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    '$growthLabel · $growthXp/$nextLevelXp XP · $completionPercent%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFFE0FF64),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime date) =>
      '${date.month} 月 ${date.day} 日 · $weeklyConsistencyLabel';
}
