import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/ai_chat.dart';
import 'package:trainflow_ai/data/repositories/ai_chat_repository.dart';
import 'package:trainflow_ai/features/ai_center/application/ai_chat_controller.dart';
import 'package:trainflow_ai/features/ai_center/application/chat_privacy_router.dart';
import 'package:trainflow_ai/features/auth/application/auth_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

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
            goal: '保持训练',
            sports: <String>['跑步'],
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
}
