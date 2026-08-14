import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'authenticated_api_client.dart';

final authApiProvider = Provider<AuthApi>(
  (Ref ref) => AuthApi(ref.watch(authenticatedApiClientProvider)),
);

class PublicAuthConfig {
  final String termsVersion;
  final String privacyVersion;
  final String emailMode;
  final String smsMode;

  const PublicAuthConfig({
    required this.termsVersion,
    required this.privacyVersion,
    required this.emailMode,
    this.smsMode = 'disabled',
  });

  factory PublicAuthConfig.fromJson(Map<String, dynamic> json) {
    return PublicAuthConfig(
      termsVersion: json['terms_version'] as String,
      privacyVersion: json['privacy_version'] as String,
      emailMode: json['email_mode'] as String,
      smsMode: json['sms_mode'] as String? ?? 'disabled',
    );
  }
}

class EmailChallenge {
  final String challengeId;
  final int expiresInSeconds;

  const EmailChallenge({
    required this.challengeId,
    required this.expiresInSeconds,
  });
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
  });
}

class AuthUser {
  final String userId;
  final String sessionId;
  final String accountType;
  final String? maskedEmail;
  final String? phoneLast4;
  final bool hasRequiredConsents;

  const AuthUser({
    required this.userId,
    required this.sessionId,
    this.accountType = 'email',
    this.maskedEmail,
    this.phoneLast4,
    required this.hasRequiredConsents,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final String? maskedEmail = json['masked_email'] as String?;
    final String? phoneLast4 = json['phone_last4'] as String?;
    return AuthUser(
      userId: json['user_id'] as String,
      sessionId: json['session_id'] as String,
      accountType: json['account_type'] as String? ??
          (maskedEmail != null
              ? 'email'
              : phoneLast4 != null
                  ? 'phone'
                  : 'unknown'),
      maskedEmail: maskedEmail,
      phoneLast4: phoneLast4,
      hasRequiredConsents: json['has_required_consents'] as bool,
    );
  }

  String get maskedAccountLabel {
    final String? email = maskedEmail;
    if (email != null && email.isNotEmpty) {
      return email;
    }
    final String? last4 = phoneLast4;
    if (last4 != null && last4.isNotEmpty) {
      return '旧账号尾号 $last4';
    }
    return '账号信息不可用';
  }
}

class AuthApi {
  final AuthenticatedApiClient _client;

  const AuthApi(this._client);

  Future<PublicAuthConfig> publicConfig() async {
    return PublicAuthConfig.fromJson(
      await _client.getJson('/v1/auth/public-config'),
    );
  }

  Future<EmailChallenge> requestEmailChallenge(String email) async {
    final Map<String, dynamic> payload = await _client.postJson(
      '/v1/auth/email-challenges',
      <String, dynamic>{'email': email},
    );
    return EmailChallenge(
      challengeId: payload['challenge_id'] as String,
      expiresInSeconds: payload['expires_in_seconds'] as int,
    );
  }

  Future<EmailChallenge> requestSmsChallenge(String phone) async {
    final Map<String, dynamic> payload = await _client.postJson(
      '/v1/auth/sms-challenges',
      <String, dynamic>{'phone': phone},
    );
    return EmailChallenge(
      challengeId: payload['challenge_id'] as String,
      expiresInSeconds: payload['expires_in_seconds'] as int,
    );
  }

  Future<AuthTokens> createSession({
    required String email,
    required String challengeId,
    required String code,
    required String installationId,
    required PublicAuthConfig config,
  }) async {
    final Map<String, dynamic> payload = await _client.postJson(
      '/v1/auth/sessions',
      <String, dynamic>{
        'email': email,
        'challenge_id': challengeId,
        'code': code,
        'device': <String, dynamic>{
          'installation_id': installationId,
          'platform': _platformName(),
          'device_name': kIsWeb ? 'TrainFlow Web' : 'TrainFlow App',
        },
        'consents': <String, dynamic>{
          'terms_version': config.termsVersion,
          'privacy_version': config.privacyVersion,
        },
      },
    );
    return AuthTokens(
      accessToken: payload['access_token'] as String,
      refreshToken: payload['refresh_token'] as String,
    );
  }

  Future<AuthTokens> createPhoneSession({
    required String phone,
    required String challengeId,
    required String code,
    required String installationId,
    required PublicAuthConfig config,
  }) async {
    final Map<String, dynamic> payload = await _client.postJson(
      '/v1/auth/sessions',
      <String, dynamic>{
        'phone': phone,
        'challenge_id': challengeId,
        'code': code,
        'device': <String, dynamic>{
          'installation_id': installationId,
          'platform': _platformName(),
          'device_name': kIsWeb ? 'TrainFlow Web' : 'TrainFlow App',
        },
        'consents': <String, dynamic>{
          'terms_version': config.termsVersion,
          'privacy_version': config.privacyVersion,
        },
      },
    );
    return AuthTokens(
      accessToken: payload['access_token'] as String,
      refreshToken: payload['refresh_token'] as String,
    );
  }

  Future<AuthUser> currentUser() async {
    return AuthUser.fromJson(
      await _client.getJson('/v1/auth/me', authenticated: true),
    );
  }

  Future<void> logout() async {
    await _client.deleteJson('/v1/auth/sessions/current');
  }

  String _platformName() {
    if (kIsWeb) {
      return 'web';
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'linux',
    };
  }
}
