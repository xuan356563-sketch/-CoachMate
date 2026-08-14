import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/pre_exercise_clearance.dart';
import '../../../data/repositories/pre_exercise_clearance_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/account_binding_service.dart';

final preExerciseClearanceRealtimeClockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now);

final preExerciseClearanceControllerProvider = AsyncNotifierProvider<
    PreExerciseClearanceController,
    PreExerciseClearanceState>(PreExerciseClearanceController.new);

class PreExerciseClearanceState {
  final PreExerciseClearance clearance;
  final bool isSaving;
  final String statusMessage;

  const PreExerciseClearanceState({
    required this.clearance,
    required this.isSaving,
    required this.statusMessage,
  });

  bool canActivateAt(DateTime now) => clearance.isValidAt(now);

  PreExerciseClearanceState copyWith({
    PreExerciseClearance? clearance,
    bool? isSaving,
    String? statusMessage,
  }) {
    return PreExerciseClearanceState(
      clearance: clearance ?? this.clearance,
      isSaving: isSaving ?? this.isSaving,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

class PreExerciseClearanceController
    extends AsyncNotifier<PreExerciseClearanceState> {
  static const Duration _maximumExpiryTimerDelay = Duration(days: 1);

  Timer? _expiryTimer;

  @override
  Future<PreExerciseClearanceState> build() async {
    ref.onDispose(() => _expiryTimer?.cancel());
    final AuthState authState = await ref.watch(authControllerProvider.future);
    final String? accountId = authState.user?.userId;
    if (!authState.isAuthenticated || accountId == null) {
      return const PreExerciseClearanceState(
        clearance: PreExerciseClearance.notCompleted(),
        isSaving: false,
        statusMessage: '登录后才能保存本机筛查状态。',
      );
    }
    final PreExerciseClearance clearance =
        await ref.read(preExerciseClearanceRepositoryProvider).read(
              accountId: accountId,
              installationId:
                  ref.read(accountBindingServiceProvider).installationId,
            );
    final PreExerciseClearanceState result = PreExerciseClearanceState(
      clearance: clearance,
      isSaving: false,
      statusMessage: clearance
              .isValidAt(ref.read(preExerciseClearanceRealtimeClockProvider)())
          ? '筛查状态有效，仅保存在本机。'
          : clearance.blockingReasonAt(
              ref.read(preExerciseClearanceRealtimeClockProvider)(),
            ),
    );
    _scheduleExpiry(clearance);
    return result;
  }

  Future<bool> record({
    required PreExerciseClearanceStatus status,
    required bool currentInjuryOrRestriction,
  }) async {
    final PreExerciseClearanceState? current = state.value;
    if (current == null || current.isSaving) return false;
    state = AsyncData<PreExerciseClearanceState>(
      current.copyWith(isSaving: true, statusMessage: '正在保存本机筛查状态…'),
    );
    try {
      final AuthState authState = await ref.read(authControllerProvider.future);
      final String? accountId = authState.user?.userId;
      if (!authState.isAuthenticated || accountId == null) {
        throw const _ClearanceSaveException('登录状态已失效，请重新登录。');
      }
      final DateTime now =
          ref.read(preExerciseClearanceRealtimeClockProvider)();
      final PreExerciseClearance clearance = PreExerciseClearance.recorded(
        status: status,
        currentInjuryOrRestriction: currentInjuryOrRestriction,
        completedAt: now,
      );
      await ref.read(preExerciseClearanceRepositoryProvider).save(
            accountId: accountId,
            installationId:
                ref.read(accountBindingServiceProvider).installationId,
            clearance: clearance,
          );
      state = AsyncData<PreExerciseClearanceState>(
        PreExerciseClearanceState(
          clearance: clearance,
          isSaving: false,
          statusMessage: clearance.isValidAt(now)
              ? '已保存，筛查状态仅保存在本机。'
              : clearance.blockingReasonAt(now),
        ),
      );
      _scheduleExpiry(clearance);
      return true;
    } on _ClearanceSaveException catch (error) {
      state = AsyncData<PreExerciseClearanceState>(
        current.copyWith(isSaving: false, statusMessage: error.message),
      );
      return false;
    } catch (_) {
      state = AsyncData<PreExerciseClearanceState>(
        current.copyWith(
          isSaving: false,
          statusMessage: '筛查状态未能安全保存，请重试。',
        ),
      );
      return false;
    }
  }

  Future<void> invalidateForConditionChange() async {
    final PreExerciseClearanceState? current = state.value;
    if (current == null || current.isSaving) return;
    final DateTime now = ref.read(preExerciseClearanceRealtimeClockProvider)();
    final PreExerciseClearance invalidated =
        current.clearance.invalidateForConditionChange(now);
    final AuthState authState = await ref.read(authControllerProvider.future);
    final String? accountId = authState.user?.userId;
    if (!authState.isAuthenticated || accountId == null) return;
    await ref.read(preExerciseClearanceRepositoryProvider).save(
          accountId: accountId,
          installationId:
              ref.read(accountBindingServiceProvider).installationId,
          clearance: invalidated,
        );
    state = AsyncData<PreExerciseClearanceState>(
      PreExerciseClearanceState(
        clearance: invalidated,
        isSaving: false,
        statusMessage: invalidated.blockingReasonAt(now),
      ),
    );
    _expiryTimer?.cancel();
  }

  Future<void> clear() async {
    _expiryTimer?.cancel();
    await ref.read(preExerciseClearanceRepositoryProvider).clear();
    state = const AsyncData<PreExerciseClearanceState>(
      PreExerciseClearanceState(
        clearance: PreExerciseClearance.notCompleted(),
        isSaving: false,
        statusMessage: '已清除本机筛查状态。',
      ),
    );
  }

  void _scheduleExpiry(PreExerciseClearance clearance) {
    _expiryTimer?.cancel();
    final DateTime? validUntil = clearance.validUntil;
    if (validUntil == null ||
        clearance.invalidatedAt != null ||
        clearance.conditionChangedAt != null ||
        clearance.currentInjuryOrRestriction) {
      return;
    }
    final DateTime now = ref.read(preExerciseClearanceRealtimeClockProvider)();
    final Duration remaining = validUntil.difference(now);
    if (remaining.isNegative) {
      unawaited(_expireIfDue());
      return;
    }
    final Duration delay = remaining > _maximumExpiryTimerDelay
        ? _maximumExpiryTimerDelay
        : remaining + const Duration(milliseconds: 1);
    _expiryTimer = Timer(
      delay,
      () => unawaited(_expireIfDue()),
    );
  }

  Future<void> _expireIfDue() async {
    if (!ref.mounted) return;
    final PreExerciseClearanceState? current = state.value;
    if (current == null) return;
    final DateTime now = ref.read(preExerciseClearanceRealtimeClockProvider)();
    final DateTime? validUntil = current.clearance.validUntil;
    if (validUntil == null || !now.isAfter(validUntil)) {
      _scheduleExpiry(current.clearance);
      return;
    }
    final PreExerciseClearance expired =
        current.clearance.invalidateForExpiry(now);
    try {
      final AuthState authState = await ref.read(authControllerProvider.future);
      final String? accountId = authState.user?.userId;
      if (authState.isAuthenticated && accountId != null) {
        await ref.read(preExerciseClearanceRepositoryProvider).save(
              accountId: accountId,
              installationId:
                  ref.read(accountBindingServiceProvider).installationId,
              clearance: expired,
            );
      }
    } on Object {
      // 内存态仍立即失效；持久化失败时下次读取会按 validUntil 再次判定。
    }
    if (!ref.mounted) return;
    state = AsyncData<PreExerciseClearanceState>(
      PreExerciseClearanceState(
        clearance: expired,
        isSaving: false,
        statusMessage: expired.blockingReasonAt(now),
      ),
    );
  }
}

class _ClearanceSaveException implements Exception {
  final String message;

  const _ClearanceSaveException(this.message);
}
