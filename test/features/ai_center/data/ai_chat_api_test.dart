import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trainflow_ai/data/models/ai_chat.dart';
import 'package:trainflow_ai/features/ai_center/data/ai_api.dart';
import 'package:trainflow_ai/features/auth/data/authenticated_api_client.dart';
import 'package:trainflow_ai/features/auth/data/session_token_store.dart';

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
  test('结构化聊天请求不包含自由文本和展示标签', () async {
    final MockClient httpClient = MockClient((http.Request request) async {
      expect(request.url.path, '/v2/ai/chat');
      final Map<String, dynamic> body =
          jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys, <String>{
        'contract_version',
        'request_id',
        'intent',
        'context',
      });
      expect(body['contract_version'], 2);
      expect(body['intent'], 'explain_today_training');
      expect(
        body['context'],
        <String, dynamic>{
          'sport_codes': <String>['marathon', 'strength'],
          'available_minutes': 30,
          'scheduled_minutes': 25,
          'scheduled_period': 'evening',
        },
      );
      final String encoded = jsonEncode(body);
      expect(encoded, isNot(contains('messages')));
      expect(encoded, isNot(contains('goal')));
      expect(encoded, isNot(contains('膝盖')));
      expect(encoded, isNot(contains('跑步')));
      return http.Response(
        jsonEncode(<String, dynamic>{
          'reply': '按计划控制节奏。',
          'intent': 'training_question',
          'suggested_actions': <String>[],
          'warnings': <String>[],
          'provider': 'test',
          'model': 'test-chat',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final AiApi api = AiApi(
      AuthenticatedApiClient(
        client: httpClient,
        tokenStore: _TokenStore(),
      ),
    );

    final AiChatResponse response = await api.chat(
      requestId: 'request-12345678',
      intent: AiChatCloudIntent.explainTodayTraining,
      context: const AiChatContext(
        sportCodes: <String>['marathon', 'rehab', 'strength', 'fat_loss'],
        availableMinutes: 30,
        scheduledMinutes: 25,
        scheduledPeriod: 'evening',
      ),
    );

    expect(response.reply, '按计划控制节奏。');
  });
}
