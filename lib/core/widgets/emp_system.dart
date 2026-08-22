import 'package:flutter/material.dart';

import '../theme/trainflow_tokens.dart';
import 'trainmate_action_character.dart';

/// 环形进度：深紫进度弧 + 浅色轨道 + 中心值。
class EmpProgressRing extends StatelessWidget {
  const EmpProgressRing({
    super.key,
    required this.progress,
    this.size = 72,
    this.label,
    this.strokeWidth = 8,
    this.color = TrainFlowTokens.accent,
    this.trackColor = TrainFlowTokens.darkTrainingRaised,
  });

  final double progress; // 0..1
  final double size;
  final String? label;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final double safe = progress.clamp(0, 1);
    return Semantics(
      label: label ?? '进度 ${(safe * 100).round()}%',
      value: '${(safe * 100).round()}',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _ProgressRingPainter(
            progress: safe,
            strokeWidth: strokeWidth,
            color: color,
            trackColor: trackColor,
          ),
          child: label == null
              ? null
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(
                    child: Text(
                      label!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: TrainFlowTokens.darkTrainingOnSurface,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = (size.width - strokeWidth) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    final Paint track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    if (progress > 0) {
      final Paint value = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        rect,
        -1.5707963,
        6.2831853 * progress,
        false,
        value,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}

/// 骨架屏占位：浅灰圆角块，支持「减少动态效果」。
class EmpSkeleton extends StatefulWidget {
  const EmpSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<EmpSkeleton> createState() => _EmpSkeletonState();
}

class _EmpSkeletonState extends State<EmpSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 一次性脉冲（0→1→0），避免无限 repeat 阻塞测试 settle；减少动效下静态。
    if (TrainFlowMotion.isEnabled(context)) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: TrainFlowTokens.darkTrainingRaised.withValues(
                alpha: 0.4 + 0.4 * (_animationWave(_controller.value)),
              ),
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          );
        },
      ),
    );
  }

  double _animationWave(double t) {
    // 0..1 往返波形。
    return (t * 2) % 2 > 1 ? 2 - (t * 2) % 2 : (t * 2) % 2;
  }
}

/// 空状态：原创图标 + 标题 + 说明 + 明确操作。
class EmpEmptyState extends StatelessWidget {
  const EmpEmptyState({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String description;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title，$description',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: TrainFlowTokens.darkTrainingHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SizedBox.square(
                dimension: 64,
                child: Icon(icon, color: TrainFlowTokens.accent, size: 30),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: TrainFlowTokens.darkTrainingOnSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
                  ),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 多色功能徽章：深紫/黄/粉/蓝/薄荷绿语义。
enum EmpBadgeTone { brand, yellow, pink, blue, mint, neutral }

class EmpBadge extends StatelessWidget {
  const EmpBadge({
    super.key,
    required this.label,
    this.tone = EmpBadgeTone.brand,
    this.icon,
  });

  final String label;
  final EmpBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (tone) {
      EmpBadgeTone.brand => (
          TrainFlowTokens.accent,
          TrainFlowTokens.onAccent,
        ),
      EmpBadgeTone.yellow => (
          TrainFlowTokens.yellow,
          TrainFlowTokens.brandDark,
        ),
      EmpBadgeTone.pink => (
          TrainFlowTokens.pink,
          TrainFlowTokens.brandDark,
        ),
      EmpBadgeTone.blue => (
          TrainFlowTokens.blue,
          TrainFlowTokens.onAccent,
        ),
      EmpBadgeTone.mint => (
          TrainFlowTokens.mint,
          TrainFlowTokens.brandDark,
        ),
      EmpBadgeTone.neutral => (
          TrainFlowTokens.darkTrainingRaised,
          TrainFlowTokens.darkTrainingOnSurface,
        ),
    };
    return Semantics(
      label: '$label${icon == null ? '' : '，图标'}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(TrainFlowTokens.pillRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 高亮统计面板（参考图「大数字块」）：彩色底 + 大数字/单位 + 副值 + 分段进度。
class EmpStatPanel extends StatelessWidget {
  const EmpStatPanel({
    super.key,
    required this.value,
    required this.unit,
    this.secondary,
    this.timer,
    this.color = TrainFlowTokens.accent,
    this.foreground = TrainFlowTokens.onAccent,
    this.progress,
    this.progressColor = TrainFlowTokens.yellow,
  });

  final String value;
  final String unit;
  final String? secondary;
  final String? timer;
  final Color color;
  final Color foreground;
  final double? progress;
  final Color progressColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value $unit${secondary == null ? '' : '，${secondary!}'}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    value,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: foreground.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              if (secondary != null || timer != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  [secondary, timer].whereType<String>().join('  ·  '),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foreground.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              if (progress != null) ...<Widget>[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: foreground.withValues(alpha: 0.18),
                    color: progressColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 插画卡（参考图：纯色底 + 扁平插画 + 标题/时间 + 可选动作）。
/// 插画使用 CoachMate 原创角色 [TrainMateActionCharacter]，不复制参考图人物。
class EmpIllustrationCard extends StatelessWidget {
  const EmpIllustrationCard({
    super.key,
    required this.title,
    this.subtitle,
    this.bg = TrainFlowTokens.yellow,
    this.illustration,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final Color bg;
  final Widget? illustration;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final bool light = bg.computeLuminance() > 0.5;
    final Color fg = light
        ? TrainFlowTokens.brandDark
        : TrainFlowTokens.onAccent;
    final Widget illo = illustration ??
        TrainMateActionCharacter(
          action: TrainMateAction.running,
          size: 64,
          backgroundColor: bg,
        );
    return Semantics(
      label: '$title${subtitle == null ? '' : '，${subtitle!}'}',
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: ExcludeSemantics(child: illo),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: fg.withValues(alpha: 0.78),
                      ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: fg,
                      foregroundColor: bg,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
