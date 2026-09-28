import 'dart:async';

import 'package:flutter/foundation.dart';

import 'feature_contribution.dart';
import 'plugin_context.dart';
import 'plugin_descriptor.dart';
import 'plugin_exception.dart';
import 'plugin_skill_binding.dart';
import 'trainmate_plugin.dart';

enum PluginStatus { waiting, loading, running, failed, unloading, stopped }

class PluginOperationResult {
  PluginOperationResult(
      {Map<String, Object> failures = const {},
      Iterable<String> requiredFailures = const [],
      Iterable<PluginCleanupError> cleanupErrors = const []})
      : failures = Map.unmodifiable(failures),
        requiredFailures = Set.unmodifiable(requiredFailures),
        cleanupErrors = List.unmodifiable(cleanupErrors);
  final Map<String, Object> failures;
  final Set<String> requiredFailures;
  final List<PluginCleanupError> cleanupErrors;
  bool get hasRequiredFailures => requiredFailures.isNotEmpty;
  bool get isSuccess => failures.isEmpty && cleanupErrors.isEmpty;
}

class _PluginScope {
  _PluginScope(this.context);
  final PluginContext context;
  final Map<String, Object> capabilities = {};
  final Map<String, FeatureContribution> contributions = {};
  bool ready = false;
}

/// 管理已编译的内置插件；仅在完整初始化成功后公开其登记内容。
class PluginRegistry extends ChangeNotifier {
  PluginRegistry(
      {required Iterable<TrainMatePlugin> plugins, this.hostApiVersion = 1}) {
    for (final plugin in plugins) {
      final descriptor = plugin.descriptor;
      if (_plugins.containsKey(descriptor.id)) {
        throw PluginException('duplicate_id', '插件标识重复：${descriptor.id}');
      }
      _plugins[descriptor.id] = plugin;
      _descriptors[descriptor.id] = descriptor;
      _statuses[descriptor.id] = PluginStatus.waiting;
    }
    _validate();
  }

  final int hostApiVersion;
  final Map<String, TrainMatePlugin> _plugins = {};
  final Map<String, PluginDescriptor> _descriptors = {};
  final Map<String, PluginStatus> _statuses = {};
  final Map<String, _PluginScope> _scopes = {};
  final Map<String, Object> _failures = {};
  final Set<String> _enabled = {};
  final List<String> _order = [];
  Future<void> _queue = Future.value();
  bool _disposed = false;
  int _generation = 0;
  PluginOperationResult _lastResult = PluginOperationResult();

  Map<String, PluginDescriptor> get descriptors =>
      Map.unmodifiable(_descriptors);
  Map<String, PluginStatus> get statuses => Map.unmodifiable(_statuses);
  Map<String, Object> get failures => Map.unmodifiable(_failures);
  Set<String> get enabledIds => Set.unmodifiable(_enabled);
  PluginOperationResult get lastResult => _lastResult;

  List<FeatureContribution> get contributions => List.unmodifiable([
        for (final id in _order)
          if (_scopes[id]?.ready == true && _scopes[id]!.context.isActive)
            ..._scopes[id]!.contributions.values,
      ]);

  T? readCapability<T extends Object>(String id) {
    for (final scope in _scopes.values) {
      if (!scope.ready || !scope.context.isActive) continue;
      final value = scope.capabilities[id];
      if (value == null) continue;
      if (value is! T) {
        throw PluginException('capability_type', '能力 $id 的类型不匹配');
      }
      return value;
    }
    return null;
  }

  void _validate() {
    for (final descriptor in _descriptors.values) {
      if (descriptor.hostApiVersion != hostApiVersion) {
        throw PluginException('host_version',
            '插件 ${descriptor.id} 需要宿主接口 ${descriptor.hostApiVersion}，当前为 $hostApiVersion');
      }
      for (final dependency in descriptor.dependencies) {
        if (!_plugins.containsKey(dependency)) {
          throw PluginException(
              'missing_dependency', '插件 ${descriptor.id} 缺少依赖 $dependency');
        }
      }
    }
    final visited = <String>{};
    final active = <String>[];
    void visit(String id) {
      if (active.contains(id)) {
        throw PluginException(
            'dependency_cycle', '插件依赖形成循环：${[...active, id].join(' → ')}');
      }
      if (visited.contains(id)) return;
      active.add(id);
      for (final dependency in _descriptors[id]!.dependencies) {
        visit(dependency);
      }
      active.removeLast();
      visited.add(id);
      _order.add(id);
    }

    for (final id in _plugins.keys) {
      visit(id);
    }
  }

  void _requireKnown(String id) {
    if (!_plugins.containsKey(id)) {
      throw PluginException('unknown_id', '未找到插件 $id');
    }
  }

  Set<String> _closure(Iterable<String> ids) {
    final result = <String>{};
    void visit(String id) {
      _requireKnown(id);
      if (!result.add(id)) return;
      for (final dependency in _descriptors[id]!.dependencies) {
        visit(dependency);
      }
    }

    for (final id in ids) {
      visit(id);
    }
    return result;
  }

  /// 按依赖顺序列出本次将新增启用的插件，供宿主确认与展示。
  List<String> previewEnable(String id) {
    final requested = _closure([id]);
    return List.unmodifiable(_order.where(
        (value) => requested.contains(value) && !_enabled.contains(value)));
  }

  Future<PluginOperationResult> initialize({Set<String>? enabledIds}) {
    final snapshot = enabledIds == null ? null : Set<String>.of(enabledIds);
    return _enqueue(() {
      final requested = snapshot ??
          _descriptors.values
              .where((descriptor) => descriptor.defaultEnabled)
              .map((descriptor) => descriptor.id)
              .toSet();
      return _apply(_closure([
        ...requested,
        ..._descriptors.values
            .where((descriptor) => descriptor.isRequired)
            .map((descriptor) => descriptor.id)
      ]));
    });
  }

  Future<PluginOperationResult> enable(String id) =>
      _enqueue(() => _apply(_closure([..._enabled, id])));

  Future<PluginOperationResult> disable(String id) => _enqueue(() {
        _requireKnown(id);
        if (_descriptors[id]!.isRequired) {
          throw PluginException('required_plugin', '必需插件 $id 不能停用',
              pluginIds: [id]);
        }
        final dependents = _enabled
            .where((other) => other != id && _closure([other]).contains(id))
            .toList();
        if (dependents.isNotEmpty) {
          throw PluginException(
              'enabled_dependents', '插件 $id 仍被已启用插件依赖：${dependents.join('、')}',
              pluginIds: dependents);
        }
        return _apply({..._enabled}..remove(id));
      });

  /// 恢复宿主保存失败前的精确组合，不隐式补入依赖或连带停用插件。
  Future<PluginOperationResult> restoreEnabled(Set<String> enabledIds) {
    final snapshot = Set<String>.of(enabledIds);
    return _enqueue(() {
      final closure = _closure(snapshot);
      if (closure.length != snapshot.length ||
          _descriptors.values.any((descriptor) =>
              descriptor.isRequired && !snapshot.contains(descriptor.id))) {
        throw PluginException('invalid_combination', '恢复组合必须包含所有必需插件及已启用插件的依赖');
      }
      return _apply(snapshot);
    });
  }

  Future<PluginOperationResult> _enqueue(
      Future<PluginOperationResult> Function() operation) {
    if (_disposed) return Future.error(PluginException('disposed', '插件注册表已释放'));
    final next = _queue.then((_) {
      if (_disposed) throw PluginException('disposed', '插件注册表已释放');
      return operation();
    });
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<PluginOperationResult> _apply(Set<String> target,
      {Iterable<PluginCleanupError> priorCleanupErrors = const []}) async {
    final generation = _generation;
    final cleanupErrors = <PluginCleanupError>[...priorCleanupErrors];
    _enabled
      ..clear()
      ..addAll(target);
    // 一次性失效所有待移除作用域，再按逆拓扑顺序等待清理。
    for (final id in _order.reversed) {
      if (!target.contains(id)) _scopes[id]?.context.invalidate();
    }
    _notify();
    for (final id in _order.reversed) {
      if (!target.contains(id)) {
        cleanupErrors.addAll(await _stop(id));
      }
    }
    for (final id in _order) {
      if (_disposed || generation != _generation) break;
      if (!target.contains(id) || _statuses[id] == PluginStatus.running) {
        continue;
      }
      final descriptor = _descriptors[id]!;
      final unavailable = descriptor.dependencies
          .where((dependency) =>
              _statuses[dependency] != PluginStatus.running ||
              _scopes[dependency]?.context.isActive != true)
          .toList();
      if (unavailable.isNotEmpty) {
        _failures[id] = PluginException(
            'dependency_failed', '插件 $id 的依赖不可用：${unavailable.join('、')}');
        _statuses[id] = PluginStatus.failed;
        _notify();
        continue;
      }
      late final _PluginScope scope;
      final context = PluginContext(
          descriptor: descriptor,
          registerCapability: (key, value) {
            if (_scopes.values.any((other) =>
                other.context.isActive &&
                other.capabilities.containsKey(key))) {
              throw PluginException(
                  'duplicate_capability', '能力 $key 已由其他登记占用，插件 $id 初始化失败');
            }
            scope.capabilities[key] = value;
          },
          readCapability: (key) {
            // 消费方只读取自己及显式依赖闭包内已经就绪的服务。
            final allowed = _closure([id]);
            for (final owner in allowed) {
              final candidate = _scopes[owner];
              if (candidate?.ready == true &&
                  candidate!.context.isActive &&
                  candidate.capabilities.containsKey(key)) {
                return candidate.capabilities[key];
              }
            }
            return null;
          },
          registerContribution: (contribution) {
            if (_scopes.values.any((other) =>
                other.context.isActive &&
                other.contributions.containsKey(contribution.id))) {
              throw PluginException(
                  'duplicate_contribution', '扩展标识重复：${contribution.id}');
            }
            scope.contributions[contribution.id] = contribution;
          });
      scope = _PluginScope(context);
      _scopes[id] = scope;
      _statuses[id] = PluginStatus.loading;
      _failures.remove(id);
      _notify();
      try {
        await Future.any<void>([
          _plugins[id]!.initialize(context),
          context.whenInvalidated.then((_) {
            throw PluginException('cancelled', '插件 $id 初始化已取消');
          }),
        ]);
        context.checkActive();
        for (final skill in descriptor.skills) {
          if (skill.execution == SkillExecution.local &&
              !scope.capabilities.containsKey(skill.capabilityId)) {
            throw PluginException('missing_skill_implementation',
                '插件 $id 的技能 ${skill.name} 未注册实现');
          }
        }
        scope.ready = true;
        _statuses[id] = PluginStatus.running;
      } catch (error) {
        context.invalidate();
        scope.ready = false;
        cleanupErrors.addAll(await context.dispose());
        _scopes.remove(id);
        _failures[id] = error;
        _statuses[id] = PluginStatus.failed;
      }
      _notify();
    }
    _lastResult = PluginOperationResult(
        failures: _failures,
        requiredFailures:
            _failures.keys.where((id) => _descriptors[id]!.isRequired),
        cleanupErrors: cleanupErrors);
    _notify();
    return _lastResult;
  }

  Future<List<PluginCleanupError>> _stop(String id) async {
    final scope = _scopes.remove(id);
    _failures.remove(id);
    if (scope != null) {
      scope.context.invalidate();
      scope.ready = false;
      _statuses[id] = PluginStatus.unloading;
      _notify();
      final errors = await scope.context.dispose();
      _statuses[id] = PluginStatus.stopped;
      _notify();
      return errors;
    }
    _statuses[id] = PluginStatus.stopped;
    return const [];
  }

  /// 宿主退出时可释放必需插件；返回所有清理失败，重复调用不重复释放。
  Future<PluginOperationResult> shutdown() {
    // 取消后初始化分支会移除作用域，先保留它们以汇总本次关闭触发的清理报告。
    final cancelledInitializations = [
      for (final entry in _scopes.entries)
        if (_statuses[entry.key] == PluginStatus.loading) entry.value.context,
    ];
    _generation++;
    for (final scope in _scopes.values) {
      scope.context.invalidate();
    }
    return _enqueue(() async {
      final cleanupErrors = <PluginCleanupError>[];
      for (final context in cancelledInitializations) {
        // 复用已完成的幂等清理结果，不重复释放资源。
        cleanupErrors.addAll(await context.dispose());
      }
      return _apply({}, priorCleanupErrors: cleanupErrors);
    });
  }

  /// Flutter 同步销毁立即撤销访问；需要清理结果的宿主应先 await shutdown。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    for (final scope in _scopes.values) {
      scope.context.invalidate();
    }
    unawaited(_queue.then((_) => _apply({})));
    super.dispose();
  }
}
