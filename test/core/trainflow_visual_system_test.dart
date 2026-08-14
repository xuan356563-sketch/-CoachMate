import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/core/constants/app_colors.dart';
import 'package:trainflow_ai/core/theme/tdesign_theme.dart';
import 'package:trainflow_ai/core/theme/trainmate_visual_mode.dart';
import 'package:trainflow_ai/core/theme/trainflow_tokens.dart';
import 'package:trainflow_ai/core/widgets/flow_mascot.dart';
import 'package:trainflow_ai/core/widgets/trainmate_action_character.dart';
import 'package:trainflow_ai/core/widgets/trainmate_branding.dart';
import 'package:trainflow_ai/core/widgets/trainmate_showcase_widgets.dart';
import 'package:trainflow_ai/core/widgets/trainflow_widgets.dart';

void main() {
  test('品牌视觉令牌保持深蓝橙固定色值', () {
    expect(AppColors.primary, const Color(0xFF19172C));
    expect(AppColors.white, const Color(0xFFFFFDFC));
    expect(AppColors.secondary, const Color(0xFFFFB27D));
    expect(AppColors.primaryLight, const Color(0xFFFFE2B8));
    expect(AppColors.background, const Color(0xFFF4F2F5));
  });

  test('Indore 主标签视觉令牌锁定深浅主题、青柠强调与紧凑布局', () {
    expect(TrainFlowTokens.accent, const Color(0xFFE0FF64));
    expect(TrainFlowTokens.onAccent, const Color(0xFF181814));
    expect(TrainFlowTokens.darkTrainingSurface, const Color(0xFF181814));
    expect(TrainFlowTokens.darkTrainingCard, const Color(0xFF21211D));
    expect(TrainFlowTokens.darkTrainingRaised, const Color(0xFF2A2A28));
    expect(TrainFlowTokens.darkTrainingHighest, const Color(0xFF353634));
    expect(TrainFlowTokens.lightCompanionSurface, const Color(0xFFF4F3F1));
    expect(TrainFlowTokens.lightCompanionCard, const Color(0xFFFFFFFF));
    expect(TrainFlowTokens.mainTabCardRadius, 14);
    expect(TrainFlowTokens.mainTabPageGutter, 20);
    expect(TrainFlowTokens.mainTabCardGap, 12);
    expect(TrainFlowTokens.mainTabCardPadding, 16);
  });

  test('青柠主行动在暖黑训练底色上的文字对比满足 AA', () {
    final double contrast = (TrainFlowTokens.accent.computeLuminance() + .05) /
        (TrainFlowTokens.onAccent.computeLuminance() + .05);
    expect(contrast, greaterThanOrEqualTo(4.5));
  });

  testWidgets('主标签暖黑作用域应用 14dp 卡片层级', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const TrainMateVisualScope(
          mode: TrainMateVisualMode.darkTraining,
          child: TrainFlowCard(
            key: ValueKey<String>('indore-dark-card'),
            child: Text('暖黑主标签卡片'),
          ),
        ),
      ),
    );

    Material materialFor(String key) => tester.widget<Material>(
          find
              .descendant(
                of: find.byKey(ValueKey<String>(key)),
                matching: find.byType(Material),
              )
              .first,
        );
    expect(
      materialFor('indore-dark-card').color,
      TrainFlowTokens.darkTrainingCard,
    );
    expect(
      materialFor('indore-dark-card').borderRadius,
      BorderRadius.circular(TrainFlowTokens.mainTabCardRadius),
    );
  });

  testWidgets('桌面宽屏将移动画布限制为 430 像素', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: TDesignTheme.lightTheme,
        home: const Scaffold(
          body: TrainFlowPage(
            title: '宽屏基线',
            subtitle: '移动画布保持居中',
            children: [TrainFlowCard(child: Text('内容'))],
          ),
        ),
      ),
    );

    final Size canvasSize = tester.getSize(
      find.byKey(const ValueKey<String>('trainflow-mobile-canvas')),
    );
    expect(canvasSize.width, TrainFlowTokens.pageMaxWidth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动态效果时内容直接显示最终状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TDesignTheme.lightTheme,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(393, 852),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: MotionEntrance(
              key: ValueKey<String>('reduced-motion-entrance'),
              index: 6,
              child: Text('静态内容'),
            ),
          ),
        ),
      ),
    );

    final Finder opacity = find.descendant(
      of: find.byKey(
        const ValueKey<String>('reduced-motion-entrance'),
      ),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    expect(find.text('静态内容'), findsOneWidget);
  });

  testWidgets('参考首屏在减少动态效果时跳过入场过渡', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(393, 852),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: TrainMateShowcaseEntrance(
              key: ValueKey<String>('reduced-showcase-entrance'),
              child: Text('参考首屏内容'),
            ),
          ),
        ),
      ),
    );

    final Finder entrance = find.byKey(
      const ValueKey<String>('reduced-showcase-entrance'),
    );
    final Finder animation = find.descendant(
      of: entrance,
      matching: find.byType(TweenAnimationBuilder<double>),
    );
    final Finder opacity = find.descendant(
      of: entrance,
      matching: find.byType(Opacity),
    );

    expect(
      tester.widget<TweenAnimationBuilder<double>>(animation).duration,
      Duration.zero,
    );
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    expect(find.text('参考首屏内容'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('TrainFlowPage 默认不创建分区入场动画', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrainFlowPage(
            title: '高频页面',
            headerVariant: TrainFlowHeaderVariant.none,
            includeDisclaimer: false,
            children: [Text('内容')],
          ),
        ),
      ),
    );

    expect(find.byType(MotionEntrance), findsNothing);
  });

  testWidgets('显式开启的分区入场动画在 280ms 内结束', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrainFlowPage(
            title: '低频页面',
            headerVariant: TrainFlowHeaderVariant.none,
            includeDisclaimer: false,
            animateChildren: true,
            children: [Text('第一项'), Text('第二项'), Text('第三项')],
          ),
        ),
      ),
    );

    expect(find.byType(MotionEntrance), findsNWidgets(3));
    await tester.pump(const Duration(milliseconds: 280));
    expect(find.byType(Opacity), findsNWidgets(3));
    expect(
      tester
          .widgetList<Opacity>(find.byType(Opacity))
          .every((Opacity opacity) => opacity.opacity == 1),
      isTrue,
    );
  });

  testWidgets('蜜桃重点卡片使用统一深蓝描边', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TDesignTheme.lightTheme,
        home: const Scaffold(
          body: TrainFlowCard(
            key: ValueKey<String>('peach-card'),
            tone: TrainFlowCardTone.peach,
            child: Text('重点训练'),
          ),
        ),
      ),
    );

    final Finder card = find.byKey(const ValueKey<String>('peach-card'));
    final Material material = tester.widget<Material>(
      find.descendant(of: card, matching: find.byType(Material)).first,
    );
    expect(material.color, AppColors.primaryLight);

    final Iterable<Container> containers = tester.widgetList<Container>(
      find.descendant(of: card, matching: find.byType(Container)),
    );
    final BoxDecoration decoration = containers
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((item) => item.border != null);
    final Border border = decoration.border! as Border;
    expect(border.top.color, AppColors.primary);
    expect(border.top.width, TrainFlowTokens.borderWidth);
  });

  testWidgets('可点击卡片按下时缩放，释放后恢复原尺寸', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrainFlowCard(
            key: ValueKey<String>('pressable-card'),
            onTap: _noop,
            child: Text('可点击训练卡片'),
          ),
        ),
      ),
    );

    final Finder card = find.byKey(const ValueKey<String>('pressable-card'));
    final Finder animatedScale = find.descendant(
      of: card,
      matching: find.byType(AnimatedScale),
    );
    final AnimatedScale scaleWidget = tester.widget<AnimatedScale>(
      animatedScale,
    );
    expect(scaleWidget.duration, TrainFlowMotion.button);
    expect(scaleWidget.curve, TrainFlowMotion.easeOut);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(card),
    );
    await tester.pump();

    expect(tester.widget<AnimatedScale>(animatedScale).scale, 0.97);
    await _expectScaleAnimationCompleted(tester, card, 0.97);

    await gesture.up();
    await tester.pump();
    expect(tester.widget<AnimatedScale>(animatedScale).scale, 1);
    await _expectScaleAnimationCompleted(tester, card, 1);
  });

  testWidgets('不可点击卡片始终保持原尺寸', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrainFlowCard(
            key: ValueKey<String>('static-card'),
            child: Text('信息卡片'),
          ),
        ),
      ),
    );

    final Finder card = find.byKey(const ValueKey<String>('static-card'));
    final Finder animatedScale = find.descendant(
      of: card,
      matching: find.byType(AnimatedScale),
    );
    expect(tester.widget<AnimatedScale>(animatedScale).scale, 1);

    final InkWell inkWell = tester.widget<InkWell>(
      find.descendant(of: card, matching: find.byType(InkWell)),
    );
    expect(inkWell.onHighlightChanged, isNull);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(card),
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(animatedScale).scale, 1);

    await gesture.up();
    await tester.pump();
    expect(tester.widget<AnimatedScale>(animatedScale).scale, 1);
  });

  testWidgets('同键卡片恢复可点击时不会保留按压缩放状态', (tester) async {
    final ValueNotifier<bool> clickable = ValueNotifier<bool>(true);
    addTearDown(clickable.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: clickable,
            builder: (BuildContext context, bool value, Widget? child) {
              return TrainFlowCard(
                key: const ValueKey<String>('updatable-card'),
                onTap: value ? _noop : null,
                child: const Text('可更新训练卡片'),
              );
            },
          ),
        ),
      ),
    );

    final Finder card = find.byKey(
      const ValueKey<String>('updatable-card'),
    );
    final Finder animatedScale = find.descendant(
      of: card,
      matching: find.byType(AnimatedScale),
    );
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(card),
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(animatedScale).scale, 0.97);

    clickable.value = false;
    await tester.pump();
    expect(tester.widget<AnimatedScale>(animatedScale).scale, 1);
    await gesture.up();
    await tester.pump();

    clickable.value = true;
    await tester.pump();
    expect(tester.widget<AnimatedScale>(animatedScale).scale, 1);
  });

  testWidgets('减少动态效果时可点击卡片按下仍保持原尺寸', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: TrainFlowCard(
              key: ValueKey<String>('reduced-motion-card'),
              onTap: _noop,
              child: Text('减少动态效果卡片'),
            ),
          ),
        ),
      ),
    );

    final Finder card = find.byKey(
      const ValueKey<String>('reduced-motion-card'),
    );
    final Finder animatedScale = find.descendant(
      of: card,
      matching: find.byType(AnimatedScale),
    );
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(card),
    );
    await tester.pump();

    expect(tester.widget<AnimatedScale>(animatedScale).scale, 1);
    await gesture.up();
  });

  testWidgets('393×852 页面、波形头部和透明 PNG 人物无布局异常', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: TDesignTheme.lightTheme,
        home: const Scaffold(
          body: TrainFlowPage(
            title: '今日训练',
            subtitle: '训练决策辅助系统',
            artwork: FloatingFlowMascot(
              size: 96,
              spec: FlowMascotSpec.ready,
            ),
            children: [
              SectionTitle(title: '今日状态'),
              TrainFlowCard(
                tone: TrainFlowCardTone.peach,
                child: Row(
                  children: [
                    Expanded(child: MetricPill(label: '睡眠', value: '7.1 h')),
                    SizedBox(width: 8),
                    Expanded(child: MetricPill(label: 'HRV', value: '52 ms')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.hasRunningAnimations, isFalse);

    expect(
      find.byKey(const ValueKey<String>('trainflow-organic-header')),
      findsOneWidget,
    );
    final Finder character = find.byType(FlowMascot);

    expect(find.byType(FloatingFlowMascot), findsOneWidget);
    expect(character, findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FloatingFlowMascot),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(FloatingFlowMascot),
        matching: find.byType(Padding),
      ),
      findsNothing,
    );
    expect(tester.getSize(character), const Size.square(96));
    expect(tester.takeException(), isNull);
  });

  test('Flow V2 角色品牌调色板精确匹配定版色值', () {
    expect(FlowMascotPalette.brand.body, const Color(0xFF19172C));
    expect(FlowMascotPalette.brand.outline, const Color(0xFF0E0D1B));
    expect(FlowMascotPalette.brand.face, const Color(0xFFFFFDFC));
    expect(FlowMascotPalette.brand.headband, const Color(0xFFFF6B4A));
    expect(FlowMascotPalette.brand.facialFeature, const Color(0xFF19172C));
    expect(FlowMascotPalette.brand.mouth, const Color(0xFFFF6B4A));
  });

  test('官方 Ninja Flow 用于品牌标，Flow V2 保持动作角色与旧标回退', () {
    expect(
      TrainMateBrandAssets.brandmark,
      'assets/branding/exports/png/trainmate-flow-logo-final-256.png',
    );
    expect(
      TrainMateBrandAssets.character,
      'assets/branding/flow-v2-color-detail/exports/png/'
      'trainmate-flow-character-1024.png',
    );
    expect(
      TrainMateBrandAssets.lockup,
      'assets/branding/exports/png/trainmate-flow-logo-final-lockup-1600.png',
    );
    expect(
      TrainMateBrandAssets.legacyBrandmark,
      'assets/branding/exports/png/trainmate-flow-logo-final-256.png',
    );
    expect(
      TrainMateBrandAssets.legacyLockup,
      'assets/branding/exports/png/'
      'trainmate-flow-logo-final-lockup-1600.png',
    );
    expect(
      <String>[
        TrainMateBrandAssets.brandmark,
        TrainMateBrandAssets.character,
        TrainMateBrandAssets.lockup,
        TrainMateBrandAssets.legacyBrandmark,
        TrainMateBrandAssets.legacyLockup,
      ].every((String path) => !path.contains('flow-dog-v1')),
      isTrue,
    );
  });

  test('20 个动作在两套目录中形成一一对应的唯一资源路径', () {
    expect(TrainMateAction.values, hasLength(20));
    final Set<String> navyPaths = <String>{};
    final Set<String> peachPaths = <String>{};
    for (final TrainMateAction action in TrainMateAction.values) {
      navyPaths.add(
        TrainMateActionAssets.path(action, TrainMateCharacterVariant.navy),
      );
      peachPaths.add(
        TrainMateActionAssets.path(
          action,
          TrainMateCharacterVariant.peachLight,
        ),
      );
    }
    expect(navyPaths, hasLength(20));
    expect(peachPaths, hasLength(20));
    expect(navyPaths.every((String path) => path.contains('/navy/')), isTrue);
    expect(
      peachPaths.every((String path) => path.contains('/peach-light/')),
      isTrue,
    );
  });

  testWidgets('Flow 角色减少动态效果时直接显示静态最终帧', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: FloatingFlowMascot()),
        ),
      ),
    );

    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(FlowMascot), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Flow 角色状态变化只重播一次短动画', (tester) async {
    final ValueNotifier<FlowMascotSpec> spec = ValueNotifier<FlowMascotSpec>(
      FlowMascotSpec.ready,
    );
    addTearDown(spec.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<FlowMascotSpec>(
            valueListenable: spec,
            builder: (BuildContext context, FlowMascotSpec value, Widget? _) {
              return FloatingFlowMascot(spec: value);
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.hasRunningAnimations, isFalse);

    spec.value = const FlowMascotSpec(
      action: FlowMascotAction.thumbsUp,
      expression: FlowMascotExpression.happy,
      semanticLabel: 'Flow 训练伙伴点赞',
      durationMilliseconds: 420,
      motionCycles: 2,
    );
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey<String>(
          'trainmate-action-treePoseBalance-peachLight',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新主品牌组合标使用正式 PNG 并适配手机宽度', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: TrainMateBrandLockup()),
        ),
      ),
    );

    final Finder lockup =
        find.byKey(const ValueKey<String>('trainmate-brand-lockup'));
    final Image image = tester.widget<Image>(lockup);
    final AssetImage provider = image.image as AssetImage;

    expect(lockup, findsOneWidget);
    expect(provider.assetName, TrainMateBrandAssets.lockup);
    expect(tester.getSize(lockup).width, lessThanOrEqualTo(393));
    expect(tester.takeException(), isNull);
  });

  test('背景亮度阈值选择正确的双配色版本', () {
    expect(
      TrainMateActionAssets.variantForBackground(AppColors.primary),
      TrainMateCharacterVariant.peachLight,
    );
    expect(
      TrainMateActionAssets.variantForBackground(AppColors.background),
      TrainMateCharacterVariant.navy,
    );
    expect(
      TrainMateActionAssets.variantForBackground(AppColors.primaryLight),
      TrainMateCharacterVariant.navy,
    );
  });

  testWidgets('TrainFlowPage 头部支持左侧返回键且保持可访问点击尺寸', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final (Size size, TrainFlowHeaderVariant variant) in [
      (const Size(320, 568), TrainFlowHeaderVariant.organic),
      (const Size(393, 852), TrainFlowHeaderVariant.organic),
      (const Size(430, 932), TrainFlowHeaderVariant.compact),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: Scaffold(
            body: TrainFlowPage(
              title: '站姿提踵动作详情',
              subtitle: '动作说明',
              headerVariant: variant,
              leading: IconButton(
                key: const ValueKey<String>('test-page-leading'),
                tooltip: '返回',
                onPressed: _noop,
                icon: const Icon(Icons.arrow_back),
              ),
              children: const [Text('详情内容')],
            ),
          ),
        ),
      );

      final Finder leading = find.byKey(
        const ValueKey<String>('test-page-leading'),
      );
      final Size leadingSize = tester.getSize(leading);
      expect(leading, findsOneWidget);
      expect(leadingSize.width, greaterThanOrEqualTo(48));
      expect(leadingSize.height, greaterThanOrEqualTo(48));
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('TrainFlowPage 未提供 leading 时维持原头部标题起点', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrainFlowPage(
            title: '原头部标题',
            children: [Text('详情内容')],
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.text('原头部标题')).dx, 20);
    expect(tester.takeException(), isNull);
  });

  test('全页面视觉令牌使用分层圆角与固定间距', () {
    expect(TrainFlowTokens.heroRadius, 40);
    expect(TrainFlowTokens.sectionRadius, 32);
    expect(TrainFlowTokens.cardRadius, 24);
    expect(TrainFlowTokens.controlRadius, 16);
    expect(TrainFlowTokens.pillRadius, 999);
    expect(
      TrainFlowTokens.spacing,
      const <double>[8, 12, 16, 20, 24, 32],
    );
  });

  testWidgets('页面布局类型会创建对应内容画布与头部层级', (tester) async {
    for (final TrainFlowPageLayout layout in TrainFlowPageLayout.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: Scaffold(
            body: TrainFlowPage(
              title: '${layout.name} 页面',
              layout: layout,
              includeDisclaimer: false,
              children: const <Widget>[Text('页面内容')],
            ),
          ),
        ),
      );

      expect(
        find.byKey(ValueKey<String>('trainflow-page-layout-${layout.name}')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('trainflow-page-content-surface')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('主标签展示头包含标题指标插画与中文语义', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TDesignTheme.lightTheme,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: TrainMateHubHeader(
              title: '训练计划',
              subtitle: '下一次训练已准备好',
              eyebrow: '本周节奏',
              semanticLabel: '训练计划概览',
              artwork: TrainMateActionCharacter(
                action: TrainMateAction.running,
                backgroundColor: AppColors.white,
              ),
              metrics: <Widget>[
                TrainMateHubMetric(label: '本周', value: '4 次'),
                TrainMateHubMetric(label: '下一练', value: '45 分钟'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('trainmate-hub-header')),
      findsOneWidget,
    );
    expect(find.byType(TrainMateHubMetric), findsNWidgets(2));
    final Semantics header = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('trainmate-hub-header')),
    );
    expect(header.properties.label, '训练计划概览');
    expect(tester.takeException(), isNull);
  });

  testWidgets('主标签展示头适配 320 宽与两倍文字缩放', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: TDesignTheme.lightTheme,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: TrainMateHubHeader(
                title: '动作库与动作检测',
                subtitle: '按身体部位筛选动作，并在开始前查看安全提示。',
                artwork: TrainMateActionCharacter(
                  action: TrainMateAction.running,
                  backgroundColor: AppColors.white,
                ),
                metrics: <Widget>[
                  TrainMateHubMetric(label: '动作', value: '221 个'),
                  TrainMateHubMetric(label: '部位', value: '11 组'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('动作库与动作检测'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('统一状态面板支持操作并保持 48dp 点击区', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TDesignTheme.lightTheme,
        home: Scaffold(
          body: TrainMateStatePanel(
            title: '暂时无法读取',
            message: '训练功能仍可正常使用。',
            actionLabel: '重新加载',
            onAction: _noop,
          ),
        ),
      ),
    );

    final Finder action = find.widgetWithText(FilledButton, '重新加载');
    expect(action, findsOneWidget);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    final Semantics panel = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('trainmate-state-panel')),
    );
    expect(panel.properties.label, '暂时无法读取，训练功能仍可正常使用。');
  });

  testWidgets('插画读取失败时显示既有动作人物回退', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrainMateIllustration(
            assetPath: 'assets/images/not-found-showcase.png',
            semanticLabel: '统一训练插画',
            fallback: TrainMateActionCharacter(
              action: TrainMateAction.pointingGuide,
              backgroundColor: AppColors.white,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('统一训练插画'), findsOneWidget);
    expect(find.byType(TrainMateActionCharacter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('沉浸页面在关闭动画与窄屏下直接显示最终状态', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(320, 568),
            disableAnimations: true,
          ),
          child: TrainMateImmersivePage(
            title: '跟练执行',
            subtitle: '专注当前动作',
            children: <Widget>[Text('训练内容')],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('trainmate-immersive-page')),
      findsOneWidget,
    );
    expect(find.text('训练内容'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

Future<void> _expectScaleAnimationCompleted(
  WidgetTester tester,
  Finder card,
  double targetScale,
) async {
  final Finder scaleTransition = find.descendant(
    of: card,
    matching: find.byType(ScaleTransition),
  );

  await tester.pump(TrainFlowMotion.button ~/ 2);
  expect(
    tester.widget<ScaleTransition>(scaleTransition).scale.value,
    allOf(greaterThan(0.97), lessThan(1)),
  );

  await tester.pump(TrainFlowMotion.button ~/ 2);
  expect(
    tester.widget<ScaleTransition>(scaleTransition).scale.value,
    closeTo(targetScale, 0.0001),
  );
}
