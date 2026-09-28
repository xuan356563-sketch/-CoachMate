import 'package:flutter/material.dart';

import '../../../core/widgets/trainmate_branding.dart';
import '../../../core/widgets/trainflow_widgets.dart';
import '../../../data/models/growth_evidence.dart';

class ProfileShowcaseHeader extends StatelessWidget {
  const ProfileShowcaseHeader({
    super.key,
    required this.name,
    required this.trainingGoal,
    required this.onEditProfile,
  });

  final String name;
  final String trainingGoal;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final String safeName = name.trim().isEmpty ? '训练者' : name;
    final String safeGoal =
        trainingGoal.trim().isEmpty ? '持续建立训练节奏' : trainingGoal;
    return Semantics(
      key: const ValueKey<String>('profile-showcase-header'),
      container: true,
      label: '个人档案，$safeName，训练目标 $safeGoal',
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: TrainFlowTokens.paper,
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(TrainFlowTokens.sectionRadius),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Stack(
            children: <Widget>[
              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  '我的',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: TrainFlowTokens.brandDark,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  key: const ValueKey<String>('profile-edit-button'),
                  tooltip: '编辑资料',
                  onPressed: onEditProfile,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    backgroundColor: TrainFlowTokens.showcasePaper,
                    foregroundColor: TrainFlowTokens.brandDark,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(TrainFlowTokens.mainTabControlRadius),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Align(
                      child: DecoratedBox(
                        key: const ValueKey<String>('profile-showcase-avatar'),
                        decoration: BoxDecoration(
                          color: TrainFlowTokens.purpleSoft,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: TrainFlowTokens.paper,
                            width: 4,
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: TrainFlowTokens.showcaseShadow,
                              blurRadius: 18,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const SizedBox.square(
                          dimension: 92,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: TrainMateBrandmark(size: 76),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      safeName,
                      key: const ValueKey<String>('profile-showcase-name'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: TrainFlowTokens.brandDark,
                                fontSize: 26,
                                height: 1.12,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      safeGoal,
                      key: const ValueKey<String>('profile-showcase-goal'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: TrainFlowTokens.textMuted,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

  final int? readinessScore;
  final int completedSessionCount;
  final GrowthLevelProgress growthProgress;
  final int achievementCount;
  final int trainingRecordCount;
  final VoidCallback onOpenGrowthEvidence;
  final VoidCallback onOpenWeeklyReport;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stackMetrics = constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.35;
        return DecoratedBox(
          key: const ValueKey<String>('profile-showcase-overview-card'),
          decoration: BoxDecoration(
            color: TrainFlowTokens.paper,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: TrainFlowTokens.showcaseShadow,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DecoratedBox(
                  key: const ValueKey<String>('profile-showcase-stat-capsule'),
                  decoration: BoxDecoration(
                    color: TrainFlowTokens.showcaseActionSurface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: stackMetrics
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _ProfileSnapshotMetric(
                                key: const ValueKey<String>(
                                  'profile-readiness-metric',
                                ),
                                label: '训练准备度',
                                value: '${readinessScore ?? '无法评估'}',
                                unit: readinessScore == null ? '' : '估算',
                                icon: Icons.favorite_outline,
                              ),
                              const SizedBox(height: 14),
                              Divider(
                                height: 1,
                                color: TrainFlowTokens.paper
                                    .withValues(alpha: 0.24),
                              ),
                              const SizedBox(height: 14),
                              _ProfileSnapshotMetric(
                                key: const ValueKey<String>(
                                  'profile-completed-metric',
                                ),
                                label: '完成训练',
                                value: '$completedSessionCount',
                                unit: '次',
                                icon: Icons.fitness_center_outlined,
                              ),
                            ],
                          )
                        : Row(
                            children: <Widget>[
                              Expanded(
                                child: _ProfileSnapshotMetric(
                                  key: const ValueKey<String>(
                                    'profile-readiness-metric',
                                  ),
                                  label: '训练准备度',
                                  value: '${readinessScore ?? '无法评估'}',
                                  unit: readinessScore == null ? '' : '估算',
                                  icon: Icons.favorite_outline,
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 58,
                                color: TrainFlowTokens.paper
                                    .withValues(alpha: 0.24),
                              ),
                              Expanded(
                                child: _ProfileSnapshotMetric(
                                  key: const ValueKey<String>(
                                    'profile-completed-metric',
                                  ),
                                  alignment: CrossAxisAlignment.end,
                                  label: '完成训练',
                                  value: '$completedSessionCount',
                                  unit: '次',
                                  icon: Icons.fitness_center_outlined,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                _ProfileGrowthLine(
                  key: const ValueKey<String>(
                    'profile-showcase-growth-progress',
                  ),
                  label: growthProgress.label,
                  currentXp: growthProgress.currentXp,
                  nextLevelXp: growthProgress.nextLevelXp,
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                Column(
                  key: const ValueKey<String>('profile-showcase-records'),
                  children: <Widget>[
                    _ProfileQuickRecordRow(
                      key: const ValueKey<String>(
                        'profile-record-achievements',
                      ),
                      icon: Icons.emoji_events_outlined,
                      title: '训练成就',
                      subtitle: '已写入本地的真实解锁记录',
                      trailing: '$achievementCount',
                      onTap: onOpenGrowthEvidence,
                    ),
                    const Divider(height: 1),
                    _ProfileQuickRecordRow(
                      key: const ValueKey<String>('profile-record-report'),
                      icon: Icons.auto_graph_outlined,
                      title: '成长报告',
                      subtitle: '完整训练记录与本周趋势',
                      trailing: '$trainingRecordCount',
                      onTap: onOpenWeeklyReport,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProfileGrowthLine extends StatelessWidget {
  const _ProfileGrowthLine({
    super.key,
    required this.label,
    required this.currentXp,
    required this.nextLevelXp,
  });

  final String label;
  final int currentXp;
  final int nextLevelXp;

  @override
  Widget build(BuildContext context) {
    final int safeNextLevelXp = nextLevelXp <= 0 ? 1 : nextLevelXp;
    final int safeCurrentXp = currentXp.clamp(0, safeNextLevelXp).toInt();
    final int remainingXp = safeNextLevelXp - safeCurrentXp;
    final double progress = safeCurrentXp / safeNextLevelXp;
    return Semantics(
      key: const ValueKey<String>('profile-showcase-xp-rail'),
      container: true,
      label: '$label，已获得 $safeCurrentXp XP，距离升级还需 $remainingXp XP',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: TrainFlowTokens.brandDark,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$safeCurrentXp/$safeNextLevelXp XP',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: TrainFlowTokens.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double markerLeft =
                      ((constraints.maxWidth * progress) - 5)
                          .clamp(0.0, constraints.maxWidth - 10)
                          .toDouble();
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      const ColoredBox(color: TrainFlowTokens.purple),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: const ColoredBox(color: TrainFlowTokens.yellow),
                      ),
                      Positioned(
                        left: markerLeft,
                        top: 0,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            color: TrainFlowTokens.yellow,
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox.square(dimension: 10),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '已获得 $safeCurrentXp XP',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: TrainFlowTokens.warning,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Text(
                '距升级 $remainingXp XP',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: TrainFlowTokens.purple,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileSnapshotMetric extends StatelessWidget {
  const _ProfileSnapshotMetric({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.alignment = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: alignment,
        children: <Widget>[
          Icon(icon, color: TrainFlowTokens.yellow, size: 18),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(child: Text(
                value,
                maxLines: 2,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: TrainFlowTokens.paper,
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
              )),
              const SizedBox(width: 3),
              Text(
                unit,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: TrainFlowTokens.paper.withValues(alpha: 0.72),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: alignment == CrossAxisAlignment.end
                ? TextAlign.right
                : TextAlign.left,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: TrainFlowTokens.paper.withValues(alpha: 0.7),
                ),
          ),
        ],
      );
}

class _ProfileQuickRecordRow extends StatelessWidget {
  const _ProfileQuickRecordRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: TrainFlowTokens.purpleSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SizedBox.square(
                    dimension: 44,
                    child: Icon(icon, color: TrainFlowTokens.purple, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: TrainFlowTokens.brandDark,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: TrainFlowTokens.textMuted,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  trailing,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: TrainFlowTokens.brandDark,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: TrainFlowTokens.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
