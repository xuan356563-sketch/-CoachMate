import '../../auth/data/authenticated_api_client.dart';
import '../domain/first_run_models.dart';

class MembershipApi {
  const MembershipApi(this._client);

  final AuthenticatedApiClient _client;

  Future<MembershipEntitlement> entitlement() async {
    return _fromJson(
      await _client.getJson('/v1/billing/entitlement', authenticated: true),
    );
  }

  Future<MembershipEntitlement> verifyTransaction({
    required String requestId,
    required String verificationData,
    required String appAccountToken,
  }) async {
    return _fromJson(
      await _client.postJson(
        '/v1/billing/apple/transactions/verify',
        <String, dynamic>{
          'request_id': requestId,
          'verification_data': verificationData,
          'app_account_token': appAccountToken,
        },
        authenticated: true,
      ),
    );
  }

  MembershipEntitlement _fromJson(Map<String, dynamic> json) {
    final String raw = json['status'] as String;
    return MembershipEntitlement(
      status: switch (raw) {
        'trial' => MembershipEntitlementStatus.trial,
        'active' => MembershipEntitlementStatus.active,
        'grace_period' => MembershipEntitlementStatus.gracePeriod,
        'billing_retry' => MembershipEntitlementStatus.billingRetry,
        'expired' => MembershipEntitlementStatus.expired,
        'revoked' => MembershipEntitlementStatus.revoked,
        _ => MembershipEntitlementStatus.none,
      },
      canGeneratePlan: json['can_generate_plan'] as bool,
      productId: json['product_id'] as String?,
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
    );
  }
}
