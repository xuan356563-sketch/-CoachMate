class PluginException implements Exception {
  PluginException(this.code, this.message,
      {Iterable<String> pluginIds = const []})
      : pluginIds = List.unmodifiable(pluginIds);
  final String code;
  final String message;
  final List<String> pluginIds;
  @override
  String toString() => '插件错误（$code）：$message';
}

class PluginCleanupError {
  const PluginCleanupError(
      {required this.pluginId, required this.error, required this.stackTrace});
  final String pluginId;
  final Object error;
  final StackTrace stackTrace;
  @override
  String toString() => '插件 $pluginId 的资源清理失败：$error';
}
