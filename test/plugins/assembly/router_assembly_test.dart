import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/app/navigation/trainmate_bottom_navigation_v2.dart';
import 'package:trainflow_ai/features/auth/application/auth_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/data/models/weekly_report.dart';
import 'package:trainflow_ai/data/repositories/weekly_report_repository.dart';
import '../../support/test_harness.dart';

void main() {
  testWidgets('我的打开管理页后点击核心历史不重复挂载底部导航', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    final storage = _CountingStorage();
    await tester.pumpWidget(ProviderScope(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      authControllerProvider.overrideWith(TestAuthenticatedAuthController.new),
    ], child: const TrainFlowApp()));
    router.go(AppRoutes.profile);
    await tester.pumpAndSettle();
    router.push<void>(AppRoutes.capabilities);
    await tester.pumpAndSettle();
    await runtime.disable('feature.weekly_report');
    await tester.pumpAndSettle();
    storage.writeCount = 0;
    final entry = find.widgetWithText(ListTile, '历史记录');
    await tester.scrollUntilVisible(entry, 500,
        maxScrolls: 60, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.history);
    expect(find.byType(TrainMateBottomNavigationV2), findsOneWidget);
    expect(storage.writeCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('周报停用后深链回说明页，核心历史仍可展开原报告且不写入', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    await runtime.disable('feature.weekly_report');
    final storage = _CountingStorage();
    PersistedWeeklyReportRepository(storage).saveReport(WeeklyReport(
        id: 'disabled-weekly', weekLabel: '已保存的合成周报',
        generatedAt: DateTime(2026, 9, 16), completedWorkouts: 0,
        plannedWorkouts: 3, completionRate: 0,
        loadTrendLabel: '无法评估', decisionReview: '原报告决策',
        recoverySummary: '原报告恢复说明', highlights: const [], nextWeekFocus: const [],
        realityObservation: '原报告事实依据仍可阅读'));
    final before = storage.readJson(PersistedWeeklyReportRepository.storageKey);
    await tester.pumpWidget(ProviderScope(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      authControllerProvider.overrideWith(TestAuthenticatedAuthController.new),
    ], child: const TrainFlowApp()));
    await tester.pumpAndSettle();
    storage.writeCount = 0;
    router.go(AppRoutes.weeklyReport);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.capabilities);
    expect(find.byKey(const ValueKey('capability-unavailable-message')), findsOneWidget);
    router.go(AppRoutes.history);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.history);
    final card = find.byKey(const ValueKey('history-weekly-disabled-weekly'));
    await tester.scrollUntilVisible(card, 250, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('已保存的合成周报'));
    await tester.tap(find.text('已保存的合成周报'));
    await tester.pumpAndSettle();
    expect(find.text('原报告事实依据仍可阅读'), findsOneWidget);
    expect(find.byKey(const ValueKey('weekly-psych-save')), findsNothing);
    expect(storage.writeCount, 0);
    expect(storage.readJson(PersistedWeeklyReportRepository.storageKey), before);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('授权通过后关闭深链到说明页，根和底栏正确回今日', (tester) async {
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    for (final id in [
      'feature.training_plan',
      'feature.companion',
      'feature.exercise_library'
    ]) {
      await runtime.disable(id);
    }
    await tester.pumpWidget(ProviderScope(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      authControllerProvider.overrideWith(TestAuthenticatedAuthController.new),
    ], child: const TrainFlowApp()));
    router.go('/plans/generate');
    await tester.pumpAndSettle();
    expect(
        router.routeInformationProvider.value.uri.path, AppRoutes.capabilities);
    expect(find.textContaining('训练计划当前未启用'), findsOneWidget);
    router.go('/');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.dashboard);
    final nav = tester.widget<TrainMateBottomNavigationV2>(
        find.byType(TrainMateBottomNavigationV2));
    expect(
        nav.items.map((i) => i.path), [AppRoutes.dashboard, AppRoutes.profile]);
    expect(nav.selectedIndex, 0);
    await tester.tap(find.byKey(const Key('bottom-nav-item-1')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.profile);
    expect(
        tester
            .widget<TrainMateBottomNavigationV2>(
                find.byType(TrainMateBottomNavigationV2))
            .selectedIndex,
        1);
    await runtime.registry.shutdown();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('未登录的禁用深链仍先经过身份授权，公开条款保持可达', (tester) async {
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    await runtime.disable('feature.training_plan');
    await tester.pumpWidget(ProviderScope(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      authControllerProvider.overrideWith(_SignedOut.new),
    ], child: const TrainFlowApp()));
    router.go('/plans/generate');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.login);
    router.go(AppRoutes.terms);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.terms);
    await runtime.registry.shutdown();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('当前底栏功能关闭后立即回退到管理页', (tester) async {
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    await tester.pumpWidget(ProviderScope(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      authControllerProvider.overrideWith(TestAuthenticatedAuthController.new),
    ], child: const TrainFlowApp()));
    router.go(AppRoutes.exercises);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.exercises);

    await runtime.disable('feature.exercise_library');
    await tester.pumpAndSettle();

    expect(
        router.routeInformationProvider.value.uri.path, AppRoutes.capabilities);
    expect(find.textContaining('动作库当前未启用'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('停用训练计划后参数详情深链回退且核心历史仍纯读可达', (WidgetTester tester) async {
    final PluginRuntime runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    await runtime.disable('feature.training_plan');
    final _CountingStorage storage = _CountingStorage();
    await tester.pumpWidget(ProviderScope(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      authControllerProvider.overrideWith(TestAuthenticatedAuthController.new),
    ], child: const TrainFlowApp()));
    await tester.pumpAndSettle();
    storage.writeCount = 0;

    router.go('/plans/example-plan');
    await tester.pumpAndSettle();
    expect(
        router.routeInformationProvider.value.uri.path, AppRoutes.capabilities);
    expect(storage.writeCount, 0);

    router.go('/plans/example-plan/workouts/example-workout');
    await tester.pumpAndSettle();
    expect(
        router.routeInformationProvider.value.uri.path, AppRoutes.capabilities);
    expect(storage.writeCount, 0);

    router.go('/history/plans/example-version');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path,
        '/history/plans/example-version');
    expect(find.text('计划版本不可用'), findsOneWidget);
    expect(storage.writeCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _SignedOut extends AuthController {
  @override
  Future<AuthState> build() async =>
      const AuthState(status: AuthStatus.unauthenticated);
}

class _CountingStorage extends InMemoryLocalStorageService {
  int writeCount = 0;

  @override
  void saveJson(String key, Map<String, dynamic> value) {
    writeCount++;
    super.saveJson(key, value);
  }

  @override
  void remove(String key) {
    writeCount++;
    super.remove(key);
  }
}
