import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/pre_exercise_clearance.dart';
import 'package:trainflow_ai/data/repositories/pre_exercise_clearance_repository.dart';
import 'package:trainflow_ai/features/auth/application/auth_controller.dart';
import 'package:trainflow_ai/features/auth/data/auth_api.dart';
import 'package:trainflow_ai/features/training_plan/application/pre_exercise_clearance_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

class _AuthenticatedController extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState.authenticated(
        AuthUser(
          userId: 'user-a',
          sessionId: 'session-a',
          accountType: 'email',
          maskedEmail: 'a***@example.com',
          hasRequiredConsents: true,
        ),
      );
}

class _MemoryClearanceRepository implements PreExerciseClearanceRepository {
  PreExerciseClearance? value;
  String? accountId;
  String? installationId;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<PreExerciseClearance> read({
    required String accountId,
    required String installationId,
  }) async {
    this.accountId = accountId;
    this.installationId = installationId;
    return value ?? const PreExerciseClearance.notCompleted();
  }

  @override
  Future<void> save({
    required String accountId,
    required String installationId,
    required PreExerciseClearance clearance,
  }) async {
    this.accountId = accountId;
    this.installationId = installationId;
    value = clearance;
  }
}

void main() {
  test('筛查状态绑定账号与安装标识，当前伤病只在本机阻断', () async {
    final _MemoryClearanceRepository repository = _MemoryClearanceRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
        authControllerProvider.overrideWith(_AuthenticatedController.new),
        preExerciseClearanceRepositoryProvider.overrideWithValue(repository),
        preExerciseClearanceRealtimeClockProvider.overrideWithValue(
          () => DateTime(2026, 7, 17),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(preExerciseClearanceControllerProvider.future);
    final bool saved = await container
        .read(preExerciseClearanceControllerProvider.notifier)
        .record(
          status: PreExerciseClearanceStatus.selfCleared,
          currentInjuryOrRestriction: true,
        );

    expect(saved, isTrue);
    expect(repository.accountId, 'user-a');
    expect(repository.installationId, isNotEmpty);
    expect(repository.value?.currentInjuryOrRestriction, isTrue);
    expect(
      container
          .read(preExerciseClearanceControllerProvider)
          .value
          ?.canActivateAt(DateTime(2026, 7, 17)),
      isFalse,
    );
  });
}
