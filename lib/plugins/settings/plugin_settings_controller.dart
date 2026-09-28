import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../services/local_storage_service.dart';
import '../application/plugin_runtime.dart';
import '../application/plugin_runtime_provider.dart';
import '../core/plugin_descriptor.dart';
import '../core/plugin_registry.dart';
import 'plugin_settings.dart';
import 'plugin_settings_repository.dart';

class PluginSettingsState {
  const PluginSettingsState({
    required this.settings,
    required this.rawDocument,
    this.rawDocumentText,
    this.rawDocumentUnreadable = false,
    this.recoveryMessage,
    this.operationMessage,
    this.isBusy = false,
    this.persistenceUnknown = false,
  });

  final PluginSettings settings;
  final Map<String, dynamic>? rawDocument;
  final String? rawDocumentText;
  final bool rawDocumentUnreadable;
  final String? recoveryMessage;
  final String? operationMessage;
  final bool isBusy;
  final bool persistenceUnknown;

  PluginSettingsState copyWith({
    PluginSettings? settings,
    Map<String, dynamic>? rawDocument,
    bool replaceRawDocument = false,
    String? rawDocumentText,
    bool replaceRawDocumentText = false,
    bool? rawDocumentUnreadable,
    String? recoveryMessage,
    bool clearRecoveryMessage = false,
    String? operationMessage,
    bool clearOperationMessage = false,
    bool? isBusy,
    bool? persistenceUnknown,
  }) {
    return PluginSettingsState(
      settings: settings ?? this.settings,
      rawDocument:
          replaceRawDocument ? rawDocument : (rawDocument ?? this.rawDocument),
      rawDocumentText: replaceRawDocumentText
          ? rawDocumentText
          : (rawDocumentText ?? this.rawDocumentText),
      rawDocumentUnreadable:
          rawDocumentUnreadable ?? this.rawDocumentUnreadable,
      recoveryMessage: clearRecoveryMessage
          ? null
          : (recoveryMessage ?? this.recoveryMessage),
      operationMessage: clearOperationMessage
          ? null
          : (operationMessage ?? this.operationMessage),
      isBusy: isBusy ?? this.isBusy,
      persistenceUnknown: persistenceUnknown ?? this.persistenceUnknown,
    );
  }
}

class PluginSettingsController extends ChangeNotifier {
  PluginSettingsController({
    required this.runtime,
    required LocalStorageService storage,
  }) : _repository = PluginSettingsRepository(storage) {
    _reload();
  }

  final PluginRuntime runtime;
  final PluginSettingsRepository _repository;
  late PluginSettingsState _state;
  int _scopeEpoch = 0;

  PluginSettingsState get state => _state;

  Set<String> desiredEnabledIds() =>
      _state.settings.enabledIds(runtime.registry.descriptors);

  void _reload() {
    final PluginSettingsReadResult result = _repository.read();
    _state = PluginSettingsState(
      settings: result.settings,
      rawDocument: result.rawDocument,
      rawDocumentText: result.rawDocumentText,
      rawDocumentUnreadable: result.rawDocumentUnreadable,
      recoveryMessage: result.recoveryMessage,
    );
  }

  void _publish(PluginSettingsState next) {
    _state = next;
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    if (_state.isBusy) {
      throw StateError('正在处理功能设置，请稍后再试。');
    }
    final PluginDescriptor? descriptor = runtime.registry.descriptors[id];
    if (descriptor == null) throw StateError('未找到该功能。');
    if (descriptor.isRequired) {
      throw StateError('${descriptor.name}是常驻能力，不能关闭。');
    }
    if (_state.recoveryMessage != null) {
      throw StateError(_state.recoveryMessage!);
    }
    if (runtime.isEnabled(id) == enabled) return;

    final int epoch = _scopeEpoch;
    final PluginSettingsState previous = _state;
    _publish(previous.copyWith(
      isBusy: true,
      clearOperationMessage: true,
      persistenceUnknown: false,
    ));
    PluginSettings? nextSettings;
    try {
      Future<void> persist(Set<String> enabledIds) async {
        if (epoch != _scopeEpoch) {
          throw StateError('账户已变化，本次功能设置已取消，请重新操作。');
        }
        nextSettings = previous.settings.forEnabledIds(
          runtime.registry.descriptors,
          enabledIds,
        );
        await _repository.commit(
          nextSettings!,
          previousDocument: previous.rawDocument,
          previousDocumentText: previous.rawDocumentText,
          previousDocumentUnreadable: previous.rawDocumentUnreadable,
        );
      }

      if (enabled) {
        await runtime.enable(id, persist: persist);
      } else {
        await runtime.disable(id, persist: persist);
      }
      if (epoch != _scopeEpoch) return;
      final PluginSettings committed = nextSettings ?? previous.settings;
      _publish(PluginSettingsState(
        settings: committed,
        rawDocument: committed.toJson(),
        operationMessage: enabled
            ? '${descriptor.name}已启用。'
            : '${descriptor.name}已关闭；已有记录仍可在历史记录中查看。',
      ));
    } catch (error) {
      if (epoch != _scopeEpoch) rethrow;
      final bool unknown =
          error is PluginSettingsPersistenceException && error.recoveryFailed;
      _publish(previous.copyWith(
        isBusy: false,
        operationMessage: _messageFor(error),
        persistenceUnknown: unknown,
      ));
      rethrow;
    }
  }

  Future<void> restoreDefaults() async {
    if (_state.isBusy) throw StateError('正在处理功能设置，请稍后再试。');
    final int epoch = _scopeEpoch;
    final PluginSettingsState previous = _state;
    final PluginSettings defaults = const PluginSettings();
    final Set<String> enabled =
        defaults.enabledIds(runtime.registry.descriptors);
    _publish(previous.copyWith(isBusy: true, clearOperationMessage: true));
    try {
      if (!_sameIds(enabled, runtime.registry.enabledIds) ||
          enabled.any((String id) => !runtime.isEnabled(id))) {
        throw StateError('当前功能组合尚未恢复，请重启应用后再恢复默认设置。');
      }
      await _repository.commit(
        defaults,
        previousDocument: previous.rawDocument,
        previousDocumentText: previous.rawDocumentText,
        previousDocumentUnreadable: previous.rawDocumentUnreadable,
      );
      if (epoch != _scopeEpoch) return;
      _publish(PluginSettingsState(
        settings: defaults,
        rawDocument: defaults.toJson(),
        operationMessage: '已恢复默认功能设置。',
      ));
    } catch (error) {
      if (epoch == _scopeEpoch) {
        _publish(previous.copyWith(
          isBusy: false,
          operationMessage: _messageFor(error),
          persistenceUnknown: error is PluginSettingsPersistenceException &&
              error.recoveryFailed,
        ));
      }
      rethrow;
    }
  }

  Future<void> changeAccountScope({
    required bool scopeAlreadyReplaced,
    required FutureOr<void> Function() replaceScope,
  }) async {
    if (_state.isBusy) throw StateError('正在处理功能设置，请稍后切换账户。');
    _scopeEpoch++;
    _publish(_state.copyWith(
      isBusy: true,
      clearOperationMessage: true,
      persistenceUnknown: false,
    ));
    PluginSettingsReadResult? next;
    try {
      await runtime.changeAccountScope(replaceScope: () async {
        if (!scopeAlreadyReplaced) {
          await replaceScope();
        }
        next = _repository.read();
        final PluginOperationResult result = await runtime.registry
            .restoreEnabled(
                next!.settings.enabledIds(runtime.registry.descriptors));
        if (!result.isSuccess || result.hasRequiredFailures) {
          throw StateError('新账户功能装配失败');
        }
      });
      final PluginSettingsReadResult loaded = next ?? _repository.read();
      _publish(PluginSettingsState(
        settings: loaded.settings,
        rawDocument: loaded.rawDocument,
        rawDocumentText: loaded.rawDocumentText,
        rawDocumentUnreadable: loaded.rawDocumentUnreadable,
        recoveryMessage: loaded.recoveryMessage,
      ));
    } catch (error) {
      _publish(_state.copyWith(
        isBusy: false,
        operationMessage: _messageFor(error),
      ));
      rethrow;
    }
  }

  String _messageFor(Object error) {
    if (error is PluginSettingsPersistenceException) return error.message;
    if (error is StateError) return error.message.toString();
    return '功能设置操作失败，请重试；已有训练数据未被清除。';
  }

  bool _sameIds(Set<String> first, Set<String> second) =>
      first.length == second.length && first.containsAll(second);
}

final pluginSettingsControllerProvider =
    ChangeNotifierProvider<PluginSettingsController>((ref) {
  return PluginSettingsController(
    // 运行时内部状态变化由页面直接订阅，这里只取稳定实例。
    // 若订阅 ChangeNotifier，每次启停中间通知都会销毁正在执行的设置事务。
    runtime: ref.read(pluginRuntimeProvider),
    storage: ref.watch(localStorageServiceProvider),
  );
});
