import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/features/auth/application/auth_controller.dart';
import 'package:trainflow_ai/features/auth/data/auth_api.dart';

class TestHarness {
  TestHarness({
    InMemoryLocalStorageService? storageService,
    this.authenticated = true,
  }) : storageService = storageService ?? InMemoryLocalStorageService();

  final InMemoryLocalStorageService storageService;
  final bool authenticated;

  Widget buildApp(Widget child) {
    return ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storageService),
        if (authenticated)
          authControllerProvider.overrideWith(
            TestAuthenticatedAuthController.new,
          ),
      ],
      child: child,
    );
  }
}

class TestAuthenticatedAuthController extends AuthController {
  @override
  Future<AuthState> build() async {
    return const AuthState.authenticated(
      AuthUser(
        userId: 'test-user-id',
        sessionId: 'test-session-id',
        accountType: 'email',
        maskedEmail: 't***@example.com',
        hasRequiredConsents: true,
      ),
    );
  }
}
