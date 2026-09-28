import 'dart:async';

/// 业务动作只依赖此接口；核心安全与数据权利直接使用核心服务。
abstract interface class FeatureAccess {
  bool isEnabled(String id);
  bool isWritable(String id);
  void requireEnabled(String id);
  FeatureOperation beginOperation(String id,
      {Iterable<String> dependencies = const []});
  void Function() registerCleanup(String id, FutureOr<void> Function() cleanup,
      {FutureOr<void> Function()? onRestore});
  void Function() registerDisableLock(String id, String? Function() reason);
}

/// 仅标识已创建操作的生命周期失效；普通可用态或业务错误不能冒充取消。
class FeatureOperationInvalidation extends StateError {
  FeatureOperationInvalidation.accountChanged()
      : super('账户已变化，本次操作结果已失效，请重新操作。');
  FeatureOperationInvalidation.sourcesChanged()
      : super('功能或参与来源已变化，本次操作结果已失效，请重新操作。');
}

/// 网络等待期间不持有提交锁；真正落库必须放入 commit。
class FeatureOperation {
  FeatureOperation(
      {required void Function() check,
      bool Function(String)? containsSource,
      required void Function(Iterable<String>) includeDependencies,
      required Future<T> Function<T>(FutureOr<T> Function()) commit})
      : _check = check,
        _containsSource = containsSource ?? ((_) => false),
        _includeDependencies = includeDependencies,
        _commit = commit;
  final void Function() _check;
  final bool Function(String) _containsSource;
  final void Function(Iterable<String>) _includeDependencies;
  final Future<T> Function<T>(FutureOr<T> Function()) _commit;
  void checkActive() => _check();

  /// 查询操作创建时或等待阶段已登记的真实来源，查询同时验证操作仍有效。
  bool containsSource(String id) {
    _check();
    return _containsSource(id);
  }

  /// 同步编译返回真实来源后、下一次 await 前登记；关闭参与来源也会使任务失效。
  void includeDependencies(Iterable<String> ids) => _includeDependencies(ids);
  Future<T> commit<T>(FutureOr<T> Function() write) => _commit<T>(write);
}
