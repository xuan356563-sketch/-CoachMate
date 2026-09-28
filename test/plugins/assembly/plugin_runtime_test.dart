import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_routes.dart';
import 'package:trainflow_ai/plugins/features/built_in_features.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/app/navigation/main_shell.dart';

void main() {
  Future<PluginRuntime> create(
      {Map<String, TrainMatePlugin> replacements = const {}}) async {
    final runtime = PluginRuntime(PluginRegistry(
        plugins: builtInDistribution(replacements: replacements)));
    await runtime.initialize();
    addTearDown(() async {
      await runtime.shutdown();
      runtime.dispose();
      runtime.registry.dispose();
    });
    return runtime;
  }

  test('发行适配逐项覆盖原有业务目录、资源库及核心管理目录且所有策略真实注册', () async {
    final directories = Directory('lib/features')
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.split('/').last)
        .toSet();
    expect(builtInFeatures.map((f) => f.directory).toSet(), directories);
    expect(directories, hasLength(35));
    final runtime = await create();
    expect(runtime.registry.failures, isEmpty);
    expect(
        runtime.registry.statuses.values
            .every((s) => s == PluginStatus.running),
        isTrue);
    expect(runtime.sportDirectory.strategies, hasLength(7));
    for (final feature in builtInFeatures) {
      expect(runtime.service(feature.id), isNotNull);
    }
  });
  test('可选失败隔离，今日与我的保留且独立功能可继续启停', () async {
    final runtime = await create(
        replacements: {'feature.companion': _Failing('feature.companion')});
    expect(runtime.hasRequiredFailures, isFalse);
    expect(runtime.isEnabled('feature.companion'), isFalse);
    expect(runtime.isWritable('core.dashboard'), isTrue);
    await runtime.disable('feature.motion_check');
    await runtime.enable('feature.motion_check');
    expect(runtime.isWritable('feature.motion_check'), isTrue);
  });
  test('必需失败阻止全部可写业务', () async {
    final runtime = await create(replacements: {
      'core.storage': _Failing('core.storage', required: true)
    });
    expect(runtime.hasRequiredFailures, isTrue);
    expect(runtime.isWritable('sport.marathon'), isFalse);
    expect(() => runtime.beginOperation('sport.marathon'), throwsStateError);
  });
  test('关闭仅清理目标的延迟服务和资源，过期结果不能提交', () async {
    final runtime = await create();
    var cleaned = 0;
    runtime
        .service('feature.motion_check')!
        .bind('image', Object(), cleanup: () => cleaned++);
    runtime.registerCleanup('feature.motion_check', () => cleaned++);
    final operation = runtime.beginOperation('feature.motion_check');
    await runtime.disable('feature.motion_check');
    expect(cleaned, 2);
    expect(runtime.service('feature.ai_center'), isNotNull);
    await expectLater(
        operation.commit(() => fail('关闭后不得写入')), throwsStateError);
    await runtime.enable('feature.motion_check');
    expect(operation.checkActive, throwsStateError);
  });
  test('异步数据库提交临界区阻止停用与换账户，完成后方可停用', () async {
    final runtime = await create();
    final database = Completer<void>();
    final committing = runtime
        .beginOperation('feature.motion_check')
        .commit(() => database.future);
    expect(
        runtime.checkDisable('feature.motion_check').join(), contains('正在保存'));
    await expectLater(
        runtime.disable('feature.motion_check'), throwsStateError);
    await expectLater(runtime.changeAccountScope(), throwsStateError);
    database.complete();
    await committing;
    await runtime.disable('feature.motion_check');
    expect(runtime.isEnabled('feature.motion_check'), isFalse);
  });
  test('暂停清理期间阻止新动作，持久化失败恢复原组合', () async {
    final runtime = await create();
    final gate = Completer<void>();
    var resourceActive = true;
    runtime.registerCleanup('feature.motion_check', () async {
      resourceActive = false;
      await gate.future;
    }, onRestore: () => resourceActive = true);
    final disabling = runtime.disable('feature.motion_check',
        persist: (_) async => throw StateError('模拟保存失败'));
    expect(runtime.isSwitching, isTrue);
    expect(() => runtime.beginOperation('feature.ai_center'), throwsStateError);
    gate.complete();
    await expectLater(disabling, throwsStateError);
    expect(runtime.isWritable('feature.motion_check'), isTrue);
    expect(resourceActive, isTrue);
  });
  test('动态锁与必需项及真实执行依赖阻断，不连带停用', () async {
    final runtime = await create();
    expect(runtime.checkDisable('core.profile').join(), contains('必需'));
    expect(
        runtime.checkDisable('feature.training_log').join(), contains('课程跟练'));
    final remove =
        runtime.registerDisableLock('feature.workout_player', () => '训练尚未结束');
    await expectLater(
        runtime.disable('feature.workout_player'), throwsStateError);
    remove();
    await runtime.disable('feature.workout_player');
    expect(runtime.previewEnable('feature.workout_player').last.name, '训练播放器');
  });
  test('实际参与运动来源在等待阶段失效并在提交阶段阻止关闭', () async {
    final runtime = await create();
    final waiting = runtime.beginOperation('feature.training_plan');
    expect(waiting.containsSource('feature.training_plan'), isTrue);
    expect(waiting.containsSource('core.history'), isTrue);
    expect(waiting.containsSource('feature.ai_center'), isFalse);
    waiting.includeDependencies(['sport.marathon']);
    expect(waiting.containsSource('sport.marathon'), isTrue);
    await runtime.disable('sport.marathon');
    await expectLater(waiting.commit(() => fail('失效来源不得提交')), throwsStateError);
    await runtime.enable('sport.marathon');
    final database = Completer<void>();
    final commit = runtime.beginOperation('feature.training_plan',
        dependencies: ['sport.marathon']).commit(() => database.future);
    expect(runtime.checkDisable('sport.marathon').join(), contains('正在保存'));
    await expectLater(runtime.disable('sport.marathon'), throwsStateError);
    database.complete();
    await commit;
    await runtime.disable('sport.marathon');
  });
  test('活动恢复失败时显式阻止该能力并给出重启恢复说明', () async {
    final runtime = await create();
    runtime.registerCleanup('feature.motion_check', () {},
        onRestore: () => throw StateError('恢复失败'));
    await expectLater(
        runtime.disable('feature.motion_check',
            persist: (_) async => throw StateError('保存失败')),
        throwsA(isA<StateError>()
            .having((e) => e.message, '说明', contains('活动资源恢复失败'))));
    expect(runtime.registry.enabledIds, contains('feature.motion_check'));
    expect(runtime.isWritable('feature.motion_check'), isFalse);
    expect(
        () => runtime.beginOperation('feature.motion_check'), throwsStateError);
  });
  test('按功能订阅重新启用时可安全重绑且无关切换不通知', () async {
    final runtime = await create();
    final container = ProviderContainer(
        overrides: [pluginRuntimeProvider.overrideWith((ref) => runtime)]);
    final enabled = <bool>[];
    final subscription = container.listen(
        featureEnabledProvider('feature.motion_check'), (previous, next) {
      enabled.add(next);
      if (next) runtime.requireEnabled('feature.motion_check');
    });
    await runtime.disable('feature.motion_check');
    await container.pump();
    await runtime.enable('feature.motion_check');
    await container.pump();
    await runtime.disable('feature.meal_guide');
    await container.pump();
    expect(enabled, [false, true]);
    subscription.close();
    // runtime 由上方 create 的 tearDown 统一关闭。
    await runtime.shutdown();
    container.dispose();
  });
  test('账号变化使旧结果失效但不关闭功能', () async {
    final runtime = await create();
    final operation = runtime.beginOperation('feature.ai_center');
    final gate = Completer<void>();
    final change = runtime.changeAccountScope(replaceScope: () => gate.future);
    expect(() => runtime.beginOperation('feature.ai_center'), throwsStateError);
    gate.complete();
    await change;
    expect(operation.checkActive, throwsStateError);
    expect(runtime.isWritable('feature.ai_center'), isTrue);
  });
  test('关闭计划后旧写详情受限而核心历史保留，底栏缩减和恢复', () async {
    final runtime = await create();
    for (final id in [
      'feature.training_plan',
      'feature.companion',
      'feature.exercise_library'
    ]) {
      await runtime.disable(id);
    }
    expect(disabledRouteOwner(runtime, '/plans/generate'),
        'feature.training_plan');
    expect(disabledRouteOwner(runtime, '/plans/saved-version'),
        'feature.training_plan');
    expect(disabledRouteOwner(runtime, '/history/plans/old-version'), isNull);
    expect(defaultPluginRoute(runtime), '/dashboard');
    expect(navigationItemsFor(runtime.contributions).map((i) => i.path),
        ['/dashboard', '/profile']);
    await runtime.enable('feature.companion');
    expect(navigationItemsFor(runtime.contributions).map((i) => i.path),
        ['/dashboard', '/companion', '/profile']);
  });
  test('只记录实际编译来源，无关功能关闭不使来源失效', () async {
    final runtime = await create();
    final sources = runtime.decoratePlanSources(
        [runtime.registry.descriptors['sport.marathon']!.ref]);
    expect(
        sources.map((s) => s.id), ['sport.marathon', 'feature.training_plan']);
    await runtime.disable('feature.motion_check');
    expect(runtime.resolvePlanSources(sources), sources);
    await runtime.disable('feature.training_plan');
    expect(runtime.resolvePlanSources(sources), isNull);
  });
}

class _Failing extends TrainMatePlugin {
  _Failing(String id, {bool required = false})
      : descriptor = PluginDescriptor(
            id: id,
            type: PluginType.core,
            version: '1.0.0',
            name: '模拟故障',
            description: '只用于测试故障隔离',
            isRequired: required);
  @override
  final PluginDescriptor descriptor;
  @override
  Future<void> initialize(PluginContext context) async =>
      throw StateError('模拟初始化失败');
}
