import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/data/models/pre_exercise_clearance.dart';
import 'package:trainflow_ai/data/repositories/pre_exercise_clearance_repository.dart';
import 'package:trainflow_ai/features/auth/application/auth_controller.dart';
import 'package:trainflow_ai/features/auth/data/account_binding_service.dart';
import 'package:trainflow_ai/features/auth/data/auth_api.dart';
import 'package:trainflow_ai/features/auth/data/authenticated_api_client.dart';
import 'package:trainflow_ai/features/auth/data/session_token_store.dart';
import 'package:trainflow_ai/features/auth/presentation/auth_pages.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

const String _agreementVersion = 'internal-test-2026-07-13.1';

class MemorySessionTokenStore implements SessionTokenStore {
  @override
  String? accessToken;
  String? refreshToken;

  MemorySessionTokenStore({this.accessToken, this.refreshToken});

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> updateAccessToken(String accessToken) async {
    this.accessToken = accessToken;
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }
}

class MissingEntitlementSessionTokenStore extends MemorySessionTokenStore {
  @override
  Future<void> clear() {
    throw PlatformException(
      code: 'Unexpected security result code',
      message: 'Code: -34018, Message: A required entitlement is not present.',
      details: -34018,
    );
  }
}

void main() {
  test('Debug 本地体验保留云端会话与运动前筛查且会话失效不会退出', () async {
    final MemorySessionTokenStore tokenStore = MemorySessionTokenStore(
      accessToken: 'existing-access-token',
      refreshToken: 'existing-refresh-token',
    );
    final _TrackingClearanceRepository clearanceRepository =
        _TrackingClearanceRepository();
    final ProviderContainer container = _containerWith(
      client: _authMockClient(),
      tokenStore: tokenStore,
      localPreviewEnabled: true,
      clearanceRepository: clearanceRepository,
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final bool entered = await container
        .read(authControllerProvider.notifier)
        .enterLocalPreview();

    expect(entered, isTrue);
    expect(
      container.read(authControllerProvider).requireValue.status,
      AuthStatus.authenticated,
    );
    expect(
      container.read(authControllerProvider).requireValue.isLocalPreview,
      isTrue,
    );
    expect(tokenStore.accessToken, 'refreshed-access-token');
    expect(tokenStore.refreshToken, 'rotated-refresh-token');
    expect(clearanceRepository.clearCount, 0);

    await container
        .read(authControllerProvider.notifier)
        .handleSessionExpired();

    expect(
      container.read(authControllerProvider).requireValue.status,
      AuthStatus.authenticated,
    );
  });

  test('模拟器钥匙串缺少 entitlement 时仍可进入 Debug 本地体验', () async {
    final ProviderContainer container = _containerWith(
      client: _authMockClient(),
      tokenStore: MissingEntitlementSessionTokenStore(),
      localPreviewEnabled: true,
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final bool entered = await container
        .read(authControllerProvider.notifier)
        .enterLocalPreview();

    expect(entered, isTrue);
    final AuthState state = container.read(authControllerProvider).requireValue;
    expect(state.status, AuthStatus.authenticated);
    expect(state.isLocalPreview, isTrue);
  });

  test('关闭本地体验开关时控制器拒绝进入', () async {
    final ProviderContainer container = _containerWith(
      client: _authMockClient(),
      tokenStore: MemorySessionTokenStore(),
      localPreviewEnabled: false,
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final bool entered = await container
        .read(authControllerProvider.notifier)
        .enterLocalPreview();

    expect(entered, isFalse);
    expect(
      container.read(authControllerProvider).requireValue.status,
      AuthStatus.unauthenticated,
    );
    expect(
      container.read(authControllerProvider).requireValue.message,
      '当前构建不支持本地体验',
    );
  });

  test('未保存刷新令牌时启动为未登录状态', () async {
    final ProviderContainer container = _containerWith(
      client: _authMockClient(),
      tokenStore: MemorySessionTokenStore(),
    );
    addTearDown(container.dispose);

    final AuthState state = await container.read(authControllerProvider.future);

    expect(state.status, AuthStatus.unauthenticated);
    expect(state.publicConfig?.termsVersion, _agreementVersion);
  });

  test('已保存刷新令牌时会轮换令牌并恢复账号', () async {
    final MemorySessionTokenStore tokenStore = MemorySessionTokenStore(
      refreshToken: 'stored-refresh-token',
    );
    final ProviderContainer container = _containerWith(
      client: _authMockClient(),
      tokenStore: tokenStore,
    );
    addTearDown(container.dispose);

    final AuthState state = await container.read(authControllerProvider.future);

    expect(state.status, AuthStatus.authenticated);
    expect(state.user?.accountType, 'email');
    expect(state.user?.maskedEmail, 't***@example.com');
    expect(tokenStore.accessToken, 'refreshed-access-token');
    expect(tokenStore.refreshToken, 'rotated-refresh-token');
  });

  test('AuthUser 同时兼容脱敏邮箱与旧手机号响应', () {
    final AuthUser emailUser = AuthUser.fromJson(<String, dynamic>{
      'user_id': 'email-user',
      'session_id': 'email-session',
      'account_type': 'email',
      'masked_email': 't***@example.com',
      'has_required_consents': true,
    });
    final AuthUser legacyPhoneUser = AuthUser.fromJson(<String, dynamic>{
      'user_id': 'phone-user',
      'session_id': 'phone-session',
      'phone_last4': '8000',
      'has_required_consents': true,
    });

    expect(emailUser.accountType, 'email');
    expect(emailUser.maskedAccountLabel, 't***@example.com');
    expect(emailUser.phoneLast4, isNull);
    expect(legacyPhoneUser.accountType, 'phone');
    expect(legacyPhoneUser.maskedEmail, isNull);
    expect(legacyPhoneUser.maskedAccountLabel, '旧账号尾号 8000');
  });

  test('邮箱 challenge 和会话请求只提交规范化邮箱', () async {
    final List<http.Request> requests = <http.Request>[];
    final ProviderContainer container = _containerWith(
      client: _authMockClient(onRequest: requests.add),
      tokenStore: MemorySessionTokenStore(),
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final EmailChallenge challenge = (await container
        .read(authControllerProvider.notifier)
        .requestEmailCode('  Test@Example.COM  '))!;
    final bool loggedIn =
        await container.read(authControllerProvider.notifier).login(
              email: '  Test@Example.COM  ',
              challengeId: challenge.challengeId,
              code: '246810',
            );

    expect(loggedIn, isTrue);
    final http.Request challengeRequest = requests.singleWhere(
      (http.Request request) => request.url.path == '/v1/auth/email-challenges',
    );
    final http.Request sessionRequest = requests.singleWhere(
      (http.Request request) => request.url.path == '/v1/auth/sessions',
    );
    final Map<String, dynamic> challengeBody =
        jsonDecode(challengeRequest.body) as Map<String, dynamic>;
    final Map<String, dynamic> sessionBody =
        jsonDecode(sessionRequest.body) as Map<String, dynamic>;
    expect(challengeBody, <String, dynamic>{'email': 'test@example.com'});
    expect(sessionBody['email'], 'test@example.com');
    expect(sessionBody.containsKey('phone'), isFalse);
  });

  test('并发 401 只轮换一次刷新令牌并各自重试', () async {
    int refreshCount = 0;
    final MemorySessionTokenStore tokenStore = MemorySessionTokenStore(
      accessToken: 'expired-access-token',
      refreshToken: 'refresh-token',
    );
    final MockClient mockClient = MockClient((http.Request request) async {
      if (request.url.path == '/v1/auth/tokens/refresh') {
        refreshCount += 1;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _jsonResponse(<String, dynamic>{
          'access_token': 'new-access-token',
          'refresh_token': 'new-refresh-token',
        });
      }
      if (request.url.path == '/protected') {
        if (request.headers['Authorization'] == 'Bearer new-access-token') {
          return _jsonResponse(<String, dynamic>{'ok': true});
        }
        return _jsonResponse(
          <String, dynamic>{
            'code': 'access_token_invalid',
            'detail': '访问令牌无效或已过期',
          },
          statusCode: 401,
        );
      }
      return _jsonResponse(<String, dynamic>{}, statusCode: 404);
    });
    final AuthenticatedApiClient client = AuthenticatedApiClient(
      client: mockClient,
      tokenStore: tokenStore,
    );

    final List<Map<String, dynamic>> responses = await Future.wait([
      client.getJson('/protected', authenticated: true),
      client.getJson('/protected', authenticated: true),
    ]);

    expect(responses.every((item) => item['ok'] == true), isTrue);
    expect(refreshCount, 1);
  });

  test('不同账号登录先进入冲突页，确认后才清理业务数据', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final _TrackingClearanceRepository clearanceRepository =
        _TrackingClearanceRepository();
    storage.saveJson(AccountBindingService.installationIdKey, <String, dynamic>{
      'value': '019f4220-5ce2-7082-b418-5d087d24a4a9',
    });
    storage.saveJson(AccountBindingService.accountBindingKey, <String, dynamic>{
      'userId': 'old-user',
    });
    storage.saveJson('trainflow.user_profile.v1', <String, dynamic>{
      'profileCompleted': true,
    });
    final ProviderContainer container = _containerWith(
      client: _authMockClient(),
      tokenStore: MemorySessionTokenStore(),
      storage: storage,
      clearanceRepository: clearanceRepository,
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final EmailChallenge? challenge = await container
        .read(authControllerProvider.notifier)
        .requestEmailCode('test@example.com');
    expect(challenge, isNotNull);
    final bool loggedIn =
        await container.read(authControllerProvider.notifier).login(
              email: 'test@example.com',
              challengeId: challenge!.challengeId,
              code: '246810',
            );

    expect(loggedIn, isTrue);
    expect(
      container.read(authControllerProvider).requireValue.status,
      AuthStatus.accountConflict,
    );
    expect(storage.readJson('trainflow.user_profile.v1'), isNotNull);

    final bool switched = await container
        .read(authControllerProvider.notifier)
        .confirmAccountSwitch();

    expect(switched, isTrue);
    expect(
      container.read(authControllerProvider).requireValue.status,
      AuthStatus.authenticated,
    );
    expect(storage.readJson('trainflow.user_profile.v1'), isNull);
    expect(
      storage.readJson(AccountBindingService.installationIdKey)?['value'],
      '019f4220-5ce2-7082-b418-5d087d24a4a9',
    );
    expect(
      storage.readJson(AccountBindingService.accountBindingKey)?['userId'],
      'new-user',
    );
    expect(clearanceRepository.clearCount, 1);
  });

  test('账号数据原子清理失败时不得进入已登录状态', () async {
    final _FailingAtomicStorage storage = _FailingAtomicStorage()
      ..saveJson(AccountBindingService.accountBindingKey, <String, dynamic>{
        'userId': 'old-user',
      })
      ..saveJson('trainflow.user_profile.v1', <String, dynamic>{
        'profileCompleted': true,
      });
    final ProviderContainer container = _containerWith(
      client: _authMockClient(),
      tokenStore: MemorySessionTokenStore(),
      storage: storage,
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    final EmailChallenge challenge = (await container
        .read(authControllerProvider.notifier)
        .requestEmailCode('test@example.com'))!;
    await container.read(authControllerProvider.notifier).login(
          email: 'test@example.com',
          challengeId: challenge.challengeId,
          code: '246810',
        );

    final bool switched = await container
        .read(authControllerProvider.notifier)
        .confirmAccountSwitch();

    expect(switched, isFalse);
    final AuthState state = container.read(authControllerProvider).requireValue;
    expect(state.status, AuthStatus.accountConflict);
    expect(state.message, contains('未切换'));
    expect(storage.readJson('trainflow.user_profile.v1'), isNotNull);
  });

  test('Web 会话只存在于当前令牌存储实例', () async {
    final PlatformSessionTokenStore first = PlatformSessionTokenStore(
      isWeb: true,
    );
    await first.writeTokens(
      accessToken: 'memory-access',
      refreshToken: 'memory-refresh',
    );

    final PlatformSessionTokenStore reloaded = PlatformSessionTokenStore(
      isWeb: true,
    );

    expect(await first.readRefreshToken(), 'memory-refresh');
    expect(await reloaded.readRefreshToken(), isNull);
  });

  testWidgets('未登录会被拦截到登录页，协议页仍可访问', (tester) async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          sessionTokenStoreProvider.overrideWithValue(
            MemorySessionTokenStore(),
          ),
          httpClientProvider.overrideWithValue(_authMockClient()),
        ],
        child: const TrainFlowApp(),
      ),
    );
    router.go(AppRoutes.dashboard);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.login,
    );
    expect(find.text('登录智练 TrainMate'), findsOneWidget);
    expect(find.text('登录并进入智练 TrainMate'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('trainmate-brand-lockup')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('trainmate-brandmark')),
      findsOneWidget,
    );

    router.go(AppRoutes.terms);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('服务协议'), findsWidgets);
    expect(find.textContaining('内部测试版本'), findsOneWidget);
  });

  testWidgets('邮箱验证码校验、60 秒倒计时与邮箱变更失效', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(
            InMemoryLocalStorageService(),
          ),
          sessionTokenStoreProvider.overrideWithValue(
            MemorySessionTokenStore(),
          ),
          httpClientProvider.overrideWithValue(_authMockClient()),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final Finder emailField = find.byKey(const ValueKey<String>('auth-email'));
    final Finder codeField = find.byKey(const ValueKey<String>('auth-code'));
    final Finder sendButton =
        find.byKey(const ValueKey<String>('auth-send-code'));
    final Finder loginButton = find.byKey(const ValueKey<String>('auth-login'));

    await tester.ensureVisible(emailField);
    await tester.pump();
    await tester.enterText(emailField, 'not-an-email');
    await tester.ensureVisible(sendButton);
    await tester.pump();
    await tester.tap(sendButton);
    await tester.pump();
    expect(find.text('请输入有效的邮箱地址'), findsOneWidget);

    await tester.enterText(emailField, '  Test@Example.COM  ');
    await tester.ensureVisible(sendButton);
    await tester.pump();
    await tester.tap(sendButton);
    await tester.pump();
    await tester.pump();
    expect(find.text('60 秒后重发'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('59 秒后重发'), findsOneWidget);

    await tester.enterText(codeField, '12a456');
    expect(find.text('12456'), findsOneWidget);
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(loginButton);
    await tester.pump();
    await tester.tap(loginButton);
    await tester.pump();
    expect(find.text('请输入六位数字验证码'), findsOneWidget);

    await tester.enterText(emailField, 'other@example.com');
    await tester.pump();
    expect(find.text('发送验证码'), findsOneWidget);

    await tester.enterText(codeField, '246810');
    await tester.ensureVisible(loginButton);
    await tester.pump();
    await tester.tap(loginButton);
    await tester.pump();
    expect(find.text('请先为当前邮箱发送验证码'), findsOneWidget);
  });

  testWidgets('Debug 登录页同意协议后可进入本地体验', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router.go(AppRoutes.login);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(
            InMemoryLocalStorageService(),
          ),
          sessionTokenStoreProvider.overrideWithValue(
            MemorySessionTokenStore(),
          ),
          httpClientProvider.overrideWithValue(_authMockClient()),
          preExerciseClearanceRepositoryProvider.overrideWithValue(
            _TrackingClearanceRepository(),
          ),
          localPreviewEnabledProvider.overrideWithValue(true),
        ],
        child: const TrainFlowApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    final Finder previewButton =
        find.byKey(const ValueKey<String>('local-preview-login'));
    expect(previewButton, findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('trainflow-card-corner-character'),
      ),
      findsNothing,
    );
    await tester.ensureVisible(previewButton);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.text('进入本地体验（不含云端功能）')).height,
      lessThan(30),
      reason: '393px 窄屏下登录入口应保持单行',
    );
    await tester.tap(previewButton);
    await tester.pump();
    expect(find.text('请先阅读并同意服务协议与隐私政策'), findsOneWidget);

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(previewButton);
    await tester.pumpAndSettle();
    await tester.tap(previewButton);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.companion,
    );
  });

  testWidgets('关闭本地体验开关时登录页不显示入口', (tester) async {
    router.go(AppRoutes.login);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(
            InMemoryLocalStorageService(),
          ),
          sessionTokenStoreProvider.overrideWithValue(
            MemorySessionTokenStore(),
          ),
          httpClientProvider.overrideWithValue(_authMockClient()),
          preExerciseClearanceRepositoryProvider.overrideWithValue(
            _TrackingClearanceRepository(),
          ),
          localPreviewEnabledProvider.overrideWithValue(false),
        ],
        child: const TrainFlowApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('local-preview-login')),
      findsNothing,
    );
  });
}

class _FailingAtomicStorage extends InMemoryLocalStorageService {
  @override
  Future<void> replaceBusinessDataAtomically({
    Set<String> preservedKeys = const <String>{},
    Map<String, Map<String, dynamic>> replacementDocuments =
        const <String, Map<String, dynamic>>{},
  }) {
    throw StateError('模拟数据库清理失败');
  }
}

class _TrackingClearanceRepository implements PreExerciseClearanceRepository {
  int clearCount = 0;

  @override
  Future<void> clear() async => clearCount += 1;

  @override
  Future<PreExerciseClearance> read({
    required String accountId,
    required String installationId,
  }) async =>
      const PreExerciseClearance.notCompleted();

  @override
  Future<void> save({
    required String accountId,
    required String installationId,
    required PreExerciseClearance clearance,
  }) async {}
}

ProviderContainer _containerWith({
  required http.Client client,
  required SessionTokenStore tokenStore,
  InMemoryLocalStorageService? storage,
  bool? localPreviewEnabled,
  PreExerciseClearanceRepository? clearanceRepository,
}) {
  return ProviderContainer(
    overrides: [
      localStorageServiceProvider.overrideWithValue(
        storage ?? InMemoryLocalStorageService(),
      ),
      sessionTokenStoreProvider.overrideWithValue(tokenStore),
      httpClientProvider.overrideWithValue(client),
      if (clearanceRepository != null)
        preExerciseClearanceRepositoryProvider.overrideWithValue(
          clearanceRepository,
        ),
      if (localPreviewEnabled != null)
        localPreviewEnabledProvider.overrideWithValue(localPreviewEnabled),
    ],
  );
}

MockClient _authMockClient({void Function(http.Request request)? onRequest}) {
  return MockClient((http.Request request) async {
    onRequest?.call(request);
    switch (request.url.path) {
      case '/v1/auth/public-config':
        return _jsonResponse(<String, dynamic>{
          'terms_version': _agreementVersion,
          'privacy_version': _agreementVersion,
          'email_mode': 'development',
        });
      case '/v1/auth/email-challenges':
        return _jsonResponse(
          <String, dynamic>{
            'challenge_id': 'challenge-id',
            'expires_in_seconds': 300,
          },
          statusCode: 201,
        );
      case '/v1/auth/sessions':
        return _jsonResponse(
          <String, dynamic>{
            'access_token': 'created-access-token',
            'refresh_token': 'created-refresh-token',
          },
          statusCode: 201,
        );
      case '/v1/auth/tokens/refresh':
        return _jsonResponse(<String, dynamic>{
          'access_token': 'refreshed-access-token',
          'refresh_token': 'rotated-refresh-token',
        });
      case '/v1/auth/me':
        return _jsonResponse(<String, dynamic>{
          'user_id': 'new-user',
          'session_id': 'session-id',
          'account_type': 'email',
          'masked_email': 't***@example.com',
          'has_required_consents': true,
        });
      case '/v1/auth/sessions/current':
        return http.Response('', 204);
      default:
        return _jsonResponse(<String, dynamic>{}, statusCode: 404);
    }
  });
}

http.Response _jsonResponse(
  Map<String, dynamic> body, {
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8'
    },
  );
}
