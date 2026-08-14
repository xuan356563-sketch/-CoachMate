import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/auth/application/auth_controller.dart';
import 'package:trainflow_ai/features/auth/data/auth_api.dart';
import 'package:trainflow_ai/features/data_rights/application/account_data_exporter.dart';
import 'package:trainflow_ai/features/data_rights/application/data_rights_controller.dart';
import 'package:trainflow_ai/features/data_rights/data/account_lifecycle_api.dart';

void main() {
  test('导出使用系统保存能力且删除申请始终需要验证码确认', () async {
    final _FakeAccountLifecycleClient client = _FakeAccountLifecycleClient();
    final _FakeAccountDataExporter exporter = _FakeAccountDataExporter();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_AuthenticatedController.new),
        accountLifecycleClientProvider.overrideWithValue(client),
        accountDataExporterProvider.overrideWithValue(exporter),
      ],
    );
    addTearDown(container.dispose);

    final DataRightsState initial =
        await container.read(dataRightsControllerProvider.future);
    expect(initial.available, isTrue);
    expect(initial.canDeleteOnline, isTrue);

    final DataRightsController controller =
        container.read(dataRightsControllerProvider.notifier);
    await controller.exportAccount();
    expect(exporter.savedBytes, Uint8List.fromList(<int>[1, 2, 3]));
    expect(
      container.read(dataRightsControllerProvider).value?.statusMessage,
      '账号数据已保存到所选位置。',
    );

    final bool withoutChallenge = await controller.requestDeletion(
      email: 'user@example.com',
      code: '246810',
    );
    expect(withoutChallenge, isFalse);
    expect(client.deletionCalls, 0);

    await controller.requestDeletionChallenge('user@example.com');
    final bool submitted = await controller.requestDeletion(
      email: 'user@example.com',
      code: '246810',
    );
    expect(submitted, isTrue);
    expect(client.deletionCalls, 1);
    expect(
      container
          .read(dataRightsControllerProvider)
          .value
          ?.deletionStatus
          ?.isPending,
      isTrue,
    );
  });

  test('撤销删除申请不会修改本机数据', () async {
    final _FakeAccountLifecycleClient client =
        _FakeAccountLifecycleClient(initiallyPending: true);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_AuthenticatedController.new),
        accountLifecycleClientProvider.overrideWithValue(client),
        accountDataExporterProvider.overrideWithValue(
          _FakeAccountDataExporter(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(dataRightsControllerProvider.future);

    await container
        .read(dataRightsControllerProvider.notifier)
        .cancelDeletion();

    expect(client.cancelCalls, 1);
    expect(
      container.read(dataRightsControllerProvider).value?.statusMessage,
      '账号删除申请已撤销。',
    );
  });
}

class _AuthenticatedController extends AuthController {
  @override
  Future<AuthState> build() async {
    return const AuthState.authenticated(
      AuthUser(
        userId: 'user-1',
        sessionId: 'session-1',
        accountType: 'email',
        maskedEmail: 'u***@example.com',
        hasRequiredConsents: true,
      ),
    );
  }
}

class _FakeAccountLifecycleClient implements AccountLifecycleClient {
  final bool initiallyPending;
  int deletionCalls = 0;
  int cancelCalls = 0;

  _FakeAccountLifecycleClient({this.initiallyPending = false});

  @override
  Future<AccountDeletionStatus> cancelDeletion() async {
    cancelCalls += 1;
    return _status('cancelled');
  }

  @override
  Future<AccountDeletionStatus> deletionStatus() async {
    return _status(initiallyPending ? 'pending' : 'not_requested');
  }

  @override
  Future<Uint8List> exportAccount() async => Uint8List.fromList(<int>[1, 2, 3]);

  @override
  Future<AccountDeletionStatus> requestDeletion({
    required String email,
    required String challengeId,
    required String code,
  }) async {
    expect(email, 'user@example.com');
    expect(challengeId, 'challenge-1');
    expect(code, '246810');
    deletionCalls += 1;
    return _status('pending');
  }

  @override
  Future<AccountDeletionChallenge> requestDeletionChallenge(
    String email,
  ) async {
    expect(email, 'user@example.com');
    return const AccountDeletionChallenge(
      challengeId: 'challenge-1',
      expiresInSeconds: 300,
    );
  }

  AccountDeletionStatus _status(String status) {
    return AccountDeletionStatus(
      status: status,
      requestId: status == 'not_requested' ? null : 'request-1',
      requestedAt: status == 'not_requested' ? null : DateTime(2026, 7, 30),
      purgeAfter: status == 'pending' ? DateTime(2026, 8, 6) : null,
      gracePeriodDays: 7,
    );
  }
}

class _FakeAccountDataExporter implements AccountDataExporter {
  Uint8List? savedBytes;

  @override
  Future<String?> saveJson(Uint8List bytes, String suggestedName) async {
    expect(suggestedName, contains('trainmate-account-export-'));
    savedBytes = bytes;
    return '/tmp/$suggestedName';
  }
}
