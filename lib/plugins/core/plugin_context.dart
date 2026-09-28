import 'dart:async';

import 'feature_contribution.dart';
import 'plugin_descriptor.dart';
import 'plugin_exception.dart';

class PluginCancellationToken {
  PluginCancellationToken._(this._context);
  final PluginContext _context;
  bool _cancelled = false;
  bool get isCancelled => _cancelled || !_context.isActive;
  void cancel() => _cancelled = true;
  void checkActive() {
    if (isCancelled) throw PluginException('cancelled', '插件任务已取消');
  }
}

/// 同进程可信插件的资源作用域，并非安全沙箱。
/// 异步结果必须经 runGuarded 的同步提交回调写入；不能撤回插件自行发起的外部副作用。
class PluginContext {
  PluginContext(
      {required this.descriptor,
      required void Function(String, Object) registerCapability,
      required Object? Function(String) readCapability,
      required void Function(FeatureContribution) registerContribution})
      : _registerCapability = registerCapability,
        _readCapability = readCapability,
        _registerContribution = registerContribution;

  final PluginDescriptor descriptor;
  final void Function(String, Object) _registerCapability;
  final Object? Function(String) _readCapability;
  final void Function(FeatureContribution) _registerContribution;
  final List<FutureOr<void> Function()> _cleanups = [];
  bool _active = true;
  final Completer<void> _invalidation = Completer<void>();
  Future<void> get whenInvalidated => _invalidation.future;
  Future<List<PluginCleanupError>>? _disposal;
  bool get isActive => _active;

  void checkActive() {
    if (!_active) {
      throw PluginException('inactive', '插件 ${descriptor.id} 的作用域已失效');
    }
  }

  void registerCapability<T extends Object>(String id, T value) {
    checkActive();
    if (!descriptor.capabilities.contains(id)) {
      throw PluginException(
          'undeclared_capability', '插件 ${descriptor.id} 未声明能力 $id');
    }
    _registerCapability(id, value);
  }

  T? readCapability<T extends Object>(String id) {
    checkActive();
    final value = _readCapability(id);
    if (value == null) return null;
    if (value is! T) throw PluginException('capability_type', '能力 $id 的类型不匹配');
    return value;
  }

  void registerContribution(FeatureContribution contribution) {
    checkActive();
    _registerContribution(contribution);
  }

  void addCleanup(FutureOr<void> Function() cleanup) {
    checkActive();
    _cleanups.add(cleanup);
  }

  StreamSubscription<T> listen<T>(Stream<T> stream, void Function(T) onData) {
    checkActive();
    final subscription = stream.listen((value) {
      if (isActive) onData(value);
    });
    addCleanup(subscription.cancel);
    return subscription;
  }

  PluginCancellationToken createCancellationToken() {
    checkActive();
    return PluginCancellationToken._(this);
  }

  Future<bool> runGuarded<T>(
      Future<T> Function(PluginCancellationToken) task, void Function(T) commit,
      {PluginCancellationToken? token}) async {
    checkActive();
    final current = token ?? createCancellationToken();
    if (!identical(current._context, this)) {
      throw PluginException('foreign_token', '任务取消标记不属于当前插件作用域');
    }
    if (current.isCancelled) return false;
    try {
      final result = await task(current);
      if (current.isCancelled) return false;
      commit(result);
      return true;
    } catch (_) {
      if (current.isCancelled) return false;
      rethrow;
    }
  }

  /// 同步失效，确保等待资源清理期间没有新结果提交。
  void invalidate() {
    _active = false;
    if (!_invalidation.isCompleted) _invalidation.complete();
  }

  Future<List<PluginCleanupError>> dispose() {
    invalidate();
    return _disposal ??= _release();
  }

  Future<List<PluginCleanupError>> _release() async {
    final errors = <PluginCleanupError>[];
    while (_cleanups.isNotEmpty) {
      final cleanup = _cleanups.removeLast();
      try {
        await cleanup();
      } catch (error, stackTrace) {
        errors.add(PluginCleanupError(
            pluginId: descriptor.id, error: error, stackTrace: stackTrace));
      }
    }
    return List.unmodifiable(errors);
  }
}
