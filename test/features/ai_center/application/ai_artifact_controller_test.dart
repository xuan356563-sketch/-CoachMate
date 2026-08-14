import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:trainflow_ai/data/models/ai_artifact.dart';
import 'package:trainflow_ai/data/repositories/ai_artifact_repository.dart';
import 'package:trainflow_ai/features/ai_center/application/ai_artifact_controller.dart';
import 'package:trainflow_ai/features/auth/data/authenticated_api_client.dart';
import 'package:trainflow_ai/features/auth/data/session_token_store.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

class _MemoryTokenStore implements SessionTokenStore {
  @override
  String? accessToken = 'test-access-token';

  @override
  Future<void> clear() async => accessToken = null;

  @override
  Future<String?> readRefreshToken() async => 'test-refresh-token';

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

AiGenerationContext _context() => const AiGenerationContext(
      goal: '提高跑步耐力',
      sports: <String>['跑步'],
      availableMinutes: 45,
      readinessScore: 72,
      dailyDecision: '可以训练',
      painLevel: 0,
    );

Map<String, dynamic> _artifactJson({
  String id = 'ai-artifact-1',
  String decision = 'pending',
}) =>
    <String, dynamic>{
      'id': id,
      'capability': 'trainer',
      'artifact_type': 'trainer_plan_v1',
      'schema_version': 1,
      'decision_status': decision,
      'context_digest': 'safe-context-digest',
      'payload': <String, dynamic>{
        'cycle_label': '四周跑步耐力周期',
        'weekly_structure': '每周三练，恢复日穿插安排。',
        'workout_cards': <Map<String, dynamic>>[
          <String, dynamic>{
            'title': '轻松跑',
            'duration_minutes': 45,
            'intensity': '低强度',
            'focus': <String>['呼吸节奏'],
            'safety_note': '疼痛加重时停止。',
          },
        ],
        'safety_notes': <String>['恢复不足时降级。'],
      },
      'warnings': <String>[],
      'provider': 'deepseek',
      'model': 'deepseek-chat',
      'generated_at': '2026-07-13T12:00:00Z',
      'decided_at': null,
    };

ProviderContainer _container({
  required http.Client client,
  InMemoryLocalStorageService? storage,
}) {
  return ProviderContainer(
    overrides: [
      localStorageServiceProvider.overrideWithValue(
        storage ?? InMemoryLocalStorageService(),
      ),
      httpClientProvider.overrideWithValue(client),
      sessionTokenStoreProvider.overrideWithValue(_MemoryTokenStore()),
    ],
  );
}

void main() {
  test('生成 AI Trainer 后只缓存结构化卡片，不持久化原始提示词', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final MockClient client = MockClient((http.Request request) async {
      expect(request.url.path, '/v1/ai/generations');
      expect(request.headers['authorization'], 'Bearer test-access-token');
      final Map<String, dynamic> body =
          jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['prompt'], '下周只能晚上训练 45 分钟');
      final Map<String, dynamic> context =
          body['context']! as Map<String, dynamic>;
      expect(context, isNot(contains('readiness_score')));
      expect(context, isNot(contains('daily_decision')));
      expect(context, isNot(contains('pain_level')));
      expect(context, isNot(contains('health_summary')));
      return http.Response(
        jsonEncode(_artifactJson()),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final ProviderContainer container = _container(
      client: client,
      storage: storage,
    );
    addTearDown(container.dispose);

    final AiArtifact? artifact = await container
        .read(aiArtifactControllerProvider.notifier)
        .generateText(
          capability: AiCapability.trainer,
          prompt: '下周只能晚上训练 45 分钟',
          context: _context(),
        );

    expect(artifact?.trainerPlan?.cycleLabel, '四周跑步耐力周期');
    expect(
      container.read(aiArtifactControllerProvider).artifacts,
      hasLength(1),
    );

    final Map<String, dynamic>? persisted =
        storage.readJson(PersistedAiArtifactRepository.storageKey);
    expect(persisted, isNotNull);
    final String persistedText = jsonEncode(persisted);
    expect(persistedText, isNot(contains('下周只能晚上训练 45 分钟')));
    expect(persistedText, contains('trainer_plan_v1'));
  });

  test('确认采用后会更新本地卡片状态，并强制关闭旧健康摘要开关', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.url.path, '/v1/ai/artifacts/ai-artifact-1/decision');
      return http.Response(
        jsonEncode(_artifactJson(decision: 'accepted')),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final ProviderContainer container = _container(client: client);
    addTearDown(container.dispose);
    final AiArtifact pending = AiArtifact.fromJson(_artifactJson());
    container.read(aiArtifactRepositoryProvider).upsert(pending);
    container.invalidate(aiArtifactControllerProvider);
    final AiArtifactState initial =
        container.read(aiArtifactControllerProvider);

    container
        .read(aiArtifactControllerProvider.notifier)
        .setHealthDataProcessingConsent(true);
    final AiArtifact? accepted =
        await container.read(aiArtifactControllerProvider.notifier).decide(
              artifact: initial.artifacts.single,
              decision: AiArtifactDecision.accepted,
            );

    expect(accepted?.decision, AiArtifactDecision.accepted);
    expect(
      container.read(aiArtifactControllerProvider).artifacts.single.decision,
      AiArtifactDecision.accepted,
    );
    expect(
      container
          .read(aiArtifactControllerProvider)
          .healthDataProcessingConsented,
      isFalse,
    );
  });

  test('即使上下文对象含健康摘要，网络 DTO 也不会序列化健康派生字段', () {
    const AiGenerationContext context = AiGenerationContext(
      goal: '恢复',
      sports: <String>['跑步'],
      availableMinutes: 30,
      readinessScore: 25,
      dailyDecision: '降低强度',
      painLevel: 7,
      healthSummary: AiHealthSummary(
        sleepHours: 4.5,
        restingHeartRate: 82,
        hrvMs: 20,
        fatigueLevel: 9,
      ),
    );

    final Map<String, dynamic> json = context.toJson();

    expect(json, isNot(contains('readiness_score')));
    expect(json, isNot(contains('daily_decision')));
    expect(json, isNot(contains('pain_level')));
    expect(json, isNot(contains('health_summary')));
  });

  test('已接受训练处方再次激活前会请求服务端复核，Skill 不可用时返回失败', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.url.path, '/v1/ai/artifacts/ai-artifact-1/decision');
      return http.Response(
        jsonEncode(<String, dynamic>{
          'code': 'training_plan_skill_unavailable',
          'detail': '当前 Skill 已停用，请重新生成。',
        }),
        503,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final ProviderContainer container = _container(client: client);
    addTearDown(container.dispose);
    final AiArtifact accepted = AiArtifact.fromJson(
      _artifactJson(decision: 'accepted')
        ..['artifact_type'] = 'training_prescription_v1',
    );
    container.read(aiArtifactRepositoryProvider).upsert(accepted);
    container.invalidate(aiArtifactControllerProvider);

    final AiArtifact? result =
        await container.read(aiArtifactControllerProvider.notifier).decide(
              artifact: accepted,
              decision: AiArtifactDecision.accepted,
            );

    expect(result, isNull);
    expect(
      container.read(aiArtifactControllerProvider).statusMessage,
      contains('当前 Skill 已停用'),
    );
  });
}
