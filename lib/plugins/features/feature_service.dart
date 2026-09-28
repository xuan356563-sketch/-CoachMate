import 'dart:async';
import '../core/plugin_core.dart';

/// 旧控制器按需绑定自身服务与清理，不因装配启动全部业务控制器。
class FeatureService {
  FeatureService(this.context);
  final PluginContext context;
  final Map<String, Object> _services = {};
  void Function() bind<T extends Object>(String key, T service,
      {FutureOr<void> Function()? cleanup}) {
    context.checkActive();
    if (_services.containsKey(key)) throw StateError('服务已登记：$key');
    _services[key] = service;
    var registered = true;
    context.addCleanup(() async {
      if (!registered) return;
      registered = false;
      if (identical(_services[key], service)) _services.remove(key);
      await cleanup?.call();
    });
    return () {
      if (!registered) return;
      registered = false;
      if (identical(_services[key], service)) _services.remove(key);
    };
  }

  T? read<T extends Object>(String key) {
    context.checkActive();
    return _services[key] as T?;
  }
}
