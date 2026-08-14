import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/ai_chat.dart';
import 'package:trainflow_ai/data/repositories/ai_chat_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('聊天记录按账号隔离，并限制会话与消息数量', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final PersistedAiChatRepository repository =
        PersistedAiChatRepository(storage);
    final DateTime now = DateTime(2026, 7, 27, 12);

    for (int sessionIndex = 0; sessionIndex < 22; sessionIndex++) {
      repository.saveSession(
        AiChatSession(
          id: 'session-$sessionIndex',
          accountId: 'user-a',
          createdAt: now.subtract(Duration(days: sessionIndex)),
          updatedAt: now.subtract(Duration(days: sessionIndex)),
          messages: List<AiChatMessage>.generate(
            105,
            (int messageIndex) => AiChatMessage(
              id: 'message-$sessionIndex-$messageIndex',
              role: AiChatMessageRole.user,
              content: '消息 $messageIndex',
              createdAt: now.add(Duration(seconds: messageIndex)),
              status: AiChatMessageStatus.sent,
              cloudEligible: true,
            ),
          ),
        ),
        now: now,
      );
    }
    repository.saveSession(
      AiChatSession(
        id: 'user-b-session',
        accountId: 'user-b',
        createdAt: now,
        updatedAt: now,
        messages: const <AiChatMessage>[],
      ),
      now: now,
    );

    final List<AiChatSession> userA =
        repository.listSessions('user-a', now: now);
    final List<AiChatSession> userB =
        repository.listSessions('user-b', now: now);

    expect(userA, hasLength(20));
    expect(userA.first.messages, hasLength(100));
    expect(userA.map((AiChatSession item) => item.accountId).toSet(),
        <String>{'user-a'});
    expect(userB.single.id, 'user-b-session');
  });

  test('超过 30 天的聊天会话会被清理', () {
    final PersistedAiChatRepository repository =
        PersistedAiChatRepository(InMemoryLocalStorageService());
    final DateTime now = DateTime(2026, 7, 27);

    repository.saveSession(
      AiChatSession(
        id: 'expired',
        accountId: 'user-a',
        createdAt: now.subtract(const Duration(days: 31)),
        updatedAt: now.subtract(const Duration(days: 31)),
        messages: const <AiChatMessage>[],
      ),
      now: now,
    );

    expect(repository.listSessions('user-a', now: now), isEmpty);
  });
}
