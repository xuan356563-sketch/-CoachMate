import 'package:flutter/material.dart';

import '../theme/trainflow_tokens.dart';
import 'trainmate_primitives.dart';
import 'trainmate_states.dart';

/// 数据指标卡（计划 7.5）：图标 + 数值 + 单位 + 标签 + 趋势，支持骨架屏状态。
class TrainMateStatCard extends StatelessWidget {
  const TrainMateStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.unit,
    this.tone = TrainMateTone.purple,
    this.trend,
    this.trendUp = true,
    this.loading = false,
    this.onTap,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final TrainMateTone tone;
  final String? trend;
  final bool trendUp;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const _StatCardSkeleton();
    }
    final Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: TrainFlowTokens.darkTrainingCard,
        borderRadius: BorderRadius.circular(TrainFlowTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tone.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SizedBox.square(
                    dimension: 40,
                    child: Icon(icon, size: 22, color: tone.foreground),
                  ),
                ),
                const Spacer(),
                if (trend != null)
                  _TrendChip(label: trend!, up: trendUp),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: TrainFlowTokens.darkTrainingOnSurface,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                  ),
                ),
                if (unit != null) ...<Widget>[
                  const SizedBox(width: 4),
                  Text(
                    unit!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TrainFlowTokens.darkTrainingMuted,
                        ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
                  ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) {
      return card;
    }
    return Semantics(button: true, label: '$label $value', child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TrainFlowTokens.cardRadius),
      child: card,
    ));
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.label, required this.up});

  final String label;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final Color color = up
        ? TrainFlowTokens.success
        : TrainFlowTokens.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TrainFlowTokens.pillRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCardSkeleton extends StatelessWidget {
  const _StatCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TrainFlowTokens.darkTrainingCard,
        borderRadius: BorderRadius.circular(TrainFlowTokens.cardRadius),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TrainMateSkeleton(size: Size(40, 40), radius: 14),
            SizedBox(height: 14),
            TrainMateSkeleton(size: Size(96, 22)),
            SizedBox(height: 8),
            TrainMateSkeleton(size: Size(64, 14)),
          ],
        ),
      ),
    );
  }
}

/// 挑战卡片状态（计划 7.4）。
enum TrainMateChallengeStatus {
  available,
  active,
  completed,
  expired,
  locked,
  failed,
}

extension TrainMateChallengeStatusMeta on TrainMateChallengeStatus {
  String get actionLabel {
    switch (this) {
      case TrainMateChallengeStatus.available:
        return '立即参加';
      case TrainMateChallengeStatus.active:
        return '继续挑战';
      case TrainMateChallengeStatus.completed:
        return '查看成果';
      case TrainMateChallengeStatus.expired:
        return '已结束';
      case TrainMateChallengeStatus.locked:
        return '解锁条件';
      case TrainMateChallengeStatus.failed:
        return '重新加载';
    }
  }

  bool get actionEnabled => this != TrainMateChallengeStatus.expired &&
      this != TrainMateChallengeStatus.locked;

  String get statusLabel {
    switch (this) {
      case TrainMateChallengeStatus.available:
        return '可参加';
      case TrainMateChallengeStatus.active:
        return '进行中';
      case TrainMateChallengeStatus.completed:
        return '已完成';
      case TrainMateChallengeStatus.expired:
        return '已过期';
      case TrainMateChallengeStatus.locked:
        return '未解锁';
      case TrainMateChallengeStatus.failed:
        return '加载失败';
    }
  }
}

/// 挑战卡片（计划 7.4）：原创主题图标 + 标题 + 进度 + 元信息 + 状态按钮。
class TrainMateChallengeCard extends StatelessWidget {
  const TrainMateChallengeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.progress,
    required this.icon,
    this.progressLabel,
    this.remaining,
    this.reward,
    this.participants,
    this.tone = TrainMateTone.purple,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final TrainMateChallengeStatus status;
  final double progress;
  final IconData icon;
  final String? progressLabel;
  final String? remaining;
  final String? reward;
  final int? participants;
  final TrainMateTone tone;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TrainFlowTokens.darkTrainingCard,
          borderRadius: BorderRadius.circular(TrainFlowTokens.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tone.background,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: SizedBox.square(
                      dimension: 56,
                      child: Icon(icon, size: 30, color: tone.foreground),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: TrainFlowTokens.darkTrainingOnSurface,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: TrainFlowTokens.darkTrainingMuted,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TrainMateBadge(label: status.statusLabel, tone: _statusTone()),
                ],
              ),
              const SizedBox(height: 14),
              TrainMateProgressBar(
                value: progress,
                color: tone.foreground,
                semanticLabel: progressLabel ?? title,
              ),
              const SizedBox(height: 6),
              Text(
                progressLabel ?? '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
              if (remaining != null || reward != null || participants != null) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    if (remaining != null) _MetaItem(
                      icon: Icons.schedule_rounded,
                      text: remaining!,
                    ),
                    if (reward != null) _MetaItem(
                      icon: Icons.card_giftcard_rounded,
                      text: reward!,
                    ),
                    if (participants != null) _MetaItem(
                      icon: Icons.groups_rounded,
                      text: '$participants 人',
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              TrainMateButton(
                label: status.actionLabel,
                onPressed: status.actionEnabled ? onAction : null,
                variant: status == TrainMateChallengeStatus.active
                    ? TrainMateButtonVariant.secondary
                    : TrainMateButtonVariant.primary,
                size: TrainMateButtonSize.medium,
                expand: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  TrainMateTone _statusTone() {
    switch (status) {
      case TrainMateChallengeStatus.available:
        return TrainMateTone.blue;
      case TrainMateChallengeStatus.active:
        return TrainMateTone.purple;
      case TrainMateChallengeStatus.completed:
        return TrainMateTone.mint;
      case TrainMateChallengeStatus.expired:
        return TrainMateTone.neutral;
      case TrainMateChallengeStatus.locked:
        return TrainMateTone.neutral;
      case TrainMateChallengeStatus.failed:
        return TrainMateTone.coral;
    }
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: TrainFlowTokens.darkTrainingMuted),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }
}
