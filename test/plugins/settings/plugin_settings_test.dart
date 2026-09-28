import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trainflow_ai/features/auth/data/account_binding_service.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/feature_access.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/features/feature_service.dart';
import 'package:trainflow_ai/plugins/settings/plugin_settings.dart';
import 'package:trainflow_ai/plugins/settings/plugin_settings_controller.dart';
import 'package:trainflow_ai/plugins/settings/plugin_settings_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('首次升级保持全部默认能力，未知未来标识在有效v1设置中原样保留', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    storage.saveJson(pluginSettingsStorageKey, <String, dynamic>{
      'version': 1,
      'enabledOverrides': <String, bool>{'future.example': false},
    });
    final PluginRuntime runtime = _runtime();
    final PluginSettingsController controller = PluginSettingsController(
      runtime: runtime,
      storage: storage,
    );
    await runtime.initialize(enabledIds: controller.desiredEnabledIds());

    expect(
        runtime.registry.descriptors.values
            .where((PluginDescriptor item) => item.defaultEnabled)
            .every((PluginDescriptor item) => runtime.isEnabled(item.id)),
        isTrue);
    await controller.setEnabled('feature.motion_check', false);

    expect(
      storage.readJson(pluginSettingsStorageKey)?['enabledOverrides'],
      <String, bool>{
        'future.example': false,
        'feature.motion_check': false,
      },
    );
    await runtime.shutdown();
    runtime.dispose();
  });

  test('损坏和高版本设置临时使用默认组合，但必须显式恢复后才可修改', () async {
    for (final Map<String, dynamic> document in <Map<String, dynamic>>[
      <String, dynamic>{
        'version': 1,
        'enabledOverrides': <String, Object>{'x': 1}
      },
      <String, dynamic>{'version': 2, 'enabledOverrides': <String, bool>{}},
      <String, dynamic>{'version': 1.0, 'enabledOverrides': <String, bool>{}},
      <String, dynamic>{'version': '1', 'enabledOverrides': <String, bool>{}},
      <String, dynamic>{'version': null, 'enabledOverrides': <String, bool>{}},
      <String, dynamic>{'enabledOverrides': <String, bool>{}},
    ]) {
      final InMemoryLocalStorageService storage = InMemoryLocalStorageService()
        ..saveJson(pluginSettingsStorageKey, document);
      final PluginRuntime runtime = _runtime();
      final PluginSettingsController controller = PluginSettingsController(
        runtime: runtime,
        storage: storage,
      );
      await runtime.initialize(enabledIds: controller.desiredEnabledIds());

      expect(controller.state.recoveryMessage, isNotNull);
      await expectLater(
        controller.setEnabled('feature.motion_check', false),
        throwsStateError,
      );
      expect(storage.readJson(pluginSettingsStorageKey), document);

      await controller.restoreDefaults();
      expect(controller.state.recoveryMessage, isNull);
      expect(storage.readJson(pluginSettingsStorageKey), <String, dynamic>{
        'version': 1,
        'enabledOverrides': <String, bool>{},
      });
      await runtime.shutdown();
      runtime.dispose();
    }
  });

  test('保存flush失败时恢复原配置与运行时开关，恢复flush失败时准确标记', () async {
    final _FailingFlushStorage storage = _FailingFlushStorage(failures: 1);
    final PluginRuntime runtime = _runtime();
    final PluginSettingsController controller = PluginSettingsController(
      runtime: runtime,
      storage: storage,
    );
    await runtime.initialize(enabledIds: controller.desiredEnabledIds());

    await expectLater(
      controller.setEnabled('feature.motion_check', false),
      throwsA(isA<PluginSettingsPersistenceException>()),
    );
    expect(runtime.isEnabled('feature.motion_check'), isTrue);
    expect(storage.readJson(pluginSettingsStorageKey), isNull);
    expect(controller.state.operationMessage, contains('已恢复原设置'));
    expect(controller.state.persistenceUnknown, isFalse);

    storage.failures = 2;
    await expectLater(
      controller.setEnabled('feature.motion_check', false),
      throwsA(isA<PluginSettingsPersistenceException>()),
    );
    expect(runtime.isEnabled('feature.motion_check'), isTrue);
    expect(controller.state.operationMessage, contains('恢复落盘也失败'));
    expect(controller.state.persistenceUnknown, isTrue);
    await runtime.shutdown();
    runtime.dispose();
  });

  test('只读恢复存储拒绝修改且运行时组合不变', () async {
    const ReadOnlyRecoveryLocalStorageService storage =
        ReadOnlyRecoveryLocalStorageService();
    final PluginRuntime runtime = _runtime();
    final PluginSettingsController controller = PluginSettingsController(
      runtime: runtime,
      storage: storage,
    );
    await runtime.initialize(enabledIds: controller.desiredEnabledIds());

    await expectLater(
      controller.setEnabled('feature.motion_check', false),
      throwsStateError,
    );
    expect(runtime.isEnabled('feature.motion_check'), isTrue);
    expect(controller.state.isBusy, isFalse);
    await runtime.shutdown();
    runtime.dispose();
  });

  test('显式恢复默认落盘失败时保留原损坏文档和恢复状态', () async {
    final Map<String, dynamic> corrupt = <String, dynamic>{
      'version': 1,
      'enabledOverrides': <String, Object>{'feature.motion_check': 1},
    };
    final _FailingFlushStorage storage = _FailingFlushStorage(failures: 1)
      ..saveJson(pluginSettingsStorageKey, corrupt);
    final PluginRuntime runtime = _runtime();
    final PluginSettingsController controller = PluginSettingsController(
      runtime: runtime,
      storage: storage,
    );
    await runtime.initialize(enabledIds: controller.desiredEnabledIds());

    await expectLater(
      controller.restoreDefaults(),
      throwsA(isA<PluginSettingsPersistenceException>()),
    );

    expect(storage.readJson(pluginSettingsStorageKey), corrupt);
    expect(controller.state.recoveryMessage, isNotNull);
    expect(controller.state.operationMessage, contains('已恢复原设置'));
    expect(controller.state.isBusy, isFalse);
    expect(controller.state.persistenceUnknown, isFalse);
    await runtime.shutdown();
    runtime.dispose();
  });

  test('账号清理后重读默认设置，旧epoch操作失效且装配失败重试不重复清理', () async {
    final _CountingAccountStorage storage = _CountingAccountStorage()
      ..saveJson(AccountBindingService.installationIdKey,
          <String, dynamic>{'value': 'device'})
      ..saveJson(AccountBindingService.accountBindingKey,
          <String, dynamic>{'userId': 'old-user'})
      ..saveJson(pluginSettingsStorageKey, <String, dynamic>{
        'version': 1,
        'enabledOverrides': <String, bool>{'feature.ai_coach': false},
      });
    final _FailOncePlugin flaky = _FailOncePlugin();
    final PluginRuntime runtime = _runtime(
      replacements: <String, TrainMatePlugin>{'feature.ai_coach': flaky},
    );
    final PluginSettingsController controller = PluginSettingsController(
      runtime: runtime,
      storage: storage,
    );
    await runtime.initialize(enabledIds: controller.desiredEnabledIds());
    final FeatureOperation oldOperation =
        runtime.beginOperation('feature.motion_check');
    final AccountBindingService binding = AccountBindingService(storage);

    await expectLater(
      controller.changeAccountScope(
        scopeAlreadyReplaced: binding.boundUserId == 'new-user',
        replaceScope: () => binding.clearBusinessDataAndBind('new-user'),
      ),
      throwsStateError,
    );
    expect(storage.atomicReplacementCount, 1);
    expect(binding.boundUserId, 'new-user');
    expect(runtime.isAccountChanging, isTrue);
    expect(runtime.recoveryFailures['core.identity'], isNotNull);

    await controller.changeAccountScope(
      scopeAlreadyReplaced: binding.boundUserId == 'new-user',
      replaceScope: () => binding.clearBusinessDataAndBind('new-user'),
    );
    expect(storage.atomicReplacementCount, 1);
    expect(runtime.isAccountChanging, isFalse);
    expect(runtime.recoveryFailures['core.identity'], isNull);
    expect(runtime.isEnabled('feature.ai_coach'), isTrue);
    expect(storage.readJson(pluginSettingsStorageKey), isNull);
    await expectLater(oldOperation.commit(() {}), throwsStateError);
    await runtime.shutdown();
    runtime.dispose();
  });

  test('SharedPreferences白名单在服务重建后仍可读取功能设置', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final SharedPreferencesLocalStorageService first =
        await SharedPreferencesLocalStorageService.create();
    first.saveJson(pluginSettingsStorageKey, <String, dynamic>{
      'version': 1,
      'enabledOverrides': <String, bool>{'feature.motion_check': false},
    });
    await first.flush();

    final SharedPreferencesLocalStorageService second =
        await SharedPreferencesLocalStorageService.create();
    expect(
      second.readJson(pluginSettingsStorageKey)?['enabledOverrides'],
      <String, dynamic>{'feature.motion_check': false},
    );
    expect(
      SharedPreferencesLocalStorageService.allowedKeys,
      contains(pluginSettingsStorageKey),
    );
  });

  test('SharedPreferences原始坏JSON按默认组合启动且显式恢复前保留原文', () async {
    const String corrupt = '{不是合法 JSON';
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
      pluginSettingsStorageKey: corrupt,
    });
    final SharedPreferencesLocalStorageService storage =
        await SharedPreferencesLocalStorageService.create();
    final PluginRuntime runtime = _runtime();
    final PluginSettingsController controller = PluginSettingsController(
      runtime: runtime,
      storage: storage,
    );

    await runtime.initialize(enabledIds: controller.desiredEnabledIds());

    expect(runtime.isEnabled('feature.motion_check'), isTrue);
    expect(controller.state.recoveryMessage, contains('已损坏'));
    expect(storage.readRawJsonDocument(pluginSettingsStorageKey), corrupt);
    await expectLater(
      controller.setEnabled('feature.motion_check', false),
      throwsStateError,
    );
    expect(storage.readRawJsonDocument(pluginSettingsStorageKey), corrupt);

    await controller.restoreDefaults();
    expect(controller.state.recoveryMessage, isNull);
    expect(storage.readJson(pluginSettingsStorageKey), <String, dynamic>{
      'version': 1,
      'enabledOverrides': <String, dynamic>{},
    });
    await runtime.shutdown();
    runtime.dispose();
  });

  test('SharedPreferences空字符串按损坏设置恢复且显式恢复前不覆盖', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
      pluginSettingsStorageKey: '',
    });
    final SharedPreferencesLocalStorageService storage =
        await SharedPreferencesLocalStorageService.create();
    final PluginRuntime runtime = _runtime();
    final PluginSettingsController controller = PluginSettingsController(
      runtime: runtime,
      storage: storage,
    );

    await runtime.initialize(enabledIds: controller.desiredEnabledIds());

    expect(runtime.isEnabled('feature.motion_check'), isTrue);
    expect(controller.state.recoveryMessage, contains('已损坏'));
    expect(storage.readRawJsonDocument(pluginSettingsStorageKey), '');
    await expectLater(
      controller.setEnabled('feature.motion_check', false),
      throwsStateError,
    );
    expect(storage.readRawJsonDocument(pluginSettingsStorageKey), '');

    await controller.restoreDefaults();
    expect(controller.state.recoveryMessage, isNull);
    expect(storage.readJson(pluginSettingsStorageKey), <String, dynamic>{
      'version': 1,
      'enabledOverrides': <String, dynamic>{},
    });
    await runtime.shutdown();
    runtime.dispose();
  });

  test('空字符串显式恢复落盘失败时保留原字节并可重试', () async {
    final _RawFailingStorage storage = _RawFailingStorage('', failures: 1);
    final PluginRuntime runtime = _runtime();
    final PluginSettingsController controller = PluginSettingsController(
      runtime: runtime,
      storage: storage,
    );
    await runtime.initialize(enabledIds: controller.desiredEnabledIds());

    await expectLater(
      controller.restoreDefaults(),
      throwsA(isA<PluginSettingsPersistenceException>()),
    );

    expect(storage.readRawJsonDocument(pluginSettingsStorageKey), '');
    expect(controller.state.recoveryMessage, isNotNull);
    expect(controller.state.operationMessage, contains('已恢复原设置'));
    expect(controller.state.isBusy, isFalse);

    await controller.restoreDefaults();
    expect(controller.state.recoveryMessage, isNull);
    expect(storage.raw, '{"version":1,"enabledOverrides":{}}');
    await runtime.shutdown();
    runtime.dispose();
  });

  test('原始坏JSON显式恢复落盘失败时恢复原字节并保持可重试状态', () async {
    const String corrupt = ' {坏 JSON 保留空格';
    final _RawFailingStorage storage = _RawFailingStorage(corrupt, failures: 1);
    final PluginRuntime runtime = _runtime();
    final PluginSettingsController controller = PluginSettingsController(
      runtime: runtime,
      storage: storage,
    );
    await runtime.initialize(enabledIds: controller.desiredEnabledIds());

    await expectLater(
      controller.restoreDefaults(),
      throwsA(isA<PluginSettingsPersistenceException>()),
    );

    expect(storage.readRawJsonDocument(pluginSettingsStorageKey), corrupt);
    expect(controller.state.recoveryMessage, isNotNull);
    expect(controller.state.isBusy, isFalse);
    await runtime.shutdown();
    runtime.dispose();
  });
}

PluginRuntime _runtime({
  Map<String, TrainMatePlugin> replacements = const <String, TrainMatePlugin>{},
}) {
  return PluginRuntime(
    PluginRegistry(plugins: builtInDistribution(replacements: replacements)),
  );
}

class _FailingFlushStorage extends InMemoryLocalStorageService {
  _FailingFlushStorage({required this.failures});
  int failures;

  @override
  Future<void> flush() async {
    if (failures > 0) {
      failures--;
      throw StateError('模拟写入失败');
    }
  }
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

class _RawFailingStorage
    implements LocalStorageService, RawJsonDocumentStorage {
  _RawFailingStorage(this.raw, {required this.failures});

  String? raw;
  int failures;

  @override
  String? readRawJsonDocument(String key) => raw;

  @override
  void saveRawJsonDocument(String key, String value) => raw = value;

  @override
  Map<String, dynamic>? readJson(String key) => throw const FormatException();

  @override
  void saveJson(String key, Map<String, dynamic> value) {
    raw = '{"version":1,"enabledOverrides":{}}';
  }

  @override
  void remove(String key) => raw = null;

  @override
  void clearBusinessData({Set<String> preservedKeys = const <String>{}}) {
    raw = null;
  }

  @override
  Future<void> flush() async {
    if (failures > 0) {
      failures--;
      throw StateError('模拟写入失败');
    }
  }

  @override
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  }) async {
    clearBusinessData(preservedKeys: preservedKeys);
    for (final MapEntry<String, Map<String, dynamic>> entry
        in replacementDocuments.entries) {
      saveJson(entry.key, entry.value);
    }
    await flush();
  }
}

class _FailOncePlugin extends TrainMatePlugin {
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
