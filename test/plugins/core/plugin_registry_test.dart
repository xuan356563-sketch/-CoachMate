import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';

class TestPlugin extends TrainMatePlugin {
  TestPlugin(String id,
      {List<String> dependencies = const [],
      List<String> capabilities = const [],
      bool required = false,
      bool enabled = true,
      int hostApiVersion = 1,
      this.onInitialize})
      : descriptor = PluginDescriptor(
            id: id,
            type: PluginType.feature,
            version: '1.0.0',
            name: '测试插件',
            description: '测试插件生命周期',
            dependencies: dependencies,
            capabilities: capabilities,
            isRequired: required,
            defaultEnabled: enabled,
            hostApiVersion: hostApiVersion);
  @override
  final PluginDescriptor descriptor;
  final FutureOr<void> Function(PluginContext)? onInitialize;
  @override
  Future<void> initialize(PluginContext context) async {
    await onInitialize?.call(context);
  }
}

void main() {
  test('依赖按拓扑顺序初始化且加载期间不贡献能力', () async {
    final order = <String>[];
    final gate = Completer<void>();
    final started = Completer<void>();
    final registry = PluginRegistry(plugins: [
      TestPlugin('feature', dependencies: ['core'], onInitialize: (c) {
        expect(c.readCapability<String>('service'), '就绪');
        order.add('feature');
      }),
      TestPlugin('core', capabilities: ['service'], onInitialize: (c) async {
        order.add('core');
        c.registerCapability('service', '就绪');
        started.complete();
        await gate.future;
      }),
    ]);
    final pending = registry.initialize();
    await started.future;
    expect(registry.statuses['core'], PluginStatus.loading);
    expect(registry.readCapability<String>('service'), isNull);
    gate.complete();
    await pending;
    expect(order, ['core', 'feature']);
    expect(registry.statuses.values, everyElement(PluginStatus.running));
    await registry.shutdown();
  });

  test('重复 ID、缺失依赖、循环依赖和宿主版本明确拒绝', () {
    for (final plugins in [
      [TestPlugin('a'), TestPlugin('a')],
      [
        TestPlugin('a', dependencies: ['missing'])
      ],
      [
        TestPlugin('a', dependencies: ['b']),
        TestPlugin('b', dependencies: ['a'])
      ],
      [TestPlugin('a', hostApiVersion: 2)],
    ]) {
      expect(() => PluginRegistry(plugins: plugins),
          throwsA(isA<PluginException>()));
    }
  });

  test('预览依赖闭包，拒绝停用必需插件和被依赖插件', () async {
    final registry = PluginRegistry(plugins: [
      TestPlugin('core', required: true),
      TestPlugin('base', dependencies: ['core'], enabled: false),
      TestPlugin('feature', dependencies: ['base'], enabled: false),
    ]);
    await registry.initialize();
    expect(registry.previewEnable('feature'), ['base', 'feature']);
    await registry.enable('feature');
    await expectLater(
        registry.disable('core'), throwsA(isA<PluginException>()));
    await expectLater(
        registry.disable('base'), throwsA(isA<PluginException>()));
    await registry.disable('feature');
    await registry.disable('base');
    expect(registry.enabledIds, {'core'});
    await registry.shutdown();
  });

  test('初始化失败回收部分注册且不影响独立插件', () async {
    final cleaned = <String>[];
    final registry = PluginRegistry(plugins: [
      TestPlugin('broken', capabilities: ['broken.value'], onInitialize: (c) {
        c.registerCapability('broken.value', 1);
        c.addCleanup(() => cleaned.add('第一个'));
        c.addCleanup(() {
          cleaned.add('第二个');
          throw StateError('清理失败');
        });
        throw StateError('初始化失败');
      }),
      TestPlugin('dependent', dependencies: ['broken']),
      TestPlugin('healthy'),
    ]);
    final result = await registry.initialize();
    expect(result.failures.keys, containsAll(['broken', 'dependent']));
    expect(result.cleanupErrors, hasLength(1));
    expect(result.hasRequiredFailures, isFalse);
    expect(cleaned, ['第二个', '第一个']);
    expect(registry.readCapability<int>('broken.value'), isNull);
    expect(registry.statuses['healthy'], PluginStatus.running);
    await registry.shutdown();
    await registry.shutdown();
    expect(cleaned, ['第二个', '第一个']);
  });

  test('必需核心失败可被宿主识别', () async {
    final registry = PluginRegistry(plugins: [
      TestPlugin('core',
          required: true, onInitialize: (_) => throw StateError('核心不可用'))
    ]);
    expect((await registry.initialize()).hasRequiredFailures, isTrue);
    await registry.shutdown();
  });

  test('重复能力失败不能删除另一个作用域能力', () async {
    final registry = PluginRegistry(plugins: [
      TestPlugin('first',
          capabilities: ['shared'],
          onInitialize: (c) => c.registerCapability('shared', 1)),
      TestPlugin('second',
          capabilities: ['shared'],
          onInitialize: (c) => c.registerCapability('shared', 2)),
    ]);
    final result = await registry.initialize();
    expect(result.failures.keys, ['second']);
    expect(registry.readCapability<int>('shared'), 1);
    await registry.disable('second');
    expect(registry.readCapability<int>('shared'), 1);
    await registry.shutdown();
  });

  test('取消后异步任务不提交，事件取消且清理幂等', () async {
    final gate = Completer<int>();
    final stream = StreamController<int>.broadcast(sync: true);
    late PluginContext context;
    var writes = 0;
    final registry = PluginRegistry(plugins: [
      TestPlugin('worker', onInitialize: (c) {
        context = c;
        c.listen(stream.stream, (_) => writes++);
      })
    ]);
    await registry.initialize();
    final pending =
        context.runGuarded<int>((_) => gate.future, (_) => writes++);
    stream.add(1);
    expect(writes, 1);
    await registry.disable('worker');
    gate.complete(2);
    expect(await pending, isFalse);
    stream.add(2);
    expect(writes, 1);
    expect(context.isActive, isFalse);
    expect(() => context.registerCapability('late', 1),
        throwsA(isA<PluginException>()));
    await context.dispose();
    await context.dispose();
    await stream.close();
    await registry.shutdown();
  });

  test('显式取消单个任务不影响同作用域其他任务', () async {
    late PluginContext context;
    final registry = PluginRegistry(
        plugins: [TestPlugin('worker', onInitialize: (c) => context = c)]);
    await registry.initialize();
    final token = context.createCancellationToken();
    token.cancel();
    var writes = 0;
    expect(
        await context.runGuarded<int>((_) async => 1, (_) => writes++,
            token: token),
        isFalse);
    expect(
        await context.runGuarded<int>((_) async => 2, (_) => writes++), isTrue);
    expect(writes, 1);
    await registry.shutdown();
  });

  test('初始化未完成时关闭立即取消作用域且不启动后续插件', () async {
    final started = Completer<void>();
    final blocked = Completer<void>();
    var laterStarts = 0;
    late PluginContext context;
    final registry = PluginRegistry(plugins: [
      TestPlugin('first', onInitialize: (c) async {
        context = c;
        started.complete();
        await blocked.future;
      }),
      TestPlugin('later', onInitialize: (_) => laterStarts++),
    ]);
    final initialization = registry.initialize();
    await started.future;
    await registry.shutdown().timeout(const Duration(seconds: 1));
    await initialization;
    expect(context.isActive, isFalse);
    expect(laterStarts, 0);
    expect(registry.statuses.values, everyElement(PluginStatus.stopped));
    blocked.complete();
    await Future<void>.delayed(Duration.zero);
    expect(registry.statuses.values, everyElement(PluginStatus.stopped));
  });

  test('关闭汇总在途初始化与已运行插件的清理失败且不重复释放', () async {
    final started = Completer<void>();
    final blocked = Completer<void>();
    final cleaned = <String>[];
    final registry = PluginRegistry(plugins: [
      TestPlugin('running', onInitialize: (context) {
        context.addCleanup(() {
          cleaned.add('running');
          throw StateError('运行插件清理失败');
        });
      }),
      TestPlugin('loading', onInitialize: (context) async {
        context.addCleanup(() {
          cleaned.add('loading');
          throw StateError('在途初始化清理失败');
        });
        started.complete();
        await blocked.future;
      }),
    ]);
    final initialization = registry.initialize();
    await started.future;
    final shutdown =
        await registry.shutdown().timeout(const Duration(seconds: 1));
    expect(shutdown.cleanupErrors.map((error) => error.pluginId),
        ['loading', 'running']);
    expect(shutdown.isSuccess, isFalse);
    expect(registry.lastResult, same(shutdown));
    expect(registry.lastResult.isSuccess, isFalse);
    expect((await initialization).cleanupErrors.map((error) => error.pluginId),
        ['loading']);
    expect(cleaned, ['loading', 'running']);
    expect(registry.statuses.values, everyElement(PluginStatus.stopped));
    await registry.shutdown();
    expect(cleaned, ['loading', 'running']);
    blocked.complete();
  });

  test('扩展元数据只在成功后出现，停用与失败都撤销登记', () async {
    final registry = PluginRegistry(plugins: [
      TestPlugin('first', onInitialize: (c) {
        c.registerContribution(const RouteContribution(
            id: 'first.route', label: '页面', path: '/first'));
        c.registerContribution(const NavigationContribution(
            id: 'first.nav', label: '导航', routeId: 'first.route'));
        c.registerContribution(const CardContribution(
            id: 'first.card', label: '卡片', slot: 'dashboard'));
        c.registerContribution(const FormContribution(
            id: 'first.form', label: '表单', formId: 'profile'));
        c.registerContribution(const ReportContribution(
            id: 'first.report', label: '报告', reportId: 'weekly'));
      }),
      TestPlugin('broken', onInitialize: (c) {
        c.registerContribution(const RouteContribution(
            id: 'broken.route', label: '失败页面', path: '/broken'));
        throw StateError('初始化失败');
      }),
    ]);
    await registry.initialize();
    expect(registry.contributions, hasLength(5));
    expect(registry.contributions.whereType<RouteContribution>().single.path,
        '/first');
    await registry.disable('first');
    expect(registry.contributions, isEmpty);
    await registry.shutdown();
  });

  test('能力读取限显式依赖闭包且注册限声明能力', () async {
    final registry = PluginRegistry(plugins: [
      TestPlugin('owner',
          capabilities: ['service'],
          onInitialize: (c) => c.registerCapability('service', 1)),
      TestPlugin('stranger', onInitialize: (c) {
        expect(c.readCapability<int>('service'), isNull);
        c.registerCapability('undeclared', 1);
      }),
    ]);
    final result = await registry.initialize();
    expect(result.failures.keys, ['stranger']);
    expect(registry.readCapability<int>('service'), 1);
    await registry.shutdown();
  });

  test('保存失败可恢复原启用组合且状态只读并通知', () async {
    final registry = PluginRegistry(plugins: [
      TestPlugin('core', required: true),
      TestPlugin('optional', enabled: false)
    ]);
    var notifications = 0;
    registry.addListener(() => notifications++);
    await registry.initialize();
    final previous = registry.enabledIds;
    await registry.enable('optional');
    await registry.restoreEnabled(previous);
    expect(registry.enabledIds, {'core'});
    expect(registry.statuses['optional'], PluginStatus.stopped);
    expect(notifications, greaterThan(3));
    expect(() => registry.enabledIds.add('fake'), throwsUnsupportedError);
    expect(() => registry.statuses['core'] = PluginStatus.failed,
        throwsUnsupportedError);
    await registry.shutdown();
  });
}
