import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'plugin_runtime_provider.dart';

/// 控制器已被业务按需读取后才登记；启停不会主动创建控制器。
void bindFeatureController(Ref ref, String id, String key, Object controller,
    {FutureOr<void> Function()? cleanup,
    FutureOr<void> Function()? onRestore}) {
  final runtime = ref.read(pluginRuntimeProvider);
  void Function()? unbind;
  void Function()? unregister;
  var disposed = false;
  Object? boundService;
  void bind() {
    if (disposed) return;
    unbind?.call();
    final service = runtime.service(id);
    boundService = service;
    unbind = service?.bind(key, controller);
  }

  void register() {
    if (disposed || !runtime.isWritable(id)) return;
    bind();
    unregister?.call();
    unregister = runtime.registerCleanup(id, () async {
      unbind?.call();
      unbind = null;
      await cleanup?.call();
    }, onRestore: () async {
      // 回滚仍在切换保护区，只恢复原资源，不调用写动作。
      bind();
      await onRestore?.call();
    });
  }

  register();
  // 未被页面watch的存活控制器也需要重新登记，不能依赖被暂停的provider订阅。
  void changed() {
    final service = runtime.service(id);
    // registry 的宿主级 shutdown 会先撤下服务；此时不能把它误判为重开。
    if (service != null &&
        runtime.isWritable(id) &&
        (!identical(boundService, service) || unbind == null)) {
      register();
    }
  }

  runtime.addListener(changed);
  ref.onDispose(() {
    disposed = true;
    runtime.removeListener(changed);
    unregister?.call();
    unbind?.call();
  });
}

/// 使用已有类型化控制器作为公共服务；兼容未装配运行时的独立业务测试。
T readFeatureController<T extends Object>(
    Ref ref, String id, String key, T Function() load) {
  final runtime = ref.read(pluginRuntimeProvider);
  runtime.requireEnabled(id);
  final controller = load();
  final service = runtime.service(id);
  if (service == null && !runtime.initialized && runtime.compatibilityMode) {
    return controller;
  }
  return service?.read<T>(key) ?? (throw StateError('功能服务尚未就绪，请重新打开页面。'));
}

/// Widget 层与业务控制器使用同一服务读取规则，避免直接跨功能读取 provider。
T readFeatureControllerFromWidgetRef<T extends Object>(
    WidgetRef ref, String id, String key, T Function() load) {
  final runtime = ref.read(pluginRuntimeProvider);
  runtime.requireEnabled(id);
  final controller = load();
  final service = runtime.service(id);
  if (service == null && !runtime.initialized && runtime.compatibilityMode) {
    return controller;
  }
  return service?.read<T>(key) ?? (throw StateError('功能服务尚未就绪，请重新打开页面。'));
}
