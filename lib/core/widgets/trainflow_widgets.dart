import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/trainmate_visual_mode.dart';
import '../theme/trainflow_tokens.dart';
import 'trainmate_action_character.dart';

export '../theme/trainflow_tokens.dart'
    show TrainFlowTokens, TrainFlowCardTone, TrainFlowHeaderVariant,
        TrainFlowPageLayout;
export 'trainmate_back_button.dart';

class TrainFlowPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? leading;
  final Widget? action;
  final Widget? artwork;
  final String? eyebrow;
  final TrainFlowHeaderVariant? headerVariant;
  final TrainFlowPageLayout layout;
  final bool includeDisclaimer;
  final bool animateChildren;
  final Widget? bottom;

  const TrainFlowPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.leading,
    this.action,
    this.artwork,
    this.eyebrow,
    this.headerVariant,
    this.layout = TrainFlowPageLayout.detail,
    this.includeDisclaimer = true,
    this.animateChildren = false,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final TrainFlowHeaderVariant resolvedHeaderVariant = headerVariant ??
        switch (layout) {
          TrainFlowPageLayout.detail ||
          TrainFlowPageLayout.report =>
            TrainFlowHeaderVariant.organic,
          TrainFlowPageLayout.form ||
          TrainFlowPageLayout.legal =>
            TrainFlowHeaderVariant.compact,
        };
    final Color pageBackground = switch (layout) {
      TrainFlowPageLayout.report => TrainFlowTokens.darkTrainingRaised,
      TrainFlowPageLayout.legal => TrainFlowTokens.darkTrainingCard,
      TrainFlowPageLayout.detail ||
      TrainFlowPageLayout.form =>
        TrainFlowTokens.darkTrainingSurface,
    };
    final Widget header = switch (resolvedHeaderVariant) {
      TrainFlowHeaderVariant.organic => OrganicPageHeader(
          title: title,
          subtitle: subtitle,
          leading: leading,
          action: action,
          artwork: artwork,
          eyebrow: eyebrow,
        ),
      TrainFlowHeaderVariant.compact => _CompactPageHeader(
          title: title,
          subtitle: subtitle,
          leading: leading,
          action: action,
          artwork: artwork,
          eyebrow: eyebrow,
        ),
      TrainFlowHeaderVariant.none => const SizedBox.shrink(),
    };

    return TrainMateVisualScope(
      mode: TrainMateVisualMode.darkTraining,
      child: Theme(
        data: TrainMateVisualScope.darkHubTheme(context),
        child: ColoredBox(
          key: ValueKey<String>('trainflow-page-layout-${layout.name}'),
          color: TrainFlowTokens.darkTrainingSurface,
          child: Center(
            child: ConstrainedBox(
              key: const ValueKey<String>('trainflow-mobile-canvas'),
              constraints: const BoxConstraints(
                maxWidth: TrainFlowTokens.pageMaxWidth,
              ),
              child: ColoredBox(
                color: pageBackground,
                child: SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            header,
                            DecoratedBox(
                              key: const ValueKey<String>(
                                'trainflow-page-content-surface',
                              ),
                              decoration: BoxDecoration(
                                color: pageBackground,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(
                                    TrainFlowTokens.sectionRadius,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    for (int index = 0;
                                        index < children.length;
                                        index++)
                                      Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          TrainFlowTokens.pageGutter,
                                          index == 0 ? 8 : 0,
                                          TrainFlowTokens.pageGutter,
                                          0,
                                        ),
                                        child: animateChildren
                                            ? MotionEntrance(
                                                index: index,
                                                child: children[index],
                                              )
                                            : children[index],
                                      ),
                                    if (includeDisclaimer)
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          TrainFlowTokens.pageGutter,
                                          4,
                                          TrainFlowTokens.pageGutter,
                                          24,
                                        ),
                                        child: TrainFlowMedicalDisclaimer(),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (bottom != null) bottom!,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OrganicPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? action;
  final Widget? artwork;
  final String? eyebrow;

  const OrganicPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.action,
    this.artwork,
    this.eyebrow,
  });

  @override
  Widget build(BuildContext context) {
    final Widget effectiveArtwork = artwork ??
        const TrainMateActionCharacter(
          action: TrainMateAction.running,
          backgroundColor: TrainFlowTokens.darkTrainingRaised,
        );
    return SizedBox(
      key: const ValueKey<String>('trainflow-organic-header'),
      height: 170,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: const _OrganicHeaderClipper(),
              child: const ColoredBox(color: TrainFlowTokens.darkTrainingRaised),
            ),
          ),
          if (leading != null)
            Positioned(
              left: 8,
              top: 8,
              child: IconTheme(
                data: const IconThemeData(color: AppColors.white),
                child: leading!,
              ),
            ),
          Positioned(
            left: leading == null ? 20 : 64,
            top: 20,
            right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: 104,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null) ...[
                          Text(
                            eyebrow!,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: TrainFlowTokens.accent,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 5),
                        ],
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: AppColors.white,
                                fontSize: 24,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 7),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 270),
                            child: Text(
                              subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppColors.white.withValues(
                                      alpha: 0.76,
                                    ),
                                    height: 1.35,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (action != null)
                  IconTheme(
                    data: const IconThemeData(color: AppColors.white),
                    child: action!,
                  ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: effectiveArtwork,
          ),
        ],
      ),
    );
  }
}

class MotionEntrance extends StatefulWidget {
  final Widget child;
  final int index;

  const MotionEntrance({
    super.key,
    required this.child,
    this.index = 0,
  });

  @override
  State<MotionEntrance> createState() => _MotionEntranceState();
}

class _MotionEntranceState extends State<MotionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final int delayMs = math.min(
      widget.index * TrainFlowMotion.cardStagger.inMilliseconds,
      80,
    );
    final int totalMs = TrainFlowMotion.entrance.inMilliseconds + delayMs;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        totalMs == 0 ? 0 : delayMs / totalMs,
        1,
        curve: TrainFlowMotion.easeOut,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    if (TrainFlowMotion.isEnabled(context)) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - _animation.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class TrainFlowCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final TrainFlowCardTone tone;
  final int? entranceIndex;
  final TrainMateAction? cornerCharacterAction;
  final double cornerCharacterSize;
  final String? cornerCharacterSemanticLabel;

  const TrainFlowCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.tone = TrainFlowCardTone.paper,
    this.entranceIndex,
    this.cornerCharacterAction,
    this.cornerCharacterSize = 64,
    this.cornerCharacterSemanticLabel,
  });

  @override
  State<TrainFlowCard> createState() => _TrainFlowCardState();
}

class _TrainFlowCardState extends State<TrainFlowCard> {
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant TrainFlowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onTap == null) {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TrainMateVisualScope? visualScope =
        TrainMateVisualScope.maybeOf(context);
    final bool scoped = visualScope != null;
    final bool dark = visualScope?.mode == TrainMateVisualMode.darkTraining;
    final Color background = scoped
        ? switch (widget.tone) {
            TrainFlowCardTone.paper => dark
                ? TrainFlowTokens.darkTrainingCard
                : TrainFlowTokens.lightCompanionCard,
            TrainFlowCardTone.ink => dark
                ? TrainFlowTokens.darkTrainingHighest
                : TrainFlowTokens.lightCompanionOnSurface,
            // 旧的 peach 语义在暖黑主标签中只表示“较高层级”，
            // 青柠仅保留给主操作、选中态与关键进度。
            TrainFlowCardTone.peach => dark
                ? TrainFlowTokens.darkTrainingHighest
                : TrainFlowTokens.lightCompanionCard,
            TrainFlowCardTone.outline => dark
                ? TrainFlowTokens.darkTrainingRaised
                : TrainFlowTokens.lightCompanionCard,
          }
        : switch (widget.tone) {
            TrainFlowCardTone.paper => AppColors.cardBackground,
            TrainFlowCardTone.ink => AppColors.primary,
            TrainFlowCardTone.peach => AppColors.primaryLight,
            TrainFlowCardTone.outline => AppColors.background,
          };
    final bool highContrast =
        scoped && (dark || widget.tone == TrainFlowCardTone.ink);
    final Color foreground = highContrast
        ? TrainFlowTokens.darkTrainingOnSurface
        : TrainMateVisualScope.foreground(context);
    final Widget content = widget.cornerCharacterAction == null
        ? widget.child
        : Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  right: widget.cornerCharacterSize + 8,
                ),
                child: widget.child,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  key: const ValueKey<String>(
                    'trainflow-card-corner-character',
                  ),
                  child: TrainMateActionCharacter(
                    action: widget.cornerCharacterAction!,
                    size: widget.cornerCharacterSize,
                    backgroundColor: background,
                    semanticLabel: widget.cornerCharacterSemanticLabel,
                  ),
                ),
              ),
            ],
          );
    final bool motionEnabled = TrainFlowMotion.isEnabled(context);
    final double scale =
        widget.onTap != null && motionEnabled && _pressed ? 0.97 : 1;
    final Widget card = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedScale(
        scale: scale,
        duration: TrainFlowMotion.resolve(context, TrainFlowMotion.button),
        curve: TrainFlowMotion.easeOut,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(
            scoped
                ? TrainFlowTokens.mainTabCardRadius
                : TrainFlowTokens.cardRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            excludeFromSemantics: widget.onTap == null,
            onHighlightChanged: widget.onTap == null
                ? null
                : (bool highlighted) {
                    if (_pressed != highlighted) {
                      setState(() => _pressed = highlighted);
                    }
                  },
            borderRadius: BorderRadius.circular(
              scoped
                  ? TrainFlowTokens.mainTabCardRadius
                  : TrainFlowTokens.cardRadius,
            ),
            child: Container(
              width: double.infinity,
              padding: widget.padding,
              decoration: BoxDecoration(
                border: scoped
                    ? null
                    : Border.all(
                        color: AppColors.border,
                        width: TrainFlowTokens.borderWidth,
                      ),
                borderRadius: BorderRadius.circular(
                  scoped
                      ? TrainFlowTokens.mainTabCardRadius
                      : TrainFlowTokens.cardRadius,
                ),
              ),
              child: widget.tone == TrainFlowCardTone.ink || scoped
                  ? DefaultTextStyle.merge(
                      style: TextStyle(color: foreground),
                      child: IconTheme(
                        data: IconThemeData(
                          color: TrainFlowTokens.accent,
                        ),
                        child: content,
                      ),
                    )
                  : content,
            ),
          ),
        ),
      ),
    );
    if (widget.entranceIndex == null) {
      return card;
    }
    return MotionEntrance(index: widget.entranceIndex!, child: card);
  }
}

class TrainFlowExpandable extends StatefulWidget {
  final String title;
  final String summary;
  final Widget child;
  final int summaryMaxLines;
  final bool initiallyExpanded;

  const TrainFlowExpandable({
    super.key,
    required this.title,
    required this.summary,
    required this.child,
    this.summaryMaxLines = 1,
    this.initiallyExpanded = false,
  }) : assert(summaryMaxLines > 0);

  @override
  State<TrainFlowExpandable> createState() => _TrainFlowExpandableState();
}

class _TrainFlowExpandableState extends State<TrainFlowExpandable> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Duration duration = TrainFlowMotion.resolve(
      context,
      TrainFlowMotion.selection,
    );
    final bool scoped = TrainMateVisualScope.maybeOf(context) != null;
    final Color summaryColor = scoped
        ? TrainMateVisualScope.muted(context)
        : AppColors.textSecondary;
    final Widget detail = _expanded
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: widget.child,
          )
        : const SizedBox(width: double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '${widget.title}，${widget.summary}',
          container: true,
          button: true,
          expanded: _expanded,
          onTap: _toggle,
          excludeSemantics: true,
          child: Material(
            color: AppColors.transparent,
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(
                TrainFlowTokens.cardRadius,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (!_expanded) ...[
                            const SizedBox(height: 3),
                            Text(
                              widget.summary,
                              maxLines: widget.summaryMaxLines,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: summaryColor,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: duration,
                      curve: TrainFlowMotion.easeOut,
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (duration == Duration.zero)
          detail
        else
          ClipRect(
            child: AnimatedSize(
              duration: duration,
              curve: TrainFlowMotion.easeOut,
              alignment: Alignment.topCenter,
              child: detail,
            ),
          ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onActionTap;

  const SectionTitle({
    super.key,
    required this.title,
    this.actionText,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool scoped = TrainMateVisualScope.maybeOf(context) != null;
    final Color foreground = scoped
        ? TrainMateVisualScope.foreground(context)
        : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 6,
            decoration: BoxDecoration(
              color: scoped ? TrainFlowTokens.accent : AppColors.secondary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
            ),
          ),
          if (actionText != null)
            TextButton(
              onPressed: onActionTap,
              child: Text(actionText!),
            ),
        ],
      ),
    );
  }
}

class MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const MetricPill({
    super.key,
    required this.label,
    required this.value,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final bool scoped = TrainMateVisualScope.maybeOf(context) != null;
    if (scoped) {
      final bool dark = TrainMateVisualScope.isDark(context);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: dark
              ? TrainFlowTokens.darkTrainingRaised
              : TrainFlowTokens.lightCompanionCard,
          borderRadius:
              BorderRadius.circular(TrainFlowTokens.mainTabControlRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TrainMateVisualScope.muted(context),
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: TrainMateVisualScope.foreground(context),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      );
    }
    final bool isBrandAccent = color == AppColors.secondary;
    final Color foreground = isBrandAccent ? AppColors.primary : color;
    final Color background =
        isBrandAccent ? AppColors.primaryLight : color.withValues(alpha: 0.09);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: AppColors.primary, width: 1.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
          ),
        ],
      ),
    );
  }
}

class ToneBadge extends StatelessWidget {
  final String label;
  final Color color;

  const ToneBadge({
    super.key,
    required this.label,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final bool scoped = TrainMateVisualScope.maybeOf(context) != null;
    if (scoped) {
      final bool dark = TrainMateVisualScope.isDark(context);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: dark
              ? TrainFlowTokens.darkTrainingHighest
              : TrainFlowTokens.lightCompanionSurface,
          borderRadius:
              BorderRadius.circular(TrainFlowTokens.mainTabControlRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: TrainMateVisualScope.foreground(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      );
    }
    final bool isPeach = color == AppColors.secondary;
    final Color foreground = isPeach ? AppColors.primary : color;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isPeach ? AppColors.primaryLight : color.withValues(alpha: 0.1),
        border: Border.all(color: foreground, width: 1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final bool scoped = TrainMateVisualScope.maybeOf(context) != null;
    final Color labelColor = scoped
        ? TrainMateVisualScope.muted(context)
        : AppColors.textSecondary;
    final Color valueColor = scoped
        ? TrainMateVisualScope.foreground(context)
        : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: labelColor,
                    letterSpacing: 0,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? action;
  final Widget? artwork;
  final String? eyebrow;

  const _CompactPageHeader({
    required this.title,
    this.subtitle,
    this.leading,
    this.action,
    this.artwork,
    this.eyebrow,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            IconTheme(
              data: const IconThemeData(
                color: TrainFlowTokens.darkTrainingOnSurface,
              ),
              child: leading!,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: TrainFlowTokens.accent,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: TrainFlowTokens.darkTrainingOnSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: TrainFlowTokens.darkTrainingMuted,
                          letterSpacing: 0,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (artwork != null) ...[
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints.tightFor(
                width: 72,
                height: 72,
              ),
              child: FittedBox(child: artwork!),
            ),
          ],
          if (action != null) ...[
            const SizedBox(width: 8),
            action!,
          ],
        ],
      ),
    );
  }
}

class _OrganicHeaderClipper extends CustomClipper<Path> {
  const _OrganicHeaderClipper();

  @override
  Path getClip(Size size) {
    final double base = size.height - 25;
    return Path()
      ..lineTo(0, base - 10)
      ..cubicTo(
        size.width * 0.18,
        base + 15,
        size.width * 0.34,
        base - 17,
        size.width * 0.52,
        base + 2,
      )
      ..cubicTo(
        size.width * 0.70,
        base + 20,
        size.width * 0.84,
        base - 9,
        size.width,
        base + 7,
      )
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant _OrganicHeaderClipper oldClipper) {
    return false;
  }
}

class TrainFlowMedicalDisclaimer extends StatelessWidget {
  const TrainFlowMedicalDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    final bool scoped = TrainMateVisualScope.maybeOf(context) != null;
    final Color color = scoped
        ? TrainMateVisualScope.muted(context)
        : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '免责声明：本系统提供训练建议，不替代医生或物理治疗师诊断；明显疼痛、持续疼痛或疼痛 ≥7 分时请停止相关训练并就医。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              height: 1.45,
              letterSpacing: 0,
            ),
      ),
    );
  }
}

Color readinessColor(int score) {
  if (score >= 82) {
    return AppColors.success;
  }
  if (score >= 66) {
    return AppColors.primary;
  }
  if (score >= 52) {
    return AppColors.warningDark;
  }
  return AppColors.danger;
}
