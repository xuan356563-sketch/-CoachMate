import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/trainflow_tokens.dart';

/// 功能色语义（计划 5.2：紫/黄/粉/珊瑚/蓝/薄荷绿 + 中性）。
///
/// 每个 tone 提供一套「前景 + 浅底」配对，浅色文字一律使用更深的可读色，
/// 避免把低对比度文字直接放到高饱和底色上。
enum TrainMateTone { purple, yellow, pink, coral, blue, mint, neutral }

extension TrainMateTonePalette on TrainMateTone {
  Color get foreground {
    switch (this) {
      case TrainMateTone.purple:
        return const Color(0xFF6C3DF4);
      case TrainMateTone.yellow:
        return const Color(0xFF7A5B00);
      case TrainMateTone.pink:
        return const Color(0xFFC0449B);
      case TrainMateTone.coral:
        return const Color(0xFFD43D33);
      case TrainMateTone.blue:
        return const Color(0xFF2563C4);
      case TrainMateTone.mint:
        return const Color(0xFF1F9E6E);
      case TrainMateTone.neutral:
        return TrainFlowTokens.darkTrainingMuted;
    }
  }

  Color get background {
    switch (this) {
      case TrainMateTone.purple:
        return const Color(0xFFEEE8FF);
      case TrainMateTone.yellow:
        return const Color(0xFFFFF4CC);
      case TrainMateTone.pink:
        return const Color(0xFFFDE7F6);
      case TrainMateTone.coral:
        return const Color(0xFFFFE7E4);
      case TrainMateTone.blue:
        return const Color(0xFFE3EEFF);
      case TrainMateTone.mint:
        return const Color(0xFFDFF7EC);
      case TrainMateTone.neutral:
        return TrainFlowTokens.darkTrainingRaised;
    }
  }
}

enum TrainMateButtonVariant { primary, secondary, tertiary, destructive }

enum TrainMateButtonSize { large, medium, small }

/// 按钮系统（计划 7.7）：Primary / Secondary / Tertiary / Destructive，
/// 支持 loading 与 disabled 状态，以及可选图标。
class TrainMateButton extends StatelessWidget {
  const TrainMateButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = TrainMateButtonVariant.primary,
    this.size = TrainMateButtonSize.medium,
    this.icon,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final TrainMateButtonVariant variant;
  final TrainMateButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool expand;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle style = _style();
    final Widget child = _buildContent();
    Widget button;
    switch (variant) {
      case TrainMateButtonVariant.tertiary:
        button = TextButton(
          onPressed: _enabled ? onPressed : null,
          style: style,
          child: child,
        );
        break;
      default:
        button = FilledButton(
          onPressed: _enabled ? onPressed : null,
          style: style,
          child: child,
        );
    }
    if (expand) {
      button = SizedBox(width: double.infinity, child: button);
    }
    return button;
  }

  ButtonStyle _style() {
    final (Color fg, Color bg) = _colors();
    final BorderRadius radius = BorderRadius.circular(
      variant == TrainMateButtonVariant.tertiary
          ? TrainFlowTokens.controlRadius
          : TrainFlowTokens.pillRadius,
    );
    final EdgeInsets padding = switch (size) {
      TrainMateButtonSize.large => const EdgeInsets.symmetric(horizontal: 24),
      TrainMateButtonSize.medium => const EdgeInsets.symmetric(horizontal: 20),
      TrainMateButtonSize.small => const EdgeInsets.symmetric(horizontal: 16),
    };
    final Size minSize = switch (size) {
      TrainMateButtonSize.large => const Size(52, 52),
      TrainMateButtonSize.medium => const Size(48, 48),
      TrainMateButtonSize.small => const Size(36, 36),
    };
    return ButtonStyle(
      minimumSize: WidgetStateProperty.all(minSize),
      padding: WidgetStateProperty.all(padding),
      shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: radius)),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return TrainFlowTokens.darkTrainingRaised;
        }
        return bg;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return TrainFlowTokens.darkTrainingTextTertiary;
        }
        return fg;
      }),
      elevation: variant == TrainMateButtonVariant.primary
          ? WidgetStateProperty.all(0)
          : WidgetStateProperty.all(0),
      textStyle: WidgetStateProperty.all(
        TextStyle(
          fontSize: switch (size) {
            TrainMateButtonSize.large => 16,
            TrainMateButtonSize.medium => 15,
            TrainMateButtonSize.small => 13,
          },
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }

  (Color, Color) _colors() {
    return switch (variant) {
      TrainMateButtonVariant.primary => (
          TrainFlowTokens.onAccent,
          TrainFlowTokens.accent,
        ),
      TrainMateButtonVariant.secondary => (
          TrainFlowTokens.accent,
          TrainFlowTokens.accentLight,
        ),
      TrainMateButtonVariant.tertiary => (
          TrainFlowTokens.accent,
          Colors.transparent,
        ),
      TrainMateButtonVariant.destructive => (
          Colors.white,
          TrainFlowTokens.error,
        ),
    };
  }

  Widget _buildContent() {
    if (loading) {
      return SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: TrainFlowTokens.darkTrainingTextTertiary,
        ),
      );
    }
    final Widget text = Text(label);
    if (icon == null) {
      return text;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        text,
      ],
    );
  }
}

enum TrainMateIconButtonTone { neutral, filled, outline }

/// 图标按钮（计划 7.7 Icon Button）：触控区域 >= 44pt，带可访问名称。
class TrainMateIconButton extends StatelessWidget {
  const TrainMateIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.tone = TrainMateIconButtonTone.neutral,
    this.size = 44,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final TrainMateIconButtonTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color bg = switch (tone) {
      TrainMateIconButtonTone.filled => TrainFlowTokens.accent,
      TrainMateIconButtonTone.outline => TrainFlowTokens.paper,
      TrainMateIconButtonTone.neutral => Colors.transparent,
    };
    final Color fg = switch (tone) {
      TrainMateIconButtonTone.filled => TrainFlowTokens.onAccent,
      TrainMateIconButtonTone.outline => TrainFlowTokens.brandDark,
      TrainMateIconButtonTone.neutral => TrainFlowTokens.darkTrainingMuted,
    };
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: onPressed != null,
        child: IconButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: onPressed == null
                ? TrainFlowTokens.darkTrainingRaised
                : bg,
            foregroundColor: onPressed == null
                ? TrainFlowTokens.darkTrainingTextTertiary
                : fg,
            minimumSize: Size.square(math.max(size, 44)),
            side: tone == TrainMateIconButtonTone.outline
                ? const BorderSide(color: TrainFlowTokens.border)
                : BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TrainFlowTokens.controlRadius),
            ),
          ),
          icon: Icon(icon, size: math.min(size - 8, 22)),
        ),
      ),
    );
  }
}

/// 徽章（计划 7 阶段 2 Badge）：胶囊标签，支持图标与前置圆点。
class TrainMateBadge extends StatelessWidget {
  const TrainMateBadge({
    super.key,
    required this.label,
    this.tone = TrainMateTone.neutral,
    this.icon,
    this.dot = false,
  });

  final String label;
  final TrainMateTone tone;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(TrainFlowTokens.pillRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (dot)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: tone.foreground,
                    shape: BoxShape.circle,
                  ),
                ),
              if (icon != null) ...<Widget>[
                Icon(icon, size: 14, color: tone.foreground),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tone.foreground,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 连续打卡徽章（火焰）。
class TrainMateStreakBadge extends StatelessWidget {
  const TrainMateStreakBadge({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return TrainMateBadge(
      label: '连续 $days 天',
      tone: TrainMateTone.coral,
      icon: Icons.local_fire_department_rounded,
      dot: true,
    );
  }
}

/// 等级徽章。
class TrainMateLevelBadge extends StatelessWidget {
  const TrainMateLevelBadge({super.key, required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return TrainMateBadge(
      label: 'Lv.$level',
      tone: TrainMateTone.purple,
      icon: Icons.workspace_premium_rounded,
    );
  }
}

/// 奖励徽章。
class TrainMateRewardBadge extends StatelessWidget {
  const TrainMateRewardBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return TrainMateBadge(
      label: label,
      tone: TrainMateTone.yellow,
      icon: Icons.card_giftcard_rounded,
      dot: true,
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.shortestSide - strokeWidth) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    final Paint trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);
    final double clamped = value.clamp(0.0, 1.0);
    if (clamped > 0) {
      final Paint valuePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * clamped, false, valuePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// 环形进度（计划 7.3 / 阶段 2 ProgressRing）。
class TrainMateProgressRing extends StatelessWidget {
  const TrainMateProgressRing({
    super.key,
    required this.value,
    this.size = 72,
    this.strokeWidth = 8,
    this.color = TrainFlowTokens.accent,
    this.trackColor = TrainFlowTokens.darkTrainingRaised,
    this.child,
    this.semanticLabel,
  });

  final double value;
  final double size;
  final double strokeWidth;
  final Color color;
  final Color trackColor;
  final Widget? child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final String label = semanticLabel ??
        '进度 ${(value.clamp(0.0, 1.0) * 100).round()}%';
    return Semantics(
      container: true,
      label: label,
      value: '${(value.clamp(0.0, 1.0) * 100).round()}%',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _ProgressRingPainter(
            value: value,
            color: color,
            trackColor: trackColor,
            strokeWidth: strokeWidth,
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

/// 线性进度条。
class TrainMateProgressBar extends StatelessWidget {
  const TrainMateProgressBar({
    super.key,
    required this.value,
    this.color = TrainFlowTokens.accent,
    this.trackColor = TrainFlowTokens.darkTrainingRaised,
    this.height = 8,
    this.semanticLabel,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final double clamped = value.clamp(0.0, 1.0);
    return Semantics(
      container: true,
      label: semanticLabel ?? '进度 ${(clamped * 100).round()}%',
      value: '${(clamped * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Stack(
              children: <Widget>[
                Container(height: height, color: trackColor),
                FractionallySizedBox(
                  widthFactor: clamped,
                  child: Container(height: height, color: color),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
