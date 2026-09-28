import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/constants/app_brand.dart';
import 'session_token_store.dart';

final httpClientProvider = Provider<http.Client>((Ref ref) {
  final http.Client client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final authenticatedApiClientProvider = Provider<AuthenticatedApiClient>(
  (Ref ref) => AuthenticatedApiClient(
    client: ref.watch(httpClientProvider),
    tokenStore: ref.watch(sessionTokenStoreProvider),
  ),
);

class ApiException implements Exception {
  final int? statusCode;
  final String code;
  final String message;

  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  factory ApiException.fromResponse(http.Response response) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return ApiException(
          statusCode: response.statusCode,
          code: decoded['code'] as String? ?? 'api_error',
          message: decoded['detail'] as String? ?? '请求失败，请稍后重试',
        );
      }
    } on FormatException {
      // 使用下方稳定错误文案。
    }
    return ApiException(
      statusCode: response.statusCode,
      code: 'api_error',
      message: '请求失败，请稍后重试',
    );
  }

  @override
  String toString() => message;
}

class AuthenticatedApiClient {
  final http.Client _client;
  final SessionTokenStore _tokenStore;
  Completer<bool>? _refreshCompleter;

  Future<void> Function()? onSessionExpired;

  AuthenticatedApiClient({
    required http.Client client,
    required SessionTokenStore tokenStore,
  })  : _client = client,
        _tokenStore = tokenStore;

  Future<Map<String, dynamic>> getJson(
    String path, {
    bool authenticated = false,
  }) {
    return _sendJson('GET', path, authenticated: authenticated);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) {
    return _sendJson(
      'POST',
      path,
      body: body,
      authenticated: authenticated,
    );
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) {
    return _sendJson(
      'PUT',
      path,
      body: body,
      authenticated: authenticated,
    );
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    bool authenticated = true,
  }) {
    return _sendJson('DELETE', path, authenticated: authenticated);
  }

  /// 下载已认证的二进制响应，不把正文写入日志或本地缓存。
  Future<Uint8List> getBytes(
    String path, {
    bool authenticated = true,
  }) async {
    http.Response response =
        await _sendBytes(path, authenticated: authenticated);
    if (response.statusCode == 401 &&
        authenticated &&
        await refreshAccessToken()) {
      response = await _sendBytes(path, authenticated: true);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException.fromResponse(response);
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> postMultipartImage(
    String path, {
    required Uint8List bytes,
    required String filename,
    Map<String, String> fields = const <String, String>{},
  }) async {
    http.Response response = await _sendMultipart(
      path,
      bytes: bytes,
      filename: filename,
      fields: fields,
    );
    if (response.statusCode == 401 && await refreshAccessToken()) {
      response = await _sendMultipart(
        path,
        bytes: bytes,
        filename: filename,
        fields: fields,
      );
    }
    return _decodeResponse(response);
  }

  Future<bool> refreshAccessToken() {
    final Completer<bool>? active = _refreshCompleter;
    if (active != null) {
      return active.future;
    }

    final Completer<bool> completer = Completer<bool>();
    _refreshCompleter = completer;
    unawaited(_performRefresh(completer));
    return completer.future;
  }

  Future<void> _performRefresh(Completer<bool> completer) async {
    try {
      final String? refreshToken = await _tokenStore.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        await _expireSession();
        completer.complete(false);
        return;
      }
      final Map<String, dynamic> payload = await postJson(
        '/v1/auth/tokens/refresh',
        <String, dynamic>{'refresh_token': refreshToken},
      );
      await _tokenStore.writeTokens(
        accessToken: payload['access_token'] as String,
        refreshToken: payload['refresh_token'] as String,
      );
      completer.complete(true);
    } catch (_) {
      await _expireSession();
      completer.complete(false);
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required bool authenticated,
    bool canRetry = true,
  }) async {
    final Uri uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      if (authenticated && _tokenStore.accessToken != null)
        'Authorization': 'Bearer ${_tokenStore.accessToken}',
    };
    try {
      final http.Response response = switch (method) {
        'GET' => await _client.get(uri, headers: headers),
        'DELETE' => await _client.delete(uri, headers: headers),
        'PUT' => await _client.put(
            uri,
            headers: headers,
            body: jsonEncode(body ?? const <String, dynamic>{}),
          ),
        _ => await _client.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? const <String, dynamic>{}),
          ),
      };
      if (response.statusCode == 401 && authenticated && canRetry) {
        if (await refreshAccessToken()) {
          return _sendJson(
            method,
            path,
            body: body,
            authenticated: true,
            canRetry: false,
          );
        }
      }
      return _decodeResponse(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        code: 'network_unavailable',
        message: '无法连接 ${AppBrand.displayName} 服务，请检查后端是否已启动',
      );
    }
  }

  Future<http.Response> _sendMultipart(
    String path, {
    required Uint8List bytes,
    required String filename,
    required Map<String, String> fields,
  }) async {
    final http.MultipartRequest request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}$path'),
    );
    final String? accessToken = _tokenStore.accessToken;
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    request.fields.addAll(fields);
    request.files.add(
      http.MultipartFile.fromBytes('image', bytes, filename: filename),
    );
    try {
      return http.Response.fromStream(await _client.send(request));
    } catch (_) {
      throw const ApiException(
        code: 'network_unavailable',
        message: '图片上传失败，请检查网络后重试',
      );
    }
  }

  Future<http.Response> _sendBytes(
    String path, {
    required bool authenticated,
  }) async {
    final Map<String, String> headers = <String, String>{
      if (authenticated && _tokenStore.accessToken != null)
        'Authorization': 'Bearer ${_tokenStore.accessToken}',
    };
    try {
      return await _client.get(
        Uri.parse('${ApiConfig.baseUrl}$path'),
        headers: headers,
      );
    } catch (_) {
      throw const ApiException(
        code: 'network_unavailable',
        message: '无法下载账号数据，请检查网络后重试',
      );
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException.fromResponse(response);
    }
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // 使用下方稳定错误文案。
    }
    throw const ApiException(
      code: 'response_invalid',
      message: '服务返回了无法解析的数据',
    );
  }

  Future<void> _expireSession() async {
    await _tokenStore.clear();
    await onSessionExpired?.call();
  }
}
