import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/authenticated_api_client.dart';

final accountLifecycleClientProvider = Provider<AccountLifecycleClient>(
  (Ref ref) => AccountLifecycleApi(
    ref.watch(authenticatedApiClientProvider),
  ),
);

class AccountDeletionChallenge {
  final String challengeId;
  final int expiresInSeconds;

  const AccountDeletionChallenge({
    required this.challengeId,
    required this.expiresInSeconds,
  });
}

class AccountDeletionStatus {
  final String status;
  final String? requestId;
  final DateTime? requestedAt;
  final DateTime? purgeAfter;
  final int gracePeriodDays;

  const AccountDeletionStatus({
    required this.status,
    required this.requestId,
    required this.requestedAt,
    required this.purgeAfter,
    required this.gracePeriodDays,
  });

  bool get isPending => status == 'pending';

  factory AccountDeletionStatus.fromJson(Map<String, dynamic> json) {
    return AccountDeletionStatus(
      status: json['status'] as String? ?? 'not_requested',
      requestId: json['request_id'] as String?,
      requestedAt: DateTime.tryParse(json['requested_at'] as String? ?? ''),
      purgeAfter: DateTime.tryParse(json['purge_after'] as String? ?? ''),
      gracePeriodDays: (json['grace_period_days'] as num?)?.toInt() ?? 7,
    );
  }
}

abstract interface class AccountLifecycleClient {
  Future<Uint8List> exportAccount();

  Future<AccountDeletionStatus> deletionStatus();

  Future<AccountDeletionChallenge> requestDeletionChallenge(String email);

  Future<AccountDeletionStatus> requestDeletion({
    required String email,
    required String challengeId,
    required String code,
  });

  Future<AccountDeletionStatus> cancelDeletion();
}

class AccountLifecycleApi implements AccountLifecycleClient {
  final AuthenticatedApiClient _client;

  const AccountLifecycleApi(this._client);

  @override
  Future<Uint8List> exportAccount() => _client.getBytes('/v1/account/export');

  @override
  Future<AccountDeletionStatus> deletionStatus() async {
    return AccountDeletionStatus.fromJson(
      await _client.getJson(
        '/v1/account/deletion-status',
        authenticated: true,
      ),
    );
  }

  @override
  Future<AccountDeletionChallenge> requestDeletionChallenge(
    String email,
  ) async {
    final Map<String, dynamic> payload = await _client.postJson(
      '/v1/account/deletion-challenges',
      <String, dynamic>{'email': email.trim()},
      authenticated: true,
    );
    return AccountDeletionChallenge(
      challengeId: payload['challenge_id'] as String,
      expiresInSeconds: (payload['expires_in_seconds'] as num).toInt(),
    );
  }

  @override
  Future<AccountDeletionStatus> requestDeletion({
    required String email,
    required String challengeId,
    required String code,
  }) async {
    return AccountDeletionStatus.fromJson(
      await _client.postJson(
        '/v1/account/deletion-requests',
        <String, dynamic>{
          'email': email.trim(),
          'challenge_id': challengeId,
          'code': code.trim(),
        },
        authenticated: true,
      ),
    );
  }

  @override
  Future<AccountDeletionStatus> cancelDeletion() async {
    return AccountDeletionStatus.fromJson(
      await _client.postJson(
        '/v1/account/deletion-cancellations',
        const <String, dynamic>{},
        authenticated: true,
      ),
    );
  }
}
