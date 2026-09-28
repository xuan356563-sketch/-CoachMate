import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/plugin_core.dart';
import '../features/feature_service.dart';
import '../features/built_in_features.dart';
import '../sports/sport_capability_directory.dart';
import 'feature_access.dart';

class PluginRuntime extends ChangeNotifier implements FeatureAccess {
  PluginRuntime(this.registry, {this.compatibilityMode = false}) {
    registry.addListener(_registryChanged);
  }
  final PluginRegistry registry;

  /// 独立旧组件测试允许默认发行；生产必须先 initialize 再挂载业务树。
  final bool compatibilityMode;
  bool initialized = false;
  bool _switching = false;
  bool _accountChanging = false;
  String? _accountRecoveryFailure;
  bool get isAccountChanging =>
      _accountChanging || _accountRecoveryFailure != null;
  bool _disposed = false;
  int _accountEpoch = 0;
  Completer<void>? _commitDrain;
  Future<PluginOperationResult>? _shutdown;
  final Map<String, int> _epochs = {};
  final Map<String, int> _commits = {};
  final Map<String, Map<Object, FutureOr<void> Function()>> _cleanups = {};
  final Map<String, Map<Object, String? Function()>> _locks = {};
  final Map<String, Map<Object, FutureOr<void> Function()>> _restores = {};
  final Set<String> _recoveryBlocked = {};
  final Map<String, String> _recoveryFailures = {};
  Map<String, String> get recoveryFailures => Map.unmodifiable({
        ..._recoveryFailures,
        if (_accountRecoveryFailure != null)
          'core.identity': _accountRecoveryFailure!,
      });
  void _registryChanged() {
    // 生命周期订阅只看到完成切换后的可用状态，避免 loading/running 期间过早重绑。
    if (!_switching) _emitChange();
  }

  void _emitChange() {
    if (!_disposed) notifyListeners();
  }

  List<FeatureContribution> get contributions => !initialized &&
          compatibilityMode
      ? [for (final f in builtInFeatures) ...f.contributions]
      : registry.contributions
          .where((contribution) =>
              !_recoveryBlocked.any((id) => contribution.id.startsWith('$id.')))
          .toList(growable: false);
  SportCapabilityDirectory get sportDirectory => !initialized &&
          compatibilityMode
      ? SportCapabilityDirectory.builtIn()
      : SportCapabilityDirectory(SportCapabilityDirectory.fromRegistry(registry)
          .strategies
          .where((strategy) => isEnabled(strategy.definition.pluginRef.id)));
  List<PluginRef> decoratePlanSources(List<PluginRef> sources) {
    requireEnabled('feature.training_plan');
    return [...sources, registry.descriptors['feature.training_plan']!.ref];
  }

  List<PluginRef>? resolvePlanSources(List<PluginRef>? sources) {
    if (sources == null || sources.isEmpty) return null;
    final result = <PluginRef>[];
    for (final source in sources) {
      if (!isEnabled(source.id)) return null;
      final descriptor = registry.descriptors[source.id];
      if (descriptor == null) return null;
      result.add(descriptor.ref);
    }
    return List.unmodifiable(result);
  }

  bool get isSwitching => _switching;
  int get accountEpoch => _accountEpoch;
  bool get hasRequiredFailures =>
      initialized &&
      registry.descriptors.values.any((d) =>
          d.isRequired && registry.statuses[d.id] != PluginStatus.running);
  @override
  bool isEnabled(String id) =>
      !_disposed &&
      !_recoveryBlocked.contains(id) &&
      (registry.statuses[id] == PluginStatus.running ||
          (!initialized &&
              compatibilityMode &&
              registry.descriptors[id]?.defaultEnabled == true));
  @override
  bool isWritable(String id) =>
      isEnabled(id) &&
      !_switching &&
      !hasRequiredFailures &&
      _accountRecoveryFailure == null;
  @override
  void requireEnabled(String id) {
    if (!isWritable(id)) {
      throw StateError(
          '${registry.descriptors[id]?.name ?? id}当前不可用，请完成切换或恢复该功能后重试。');
    }
    final feature = builtInFeatures.where((feature) => feature.id == id);
    if (feature.isNotEmpty &&
        !contributions.any((c) =>
            c is FormContribution && c.formId == feature.single.directory)) {
      throw StateError('该功能的动作表单尚未就绪，请恢复功能后重试。');
    }
  }

  Future<PluginOperationResult> initialize({Set<String>? enabledIds}) async {
    _switching = true;
    try {
      return await registry.initialize(enabledIds: enabledIds);
    } finally {
      initialized = true;
      _switching = false;
      _registryChanged();
    }
  }

  List<PluginDescriptor> previewEnable(String id) => List.unmodifiable(
      registry.previewEnable(id).map((id) => registry.descriptors[id]!));
  List<String> checkDisable(String id) {
    final descriptor = registry.descriptors[id];
    if (descriptor == null) return ['未找到该功能。'];
    final reasons = <String>[];
    if (_switching) reasons.add('正在切换功能，请稍后重试。');
    if (_accountRecoveryFailure != null) reasons.add(_accountRecoveryFailure!);
    if (descriptor.isRequired) reasons.add('${descriptor.name}是必需能力，不能关闭。');
    for (final other in registry.descriptors.values) {
      if (other.id != id &&
          registry.enabledIds.contains(other.id) &&
          _dependsOn(other.id, id)) {
        reasons.add('请先关闭依赖此能力的${other.name}。');
      }
    }
    if ((_commits[id] ?? 0) > 0) reasons.add('${descriptor.name}正在保存，请等待提交完成。');
    for (final lock in _locks[id]?.values ?? <String? Function()>[]) {
      final reason = lock();
      if (reason != null) reasons.add(reason);
    }
    return List.unmodifiable(reasons);
  }

  bool _dependsOn(String owner, String id) =>
      registry.descriptors[owner]!.dependencies
          .any((dependency) => dependency == id || _dependsOn(dependency, id));
  Future<PluginOperationResult> enable(String id,
          {Future<void> Function(Set<String>)? persist}) =>
      _change(id, true, persist);
  Future<PluginOperationResult> disable(String id,
      {Future<void> Function(Set<String>)? persist}) async {
    final reasons = checkDisable(id);
    if (reasons.isNotEmpty) throw StateError(reasons.join('\n'));
    return _change(id, false, persist);
  }

  Future<PluginOperationResult> _change(String id, bool enable,
      Future<void> Function(Set<String>)? persist) async {
    if (_switching) throw StateError('正在切换功能，请稍后重试。');
    if (_accountRecoveryFailure != null) {
      throw StateError(_accountRecoveryFailure!);
    }
    final previous = registry.enabledIds;
    final previousFailures = registry.failures.keys.toSet();
    final resources =
        Map<Object, FutureOr<void> Function()>.of(_cleanups[id] ?? {});
    final restorers =
        Map<Object, FutureOr<void> Function()>.of(_restores[id] ?? {});
    _switching = true;
    _epochs[id] = (_epochs[id] ?? 0) + 1;
    _emitChange();
    try {
      if (!enable) await _release(id);
      final result =
          enable ? await registry.enable(id) : await registry.disable(id);
      if (result.cleanupErrors.isNotEmpty ||
          result.failures.keys.any((key) => !previousFailures.contains(key)) ||
          (enable && !isEnabled(id))) {
        throw StateError('功能切换失败，请重试恢复。');
      }
      await persist?.call(registry.enabledIds);
      if (!enable) _restores.remove(id);
      return result;
    } catch (_) {
      final restored = await registry.restoreEnabled(previous);
      if (restored.cleanupErrors.isNotEmpty ||
          restored.failures.keys
              .any((key) => !previousFailures.contains(key))) {
        throw StateError('功能切换及恢复失败，请重启应用恢复；原训练数据已保留。');
      }
      if (!enable && previous.contains(id)) {
        // 先恢复清理责任，再调用可能部分启动后失败的外部恢复函数。
        if (resources.isNotEmpty) (_cleanups[id] ??= {}).addAll(resources);
        if (restorers.isNotEmpty) (_restores[id] ??= {}).addAll(restorers);
        try {
          for (final restore in restorers.values) {
            await restore();
          }
        } catch (_) {
          _recoveryBlocked.add(id);
          _recoveryFailures[id] = '原启用设置已恢复，但活动资源恢复失败，请重启应用。';
          try {
            await _release(id);
          } catch (_) {
            // 未停止项仍在 _cleanups 中，由后续停用或退出重试。
            _recoveryFailures[id] = '活动资源恢复失败，部分资源尚未停止，已暂停该功能，请重试停止或重启应用。';
          }
          throw StateError(_recoveryFailures[id]!);
        }
      }
      rethrow;
    } finally {
      _switching = false;
      _registryChanged();
    }
  }

  @override
  FeatureOperation beginOperation(String id,
      {Iterable<String> dependencies = const []}) {
    final account = _accountEpoch;
    final epochs = <String, int>{};
    var committing = false;
    final Object commitZoneKey = Object();
    void include(Iterable<String> ids) {
      if (committing) throw StateError('提交期间不能更改操作来源。');
      void add(String owner) {
        requireEnabled(owner);
        if (epochs.containsKey(owner)) return;
        epochs[owner] = _epochs[owner] ?? 0;
        for (final dependency in registry.descriptors[owner]!.dependencies) {
          add(dependency);
        }
      }

      for (final owner in ids) {
        add(owner);
      }
    }

    include([id, ...dependencies]);
    void check() {
      if (account != _accountEpoch) {
        throw FeatureOperationInvalidation.accountChanged();
      }
      for (final entry in epochs.entries) {
        if (entry.value != (_epochs[entry.key] ?? 0)) {
          throw FeatureOperationInvalidation.sourcesChanged();
        }
      }
      // 先识别来源代际失效，再检查当前可用态，避免停用被误报为业务失败。
      for (final owner in epochs.keys) {
        requireEnabled(owner);
      }
    }

    return FeatureOperation(
        check: check,
        containsSource: epochs.containsKey,
        includeDependencies: (ids) {
          check();
          include(ids);
        },
        commit: <T>(FutureOr<T> Function() write) async {
          check();
          if (committing) {
            if (Zone.current[commitZoneKey] == true) {
              return await write();
            }
            throw StateError('同一操作正在提交，请勿重复保存。');
          }
          committing = true;
          _commitDrain ??= Completer<void>();
          final owners = epochs.keys.toList();
          for (final owner in owners) {
            _commits[owner] = (_commits[owner] ?? 0) + 1;
          }
          try {
            return await runZoned<Future<T>>(
              () async => await write(),
              zoneValues: <Object?, Object?>{commitZoneKey: true},
            );
          } finally {
            committing = false;
            for (final owner in owners) {
              _commits[owner] = _commits[owner]! - 1;
            }
            if (_commits.values.every((count) => count == 0)) {
              _commitDrain?.complete();
              _commitDrain = null;
            }
          }
        });
  }

  @override
  void Function() registerCleanup(String id, FutureOr<void> Function() cleanup,
      {FutureOr<void> Function()? onRestore}) {
    requireEnabled(id);
    final key = Object();
    (_cleanups[id] ??= {})[key] = cleanup;
    if (onRestore != null) (_restores[id] ??= {})[key] = onRestore;
    return () {
      _cleanups[id]?.remove(key);
      _restores[id]?.remove(key);
    };
  }

  /// 读取正在使用能力的业务锁，不包含启停依赖提示。
  List<String> activeUseReasons(String id) => [for (final reason in _locks[id]?.values ?? <String? Function()>[]) if (reason() case final String message) message];

  @override
  void Function() registerDisableLock(String id, String? Function() reason) {
    final key = Object();
    (_locks[id] ??= {})[key] = reason;
    return () => _locks[id]?.remove(key);
  }

  FeatureService? service(String id) =>
      registry.readCapability<FeatureService>('$id.service');
  Future<void> _release(String id) async {
    final callbacks = _cleanups[id]?.entries.toList().reversed ??
        <MapEntry<Object, FutureOr<void> Function()>>[];
    final errors = <Object>[];
    for (final entry in callbacks) {
      try {
        await entry.value();
        // 只有实际成功停止后才撤销责任；失败项必须可再次清理。
        if (identical(_cleanups[id]?[entry.key], entry.value)) {
          _cleanups[id]?.remove(entry.key);
        }
      } catch (error) {
        errors.add(error);
      }
    }
    if (_cleanups[id]?.isEmpty == true) _cleanups.remove(id);
    if (errors.isNotEmpty) throw StateError('功能资源清理失败，请重试或重启应用。');
  }

  /// 账户切换必须在真正替换存储域前 await；已开始的本地提交不能跨域。
  Future<void> changeAccountScope(
      {FutureOr<void> Function()? replaceScope}) async {
    if (_switching || _commits.values.any((n) => n > 0)) {
      throw StateError('操作正在保存或功能正在切换，请稍后切换账户。');
    }
    if (_accountRecoveryFailure != null && replaceScope == null) {
      throw StateError('账户仍需恢复，请显式重试账户域替换或重启应用。');
    }
    _switching = true;
    _accountChanging = true;
    _accountEpoch++;
    _emitChange();
    var replacing = false;
    try {
      for (final id in _cleanups.keys.toList()) {
        await _release(id);
        _restores.remove(id);
      }
      replacing = replaceScope != null;
      await replaceScope?.call();
      _accountRecoveryFailure = null;
    } catch (_) {
      // 换域是否已部分生效无法由宿主判断；失败后不能恢复可写状态。
      _accountRecoveryFailure = replacing
          ? '账户数据域替换失败，已暂停写入与历史读取，请重试账户切换或重启应用。'
          : '旧账户资源未能全部停止，已暂停写入与历史读取，请重试账户切换或重启应用。';
      throw StateError(_accountRecoveryFailure!);
    } finally {
      _accountChanging = false;
      _accountEpoch++;
      _switching = false;
      _registryChanged();
    }
  }

  /// 宿主主动退出时等待已经开始的提交，汇总所有资源清理结果。
  Future<PluginOperationResult> shutdown() {
    _switching = true;
    _accountEpoch++;
    return _shutdown ??= _shutdownAll();
  }

  Future<List<PluginCleanupError>> _releaseAll() async {
    await _commitDrain?.future;
    final errors = <PluginCleanupError>[];
    for (final id in _cleanups.keys.toList()) {
      try {
        await _release(id);
      } catch (error, stackTrace) {
        errors.add(PluginCleanupError(
            pluginId: id, error: error, stackTrace: stackTrace));
      }
    }
    _restores.clear();
    return errors;
  }

  Future<PluginOperationResult> _shutdownAll() async {
    final errors = await _releaseAll();
    final result = await registry.shutdown();
    // 失败资源仍有责任登记，允许再次 shutdown 或 dispose 重试。
    if (_cleanups.isNotEmpty) _shutdown = null;
    return PluginOperationResult(
        failures: result.failures,
        requiredFailures: result.requiredFailures,
        cleanupErrors: [...errors, ...result.cleanupErrors]);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _accountEpoch++;
    registry.removeListener(_registryChanged);
    // Flutter 的同步销毁仍释放登记资源；需要错误报告的宿主应先 await shutdown。
    if (_shutdown == null) {
      unawaited(_releaseAll().then((errors) {
        if (errors.isNotEmpty) debugPrint('功能资源退出清理失败，请在下次启动时检查恢复状态。');
      }));
    }
    registry.dispose();
    super.dispose();
  }
}
