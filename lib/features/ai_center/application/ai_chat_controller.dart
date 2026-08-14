import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/ai_chat.dart';
import '../../../data/repositories/ai_chat_repository.dart';
import '../../../services/local_storage_service.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/authenticated_api_client.dart';
import '../data/ai_api.dart';
import 'chat_privacy_router.dart';

final aiChatRepositoryProvider = Provider<AiChatRepository>(
  (Ref ref) => PersistedAiChatRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

final aiChatControllerProvider =
    NotifierProvider<AiChatController, AiChatState>(AiChatController.new);

class AiChatState {
  const AiChatState({
    required this.session,
    required this.sessions,
    required this.isSending,
    required this.statusMessage,
    required this.suggestedActions,
  });

  final AiChatSession session;
  final List<AiChatSession> sessions;
  final bool isSending;
  final String statusMessage;
  final List<String> suggestedActions;

  AiChatState copyWith({
    AiChatSession? session,
    List<AiChatSession>? sessions,
    bool? isSending,
    String? statusMessage,
    List<String>? suggestedActions,
  }) =>
      AiChatState(
        session: session ?? this.session,
        sessions: sessions ?? this.sessions,
        isSending: isSending ?? this.isSending,
        statusMessage: statusMessage ?? this.statusMessage,
        suggestedActions: suggestedActions ?? this.suggestedActions,
      );
}

class AiChatController extends Notifier<AiChatState> {
  static const ChatPrivacyRouter _privacyRouter = ChatPrivacyRouter();
  final Random _random = Random.secure();
  late AiChatRepository _repository;
  late String _accountId;

  @override
  AiChatState build() {
    _repository = ref.watch(aiChatRepositoryProvider);
    _accountId = ref.watch(authControllerProvider).value?.user?.userId ??
        'local-preview-user';
    final List<AiChatSession> sessions = _repository.listSessions(_accountId);
    final AiChatSession session =
        sessions.isEmpty ? _newSession(_accountId) : sessions.first;
    return AiChatState(
      session: session,
      sessions: sessions,
      isSending: false,
      statusMessage: '训练问题可发给云端；身体与健康内容只在本机处理。',
      suggestedActions: const <String>[],
    );
  }

  void startNewSession() {
    if (state.isSending) return;
    final AiChatSession session = _newSession(_accountId);
    state = state.copyWith(
      session: session,
      sessions: <AiChatSession>[session, ...state.sessions],
      statusMessage: '已开始新的本地对话。',
      suggestedActions: const <String>[],
    );
  }

  void selectSession(String sessionId) {
    if (state.isSending) return;
    for (final AiChatSession session in state.sessions) {
      if (session.id != sessionId) continue;
      state = state.copyWith(
        session: session,
        statusMessage: '已打开本机对话记录。',
        suggestedActions: const <String>[],
      );
      return;
    }
  }

  Future<void> send({
    required String text,
    required AiLocalStatusSnapshot localStatus,
    required AiChatContext context,
  }) async {
    final String content = text.trim();
    if (content.isEmpty || state.isSending) return;

    final DateTime now = DateTime.now();
    final ChatRouteDecision decision = _privacyRouter.route(
      content,
      localStatus,
    );
    final AiChatMessage userMessage = AiChatMessage(
      id: _id('user'),
      role: AiChatMessageRole.user,
      content: content,
      createdAt: now,
      status: decision.sendToCloud
          ? AiChatMessageStatus.sending
          : AiChatMessageStatus.sent,
      cloudEligible: decision.sendToCloud,
    );
    _replaceMessages(
      <AiChatMessage>[...state.session.messages, userMessage],
      now: now,
      isSending: decision.sendToCloud,
      statusMessage: decision.sendToCloud ? '正在生成训练回复…' : '身体状态已在本机读取，未发送给云端。',
    );

    if (!decision.sendToCloud) {
      final AiChatMessage localReply = AiChatMessage(
        id: _id('local'),
        role: AiChatMessageRole.local,
        content: decision.localReply!,
        createdAt: DateTime.now(),
        status: AiChatMessageStatus.sent,
        cloudEligible: false,
      );
      _replaceMessages(
        <AiChatMessage>[...state.session.messages, localReply],
        now: DateTime.now(),
        isSending: false,
        statusMessage: '身体状态只在本机处理。',
      );
      return;
    }

    final List<AiChatMessage> sentMessages = state.session.messages
        .map(
          (AiChatMessage item) => item.id == userMessage.id
              ? item.copyWith(status: AiChatMessageStatus.sent)
              : item,
        )
        .toList(growable: false);
    try {
      final AiChatResponse response = await ref.read(aiApiProvider).chat(
            requestId: _id('request'),
            messages: _privacyRouter.cloudHistory(sentMessages),
            context: context,
          );
      final AiChatMessage assistant = AiChatMessage(
        id: _id('assistant'),
        role: AiChatMessageRole.assistant,
        content: response.reply,
        createdAt: DateTime.now(),
        status: AiChatMessageStatus.sent,
        cloudEligible: true,
      );
      _replaceMessages(
        <AiChatMessage>[...sentMessages, assistant],
        now: DateTime.now(),
        isSending: false,
        statusMessage: response.warnings.isEmpty
            ? '回复已生成。计划调整仍需你确认。'
            : response.warnings.join('；'),
        suggestedActions: response.suggestedActions,
      );
    } on ApiException catch (error) {
      final List<AiChatMessage> failed = sentMessages
          .map(
            (AiChatMessage item) => item.id == userMessage.id
                ? item.copyWith(status: AiChatMessageStatus.failed)
                : item,
          )
          .toList(growable: false);
      _replaceMessages(
        failed,
        now: DateTime.now(),
        isSending: false,
        statusMessage: '发送失败：${error.message}',
      );
    }
  }

  void _replaceMessages(
    List<AiChatMessage> messages, {
    required DateTime now,
    required bool isSending,
    required String statusMessage,
    List<String>? suggestedActions,
  }) {
    final AiChatSession session = state.session.copyWith(
      updatedAt: now,
      messages: messages,
    );
    _repository.saveSession(session, now: now);
    final List<AiChatSession> sessions =
        _repository.listSessions(_accountId, now: now);
    state = state.copyWith(
      session: session,
      sessions: sessions,
      isSending: isSending,
      statusMessage: statusMessage,
      suggestedActions: suggestedActions ?? const <String>[],
    );
  }

  AiChatSession _newSession(String accountId) {
    final DateTime now = DateTime.now();
    return AiChatSession(
      id: _id('session'),
      accountId: accountId,
      createdAt: now,
      updatedAt: now,
      messages: const <AiChatMessage>[],
    );
  }

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
}
