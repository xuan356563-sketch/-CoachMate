import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final sessionTokenStoreProvider = Provider<SessionTokenStore>(
  (Ref ref) => PlatformSessionTokenStore(),
);

abstract class SessionTokenStore {
  String? get accessToken;

  Future<String?> readRefreshToken();

  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  });

  Future<void> updateAccessToken(String accessToken);

  Future<void> clear();
}

class PlatformSessionTokenStore implements SessionTokenStore {
  static const String _refreshTokenKey = 'trainflow.refresh_token.v1';

  final FlutterSecureStorage _secureStorage;
  final bool _isWeb;
  String? _accessToken;
  String? _webRefreshToken;

  PlatformSessionTokenStore({
    FlutterSecureStorage? secureStorage,
    bool? isWeb,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _isWeb = isWeb ?? kIsWeb;

  @override
  String? get accessToken => _accessToken;

  @override
  Future<String?> readRefreshToken() async {
    if (_isWeb) {
      return _webRefreshToken;
    }
    return _secureStorage.read(key: _refreshTokenKey);
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    if (_isWeb) {
      _webRefreshToken = refreshToken;
      return;
    }
    await _secureStorage.write(
      key: _refreshTokenKey,
      value: refreshToken,
    );
  }

  @override
  Future<void> updateAccessToken(String accessToken) async {
    _accessToken = accessToken;
  }

  @override
  Future<void> clear() async {
    _accessToken = null;
    _webRefreshToken = null;
    if (!_isWeb) {
      await _secureStorage.delete(key: _refreshTokenKey);
    }
  }
}
