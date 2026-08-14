import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_route_refresh.dart';
import '../data/first_run_draft_store.dart';
import '../domain/first_run_models.dart';

const bool firstRunOnboardingV2Enabled = bool.fromEnvironment(
  'FIRST_RUN_ONBOARDING_V2_ENABLED',
  defaultValue: false,
);
const bool healthProfileCloudEnabled = bool.fromEnvironment(
  'HEALTH_PROFILE_CLOUD_ENABLED',
  defaultValue: false,
);
const bool iosSubscriptionEnabled = bool.fromEnvironment(
  'IOS_SUBSCRIPTION_ENABLED',
  defaultValue: false,
);
const bool paidPlanGenerationGateEnabled = bool.fromEnvironment(
  'PAID_PLAN_GENERATION_GATE_ENABLED',
  defaultValue: false,
);

final firstRunDraftStoreProvider = Provider<FirstRunDraftStore>(
  (Ref ref) => SecureFirstRunDraftStore(),
);

final firstRunOnboardingControllerProvider =
    AsyncNotifierProvider<FirstRunOnboardingController, FirstRunDraft>(
  FirstRunOnboardingController.new,
);

class FirstRunOnboardingController extends AsyncNotifier<FirstRunDraft> {
  late FirstRunDraftStore _store;

  @override
  Future<FirstRunDraft> build() async {
    _store = ref.read(firstRunDraftStoreProvider);
    final FirstRunDraft draft =
        await _store.load() ?? FirstRunDraft.initial(DateTime.now().toUtc());
    scheduleMicrotask(authRouteRefreshNotifier.refresh);
    return draft;
  }

  Future<bool> confirmPersonal(PersonalProfileDraft profile) async {
    if (!profile.isAdult) {
      return false;
    }
    final FirstRunDraft next = _current.copyWith(
      stage: OnboardingStage.training,
      updatedAt: DateTime.now().toUtc(),
      personal: profile,
    );
    await _save(next);
    return true;
  }

  Future<void> confirmTraining(TrainingBaselineDraft training) async {
    await _save(
      _current.copyWith(
        stage: OnboardingStage.login,
        updatedAt: DateTime.now().toUtc(),
        training: training,
      ),
    );
  }

  Future<void> bindAuthenticatedUser(String userId) async {
    final String? bound = _current.boundUserId;
    if (bound != null && bound != userId) {
      throw StateError('本地建档草稿属于另一个账号，请先确认账号归属');
    }
    await _save(
      _current.copyWith(
        stage: OnboardingStage.cloudConsent,
        updatedAt: DateTime.now().toUtc(),
        boundUserId: userId,
      ),
    );
  }

  Future<void> confirmCloudConsent(HealthCloudConsent consent) async {
    await _save(
      _current.copyWith(
        stage: OnboardingStage.membership,
        updatedAt: DateTime.now().toUtc(),
        healthConsent: consent,
      ),
    );
  }

  Future<void> complete() async {
    await _save(
      _current.copyWith(
        stage: OnboardingStage.complete,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> reset() async {
    await _store.clear();
    state = AsyncData<FirstRunDraft>(
      FirstRunDraft.initial(DateTime.now().toUtc()),
    );
  }

  FirstRunDraft get _current => state.requireValue;

  Future<void> _save(FirstRunDraft draft) async {
    await _store.save(draft);
    state = AsyncData<FirstRunDraft>(draft);
    authRouteRefreshNotifier.refresh();
  }
}
