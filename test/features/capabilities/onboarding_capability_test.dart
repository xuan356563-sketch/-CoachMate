import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/features/auth/application/auth_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

import '../../support/test_harness.dart';

void main() {
  testWidgets('当前画像含已停用运动时明示并阻止静默继续生成', (WidgetTester tester) async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    await runtime.disable('sport.hyrox');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
          authControllerProvider.overrideWith(
            TestAuthenticatedAuthController.new,
          ),
        ],
        child: const TrainFlowApp(),
      ),
    );
    await tester.pumpAndSettle();
    router.go(AppRoutes.profile);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑资料'));
    await tester.pumpAndSettle();

    final Finder primary =
        find.byKey(const ValueKey<String>('onboarding-primary-goal'));
    await tester.scrollUntilVisible(
      primary,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('HYROX（已停用）'), findsOneWidget);

    final Finder save = find.text('确认资料并生成计划');
    await tester.scrollUntilVisible(
      save,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final FilledButton button = tester.widget(
      find.ancestor(of: save, matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNotNull);
    button.onPressed!();
    await tester.pumpAndSettle();

    expect(
        router.routeInformationProvider.value.uri.path, AppRoutes.capabilities);
    expect(find.textContaining('HYROX当前未启用'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
