import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';

void main() {
  Future<PluginRuntime> create() async {
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    addTearDown(() async {
      await runtime.shutdown();
      runtime.dispose();
    });
    return runtime;
  }

  test('账户清理失败保留责任并阻止写入，重试先清除旧资源再换域', () async {
    final runtime = await create();
    var stoppedAttempts = 0;
    var failedAttempts = 0;
    var oldResourceActive = true;
    var replaced = false;
    runtime.registerCleanup('feature.ai_center', () => stoppedAttempts++);
    runtime.registerCleanup('feature.motion_check', () async {
      failedAttempts++;
      if (failedAttempts == 1) throw StateError('测试取消失败');
      oldResourceActive = false;
    });

    await expectLater(
        runtime.changeAccountScope(replaceScope: () => replaced = true),
        throwsStateError);
    expect(replaced, isFalse);
    expect(runtime.isWritable('feature.motion_check'), isFalse);
    expect(runtime.isWritable('feature.ai_center'), isFalse);
    expect(runtime.recoveryFailures, isNotEmpty);
    expect(() => runtime.beginOperation('feature.ai_center'), throwsStateError);

    await runtime.changeAccountScope(replaceScope: () {
      expect(oldResourceActive, isFalse, reason: '换域必须晚于旧资源实际停止');
      replaced = true;
    });
    expect(failedAttempts, 2);
    expect(stoppedAttempts, 1, reason: '已成功清理的其他资源不应重复清理');
    expect(replaced, isTrue);
    expect(runtime.isWritable('feature.ai_center'), isTrue);
    expect(runtime.recoveryFailures, isEmpty);
  });

  test('账户域替换失败保留不可写恢复态，必须显式重试替换才能恢复', () async {
    final runtime = await create();
    final replacement = Completer<void>();
    var cleanupCount = 0;
    runtime.registerCleanup('feature.motion_check', () => cleanupCount++);
    final previousOperation = runtime.beginOperation('feature.ai_center');
    final changing =
        runtime.changeAccountScope(replaceScope: () => replacement.future);
    final failure = expectLater(changing, throwsStateError);
    replacement.completeError(StateError('测试账户域替换失败'));
    await failure;

    expect(runtime.isAccountChanging, isTrue, reason: '未知数据域仍处于保护状态');
    expect(runtime.isWritable('feature.ai_center'), isFalse);
    expect(previousOperation.checkActive, throwsStateError);
    await expectLater(runtime.changeAccountScope(), throwsStateError);
    expect(runtime.isWritable('feature.ai_center'), isFalse);
    var repaired = false;
    await runtime.changeAccountScope(replaceScope: () => repaired = true);
    expect(repaired, isTrue);
    expect(cleanupCount, 1);
    expect(runtime.isAccountChanging, isFalse);
    expect(runtime.isWritable('feature.ai_center'), isTrue);
  });

  test('部分恢复成功与部分启动后抛错的资源均有补偿清理责任', () async {
    final runtime = await create();
    var firstActive = true;
    var secondActive = true;
    var firstCleanups = 0;
    var secondCleanups = 0;
    runtime.registerCleanup('feature.motion_check', () {
      firstCleanups++;
      firstActive = false;
    }, onRestore: () => firstActive = true);
    runtime.registerCleanup('feature.motion_check', () {
      secondCleanups++;
      secondActive = false;
    }, onRestore: () {
      secondActive = true;
      throw StateError('测试第二项部分启动后失败');
    });

    await expectLater(
        runtime.disable('feature.motion_check',
            persist: (_) async => throw StateError('测试保存失败')),
        throwsStateError);
    expect(runtime.isWritable('feature.motion_check'), isFalse);
    expect(runtime.recoveryFailures, contains('feature.motion_check'));
    await runtime.shutdown();
    expect(firstActive, isFalse);
    expect(secondActive, isFalse);
    expect(firstCleanups, 2);
    expect(secondCleanups, 2);
  });

  test('恢复失败的补偿清理再失败时退出仍会重试该资源', () async {
    final runtime = await create();
    var active = true;
    var cleanups = 0;
    runtime.registerCleanup('feature.motion_check', () {
      cleanups++;
      if (cleanups == 2) throw StateError('测试补偿停止失败');
      active = false;
    }, onRestore: () {
      active = true;
      throw StateError('测试启动后失败');
    });

    await expectLater(
        runtime.disable('feature.motion_check',
            persist: (_) async => throw StateError('测试保存失败')),
        throwsStateError);
    expect(cleanups, 2, reason: '恢复失败先尝试补偿清理');
    expect(runtime.isWritable('feature.motion_check'), isFalse);
    final stopped = await runtime.shutdown();
    expect(stopped.cleanupErrors, isEmpty);
    expect(cleanups, 3);
    expect(active, isFalse);
  });

  test('退出清理失败后再次退出可重试尚未释放的资源', () async {
    final runtime = await create();
    var attempts = 0;
    var active = true;
    runtime.registerCleanup('feature.motion_check', () {
      attempts++;
      if (attempts == 1) throw StateError('测试停止失败');
      active = false;
    });
    expect((await runtime.shutdown()).cleanupErrors, hasLength(1));
    expect((await runtime.shutdown()).cleanupErrors, isEmpty);
    expect(attempts, 2);
    expect(active, isFalse);
  });

  test('旧服务注销幂等且保留同键新绑定与其清理责任', () async {
    final runtime = await create();
    final service = runtime.service('feature.motion_check')!;
    var oldCleanups = 0;
    var currentCleanups = 0;
    final object = Object();
    final oldUnregister =
        service.bind('controller', object, cleanup: () => oldCleanups++);
    oldUnregister();
    service.bind('controller', object, cleanup: () => currentCleanups++);
    oldUnregister();
    oldUnregister();
    expect(service.read<Object>('controller'), same(object));
    await runtime.shutdown();
    expect(oldCleanups, 0);
    expect(currentCleanups, 1);
    oldUnregister();
    expect(currentCleanups, 1);
  });
}
