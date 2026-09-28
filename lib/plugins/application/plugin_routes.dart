import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/app_routes.dart';
import '../core/plugin_core.dart';
import '../features/built_in_features.dart';
import 'plugin_runtime.dart';

/// 功能路由按登记模板匹配；核心历史使用独立路由，不受业务功能开关限制。
String? disabledRouteOwner(PluginRuntime runtime, String path) {
  for (final feature in builtInFeatures) {
    for (final route in feature.contributions.whereType<RouteContribution>()) {
      final pattern =
          '^${route.path.split('/').map((part) => part.startsWith(':') ? '[^/]+' : RegExp.escape(part)).join('/')}\$';
      if (RegExp(pattern).hasMatch(path) &&
          (!runtime.isEnabled(feature.id) ||
              !runtime.contributions.any((c) => c.id == route.id))) {
        return feature.id;
      }
    }
  }
  return null;
}

String defaultPluginRoute(PluginRuntime runtime) =>
    runtime.isEnabled('feature.companion')
        ? AppRoutes.companion
        : AppRoutes.dashboard;

class CapabilityUnavailablePage extends StatelessWidget {
  const CapabilityUnavailablePage({super.key, this.name});
  final String? name;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('运动与功能')),
        body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name == null
                    ? '功能管理正在准备中。'
                    : '$name当前未启用或初始化失败，暂时无法开始新操作。'),
                const SizedBox(height: 16),
                const Text('已保存的训练数据仍然保留。请返回今日或我的；初始化失败时可重启应用重试。'),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: () => context.go(AppRoutes.dashboard),
                    child: const Text('返回今日')),
                TextButton(
                    onPressed: () => context.go(AppRoutes.profile),
                    child: const Text('前往我的')),
              ],
            )),
      );
}
