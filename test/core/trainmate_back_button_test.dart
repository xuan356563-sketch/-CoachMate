import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/core/theme/tdesign_theme.dart';
import 'package:trainflow_ai/core/widgets/trainmate_action_character.dart';
import 'package:trainflow_ai/core/widgets/trainflow_widgets.dart';

void main() {
  for (final TrainFlowHeaderVariant variant in <TrainFlowHeaderVariant>[
    TrainFlowHeaderVariant.organic,
    TrainFlowHeaderVariant.compact,
  ]) {
    testWidgets('${variant.name} 页头显示 48×48 品牌返回按钮和中文语义', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: Scaffold(
            body: TrainFlowPage(
              title: '品牌返回按钮',
              headerVariant: variant,
              includeDisclaimer: false,
              leading: const TrainMateBackButton(
                fallbackRoute: '/fallback',
                onPressed: _noop,
              ),
              children: const [Text('内容')],
            ),
          ),
        ),
      );

      final Finder button = find.byKey(
        const ValueKey<String>('trainmate-back-button'),
      );
      expect(button, findsOneWidget);
      expect(tester.getSize(button), const Size(48, 48));
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(
        find.ancestor(
          of: button,
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is Semantics &&
                widget.properties.label == '返回' &&
                widget.properties.button == true &&
                widget.properties.onTap != null,
          ),
        ),
        findsOneWidget,
      );

      // 白图标钮：人物置于白底上，加载墨兰（navy）变体。
      final String expectedVariant = 'navy';
      expect(
        find.byKey(
          ValueKey<String>(
            'trainmate-action-pointingGuide-$expectedVariant',
          ),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('320、393 和 430 宽度下按钮不导致页头溢出', (tester) async {
    for (final double width in <double>[320, 393, 430]) {
      for (final TrainFlowHeaderVariant variant in <TrainFlowHeaderVariant>[
        TrainFlowHeaderVariant.organic,
        TrainFlowHeaderVariant.compact,
      ]) {
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: TDesignTheme.lightTheme,
            home: Scaffold(
              body: TrainFlowPage(
                title: '较长的业务子页面标题用于验证窄屏布局',
                subtitle: '标题、人物和返回按钮需要同时保留安全间距。',
                headerVariant: variant,
                leading: const TrainMateBackButton(
                  fallbackRoute: '/fallback',
                  onPressed: _noop,
                ),
                artwork: const TrainMateActionCharacter(
                  action: TrainMateAction.running,
                  backgroundColor: Color(0xFF19172C),
                ),
                includeDisclaimer: false,
                children: const [Text('内容')],
              ),
            ),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${variant.name} 页头在宽度 $width 不应溢出',
        );
      }
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('自定义返回处理优先于默认导航', (tester) async {
    int pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrainMateBackButton(
            fallbackRoute: '/fallback',
            onPressed: () => pressed += 1,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('trainmate-back-button')),
    );
    expect(pressed, 1);
  });
}

void _noop() {}
