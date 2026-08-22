import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/trainmate_action_character.dart';
import '../../../core/widgets/trainmate_showcase_widgets.dart';
import '../../../core/widgets/trainflow_widgets.dart';
import '../../../data/models/growth_evidence.dart';

class ProfileShowcaseHeader extends StatelessWidget {
  const ProfileShowcaseHeader({
    super.key,
    required this.name,
    required this.trainingGoal,
    required this.readinessScore,
    required this.completedSessionCount,
    required this.growthProgress,
    required this.achievementCount,
    required this.trainingRecordCount,
    required this.onEditProfile,
    required this.onOpenGrowthEvidence,
    required this.onOpenWeeklyReport,
  });

  final String name;
  final String trainingGoal;
  final int readinessScore;
  final int completedSessionCount;
  final GrowthLevelProgress growthProgress;
  final int achievementCount;
  final int trainingRecordCount;
  final VoidCallback onEditProfile;
  final VoidCallback onOpenGrowthEvidence;
  final VoidCallback onOpenWeeklyReport;

  @override
  Widget build(BuildContext context) {
    final String safeName = name.trim().isEmpty ? '训练者' : name;
    final String safeGoal =
        trainingGoal.trim().isEmpty ? '持续建立训练节奏' : trainingGoal;
    return Semantics(
      key: const ValueKey<String>('profile-showcase-header'),
      container: true,
      label: '个人档案，$safeName，训练目标 $safeGoal',
      child: Stack(
        children: <Widget>[
          TrainMateSceneHero(
            sceneAsset:
                'assets/images/immersive_scenes/trainmate_profile_recovery_room.png',
            greeting: '你好，$safeName',
            dateLabel: safeGoal,
            character: const TrainMateActionCharacter(
              action: TrainMateAction.seatedMeditation,
              size: 164,
              backgroundColor: AppColors.transparent,
              semanticLabel: 'Flow 正在陪你查看恢复与训练档案',
            ),
            taskTitle: '训练准备度 $readinessScore 分',
            taskSubtitle:
                '已完成 $completedSessionCount 次训练 · ${growthProgress.label}',
            taskIcon: Icons.favorite_outline,
            actionTooltip: '编辑资料',
            onAction: onEditProfile,
            onTaskTap: onOpenGrowthEvidence,
            taskProgress:
                (growthProgress.currentXp / growthProgress.nextLevelXp)
                    .clamp(0, 1),
            taskProgressLabel:
                '成长 ${growthProgress.currentXp}/${growthProgress.nextLevelXp} XP',
          ),
          Positioned(
            key: const ValueKey<String>('profile-showcase-avatar'),
            left: 24,
            top: 54,
            child: const IgnorePointer(
              child: TrainMateActionCharacter(
                action: TrainMateAction.pointingGuide,
                size: 42,
                backgroundColor: AppColors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileImmersiveOverview extends StatelessWidget {
  const ProfileImmersiveOverview({
    super.key,
    required this.readinessScore,
    required this.completedSessionCount,
    required this.growthProgress,
    required this.achievementCount,
    required this.trainingRecordCount,
    required this.onOpenGrowthEvidence,
    required this.onOpenWeeklyReport,
  });

  final int readinessScore;
  final int completedSessionCount;
  final GrowthLevelProgress growthProgress;
  final int achievementCount;
  final int trainingRecordCount;
  final VoidCallback onOpenGrowthEvidence;
  final VoidCallback onOpenWeeklyReport;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KeyedSubtree(
            key: const ValueKey<String>('profile-showcase-stat-capsule'),
            child: TrainMateOverviewGrid(
              first: _ProfileOverviewTile(
                  label: '准备度',
                  value: '$readinessScore 分',
                  icon: Icons.favorite_outline),
              second: _ProfileOverviewTile(
                  label: '完成训练',
                  value: '$completedSessionCount 次',
                  icon: Icons.fitness_center_outlined),
              trend: _ProfileOverviewTile(
                key: const ValueKey<String>('profile-showcase-growth-progress'),
                label: '成长等级',
                value:
                    '${growthProgress.label} · ${growthProgress.currentXp}/${growthProgress.nextLevelXp} XP',
                icon: Icons.auto_graph_outlined,
                wide: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Column(
            key: const ValueKey<String>('profile-showcase-records'),
            children: <Widget>[
              TrainMateRecordTile(
                  icon: Icons.emoji_events_outlined,
                  title: '训练成就',
                  subtitle: '已写入本地的真实解锁记录',
                  trailing: '$achievementCount',
                  onTap: onOpenGrowthEvidence),
              const SizedBox(height: 10),
              TrainMateRecordTile(
                  icon: Icons.auto_graph_outlined,
                  title: '成长报告',
                  subtitle: '完整训练记录与本周趋势',
                  trailing: '$trainingRecordCount',
                  onTap: onOpenWeeklyReport),
            ],
          ),
        ],
      );
}

class _ProfileOverviewTile extends StatelessWidget {
  const _ProfileOverviewTile(
      {super.key,
      required this.label,
      required this.value,
      required this.icon,
      this.wide = false});
  final String label;
  final String value;
  final IconData icon;
  final bool wide;
  @override
  Widget build(BuildContext context) => TrainFlowCard(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: wide ? 108 : 132),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, color: TrainFlowTokens.accent),
                const SizedBox(height: 14),
                TrainMateMetricValue(value: value, label: label),
              ]),
        ),
      );
}
