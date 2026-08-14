import '../models/ai_chat.dart';
import '../../services/local_storage_service.dart';

abstract class AiChatRepository {
  List<AiChatSession> listSessions(String accountId, {DateTime? now});

  void saveSession(AiChatSession session, {DateTime? now});
}

class PersistedAiChatRepository implements AiChatRepository {
  PersistedAiChatRepository(this._storage);

  static const String storageKey = 'trainflow.ai_chat.v1';
  static const int maxSessions = 20;
  static const int maxMessagesPerSession = 100;
  static const Duration retention = Duration(days: 30);

  final LocalStorageService _storage;

  @override
  List<AiChatSession> listSessions(String accountId, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final List<AiChatSession> sessions = _readAccount(accountId)
        .where(
          (AiChatSession item) =>
              !item.updatedAt.isBefore(reference.subtract(retention)),
        )
        .map(_trimMessages)
        .toList()
      ..sort(
        (AiChatSession left, AiChatSession right) =>
            right.updatedAt.compareTo(left.updatedAt),
      );
    final List<AiChatSession> retained =
        sessions.take(maxSessions).toList(growable: false);
    _writeAccount(accountId, retained);
    return retained;
  }

  @override
  void saveSession(AiChatSession session, {DateTime? now}) {
    final List<AiChatSession> sessions =
        listSessions(session.accountId, now: now).toList();
    sessions.removeWhere((AiChatSession item) => item.id == session.id);
    sessions.add(_trimMessages(session));
    sessions.sort(
      (AiChatSession left, AiChatSession right) =>
          right.updatedAt.compareTo(left.updatedAt),
    );
    _writeAccount(
      session.accountId,
      sessions.take(maxSessions).toList(growable: false),
    );
  }

  AiChatSession _trimMessages(AiChatSession session) => session.copyWith(
        messages: session.messages.length <= maxMessagesPerSession
            ? List<AiChatMessage>.from(session.messages)
            : session.messages
                .sublist(session.messages.length - maxMessagesPerSession),
      );

  List<AiChatSession> _readAccount(String accountId) {
    final Map<String, dynamic>? root = _storage.readJson(storageKey);
    final Object? raw = (root?['accounts'] as Map?)?[accountId];
    if (raw is! List) return const <AiChatSession>[];
    return raw
        .whereType<Map>()
        .map(
          (Map<dynamic, dynamic> item) =>
              AiChatSession.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  void _writeAccount(String accountId, List<AiChatSession> sessions) {
    final Map<String, dynamic> root =
        _storage.readJson(storageKey) ?? <String, dynamic>{};
    final Map<String, dynamic> accounts =
        Map<String, dynamic>.from(root['accounts'] as Map? ?? const {});
    accounts[accountId] = sessions
        .map((AiChatSession item) => item.toJson())
        .toList(growable: false);
    _storage.saveJson(storageKey, <String, dynamic>{
      'schemaVersion': 1,
      'accounts': accounts,
    });
  }
}
