import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

import '../../../data/repositories/pre_exercise_clearance_repository.dart';
import '../data/account_binding_service.dart';
import '../data/auth_api.dart';
import '../data/authenticated_api_client.dart';
import '../data/session_token_store.dart';
import 'auth_route_refresh.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

final localPreviewEnabledProvider = Provider<bool>((Ref ref) => kDebugMode);

enum AuthStatus { unauthenticated, authenticated, accountConflict }

class AuthState {
  final AuthStatus status;
  final PublicAuthConfig? publicConfig;
  final AuthUser? user;
  final bool isBusy;
  final bool isLocalPreview;
  final String? message;

  const AuthState({
    required this.status,
    this.publicConfig,
    this.user,
    this.isBusy = false,
    this.isLocalPreview = false,
    this.message,
  });

  const AuthState.authenticated(AuthUser authenticatedUser)
      : this(
          status: AuthStatus.authenticated,
          user: authenticatedUser,
        );

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    PublicAuthConfig? publicConfig,
    AuthUser? user,
    bool? isBusy,
    bool? isLocalPreview,
    String? message,
    bool clearMessage = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      publicConfig: publicConfig ?? this.publicConfig,
      user: user ?? this.user,
      isBusy: isBusy ?? this.isBusy,
      isLocalPreview: isLocalPreview ?? this.isLocalPreview,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

class AuthController extends AsyncNotifier<AuthState> {
  late final AuthApi _authApi;
  late final AuthenticatedApiClient _apiClient;
  late final SessionTokenStore _tokenStore;
  late final AccountBindingService _accountBinding;
  bool _isRestoring = true;

  @override
  Future<AuthState> build() async {
    _authApi = ref.read(authApiProvider);
    _apiClient = ref.read(authenticatedApiClientProvider);
    _tokenStore = ref.read(sessionTokenStoreProvider);
    _accountBinding = ref.read(accountBindingServiceProvider);
    _apiClient.onSessionExpired = handleSessionExpired;
    ref.onDispose(() {
      if (_apiClient.onSessionExpired == handleSessionExpired) {
        _apiClient.onSessionExpired = null;
      }
    });

    PublicAuthConfig? config;
    try {
      config = await _authApi.publicConfig();
    } on ApiException catch (error) {
      return _finishInitial(
        AuthState(
          status: AuthStatus.unauthenticated,
          message: error.message,
        ),
      );
    }

    final String? refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return _finishInitial(
        AuthState(
          status: AuthStatus.unauthenticated,
          publicConfig: config,
        ),
      );
    }

    if (!await _apiClient.refreshAccessToken()) {
      return _finishInitial(
        AuthState(
          status: AuthStatus.unauthenticated,
          publicConfig: config,
        ),
      );
    }
    try {
      final AuthUser user = await _authApi.currentUser();
      if (!user.hasRequiredConsents) {
        await _tokenStore.clear();
        return _finishInitial(AuthState(
          status: AuthStatus.unauthenticated,
          publicConfig: config,
          message: '协议版本已更新，请重新登录并确认',
        ));
      }
      return _finishInitial(_stateForUser(user, config));
    } on ApiException {
      await _tokenStore.clear();
      return _finishInitial(
        AuthState(
          status: AuthStatus.unauthenticated,
          publicConfig: config,
        ),
      );
    }
  }

  Future<void> reloadPublicConfig() async {
    final AuthState current = _currentState;
    _setState(current.copyWith(isBusy: true, clearMessage: true));
    try {
      final PublicAuthConfig config = await _authApi.publicConfig();
      _setState(current.copyWith(
        publicConfig: config,
        isBusy: false,
        clearMessage: true,
      ));
    } on ApiException catch (error) {
      _setState(current.copyWith(isBusy: false, message: error.message));
    }
  }

  Future<EmailChallenge?> requestEmailCode(String email) async {
    final AuthState current = _currentState;
    if (current.publicConfig == null) {
      await reloadPublicConfig();
      if (_currentState.publicConfig == null) {
        return null;
      }
    }
    _setState(_currentState.copyWith(isBusy: true, clearMessage: true));
    try {
      final String normalizedEmail = _normalizeEmail(email);
      final EmailChallenge challenge =
          await _authApi.requestEmailChallenge(normalizedEmail);
      final String message =
          _currentState.publicConfig?.emailMode == 'development'
              ? '内部测试验证码为 246810'
              : '验证码已发送至邮箱';
      _setState(_currentState.copyWith(isBusy: false, message: message));
      return challenge;
    } on ApiException catch (error) {
      _setState(_currentState.copyWith(
        isBusy: false,
        message: error.message,
      ));
      return null;
    }
  }

  Future<EmailChallenge?> requestPhoneCode(String phone) async {
    final AuthState current = _currentState;
    if (current.publicConfig == null) {
      await reloadPublicConfig();
      if (_currentState.publicConfig == null) return null;
    }
    _setState(_currentState.copyWith(isBusy: true, clearMessage: true));
    try {
      final String normalizedPhone = _normalizePhone(phone);
      final EmailChallenge challenge =
          await _authApi.requestSmsChallenge(normalizedPhone);
      final String message =
          _currentState.publicConfig?.smsMode == 'development'
              ? '内部测试验证码为 246810'
              : '验证码已发送至手机';
      _setState(_currentState.copyWith(isBusy: false, message: message));
      return challenge;
    } on ApiException catch (error) {
      _setState(_currentState.copyWith(isBusy: false, message: error.message));
      return null;
    }
  }

  Future<bool> login({
    required String email,
    required String challengeId,
    required String code,
  }) async {
    final AuthState current = _currentState;
    final PublicAuthConfig? config = current.publicConfig;
    if (config == null) {
      _setState(current.copyWith(message: '请先连接服务并读取协议版本'));
      return false;
    }
    _setState(current.copyWith(isBusy: true, clearMessage: true));
    try {
      final AuthTokens tokens = await _authApi.createSession(
        email: _normalizeEmail(email),
        challengeId: challengeId,
        code: code,
        installationId: _accountBinding.installationId,
        config: config,
      );
      await _tokenStore.writeTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      final AuthUser user = await _authApi.currentUser();
      _setState(_stateForUser(user, config));
      return true;
    } on ApiException catch (error) {
      await _tokenStore.clear();
      _setState(current.copyWith(
        isBusy: false,
        message: error.message,
      ));
      return false;
    }
  }

  Future<bool> loginWithPhone({
    required String phone,
    required String challengeId,
    required String code,
  }) async {
    final AuthState current = _currentState;
    final PublicAuthConfig? config = current.publicConfig;
    if (config == null) {
      _setState(current.copyWith(message: '请先连接服务并读取协议版本'));
      return false;
    }
    _setState(current.copyWith(isBusy: true, clearMessage: true));
    try {
      final AuthTokens tokens = await _authApi.createPhoneSession(
        phone: _normalizePhone(phone),
        challengeId: challengeId,
        code: code,
        installationId: _accountBinding.installationId,
        config: config,
      );
      await _tokenStore.writeTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      final AuthUser user = await _authApi.currentUser();
      _setState(_stateForUser(user, config));
      return true;
    } on ApiException catch (error) {
      await _tokenStore.clear();
      _setState(current.copyWith(isBusy: false, message: error.message));
      return false;
    }
  }

  Future<bool> enterLocalPreview() async {
    if (!ref.read(localPreviewEnabledProvider)) {
      _setState(_currentState.copyWith(message: '当前构建不支持本地体验'));
      return false;
    }
    _setState(const AuthState(
      status: AuthStatus.authenticated,
      user: AuthUser(
        userId: 'local-preview-user',
        sessionId: 'local-preview-session',
        accountType: 'local',
        maskedEmail: '本地体验',
        hasRequiredConsents: true,
      ),
      isLocalPreview: true,
      message: '已进入本地体验，云端功能暂不可用',
    ));
    return true;
  }

  Future<bool> confirmAccountSwitch() async {
    final AuthState current = _currentState;
    final AuthUser? user = current.user;
    if (current.status != AuthStatus.accountConflict || user == null) {
      return false;
    }
    _setState(current.copyWith(isBusy: true, clearMessage: true));
    try {
      await _clearPreExerciseClearance();
      await _accountBinding.clearBusinessDataAndBind(user.userId);
      ref.invalidate(localStorageServiceProvider);
      _setState(current.copyWith(
        status: AuthStatus.authenticated,
        isBusy: false,
        clearMessage: true,
      ));
      return true;
    } catch (_) {
      _setState(current.copyWith(
        status: AuthStatus.accountConflict,
        isBusy: false,
        message: '本地训练数据未能安全清理，账号尚未切换，请重试。',
      ));
      return false;
    }
  }

  Future<void> cancelAccountSwitch() async {
    try {
      await _authApi.logout();
    } catch (_) {
      // 即使服务端暂不可用，也必须清除本地令牌并保护旧账号数据。
    }
    await _clearPreExerciseClearance();
    await _tokenStore.clear();
    final PublicAuthConfig? config = _currentState.publicConfig;
    _setState(AuthState(
      status: AuthStatus.unauthenticated,
      publicConfig: config,
      message: '已取消账号切换，原有训练数据未改变',
    ));
  }

  Future<void> logout() async {
    final PublicAuthConfig? config = _currentState.publicConfig;
    _setState(_currentState.copyWith(isBusy: true, clearMessage: true));
    try {
      await _authApi.logout();
    } catch (_) {
      // 本地退出优先，服务端会话仍会按有效期失效。
    }
    await _clearPreExerciseClearance();
    await _tokenStore.clear();
    _setState(AuthState(
      status: AuthStatus.unauthenticated,
      publicConfig: config,
    ));
  }

  Future<void> handleSessionExpired() async {
    if (_isRestoring) {
      return;
    }
    if (_currentState.isLocalPreview) {
      return;
    }
    final PublicAuthConfig? config = _currentState.publicConfig;
    await _clearPreExerciseClearance();
    await _tokenStore.clear();
    _setState(AuthState(
      status: AuthStatus.unauthenticated,
      publicConfig: config,
      message: '登录已过期，请重新登录',
    ));
  }

  AuthState _stateForUser(AuthUser user, PublicAuthConfig config) {
    if (_accountBinding.requiresConfirmation(user.userId)) {
      return AuthState(
        status: AuthStatus.accountConflict,
        publicConfig: config,
        user: user,
      );
    }
    if (_accountBinding.boundUserId == null) {
      _accountBinding.bind(user.userId);
    }
    return AuthState(
      status: AuthStatus.authenticated,
      publicConfig: config,
      user: user,
    );
  }

  AuthState get _currentState {
    final AsyncValue<AuthState> current = state;
    if (current case AsyncData<AuthState>(:final value)) {
      return value;
    }
    return const AuthState(status: AuthStatus.unauthenticated);
  }

  AuthState _finishInitial(AuthState value) {
    _isRestoring = false;
    scheduleMicrotask(authRouteRefreshNotifier.refresh);
    return value;
  }

  void _setState(AuthState value) {
    state = AsyncData<AuthState>(value);
    authRouteRefreshNotifier.refresh();
  }

  Future<void> _clearPreExerciseClearance() async {
    try {
      await ref.read(preExerciseClearanceRepositoryProvider).clear();
    } catch (_) {
      // 平台安全存储暂不可用时继续清理会话；记录仍绑定旧账号和安装标识，
      // 新账号读取时会因绑定不匹配而自动删除，不能继承旧账号筛查状态。
    }
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  String _normalizePhone(String phone) =>
      phone.trim().replaceAll(RegExp(r'[\s-]'), '');
}
