import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/trainmate_visual_mode.dart';
import '../theme/trainflow_tokens.dart';
import 'trainmate_branding.dart';
import 'trainflow_widgets.dart';

/// 五个主标签共用的沉浸式场景骨架。
class TrainMateImmersiveHubPage extends StatelessWidget {
  const TrainMateImmersiveHubPage({
    super.key,
    required this.hero,
    this.children = const <Widget>[],
    this.storyChildren = const <Widget>[],
    this.paperOverviewChildren,
    this.deepActionChildren,
    this.includeDisclaimer = true,
    this.mode = TrainMateVisualMode.darkTraining,
    this.showcaseOverviewChildCount,
  }) : assert(
          showcaseOverviewChildCount == null || showcaseOverviewChildCount >= 0,
          '纸白概览数量不能小于 0',
        );

  final Widget hero;
  final List<Widget> children;

  /// 波浪下方的深紫行动区。为空时保持既有页面结构。
  final List<Widget> storyChildren;

  /// 参考图模式下显式放在纸白区的组件。
  ///
  /// 设置后不再依赖组件数量切割，避免间距组件被误算为内容。
  final List<Widget>? paperOverviewChildren;

  /// 参考图模式下显式放在深紫行动区的组件。
  final List<Widget>? deepActionChildren;
  final bool includeDisclaimer;
  final TrainMateVisualMode mode;

  /// 参考图模式下，保留在纸白区的前 N 个子组件。
  ///
  /// 其余子组件会跟随 [storyChildren] 进入波浪下方的深紫行动区。未设置时
  /// 保持旧布局，避免影响尚未迁移的调用方。
  final int? showcaseOverviewChildCount;

  @override
  Widget build(BuildContext context) {
    final bool dark = mode == TrainMateVisualMode.darkTraining;
    final Color surface = mode == TrainMateVisualMode.referenceShowcase
        ? TrainFlowTokens.showcasePaper
        : dark
            ? TrainFlowTokens.darkTrainingSurface
            : TrainFlowTokens.lightCompanionSurface;
    final ThemeData baseTheme = Theme.of(context);
    final Color foreground = dark
        ? TrainFlowTokens.darkTrainingOnSurface
        : TrainFlowTokens.lightCompanionOnSurface;
    final Color muted = dark
        ? TrainFlowTokens.darkTrainingMuted
        : TrainFlowTokens.lightCompanionMuted;
    final Color card = dark
        ? TrainFlowTokens.darkTrainingCard
        : TrainFlowTokens.lightCompanionCard;
    final Color raised = dark
        ? TrainFlowTokens.darkTrainingRaised
        : TrainFlowTokens.lightCompanionCard;
    final bool hasExplicitReferenceSections =
        mode == TrainMateVisualMode.referenceShowcase &&
            (paperOverviewChildren != null || deepActionChildren != null);
    final bool splitReferenceContent =
        mode == TrainMateVisualMode.referenceShowcase &&
            storyChildren.isNotEmpty &&
            showcaseOverviewChildCount != null;
    final int overviewCount = splitReferenceContent
        ? showcaseOverviewChildCount!.clamp(0, children.length).toInt()
        : children.length;
    final List<Widget> overviewChildren = hasExplicitReferenceSections
        ? paperOverviewChildren ?? const <Widget>[]
        : children.take(overviewCount).toList(growable: false);
    final List<Widget> actionChildren = hasExplicitReferenceSections
        ? <Widget>[
            ...storyChildren,
            ...?deepActionChildren,
          ]
        : splitReferenceContent
            ? <Widget>[
                ...storyChildren,
                ...children.skip(overviewCount),
              ]
            : storyChildren;
    final OutlineInputBorder inputBorder = OutlineInputBorder(
      borderRadius: const BorderRadius.all(
        Radius.circular(TrainFlowTokens.mainTabControlRadius),
      ),
      borderSide: BorderSide(color: raised),
    );
    final Brightness brightness = Brightness.light;
    final ColorScheme colorScheme = baseTheme.colorScheme.copyWith(
      brightness: brightness,
      primary: TrainFlowTokens.accent,
      onPrimary: TrainFlowTokens.onAccent,
      surface: surface,
      onSurface: foreground,
      surfaceContainer: card,
      surfaceContainerHigh: raised,
      surfaceContainerHighest: dark
          ? TrainFlowTokens.darkTrainingHighest
          : TrainFlowTokens.lightCompanionCard,
    );
    return Theme(
      key: const ValueKey<String>('trainmate-immersive-hub-theme'),
      data: baseTheme.copyWith(
        brightness: brightness,
        scaffoldBackgroundColor: surface,
        canvasColor: surface,
        dividerColor: raised,
        colorScheme: colorScheme,
        textTheme: baseTheme.textTheme.apply(
          bodyColor: foreground,
          displayColor: foreground,
        ),
        iconTheme: IconThemeData(color: TrainFlowTokens.accent),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: TrainFlowTokens.accent,
            foregroundColor: TrainFlowTokens.onAccent,
            minimumSize: const Size(48, 48),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(TrainFlowTokens.mainTabControlRadius),
              ),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: TrainFlowTokens.accent,
            side: BorderSide(color: raised),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(TrainFlowTokens.mainTabControlRadius),
              ),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: TrainFlowTokens.accent,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(TrainFlowTokens.mainTabControlRadius),
              ),
            ),
          ),
        ),
        inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: raised,
          labelStyle: TextStyle(color: muted),
          hintStyle: TextStyle(color: muted),
          border: inputBorder,
          enabledBorder: inputBorder,
          focusedBorder: inputBorder.copyWith(
            borderSide: const BorderSide(
              color: TrainFlowTokens.accent,
              width: 1.5,
            ),
          ),
        ),
        datePickerTheme: baseTheme.datePickerTheme.copyWith(
          backgroundColor: card,
          surfaceTintColor: Colors.transparent,
          headerBackgroundColor: raised,
          headerForegroundColor: foreground,
          dayForegroundColor: WidgetStateProperty.all(foreground),
          todayForegroundColor: WidgetStateProperty.all(TrainFlowTokens.accent),
          todayBorder: const BorderSide(color: TrainFlowTokens.accent),
        ),
        popupMenuTheme: baseTheme.popupMenuTheme.copyWith(
          color: card,
          textStyle: TextStyle(color: foreground),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(TrainFlowTokens.mainTabCardRadius),
            ),
          ),
        ),
        dialogTheme: baseTheme.dialogTheme.copyWith(
          backgroundColor: card,
          titleTextStyle: baseTheme.textTheme.titleLarge?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: baseTheme.textTheme.bodyMedium?.copyWith(
            color: muted,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(TrainFlowTokens.mainTabCardRadius),
            ),
          ),
        ),
        bottomSheetTheme: baseTheme.bottomSheetTheme.copyWith(
          backgroundColor: card,
          modalBackgroundColor: card,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(TrainFlowTokens.mainTabCardRadius),
            ),
          ),
        ),
      ),
      child: TrainMateVisualScope(
        mode: mode,
        child: ColoredBox(
          color: surface,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: TrainFlowTokens.pageMaxWidth,
              ),
              child: SafeArea(
                bottom: false,
                child: ListView(
                  key: const ValueKey<String>('trainmate-immersive-hub-page'),
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    hero,
                    if ((!splitReferenceContent &&
                            !hasExplicitReferenceSections) ||
                        overviewChildren.isNotEmpty)
                      DecoratedBox(
                        key: const ValueKey<String>(
                          'trainmate-showcase-paper-overview',
                        ),
                        decoration: BoxDecoration(color: surface),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            TrainFlowTokens.mainTabPageGutter,
                            18,
                            TrainFlowTokens.mainTabPageGutter,
                            splitReferenceContent ||
                                    hasExplicitReferenceSections
                                ? 12
                                : TrainFlowTokens.immersiveBottomContentPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              ...overviewChildren,
                              if (includeDisclaimer && actionChildren.isEmpty)
                                const TrainFlowMedicalDisclaimer(),
                            ],
                          ),
                        ),
                      ),
                    if (actionChildren.isNotEmpty)
                      TrainMateWaveActionSection(
                        children: <Widget>[
                          ...actionChildren,
                          if (includeDisclaimer)
                            const TrainFlowMedicalDisclaimer(),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 参考图语言中的纸白数据区到深紫行动区的波浪分界。
class TrainMateWaveActionSection extends StatelessWidget {
  const TrainMateWaveActionSection({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const ValueKey<String>('trainmate-wave-action-section'),
      painter: const _WaveActionSurfacePainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TrainFlowTokens.mainTabPageGutter,
          58,
          TrainFlowTokens.mainTabPageGutter,
          TrainFlowTokens.immersiveBottomContentPadding,
        ),
        child: TrainMateActionSurfaceScope(
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: TrainFlowTokens.paper),
            child: IconTheme(
              data: const IconThemeData(color: TrainFlowTokens.yellow),
              child: KeyedSubtree(
                key: const ValueKey<String>(
                  'trainmate-showcase-action-content',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 深紫行动区中的高对比行动卡，供五个主标签复用。
class TrainMateShowcaseActionCard extends StatelessWidget {
  const TrainMateShowcaseActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.artwork,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final Widget? artwork;

  @override
  Widget build(BuildContext context) {
    final Color foreground = color.computeLuminance() > 0.45
        ? TrainFlowTokens.showcaseActionSurface
        : TrainFlowTokens.paper;
    return Semantics(
      button: true,
      label: '$title，$subtitle',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Ink(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(28),
            ),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double artworkWidth =
                    constraints.maxWidth < 330 ? 68 : 88;
                return Row(
                  children: <Widget>[
                    Icon(icon, color: foreground, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: foreground.withValues(alpha: 0.76),
                                    ),
                          ),
                        ],
                      ),
                    ),
                    if (artwork != null) ...<Widget>[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: artworkWidth,
                        height: 72,
                        child: FittedBox(fit: BoxFit.contain, child: artwork),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, color: foreground),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveActionSurfacePainter extends CustomPainter {
  const _WaveActionSurfacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = TrainFlowTokens.showcaseActionSurface;
    final Path path = Path()
      ..moveTo(0, 28)
      ..cubicTo(
          size.width * 0.19, 4, size.width * 0.37, 48, size.width * 0.56, 28)
      ..cubicTo(size.width * 0.74, 8, size.width * 0.9, 40, size.width, 20)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WaveActionSurfacePainter oldDelegate) => false;
}

enum TrainMateSceneHeroStyle { immersive, referenceShowcase }

class TrainMateSceneHero extends StatelessWidget {
  const TrainMateSceneHero({
    super.key,
    required this.sceneAsset,
    required this.greeting,
    required this.dateLabel,
    required this.character,
    required this.taskTitle,
    required this.taskSubtitle,
    required this.taskIcon,
    this.taskTrailing,
    this.onTaskTap,
    this.actionTooltip,
    this.onAction,
    this.taskProgress,
    this.taskProgressLabel,
    this.style = TrainMateSceneHeroStyle.immersive,
    this.referenceBackgroundColor,
    this.characterInsets,
    this.metricOverlay,
  });

  final String sceneAsset;
  final String greeting;
  final String dateLabel;
  final Widget character;
  final String taskTitle;
  final String taskSubtitle;
  final IconData taskIcon;
  final Widget? taskTrailing;
  final VoidCallback? onTaskTap;
  final String? actionTooltip;
  final VoidCallback? onAction;
  final double? taskProgress;
  final String? taskProgressLabel;
  final TrainMateSceneHeroStyle style;
  final Color? referenceBackgroundColor;

  /// 人物在 Hero 内的安全区。默认值保持旧版布局。
  final EdgeInsets? characterInsets;

  /// 可选指标叠层。调用方必须通过 Positioned 明确其安全位置。
  final Widget? metricOverlay;

  @override
  Widget build(BuildContext context) {
    final bool dark = TrainMateVisualScope.isDark(context);
    final bool reference = style == TrainMateSceneHeroStyle.referenceShowcase;
    final Color referenceSurface =
        referenceBackgroundColor ?? TrainFlowTokens.showcasePaper;
    final EdgeInsets resolvedCharacterInsets =
        characterInsets ?? const EdgeInsets.fromLTRB(96, 66, 96, 108);
    final double heroHeight = (MediaQuery.sizeOf(context).height *
            TrainFlowTokens.compactHubHeroContentRatio)
        .clamp(
      TrainFlowTokens.compactHubHeroMinHeight,
      TrainFlowTokens.compactHubHeroMaxHeight,
    );
    final Widget body = SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: reference
                  ? LinearGradient(
                      colors: <Color>[referenceSurface, referenceSurface],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        TrainFlowTokens.accent,
                        TrainFlowTokens.brandDark,
                      ],
                    ),
            ),
          ),
          if (reference)
            CustomPaint(
              painter: _ReferenceHeroDoodlePainter(
                color: referenceSurface.computeLuminance() > 0.55
                    ? TrainFlowTokens.purple
                    : TrainFlowTokens.paper,
              ),
            ),
          if (reference) ...<Widget>[
            const Positioned(
              top: 34,
              right: 38,
              child: _ReferenceColorDot(
                size: 28,
                color: TrainFlowTokens.blue,
              ),
            ),
            const Positioned(
              top: 76,
              right: 70,
              child: _ReferenceColorDot(
                size: 13,
                color: TrainFlowTokens.yellow,
              ),
            ),
            const Positioned(
              bottom: 102,
              left: 28,
              child: _ReferenceColorDot(
                size: 16,
                color: TrainFlowTokens.pink,
              ),
            ),
          ],
          if (!reference)
            Opacity(
              opacity: dark ? 0.13 : 0.08,
              child: Image.asset(
                sceneAsset,
                fit: BoxFit.cover,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? stack) =>
                        const _SceneFallback(),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? <Color>[
                        TrainFlowTokens.darkTrainingGradientTop
                            .withValues(alpha: 0),
                        TrainFlowTokens.darkTrainingGradientBottom
                            .withValues(alpha: 0.55),
                      ]
                    : const <Color>[Color(0x00F4F3F1), Color(0x33F4F3F1)],
              ),
            ),
          ),
          Positioned(
            left: 20,
            top: 16,
            right: onAction == null ? 20 : 78,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _SceneGreeting(
                greeting: greeting,
                dateLabel: dateLabel,
                reference: reference,
              ),
            ),
          ),
          if (onAction != null)
            Positioned(
              right: 20,
              top: 16,
              child: IconButton(
                tooltip: actionTooltip,
                onPressed: onAction,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  backgroundColor: reference
                      ? TrainFlowTokens.paper
                      : dark
                          ? TrainFlowTokens.darkTrainingRaised
                          : TrainFlowTokens.lightCompanionCard,
                  foregroundColor: reference
                      ? TrainFlowTokens.brandDark
                      : dark
                          ? TrainFlowTokens.darkTrainingOnSurface
                          : TrainFlowTokens.lightCompanionOnSurface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(TrainFlowTokens.mainTabControlRadius),
                    ),
                  ),
                ),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ),
          Positioned(
            top: resolvedCharacterInsets.top,
            left: resolvedCharacterInsets.left,
            right: resolvedCharacterInsets.right,
            bottom: resolvedCharacterInsets.bottom,
            child: TrainMateShowcaseEntrance(
              duration: TrainFlowMotion.sceneEntrance,
              offset: 0,
              beginScale: 0.96,
              child: FittedBox(fit: BoxFit.contain, child: character),
            ),
          ),
          if (metricOverlay != null) metricOverlay!,
          Positioned(
            left: 12,
            right: 12,
            bottom: 14,
            child: TrainMateShowcaseEntrance(
              duration: TrainFlowMotion.sceneEntrance,
              offset: 10,
              child: _SceneTaskCard(
                title: taskTitle,
                subtitle: taskSubtitle,
                icon: taskIcon,
                trailing: taskTrailing,
                onTap: onTaskTap,
                progress: taskProgress,
                progressLabel: taskProgressLabel,
                reference: reference,
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      key: const ValueKey<String>('trainmate-scene-hero'),
      container: true,
      label: '$greeting，$dateLabel，$taskTitle，$taskSubtitle',
      child: body,
    );
  }
}

class _SceneGreeting extends StatelessWidget {
  const _SceneGreeting({
    required this.greeting,
    required this.dateLabel,
    required this.reference,
  });
  final String greeting;
  final String dateLabel;
  final bool reference;
  @override
  Widget build(BuildContext context) {
    final bool dark = TrainMateVisualScope.isDark(context);
    final Color foreground = TrainMateVisualScope.foreground(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: reference
            ? TrainFlowTokens.paper.withValues(alpha: 0.9)
            : dark
                ? TrainFlowTokens.darkTrainingRaised
                : const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(TrainFlowTokens.mainTabCardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const TrainMateBrandmark(size: 32),
          const SizedBox(width: 8),
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(greeting,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: foreground,
                          fontSize: reference ? 18 : null,
                          fontWeight: FontWeight.w700,
                        )),
                Text(dateLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: TrainMateVisualScope.muted(context),
                        )),
              ]),
        ]),
      ),
    );
  }
}

class _ReferenceHeroDoodlePainter extends CustomPainter {
  const _ReferenceHeroDoodlePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = color.withValues(alpha: TrainFlowTokens.mainTabDoodleOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final Path leftPath = Path()
      ..moveTo(-18, size.height * 0.36)
      ..quadraticBezierTo(
        size.width * 0.14,
        size.height * 0.22,
        size.width * 0.30,
        size.height * 0.38,
      )
      ..quadraticBezierTo(
        size.width * 0.38,
        size.height * 0.47,
        size.width * 0.48,
        size.height * 0.34,
      );
    canvas.drawPath(leftPath, line);
    canvas.drawCircle(
      Offset(size.width * 0.86, size.height * 0.45),
      34,
      line,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.78, size.height * 0.58),
        radius: 54,
      ),
      -0.7,
      2.2,
      false,
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _ReferenceHeroDoodlePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SceneTaskCard extends StatelessWidget {
  const _SceneTaskCard(
      {required this.title,
      required this.subtitle,
      required this.icon,
      this.trailing,
      this.onTap,
      this.progress,
      this.progressLabel,
      required this.reference});
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double? progress;
  final String? progressLabel;
  final bool reference;
  @override
  Widget build(BuildContext context) {
    final bool dark = TrainMateVisualScope.isDark(context);
    final Color cardColor = reference
        ? TrainFlowTokens.showcaseActionSurface
        : dark
            ? TrainFlowTokens.darkTrainingCard
            : TrainFlowTokens.lightCompanionCard;
    final Color foreground = reference
        ? TrainFlowTokens.paper
        : TrainMateVisualScope.foreground(context);
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(TrainFlowTokens.mainTabCardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TrainFlowTokens.mainTabCardRadius),
        child: Padding(
          padding: const EdgeInsets.all(TrainFlowTokens.mainTabCardPadding),
          child: Row(children: <Widget>[
            if (progress != null)
              TrainMateTrainingTrack(
                progress: progress!,
                label: progressLabel,
                size: 52,
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  color: reference
                      ? TrainFlowTokens.yellow
                      : TrainFlowTokens.accent,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(TrainFlowTokens.mainTabControlRadius),
                  ),
                ),
                child: SizedBox.square(
                  dimension: 42,
                  child: Icon(
                    icon,
                    color: reference
                        ? TrainFlowTokens.brandDark
                        : TrainFlowTokens.onAccent,
                  ),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: foreground, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: reference
                              ? TrainFlowTokens.paper.withValues(alpha: 0.72)
                              : TrainMateVisualScope.muted(context))),
                ])),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 8),
              trailing!
            ],
          ]),
        ),
      ),
    );
  }
}

class _ReferenceColorDot extends StatelessWidget {
  const _ReferenceColorDot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: SizedBox.square(dimension: size),
      );
}

class _SceneFallback extends StatelessWidget {
  const _SceneFallback();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: <Color>[TrainFlowTokens.ink, AppColors.primaryLight]),
        ),
      );
}

class TrainMateStatusMetric {
  const TrainMateStatusMetric(
      {required this.label,
      required this.value,
      required this.icon,
      this.color = AppColors.primaryLight});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class TrainMateStatusStrip extends StatelessWidget {
  const TrainMateStatusStrip(
      {super.key,
      required this.metrics,
      this.onTap,
      this.semanticLabel = '最新状态'});
  final List<TrainMateStatusMetric> metrics;
  final VoidCallback? onTap;
  final String semanticLabel;
  @override
  Widget build(BuildContext context) {
    final bool dark = TrainMateVisualScope.isDark(context);
    final Color foreground = TrainMateVisualScope.foreground(context);
    return Semantics(
      key: const ValueKey<String>('trainmate-status-strip'),
      button: onTap != null,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius:
              BorderRadius.circular(TrainFlowTokens.mainTabCardRadius),
          child: SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.hardEdge,
              padding: const EdgeInsets.only(
                right: TrainFlowTokens.mainTabCarouselPeek,
              ),
              itemCount: metrics.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (BuildContext context, int index) {
                final TrainMateStatusMetric metric = metrics[index];
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: dark
                        ? TrainFlowTokens.darkTrainingRaised
                        : TrainFlowTokens.lightCompanionCard,
                    borderRadius: BorderRadius.circular(
                      TrainFlowTokens.mainTabControlRadius,
                    ),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: metric.color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SizedBox.square(
                          dimension: 28,
                          child: Icon(
                            metric.icon,
                            size: 16,
                            color: metric.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${metric.label} ${metric.value}',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w600,
                                  )),
                    ]),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 训练数字使用大数值、单位与标签三层排版，保持中文数据页的扫读效率。
class TrainMateMetricValue extends StatelessWidget {
  const TrainMateMetricValue({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.alignment = CrossAxisAlignment.start,
  });

  final String value;
  final String label;
  final String? unit;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final Color foreground = TrainMateVisualScope.foreground(context);
    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: foreground,
                          fontSize: 32,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                        ),
                  ),
                  if (unit != null) ...<Widget>[
                    const SizedBox(width: 4),
                    Text(
                      unit!,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: TrainMateVisualScope.muted(context),
                            fontSize: 13,
                          ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: TrainMateVisualScope.muted(context),
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
        ),
      ],
    );
  }
}

/// 品牌训练轨道：进度弧、周节奏柱和当前位置圆点均用 Flutter 绘制。
class TrainMateTrainingTrack extends StatelessWidget {
  const TrainMateTrainingTrack({
    super.key,
    required this.progress,
    this.weekValues = const <double>[.25, .42, .7, .36, .82, .54, .2],
    this.currentDay = 3,
    this.label,
    this.size = 68,
  });

  final double progress;
  final List<double> weekValues;
  final int currentDay;
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String semantic =
        label ?? '训练进度 ${(progress.clamp(0, 1) * 100).round()}%';
    return Semantics(
      label: semantic,
      child: SizedBox.square(
        key: const ValueKey<String>('trainmate-training-track'),
        dimension: size,
        child: CustomPaint(
          painter: _TrainMateTrainingTrackPainter(
            progress: progress.clamp(0, 1),
            weekValues: weekValues,
            currentDay: currentDay,
            dark: TrainMateVisualScope.isDark(context),
          ),
        ),
      ),
    );
  }
}

class _TrainMateTrainingTrackPainter extends CustomPainter {
  const _TrainMateTrainingTrackPainter({
    required this.progress,
    required this.weekValues,
    required this.currentDay,
    required this.dark,
  });

  final double progress;
  final List<double> weekValues;
  final int currentDay;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final double stroke = size.width * .075;
    final Rect arcRect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.width - stroke,
    );
    final Paint base = Paint()
      ..color =
          dark ? TrainFlowTokens.darkTrainingRaised : const Color(0xFFD9D8D4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final Paint accent = Paint()
      ..color = TrainFlowTokens.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    const double start = -math.pi * .82;
    const double sweep = math.pi * 1.62;
    canvas.drawArc(arcRect, start, sweep, false, base);
    canvas.drawArc(arcRect, start, sweep * progress, false, accent);

    final int count = weekValues.isEmpty ? 7 : weekValues.length;
    final double barWidth = size.width * .045;
    final double gap = size.width * .035;
    final double total = count * barWidth + (count - 1) * gap;
    final double left = (size.width - total) / 2;
    for (int index = 0; index < count; index += 1) {
      final double height =
          size.height * (.11 + .13 * weekValues[index].clamp(0, 1));
      final double x = left + index * (barWidth + gap);
      final Rect bar =
          Rect.fromLTWH(x, size.height * .67 - height / 2, barWidth, height);
      final Paint paint = Paint()
        ..color = index == currentDay
            ? TrainFlowTokens.accent
            : (dark
                ? TrainFlowTokens.darkTrainingRaised
                : const Color(0xFFC5C4C0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, Radius.circular(barWidth / 2)),
        paint,
      );
    }
    final double angle = start + sweep * progress;
    final Offset point = Offset(
      arcRect.center.dx + arcRect.width / 2 * math.cos(angle),
      arcRect.center.dy + arcRect.height / 2 * math.sin(angle),
    );
    canvas.drawCircle(
        point, stroke * .72, Paint()..color = TrainFlowTokens.accent);
    canvas.drawCircle(
      point,
      stroke * .32,
      Paint()..color = TrainFlowTokens.onAccent,
    );
  }

  @override
  bool shouldRepaint(_TrainMateTrainingTrackPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.currentDay != currentDay ||
        oldDelegate.dark != dark ||
        oldDelegate.weekValues != weekValues;
  }
}

class TrainMateOverviewGrid extends StatelessWidget {
  const TrainMateOverviewGrid(
      {super.key,
      required this.first,
      required this.second,
      required this.trend});
  final Widget first;
  final Widget second;
  final Widget trend;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool singleColumn =
              MediaQuery.textScalerOf(context).scale(1) > 1.35 ||
                  constraints.maxWidth < 340;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (singleColumn) ...<Widget>[
                  first,
                  const SizedBox(height: 12),
                  second
                ] else
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: first),
                        const SizedBox(width: 12),
                        Expanded(child: second)
                      ]),
                const SizedBox(height: 12),
                trend,
              ]);
        },
      );
}

class TrainMateHubHeader extends StatelessWidget {
  const TrainMateHubHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.artwork,
    required this.metrics,
    this.eyebrow,
    this.semanticLabel,
    this.backgroundColor = TrainFlowTokens.darkTrainingRaised,
    this.accentColor = TrainFlowTokens.darkTrainingHighest,
    this.action,
  });

  final String title;
  final String subtitle;
  final String? eyebrow;
  final String? semanticLabel;
  final Widget artwork;
  final List<Widget> metrics;
  final Color backgroundColor;
  final Color accentColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey<String>('trainmate-hub-header'),
      container: true,
      label: semanticLabel ?? '$title，$subtitle',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(TrainFlowTokens.heroRadius),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (eyebrow != null) ...<Widget>[
                          Text(
                            eyebrow!,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: TrainFlowTokens.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(
                                color: TrainFlowTokens.darkTrainingOnSurface,
                                fontSize: 28,
                                height: 1.12,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: TrainFlowTokens.darkTrainingMuted,
                                    height: 1.4,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(
                        TrainFlowTokens.sectionRadius,
                      ),
                    ),
                    child: SizedBox.square(
                      dimension: 112,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: FittedBox(child: artwork),
                      ),
                    ),
                  ),
                ],
              ),
              if (metrics.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                Wrap(spacing: 10, runSpacing: 10, children: metrics),
              ],
              if (action != null) ...<Widget>[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class TrainMateHubMetric extends StatelessWidget {
  const TrainMateHubMetric({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone = TrainFlowCardTone.ink,
  });

  final String label;
  final String value;
  final IconData? icon;
  final TrainFlowCardTone tone;

  @override
  Widget build(BuildContext context) {
    final bool dark = tone == TrainFlowCardTone.ink;
    final Color background = dark
        ? TrainFlowTokens.darkTrainingRaised
        : TrainFlowTokens.darkTrainingHighest;
    final Color foreground = TrainFlowTokens.darkTrainingOnSurface;
    return Semantics(
      label: '$label，$value',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(TrainFlowTokens.pillRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon,
                    size: 18,
                    color: dark ? TrainFlowTokens.accent : foreground),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 7),
              Text(
                value,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TrainMateSectionSurface extends StatelessWidget {
  const TrainMateSectionSurface({
    super.key,
    required this.child,
    this.color = TrainFlowTokens.darkTrainingSurface,
    this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 24),
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(TrainFlowTokens.sectionRadius),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class TrainMateStatePanel extends StatelessWidget {
  const TrainMateStatePanel({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
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
    final bool dark = TrainMateVisualScope.isDark(context);
    final Color muted = TrainMateVisualScope.muted(context);
    return Semantics(
      key: const ValueKey<String>('trainmate-state-panel'),
      container: true,
      label: '$title，$message',
      child: TrainFlowCard(
        tone: TrainFlowCardTone.paper,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: dark
                    ? TrainFlowTokens.darkTrainingRaised
                    : AppColors.primaryLight,
                borderRadius: BorderRadius.circular(
                  TrainFlowTokens.mainTabControlRadius,
                ),
              ),
              child: SizedBox.square(
                dimension: 48,
                child: Icon(
                  icon,
                  color: dark ? TrainFlowTokens.accent : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: muted,
                  ),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TrainMateIllustration extends StatelessWidget {
  const TrainMateIllustration({
    super.key,
    required this.assetPath,
    required this.semanticLabel,
    required this.fallback,
    this.fit = BoxFit.contain,
    this.decorative = false,
  });

  final String assetPath;
  final String semanticLabel;
  final Widget fallback;
  final BoxFit fit;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final Widget image = Image.asset(
      assetPath,
      fit: fit,
      excludeFromSemantics: true,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
        return fallback;
      },
    );
    if (decorative) return ExcludeSemantics(child: image);
    return Semantics(image: true, label: semanticLabel, child: image);
  }
}

class TrainMateImmersivePage extends StatelessWidget {
  const TrainMateImmersivePage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.leading,
    this.artwork,
    this.bottom,
    this.includeDisclaimer = true,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? leading;
  final Widget? artwork;
  final Widget? bottom;
  final bool includeDisclaimer;

  @override
  Widget build(BuildContext context) {
    return TrainMateVisualScope(
      mode: TrainMateVisualMode.darkTraining,
      child: Theme(
        data: TrainMateVisualScope.darkHubTheme(context),
        child: ColoredBox(
          key: const ValueKey<String>('trainmate-immersive-page'),
          color: TrainFlowTokens.darkTrainingSurface,
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: TrainFlowTokens.pageMaxWidth),
              child: SafeArea(
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
                      child: Row(
                        children: <Widget>[
                          if (leading != null) leading!,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: TrainFlowTokens
                                            .darkTrainingOnSurface,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                Text(
                                  subtitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: TrainFlowTokens
                                            .darkTrainingOnSurface
                                            .withValues(alpha: 0.72),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (artwork != null)
                            SizedBox.square(
                              dimension: 72,
                              child: FittedBox(child: artwork!),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: TrainFlowTokens.darkTrainingSurface,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(TrainFlowTokens.sectionRadius),
                          ),
                        ),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                          children: <Widget>[
                            ...children,
                            if (includeDisclaimer)
                              const TrainFlowMedicalDisclaimer(),
                          ],
                        ),
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
    );
  }
}

/// 仅供“今日 / 我的”参考视觉页面使用的滚动画布。
class TrainMateShowcasePage extends StatelessWidget {
  const TrainMateShowcasePage({
    super.key,
    required this.showcase,
    required this.children,
    this.showcaseBackground = TrainFlowTokens.darkTrainingRaised,
    this.contentBackground = TrainFlowTokens.darkTrainingSurface,
    this.includeDisclaimer = true,
    this.bottom,
    this.lazyChildren = false,
  });

  final Widget showcase;
  final List<Widget> children;
  final Color showcaseBackground;
  final Color contentBackground;
  final bool includeDisclaimer;
  final Widget? bottom;
  final bool lazyChildren;

  @override
  Widget build(BuildContext context) {
    final Widget scrollable = lazyChildren
        ? ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: 1 + children.length + (includeDisclaimer ? 1 : 0),
            itemBuilder: _buildLazyItem,
          )
        : ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              showcase,
              DecoratedBox(
                key: const ValueKey<String>('trainmate-showcase-content'),
                decoration: BoxDecoration(
                  color: contentBackground,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(TrainFlowTokens.sectionRadius),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TrainFlowTokens.pageGutter,
                    20,
                    TrainFlowTokens.pageGutter,
                    24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      ...children,
                      if (includeDisclaimer) const TrainFlowMedicalDisclaimer(),
                    ],
                  ),
                ),
              ),
            ],
          );
    return TrainMateVisualScope(
      mode: TrainMateVisualMode.darkTraining,
      child: Theme(
        data: TrainMateVisualScope.darkHubTheme(context),
        child: ColoredBox(
          color: TrainFlowTokens.darkTrainingSurface,
          child: Center(
            child: ConstrainedBox(
              key: const ValueKey<String>('trainmate-showcase-mobile-canvas'),
              constraints: const BoxConstraints(
                maxWidth: TrainFlowTokens.pageMaxWidth,
              ),
              child: ColoredBox(
                color: showcaseBackground,
                child: SafeArea(
                  child: Column(
                    children: <Widget>[
                      Expanded(child: scrollable),
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

  Widget _buildLazyItem(BuildContext context, int index) {
    if (index == 0) return showcase;
    final int contentIndex = index - 1;
    final bool isFirst = contentIndex == 0;
    final bool isDisclaimer = contentIndex == children.length;
    final bool isLast = isDisclaimer ||
        (!includeDisclaimer && contentIndex == children.length - 1);
    final Widget child = isDisclaimer
        ? const TrainFlowMedicalDisclaimer()
        : children[contentIndex];
    return DecoratedBox(
      key:
          isFirst ? const ValueKey<String>('trainmate-showcase-content') : null,
      decoration: BoxDecoration(
        color: contentBackground,
        borderRadius: isFirst
            ? const BorderRadius.vertical(
                top: Radius.circular(TrainFlowTokens.sectionRadius),
              )
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          TrainFlowTokens.pageGutter,
          isFirst ? 20 : 0,
          TrainFlowTokens.pageGutter,
          isLast ? 24 : 0,
        ),
        child: child,
      ),
    );
  }
}

/// 首屏元素统一使用位移、缩放与透明度入场。
class TrainMateShowcaseEntrance extends StatelessWidget {
  const TrainMateShowcaseEntrance({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 520),
    this.offset = 18,
    this.beginScale = 0.98,
  });

  final Widget child;
  final Duration duration;
  final double offset;
  final double beginScale;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: TrainFlowMotion.resolve(context, duration),
      curve: TrainFlowMotion.easeOut,
      child: child,
      builder: (BuildContext context, double value, Widget? child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, offset * (1 - value)),
            child: Transform.scale(
              scale: beginScale + ((1 - beginScale) * value),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class TrainMateMetricCapsule extends StatelessWidget {
  const TrainMateMetricCapsule({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
    this.backgroundColor = AppColors.primary,
    this.foregroundColor = AppColors.white,
    this.accentColor = AppColors.secondary,
    this.contentPadding = const EdgeInsets.fromLTRB(20, 18, 20, 16),
  });

  final String label;
  final String value;
  final String? suffix;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color accentColor;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label，$value${suffix == null ? '' : ' $suffix'}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(38),
        ),
        child: Padding(
          padding: contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foregroundColor.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: value,
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 30,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (suffix != null)
                        TextSpan(
                          text: ' $suffix',
                          style: TextStyle(
                            color: foregroundColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
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

class TrainMateProgressRail extends StatelessWidget {
  const TrainMateProgressRail({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.progress,
    this.color = AppColors.primary,
    this.backgroundColor = AppColors.primaryLight,
  });

  final String label;
  final String valueLabel;
  final double progress;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final double safeProgress = progress.clamp(0, 1).toDouble();
    return Semantics(
      container: true,
      label: '$label，$valueLabel',
      value: '${(safeProgress * 100).round()}%',
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
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    valueLabel,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: safeProgress),
            duration: TrainFlowMotion.resolve(
              context,
              TrainFlowMotion.value,
            ),
            curve: TrainFlowMotion.easeOut,
            builder: (BuildContext context, double value, Widget? child) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 12,
                color: color,
                backgroundColor: backgroundColor,
                borderRadius: BorderRadius.circular(999),
              );
            },
          ),
        ],
      ),
    );
  }
}

class TrainMateRecordTile extends StatelessWidget {
  const TrainMateRecordTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = TrainMateVisualScope.isDark(context);
    return Material(
      color: dark
          ? TrainFlowTokens.darkTrainingCard
          : TrainFlowTokens.lightCompanionCard,
      borderRadius: BorderRadius.circular(TrainFlowTokens.mainTabCardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: TrainFlowTokens.accent,
                  borderRadius: BorderRadius.circular(
                      TrainFlowTokens.mainTabControlRadius),
                ),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(icon, color: TrainFlowTokens.onAccent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TrainMateVisualScope.muted(context),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                trailing,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: TrainMateVisualScope.foreground(context),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class TrainMateWaveBoundary extends StatelessWidget {
  const TrainMateWaveBoundary({
    super.key,
    this.color = AppColors.primary,
    this.height = 56,
  });

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipPath(
        clipper: const _TrainMateWaveClipper(),
        child: ColoredBox(color: color),
      ),
    );
  }
}

class _TrainMateWaveClipper extends CustomClipper<Path> {
  const _TrainMateWaveClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, size.height * 0.46)
      ..cubicTo(
        size.width * 0.20,
        size.height * 0.10,
        size.width * 0.36,
        size.height * 0.88,
        size.width * 0.56,
        size.height * 0.48,
      )
      ..cubicTo(
        size.width * 0.75,
        size.height * 0.12,
        size.width * 0.86,
        size.height * 0.82,
        size.width,
        size.height * 0.34,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _TrainMateWaveClipper oldClipper) => false;
}
