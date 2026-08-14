import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/core/theme/tdesign_theme.dart';

void main() {
  testWidgets('浅深主题切换可以安全渲染自定义按钮', (tester) async {
    final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);
    addTearDown(themeMode.dispose);

    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (context, value, child) {
          return MaterialApp(
            theme: TDesignTheme.lightTheme,
            darkTheme: TDesignTheme.darkTheme,
            themeMode: value,
            home: Scaffold(
              body: Column(
                children: [
                  ElevatedButton(onPressed: () {}, child: const Text('主按钮')),
                  OutlinedButton(onPressed: () {}, child: const Text('描边按钮')),
                  TextButton(onPressed: () {}, child: const Text('文字按钮')),
                ],
              ),
            ),
          );
        },
      ),
    );

    themeMode.value = ThemeMode.dark;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
  });
}
