import 'package:flutter/material.dart';

import '../theme/trainflow_tokens.dart';
import 'trainmate_primitives.dart';

/// 骨架屏块（计划 11.1）：静态占位，不绑定业务数据，无持续动画
/// （避免破坏测试的 pumpAndSettle）。
class TrainMateSkeleton extends StatelessWidget {
  const TrainMateSkeleton({
    super.key,
    this.size,
    this.width,
    this.height,
    this.radius = 8,
    this.shape = BoxShape.rectangle,
  });

  final Size? size;
  final double? width;
  final double? height;
  final double radius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size?.width ?? width,
        height: size?.height ?? height,
        decoration: BoxDecoration(
          color: TrainFlowTokens.darkTrainingRaised,
          shape: shape,
          borderRadius: shape == BoxShape.rectangle
              ? BorderRadius.circular(radius)
              : null,
        ),
      ),
    );
  }
}

/// 骨架屏行（头像 + 两行文字占位）。
class TrainMateSkeletonListTile extends StatelessWidget {
  const TrainMateSkeletonListTile({super.key, this.showAvatar = true});

  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          if (showAvatar) ...<Widget>[
            const TrainMateSkeleton(size: Size(44, 44), shape: BoxShape.circle),
            const SizedBox(width: 12),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TrainMateSkeleton(height: 16),
                SizedBox(height: 8),
                TrainMateSkeleton(height: 12, width: 140),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 统一空状态（计划 11.2）：插画/图标 + 标题 + 说明 + 操作按钮。
class TrainMateEmptyState extends StatelessWidget {
  const TrainMateEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title，$message',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: TrainFlowTokens.accentLight,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SizedBox.square(
                dimension: 72,
                child: Icon(icon, size: 34, color: TrainFlowTokens.accent),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: TrainFlowTokens.darkTrainingOnSurface,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
                  ),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 18),
              TrainMateButton(
                label: actionLabel!,
                onPressed: onAction,
                variant: TrainMateButtonVariant.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 统一错误状态（计划 11.3）：错误说明 + 重试按钮。
class TrainMateErrorState extends StatelessWidget {
  const TrainMateErrorState({
    super.key,
    this.title = '加载失败',
    required this.message,
    this.onRetry,
    this.retryLabel = '重试',
    this.icon = Icons.error_outline_rounded,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title，$message',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: TrainFlowTokens.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
              ),
              child: SizedBox.square(
                dimension: 72,
                child: Icon(icon, size: 34, color: TrainFlowTokens.error),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: TrainFlowTokens.darkTrainingOnSurface,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
                  ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 18),
              TrainMateButton(
                label: retryLabel,
                onPressed: onRetry,
                variant: TrainMateButtonVariant.secondary,
                icon: Icons.refresh_rounded,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum TrainMateToastTone { neutral, success, warning, error }

/// 轻提示（计划 11 状态反馈 / 阶段 2 Toast）。
class TrainMateToast extends StatelessWidget {
  const TrainMateToast({
    super.key,
    required this.message,
    this.tone = TrainMateToastTone.neutral,
    this.icon,
  });

  final String message;
  final TrainMateToastTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, IconData defaultIcon) = switch (tone) {
      TrainMateToastTone.neutral => (
          TrainFlowTokens.darkTrainingOnSurface,
          TrainFlowTokens.darkTrainingRaised,
          Icons.info_outline_rounded,
        ),
      TrainMateToastTone.success => (
          TrainFlowTokens.success,
          TrainFlowTokens.mint.withValues(alpha: 0.2),
          Icons.check_circle_outline_rounded,
        ),
      TrainMateToastTone.warning => (
          TrainFlowTokens.warning,
          TrainFlowTokens.yellow.withValues(alpha: 0.25),
          Icons.warning_amber_rounded,
        ),
      TrainMateToastTone.error => (
          TrainFlowTokens.error,
          TrainFlowTokens.error.withValues(alpha: 0.12),
          Icons.error_outline_rounded,
        ),
    };
    return Semantics(
      liveRegion: true,
      label: message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(TrainFlowTokens.pillRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon ?? defaultIcon, size: 18, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 通过 [ScaffoldMessenger] 弹出浮动 Toast。
void showTrainMateToast(
  BuildContext context,
  String message, {
  TrainMateToastTone tone = TrainMateToastTone.neutral,
  IconData? icon,
}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: TrainMateToast(message: message, tone: tone, icon: icon),
        duration: const Duration(milliseconds: 2600),
      ),
    );
}
