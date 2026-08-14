class ApiConfig {
  ApiConfig._();

  static const String _configuredBaseUrl = String.fromEnvironment(
    'TRAINFLOW_API_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl {
    return resolveBaseUrl(
      configuredBaseUrl: _configuredBaseUrl,
      isProduct: const bool.fromEnvironment('dart.vm.product'),
    );
  }

  static String resolveBaseUrl({
    required String configuredBaseUrl,
    required bool isProduct,
  }) {
    final String configured = configuredBaseUrl.trim();
    if (isProduct && configured.isEmpty) {
      throw StateError(
        '生产环境必须显式配置 TRAINFLOW_API_BASE_URL，不能使用本机默认地址',
      );
    }
    final String value =
        configured.isEmpty ? 'http://127.0.0.1:8000' : configured;
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      throw StateError('API 地址格式无效');
    }
    if (isProduct && uri.scheme != 'https') {
      throw StateError('生产环境的 API 地址必须使用 HTTPS');
    }
    if (isProduct &&
        <String>{'localhost', '127.0.0.1', '::1'}.contains(uri.host)) {
      throw StateError('生产环境的 API 地址不能指向本机');
    }
    return value.replaceFirst(RegExp(r'/+$'), '');
  }
}
