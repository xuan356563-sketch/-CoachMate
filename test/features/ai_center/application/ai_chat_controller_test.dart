import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/ai_chat.dart';
import 'package:trainflow_ai/data/repositories/ai_chat_repository.dart';
import 'package:trainflow_ai/features/ai_center/application/ai_chat_controller.dart';
import 'package:trainflow_ai/features/ai_center/application/chat_privacy_router.dart';
import 'package:trainflow_ai/features/ai_center/data/ai_api.dart';
import 'package:trainflow_ai/features/auth/application/auth_controller.dart';
import 'package:trainflow_ai/features/auth/data/authenticated_api_client.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';

import '../../../support/test_harness.dart';

void main() {
  test('身体状态消息在本地完成，不产生云端可发送消息', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        authControllerProvider.overrideWith(
          TestAuthenticatedAuthController.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    await container.read(aiChatControllerProvider.notifier).send(
          text: '结合我的疼痛看看身体状态',
          localStatus: AiLocalStatusSnapshot(
            todayWorkoutTitle: '轻松跑',
            todayWorkoutSummary: '30 分钟',
            activePlanTitle: '基础周期',
            bodyFacts: const <String>['疼痛 3/10', '疲劳 5/10'],
            bodyUpdatedAt: DateTime(2026, 7, 27),
          ),
          context: const AiChatContext(
            sportCodes: <String>['marathon'],
            availableMinutes: 30,
          ),
        );

    final AiChatState state = container.read(aiChatControllerProvider);
    expect(state.session.accountId, 'test-user-id');
    expect(state.session.messages, hasLength(2));
    expect(state.session.messages.first.cloudEligible, isFalse);
    expect(state.session.messages.last.role, AiChatMessageRole.local);
    expect(state.session.messages.last.content, contains('只在本机'));

    final PersistedAiChatRepository repository =
        PersistedAiChatRepository(storage);
    expect(
        repository.listSessions('test-user-id').single.messages, hasLength(2));
  });

  test('AI 功能停用后丢弃迟到回复且不改写已提交用户消息', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final _DeferredAiApi api = _DeferredAiApi();
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        pluginRuntimeProvider.overrideWith((ref) => runtime),
        localStorageServiceProvider.overrideWithValue(storage),
        authControllerProvider.overrideWith(
          TestAuthenticatedAuthController.new,
        ),
        aiApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final Future<void> pending =
        container.read(aiChatControllerProvider.notifier).send(
              text: '解释当前计划安排',
              localStatus: AiLocalStatusSnapshot(
                todayWorkoutTitle: '轻松跑',
                todayWorkoutSummary: '30 分钟',
                activePlanTitle: '基础周期',
                bodyFacts: const <String>[],
                bodyUpdatedAt: DateTime(2026, 9, 4),
              ),
              context: const AiChatContext(
                sportCodes: <String>['marathon'],
                availableMinutes: 30,
              ),
            );
    await api.called.future;
    await runtime.disable('feature.ai_center');
    api.response.complete(const AiChatResponse(
      reply: '这是一条迟到回复',
      intent: AiChatIntent.explainPlan,
      suggestedActions: <String>['采用'],
      warnings: <String>[],
      provider: 'test',
      model: 'test',
    ));

    await expectLater(pending, throwsStateError);
    final List<AiChatSession> sessions =
        PersistedAiChatRepository(storage).listSessions('test-user-id');
    expect(sessions.single.messages, hasLength(1));
    expect(sessions.single.messages.single.role, AiChatMessageRole.user);
    expect(sessions.single.messages.single.content, '解释当前计划安排');
    expect(
      sessions.single.messages.any(
        (AiChatMessage message) => message.content == '这是一条迟到回复',
      ),
      isFalse,
    );
  });

  test('AI 功能停用后远端迟到失败也不会写入失败状态', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final _DeferredAiApi api = _DeferredAiApi();
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        pluginRuntimeProvider.overrideWith((ref) => runtime),
        localStorageServiceProvider.overrideWithValue(storage),
        authControllerProvider.overrideWith(
          TestAuthenticatedAuthController.new,
        ),
        aiApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final Future<void> pending =
        container.read(aiChatControllerProvider.notifier).send(
              text: '解释当前计划安排',
              localStatus: AiLocalStatusSnapshot(
                todayWorkoutTitle: '轻松跑',
                todayWorkoutSummary: '30 分钟',
                activePlanTitle: '基础周期',
                bodyFacts: const <String>[],
                bodyUpdatedAt: DateTime(2026, 9, 4),
              ),
              context: const AiChatContext(
                sportCodes: <String>['marathon'],
                availableMinutes: 30,
              ),
            );
    await api.called.future;
    await runtime.disable('feature.ai_center');
    api.response.completeError(
      const ApiException(code: 'late_failure', message: '迟到失败'),
    );

    await expectLater(pending, throwsStateError);
    final AiChatMessage user = PersistedAiChatRepository(storage)
        .listSessions('test-user-id')
        .single
        .messages
        .single;
    expect(user.role, AiChatMessageRole.user);
    expect(user.status, AiChatMessageStatus.sending);
  });
}

class _DeferredAiApi implements AiApi {
  final Completer<void> called = Completer<void>();
  final Completer<AiChatResponse> response = Completer<AiChatResponse>();

  @override
  Future<AiChatResponse> chat({
    required String requestId,
    required AiChatCloudIntent intent,
    required AiChatContext context,
  }) {
    called.complete();
    return response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
