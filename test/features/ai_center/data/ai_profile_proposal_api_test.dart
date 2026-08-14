import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trainflow_ai/features/ai_center/data/ai_api.dart';
import 'package:trainflow_ai/features/auth/data/authenticated_api_client.dart';
import 'package:trainflow_ai/features/auth/data/session_token_store.dart';
import 'package:trainflow_ai/features/onboarding/application/profile_privacy_parser.dart';

class _TokenStore implements SessionTokenStore {
  @override
  String? accessToken = 'access-token';

  @override
  Future<void> clear() async => accessToken = null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> updateAccessToken(String accessToken) async {
    this.accessToken = accessToken;
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
  }
}

void main() {
  test('画像提议接口只发送本地白名单和脱敏歧义片段', () async {
    final ProfileLocalExtraction extraction =
        const ProfilePrivacyParser().parse('更喜欢有节奏、能长期坚持的项目。');
    final MockClient client = MockClient((http.Request request) async {
      expect(request.url.path, '/v1/ai/profile-proposals');
      final Map<String, dynamic> body =
          jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys, <String>{
        'contract_version',
        'request_id',
        'known_fields',
        'unresolved_field_codes',
        'ambiguity_fragments',
      });
      final String encoded = jsonEncode(body);
      expect(encoded, isNot(contains('age')));
      expect(encoded, isNot(contains('weight')));
      expect(encoded, isNot(contains('injury')));
      expect(encoded, isNot(contains('phone')));
      return http.Response(
        jsonEncode(<String, dynamic>{
          'id': 'proposal-1',
          'capability': 'trainer',
          'artifact_type': 'profile_proposal_v1',
          'schema_version': 1,
          'decision_status': 'pending',
          'context_digest': 'a' * 64,
          'payload': <String, dynamic>{
            'proposal_status': 'pending',
            'proposed_fields': <Map<String, dynamic>>[
              <String, dynamic>{
                'field_code': 'primary_sport',
                'value': 'running',
                'confidence': 0.8,
              },
            ],
            'missing_field_codes': <String>['experience_level'],
            'follow_up_codes': <String>['ask_experience'],
            'generation_meta': <String, dynamic>{
              'generation_mode': 'cloud_adaptation',
              'input_tokens': 80,
              'output_tokens': 30,
            },
          },
          'warnings': <String>[],
          'provider': 'deepseek',
          'model': 'deepseek-v4-flash',
          'generated_at': '2026-07-30T00:00:00Z',
        }),
        201,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final AiApi api = AiApi(
      AuthenticatedApiClient(
        client: client,
        tokenStore: _TokenStore(),
      ),
    );

    final proposal = await api.proposeProfile(
      extraction.toRequest(requestId: 'profile-local-1'),
    );

    expect(proposal.isPending, isTrue);
    expect(proposal.proposedFields.single.fieldCode, 'primary_sport');
  });
}
