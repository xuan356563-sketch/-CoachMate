import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import '../../../data/models/cloud_sync.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/authenticated_api_client.dart';
import 'first_run_onboarding_controller.dart';
import '../data/membership_api.dart';
import '../domain/first_run_models.dart';

const String trainMateMonthlyProductId =
    'com.zhilian.trainmate.membership.monthly';

final membershipApiProvider = Provider<MembershipApi>(
  (Ref ref) => MembershipApi(ref.watch(authenticatedApiClientProvider)),
);

final membershipControllerProvider =
    AsyncNotifierProvider<MembershipController, MembershipUiState>(
  MembershipController.new,
  retry: (int _, Object __) => null,
);

class MembershipUiState {
  const MembershipUiState({
    required this.entitlement,
    this.product,
    this.introductoryOfferEligible = false,
    this.busy = false,
    this.message,
  });

  final MembershipEntitlement entitlement;
  final ProductDetails? product;
  final bool introductoryOfferEligible;
  final bool busy;
  final String? message;

  bool get canPurchase =>
      defaultTargetPlatform == TargetPlatform.iOS && product != null && !busy;

  MembershipUiState copyWith({
    MembershipEntitlement? entitlement,
    ProductDetails? product,
    bool? introductoryOfferEligible,
    bool? busy,
    String? message,
  }) {
    return MembershipUiState(
      entitlement: entitlement ?? this.entitlement,
      product: product ?? this.product,
      introductoryOfferEligible:
          introductoryOfferEligible ?? this.introductoryOfferEligible,
      busy: busy ?? this.busy,
      message: message,
    );
  }
}

class MembershipController extends AsyncNotifier<MembershipUiState> {
  final InAppPurchase _store = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  late MembershipApi _api;
  late String _userId;

  @override
  Future<MembershipUiState> build() async {
    _api = ref.read(membershipApiProvider);
    final AuthState auth = await ref.watch(authControllerProvider.future);
    _userId = auth.user?.userId ?? '';
    _purchaseSubscription = _store.purchaseStream.listen(_handlePurchases);
    ref.onDispose(() => _purchaseSubscription?.cancel());
    MembershipEntitlement entitlement;
    try {
      entitlement = await _api.entitlement();
    } catch (_) {
      entitlement = const MembershipEntitlement(
        status: MembershipEntitlementStatus.none,
        canGeneratePlan: false,
      );
    }
    if (!iosSubscriptionEnabled) {
      return MembershipUiState(
        entitlement: entitlement,
        message: 'iOS 订阅功能尚未放量，可先进入浏览模式。',
      );
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return MembershipUiState(
        entitlement: entitlement,
        message: '当前平台可使用文字建档和浏览模式，购买仅在 iOS 提供。',
      );
    }
    try {
      if (!await _store.isAvailable()) {
        return MembershipUiState(
          entitlement: entitlement,
          message: '暂时无法连接 App Store，可先进入浏览模式。',
        );
      }
      final ProductDetailsResponse response = await _store.queryProductDetails(
        const <String>{trainMateMonthlyProductId},
      );
      final ProductDetails? product = response.productDetails.isEmpty
          ? null
          : response.productDetails.first;
      bool eligible = false;
      if (product is AppStoreProduct2Details) {
        eligible = await SK2Product.isIntroductoryOfferEligible(product.id);
      }
      return MembershipUiState(
        entitlement: entitlement,
        product: product,
        introductoryOfferEligible: eligible,
        message: response.error?.message,
      );
    } catch (_) {
      return MembershipUiState(
        entitlement: entitlement,
        message: '商品加载失败，可恢复购买或先进入浏览模式。',
      );
    }
  }

  Future<void> purchase() async {
    final MembershipUiState current = state.requireValue;
    final ProductDetails? product = current.product;
    if (product == null || !current.canPurchase) return;
    state = AsyncData<MembershipUiState>(
      current.copyWith(busy: true, message: '正在打开 App Store…'),
    );
    try {
      await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
          applicationUserName: _userId,
        ),
      );
    } catch (_) {
      state = AsyncData<MembershipUiState>(
        current.copyWith(busy: false, message: '购买未完成，可稍后重试。'),
      );
    }
  }

  Future<void> restore() async {
    final MembershipUiState current = state.requireValue;
    state = AsyncData<MembershipUiState>(
      current.copyWith(busy: true, message: '正在恢复购买…'),
    );
    try {
      await _store.restorePurchases(applicationUserName: _userId);
    } catch (_) {
      state = AsyncData<MembershipUiState>(
        current.copyWith(busy: false, message: '恢复购买失败，请稍后重试。'),
      );
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    if (!state.hasValue) return;
    for (final PurchaseDetails purchase in purchases) {
      if (purchase.productID != trainMateMonthlyProductId) continue;
      if (purchase.status == PurchaseStatus.pending) {
        state = AsyncData<MembershipUiState>(
          state.requireValue.copyWith(busy: true, message: '购买正在处理中…'),
        );
        continue;
      }
      if (purchase.status == PurchaseStatus.error ||
          purchase.status == PurchaseStatus.canceled) {
        state = AsyncData<MembershipUiState>(
          state.requireValue.copyWith(
            busy: false,
            message: purchase.status == PurchaseStatus.canceled
                ? '已取消购买，可继续浏览。'
                : '购买失败，未开通会员。',
          ),
        );
        continue;
      }
      try {
        final MembershipEntitlement entitlement = await _api.verifyTransaction(
          requestId: generateCloudSyncMutationId(),
          verificationData: purchase.verificationData.serverVerificationData,
          appAccountToken: _userId,
        );
        if (purchase.pendingCompletePurchase) {
          await _store.completePurchase(purchase);
        }
        state = AsyncData<MembershipUiState>(
          state.requireValue.copyWith(
            entitlement: entitlement,
            busy: false,
            message:
                entitlement.canGeneratePlan ? '会员权益已生效' : '交易已验证，当前没有可用生成权益。',
          ),
        );
      } catch (_) {
        state = AsyncData<MembershipUiState>(
          state.requireValue.copyWith(
            busy: false,
            message: '服务端尚未验证交易，请勿重复购买，稍后可恢复购买。',
          ),
        );
      }
    }
  }
}

class EntitlementGate {
  const EntitlementGate(this.entitlement);

  final MembershipEntitlement entitlement;

  bool get canGenerate => entitlement.canGeneratePlan;

  void requirePlanGeneration() {
    if (paidPlanGenerationGateEnabled && !canGenerate) {
      throw StateError('生成或重排新计划需要有效会员');
    }
  }
}
