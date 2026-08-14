import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/data/authenticated_api_client.dart';
import '../data/account_lifecycle_api.dart';
import 'account_data_exporter.dart';

final dataRightsControllerProvider =
    AsyncNotifierProvider<DataRightsController, DataRightsState>(
  DataRightsController.new,
  retry: (int _, Object __) => null,
);

class DataRightsState {
  final bool available;
  final bool canDeleteOnline;
  final bool busy;
  final String statusMessage;
  final String? deletionChallengeId;
  final AccountDeletionStatus? deletionStatus;

  const DataRightsState({
    required this.available,
    required this.canDeleteOnline,
    required this.busy,
    required this.statusMessage,
    this.deletionChallengeId,
    this.deletionStatus,
  });

  const DataRightsState.unavailable()
      : this(
          available: false,
          canDeleteOnline: false,
          busy: false,
          statusMessage: '本地体验账号没有云端账号数据。',
        );

  DataRightsState copyWith({
    bool? available,
    bool? canDeleteOnline,
    bool? busy,
    String? statusMessage,
    String? deletionChallengeId,
    AccountDeletionStatus? deletionStatus,
    bool clearChallenge = false,
  }) {
    return DataRightsState(
      available: available ?? this.available,
      canDeleteOnline: canDeleteOnline ?? this.canDeleteOnline,
      busy: busy ?? this.busy,
      statusMessage: statusMessage ?? this.statusMessage,
      deletionChallengeId: clearChallenge
          ? null
          : (deletionChallengeId ?? this.deletionChallengeId),
      deletionStatus: deletionStatus ?? this.deletionStatus,
    );
  }
}

class DataRightsController extends AsyncNotifier<DataRightsState> {
  AccountLifecycleClient? _client;

  @override
  Future<DataRightsState> build() async {
    final AuthState auth = await ref.watch(authControllerProvider.future);
    if (!auth.isAuthenticated || auth.isLocalPreview || auth.user == null) {
      return const DataRightsState.unavailable();
    }
    _client = ref.watch(accountLifecycleClientProvider);
    try {
      final AccountDeletionStatus deletionStatus =
          await _client!.deletionStatus();
      return DataRightsState(
        available: true,
        canDeleteOnline: auth.user!.accountType == 'email',
        busy: false,
        statusMessage: deletionStatus.isPending
            ? '账号删除申请处于撤销期，正式删除前仍可撤销。'
            : '可导出云端账号数据，或申请删除账号。',
        deletionStatus: deletionStatus,
      );
    } catch (error) {
      return DataRightsState(
        available: true,
        canDeleteOnline: auth.user!.accountType == 'email',
        busy: false,
        statusMessage: _errorMessage(error, '暂时无法读取账号数据状态。'),
      );
    }
  }

  Future<void> exportAccount() async {
    final DataRightsState current = _current;
    if (!current.available || current.busy) return;
    state = AsyncData<DataRightsState>(
      current.copyWith(busy: true, statusMessage: '正在生成账号数据导出文件…'),
    );
    try {
      final Uint8List bytes = await _requiredClient.exportAccount();
      final DateTime now = DateTime.now();
      final String date = '${now.year}${_two(now.month)}${_two(now.day)}';
      final String? savedPath = await ref
          .read(accountDataExporterProvider)
          .saveJson(bytes, 'trainmate-account-export-$date.json');
      state = AsyncData<DataRightsState>(
        current.copyWith(
          busy: false,
          statusMessage:
              savedPath == null ? '已取消保存，云端没有保留导出文件副本。' : '账号数据已保存到所选位置。',
        ),
      );
    } catch (error) {
      state = AsyncData<DataRightsState>(
        current.copyWith(
          busy: false,
          statusMessage: _errorMessage(error, '账号数据导出失败，请稍后重试。'),
        ),
      );
    }
  }

  Future<void> requestDeletionChallenge(String email) async {
    final DataRightsState current = _current;
    if (!current.canDeleteOnline || current.busy) return;
    state = AsyncData<DataRightsState>(
      current.copyWith(busy: true, statusMessage: '正在发送删除复核验证码…'),
    );
    try {
      final AccountDeletionChallenge challenge =
          await _requiredClient.requestDeletionChallenge(email);
      state = AsyncData<DataRightsState>(
        current.copyWith(
          busy: false,
          deletionChallengeId: challenge.challengeId,
          statusMessage: '验证码已发送，有效期 ${challenge.expiresInSeconds ~/ 60} 分钟。',
        ),
      );
    } catch (error) {
      state = AsyncData<DataRightsState>(
        current.copyWith(
          busy: false,
          statusMessage: _errorMessage(error, '验证码发送失败，请检查邮箱后重试。'),
        ),
      );
    }
  }

  Future<bool> requestDeletion({
    required String email,
    required String code,
  }) async {
    final DataRightsState current = _current;
    final String? challengeId = current.deletionChallengeId;
    if (!current.canDeleteOnline || current.busy || challengeId == null) {
      return false;
    }
    state = AsyncData<DataRightsState>(
      current.copyWith(busy: true, statusMessage: '正在提交账号删除申请…'),
    );
    try {
      final AccountDeletionStatus deletionStatus =
          await _requiredClient.requestDeletion(
        email: email,
        challengeId: challengeId,
        code: code,
      );
      state = AsyncData<DataRightsState>(
        current.copyWith(
          busy: false,
          clearChallenge: true,
          deletionStatus: deletionStatus,
          statusMessage: '删除申请已提交，账号将在撤销期结束后删除。',
        ),
      );
      return true;
    } catch (error) {
      state = AsyncData<DataRightsState>(
        current.copyWith(
          busy: false,
          statusMessage: _errorMessage(error, '删除申请失败，账号状态未改变。'),
        ),
      );
      return false;
    }
  }

  Future<void> cancelDeletion() async {
    final DataRightsState current = _current;
    if (current.busy || current.deletionStatus?.isPending != true) return;
    state = AsyncData<DataRightsState>(
      current.copyWith(busy: true, statusMessage: '正在撤销账号删除申请…'),
    );
    try {
      final AccountDeletionStatus deletionStatus =
          await _requiredClient.cancelDeletion();
      state = AsyncData<DataRightsState>(
        current.copyWith(
          busy: false,
          deletionStatus: deletionStatus,
          statusMessage: '账号删除申请已撤销。',
        ),
      );
    } catch (error) {
      state = AsyncData<DataRightsState>(
        current.copyWith(
          busy: false,
          statusMessage: _errorMessage(error, '撤销失败，删除申请仍保持原状态。'),
        ),
      );
    }
  }

  DataRightsState get _current =>
      state.value ?? const DataRightsState.unavailable();

  AccountLifecycleClient get _requiredClient {
    final AccountLifecycleClient? client = _client;
    if (client == null) throw StateError('当前账号无法使用云端数据权利功能。');
    return client;
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

String _errorMessage(Object error, String fallback) {
  return error is ApiException ? error.message : fallback;
}
