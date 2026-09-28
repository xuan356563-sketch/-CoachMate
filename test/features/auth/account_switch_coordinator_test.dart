import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/auth/application/account_switch_coordinator.dart';
import 'package:trainflow_ai/features/auth/data/account_binding_service.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/features/feature_service.dart';
import 'package:trainflow_ai/plugins/settings/plugin_settings.dart';
import 'package:trainflow_ai/plugins/settings/plugin_settings_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('先清理健康队列与本地健康数据，再执行数据库原子换绑', () async {
    final List<String> calls = <String>[];
    final AccountSwitchCoordinator coordinator = AccountSwitchCoordinator(
      clearPendingHealthQueue: () async => calls.add('queue'),
      confirmDatabaseAccountSwitch: () async {
        calls.add('database');
        return true;
      },
      isScopeAlreadyReplaced: () => false,
      resetInMemoryState: () => calls.add('reset'),
    );

    await coordinator.confirm();

    expect(calls, <String>['queue', 'database', 'reset']);
  });

  test('健康队列清理失败时不得继续数据库换绑', () async {
    bool databaseCalled = false;
    final AccountSwitchCoordinator coordinator = AccountSwitchCoordinator(
      clearPendingHealthQueue: () async {
        throw StateError('本地健康数据清理失败');
      },
      confirmDatabaseAccountSwitch: () async {
        databaseCalled = true;
        return true;
      },
      isScopeAlreadyReplaced: () => false,
      resetInMemoryState: () {},
    );

    await expectLater(coordinator.confirm(), throwsStateError);
    expect(databaseCalled, isFalse);
  });

  test('数据库原子换绑失败时不刷新内存状态', () async {
    final List<String> calls = <String>[];
    final AccountSwitchCoordinator coordinator = AccountSwitchCoordinator(
      clearPendingHealthQueue: () async => calls.add('queue'),
      confirmDatabaseAccountSwitch: () async {
        calls.add('database');
        return false;
      },
      isScopeAlreadyReplaced: () => false,
      resetInMemoryState: () => calls.add('reset'),
    );

    await expectLater(coordinator.confirm(), throwsStateError);
    expect(calls, <String>['queue', 'database']);
  });

  test('业务域已换绑时失败原因明确为仅待装配', () async {
    final AccountSwitchCoordinator coordinator = AccountSwitchCoordinator(
      clearPendingHealthQueue: () async {},
      confirmDatabaseAccountSwitch: () async => false,
      isScopeAlreadyReplaced: () => true,
      resetInMemoryState: () {},
    );

    await expectLater(
      coordinator.confirm(),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          '中文恢复原因',
          contains('功能装配待恢复'),
        ),
      ),
    );
  });

  test('连续确认时已完成的健康队列与业务数据清理均不重复', () async {
    final _CountingAccountStorage storage = _CountingAccountStorage()
      ..saveJson(AccountBindingService.installationIdKey,
          <String, dynamic>{'value': 'device'})
      ..saveJson(AccountBindingService.accountBindingKey,
          <String, dynamic>{'userId': 'old-user'})
      ..saveJson(pluginSettingsStorageKey, <String, dynamic>{
        'version': 1,
        'enabledOverrides': <String, bool>{'feature.ai_coach': false},
      });
    final _FailOnceAssemblyPlugin flaky = _FailOnceAssemblyPlugin();
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(
        plugins: builtInDistribution(
          replacements: <String, TrainMatePlugin>{
            'feature.ai_coach': flaky,
          },
        ),
      ),
    );
    final PluginSettingsController settings = PluginSettingsController(
      runtime: runtime,
      storage: storage,
    );
    await runtime.initialize(enabledIds: settings.desiredEnabledIds());
    final AccountBindingService binding = AccountBindingService(storage);
    var queueClearCount = 0;
    var resetCount = 0;
    final AccountSwitchCoordinator coordinator = AccountSwitchCoordinator(
      clearPendingHealthQueue: () async => queueClearCount++,
      confirmDatabaseAccountSwitch: () async {
        try {
          await settings.changeAccountScope(
            scopeAlreadyReplaced: binding.boundUserId == 'new-user',
            replaceScope: () => binding.clearBusinessDataAndBind('new-user'),
          );
          return true;
        } catch (_) {
          return false;
        }
      },
      isScopeAlreadyReplaced: () => binding.boundUserId == 'new-user',
      resetInMemoryState: () => resetCount++,
    );

    await expectLater(
      coordinator.confirm(),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          '中文恢复原因',
          '本地账号数据已切换，新账号功能装配待恢复。重试不会再次清理数据。',
        ),
      ),
    );
    expect(queueClearCount, 1);
    expect(storage.atomicReplacementCount, 1);
    expect(binding.boundUserId, 'new-user');
    expect(runtime.isAccountChanging, isTrue);
    expect(runtime.recoveryFailures['core.identity'], isNotNull);
    expect(resetCount, 0);

    await coordinator.confirm();

    expect(queueClearCount, 1);
    expect(storage.atomicReplacementCount, 1);
    expect(runtime.isAccountChanging, isFalse);
    expect(runtime.recoveryFailures['core.identity'], isNull);
    expect(resetCount, 1);
    await runtime.shutdown();
    runtime.dispose();
  });
}

class _CountingAccountStorage extends InMemoryLocalStorageService {
  int atomicReplacementCount = 0;

  @override
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  }) async {
    atomicReplacementCount++;
    await super.replaceBusinessDataAtomically(
      preservedKeys: preservedKeys,
      replacementDocuments: replacementDocuments,
    );
  }
}

class _FailOnceAssemblyPlugin extends TrainMatePlugin {
  int attempts = 0;

  @override
  final PluginDescriptor descriptor = PluginDescriptor(
    id: 'feature.ai_coach',
    type: PluginType.feature,
    version: '1.0.0',
    name: 'AI 教练兼容入口',
    description: '测试账号恢复时的一次装配失败',
    dependencies: const <String>['core.history'],
    capabilities: const <String>['feature.ai_coach.service'],
  );

  @override
  Future<void> initialize(PluginContext context) async {
    attempts++;
    if (attempts == 1) throw StateError('模拟新域装配失败');
    context.registerCapability(
      'feature.ai_coach.service',
      FeatureService(context),
    );
  }
}
