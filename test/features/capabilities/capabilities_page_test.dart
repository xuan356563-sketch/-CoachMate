import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/capabilities/capabilities_page.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/settings/plugin_settings.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('技能详情只读展示本地就绪与云端待校验，停用后跟随更新', (tester) async {
    final storage = InMemoryLocalStorageService();
    final runtime = await _pumpPage(tester, storage);
    final before = storage.readJson(pluginSettingsStorageKey);
    final button = find.byKey(const ValueKey('capability-skills-sport.hyrox'));
    await tester.scrollUntilVisible(button, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('HYROX的技能'), findsOneWidget);
    expect(find.text('本地已就绪'), findsOneWidget);
    expect(find.text('云端待请求时校验'), findsOneWidget);
    expect(find.text('云端运行 · 兼容版本 1.x'), findsOneWidget);
    expect(storage.readJson(pluginSettingsStorageKey), before);
    await runtime.disable('sport.hyrox');
    await tester.pumpAndSettle();
    expect(find.text('所属插件已停用'), findsNWidgets(2));
    expect(find.text('本地已就绪'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('康复复合插件只展示本地技能，AI关闭不会宣称云端可用', (tester) async {
    final runtime = await _pumpPage(tester, InMemoryLocalStorageService());
    await runtime.disable('feature.training_plan');
    final button = find.byKey(const ValueKey('capability-skills-sport.hyrox'));
    await tester.scrollUntilVisible(button, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('需要启用 AI 中心和训练计划功能'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    final rehab = find.byKey(const ValueKey('capability-skills-support.rehab'));
    await tester.scrollUntilVisible(rehab, 220,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(rehab);
    await tester.pumpAndSettle();
    await tester.tap(rehab);
    await tester.pumpAndSettle();
    expect(find.text('康复支持本地计划'), findsOneWidget);
    expect(find.textContaining('云端运行'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('管理页完整分组，核心常驻项没有开关', (WidgetTester tester) async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    await _pumpPage(tester, storage);

    expect(find.text('运动'), findsOneWidget);
    expect(find.text('目标与支持'), findsOneWidget);
    expect(find.text('可选功能'), findsOneWidget);
    expect(find.text('核心常驻'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('capability-sport.hyrox')),
        findsOneWidget);
    final Finder requiredCard =
        find.byKey(const ValueKey<String>('capability-core.history'));
    expect(requiredCard, findsOneWidget);
    expect(
      find.descendant(of: requiredCard, matching: find.byType(Switch)),
      findsNothing,
    );
    final Finder historyEntry = find.widgetWithText(ListTile, '历史记录');
    await tester.scrollUntilVisible(
      historyEntry,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(historyEntry, findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('启用依赖只确认一次，取消不变更且确认后原子启用', (WidgetTester tester) async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService()
      ..saveJson(pluginSettingsStorageKey, <String, dynamic>{
        'version': 1,
        'enabledOverrides': <String, bool>{
          'feature.activity_import': false,
          'feature.guided_workout': false,
          'feature.training_log': false,
          'feature.workout_player': false,
        },
      })
      ..saveJson(
          'trainflow.generated_training_plan_versions.v1', <String, dynamic>{
        'schemaVersion': 1,
        'versions': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'old-version'}
        ],
      })
      ..saveJson('trainflow.training_logs.v1', <String, dynamic>{
        'schemaVersion': 1,
        'logs': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'old-log'}
        ],
      });
    final Map<String, dynamic>? planBefore =
        storage.readJson('trainflow.generated_training_plan_versions.v1');
    final Map<String, dynamic>? logsBefore =
        storage.readJson('trainflow.training_logs.v1');
    final PluginRuntime runtime = await _pumpPage(tester, storage);
    expect(runtime.isEnabled('feature.activity_import'), isFalse);
    expect(runtime.isEnabled('feature.training_log'), isFalse);

    await _tapCapability(tester, 'feature.activity_import');
    expect(find.textContaining('还会同时启用：训练记录'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(runtime.isEnabled('feature.activity_import'), isFalse);
    expect(runtime.isEnabled('feature.training_log'), isFalse);

    await _tapCapability(tester, 'feature.activity_import');
    await tester.tap(find.widgetWithText(FilledButton, '确认启用'));
    await tester.pumpAndSettle();
    expect(runtime.isEnabled('feature.activity_import'), isTrue);
    expect(runtime.isEnabled('feature.training_log'), isTrue);
    expect(
      storage.readJson(pluginSettingsStorageKey)?['enabledOverrides'],
      <String, bool>{
        'feature.guided_workout': false,
        'feature.workout_player': false,
      },
    );
    expect(
      storage.readJson('trainflow.generated_training_plan_versions.v1'),
      planBefore,
    );
    expect(storage.readJson('trainflow.training_logs.v1'), logsBefore);

    await _dispose(tester);
  });

  testWidgets('当前主运动的停用请求被画像事实阻断', (WidgetTester tester) async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    registerPersistedSportLocks(runtime, () => storage);
    await runtime.initialize();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
        ],
        child: const MaterialApp(home: CapabilitiesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await _tapCapability(tester, 'sport.hyrox');
    expect(find.textContaining('HYROX仍是当前主运动或次运动'), findsOneWidget);
    expect(runtime.isEnabled('sport.hyrox'), isTrue);

    await tester.tap(find.widgetWithText(FilledButton, '知道了'));
    await tester.pumpAndSettle();
    await _dispose(tester);
  });

  testWidgets('保存失败时开关完整还原并显示可重试状态', (WidgetTester tester) async {
    final _FailingFlushStorage storage = _FailingFlushStorage();
    final PluginRuntime runtime = await _pumpPage(tester, storage);

    await _tapCapability(tester, 'feature.motion_check');

    expect(runtime.isEnabled('feature.motion_check'), isTrue);
    final Finder card =
        find.byKey(const ValueKey<String>('capability-feature.motion_check'));
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: card, matching: find.byType(Switch)),
          )
          .value,
      isTrue,
    );
    expect(find.textContaining('保存失败，已恢复原设置'), findsOneWidget);

    await _dispose(tester);
  });
}

Future<PluginRuntime> _pumpPage(
  WidgetTester tester,
  InMemoryLocalStorageService storage,
) async {
  final PluginRuntime runtime = PluginRuntime(
    PluginRegistry(plugins: builtInDistribution()),
  );
  final Map<String, dynamic>? document =
      storage.readJson(pluginSettingsStorageKey);
  final PluginSettings settings = document == null
      ? const PluginSettings()
      : PluginSettings.fromJson(document);
  await runtime.initialize(
    enabledIds: settings.enabledIds(runtime.registry.descriptors),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
      ],
      child: const MaterialApp(home: CapabilitiesPage()),
    ),
  );
  await tester.pumpAndSettle();
  return runtime;
}

Future<void> _tapCapability(WidgetTester tester, String id) async {
  final Finder card = find.byKey(ValueKey<String>('capability-$id'));
  await tester.scrollUntilVisible(
    card,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

class _FailingFlushStorage extends InMemoryLocalStorageService {
  bool _shouldFail = true;

  @override
  Future<void> flush() async {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('模拟保存失败');
    }
  }
}
