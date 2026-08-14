import '../../../data/models/ai_chat.dart';

class AiLocalStatusSnapshot {
  const AiLocalStatusSnapshot({
    required this.todayWorkoutTitle,
    required this.todayWorkoutSummary,
    required this.activePlanTitle,
    required this.bodyFacts,
    required this.bodyUpdatedAt,
  });

  final String todayWorkoutTitle;
  final String todayWorkoutSummary;
  final String activePlanTitle;
  final List<String> bodyFacts;
  final DateTime? bodyUpdatedAt;
}

class ChatRouteDecision {
  const ChatRouteDecision.cloud()
      : sendToCloud = true,
        localReply = null;

  const ChatRouteDecision.local(this.localReply) : sendToCloud = false;

  final bool sendToCloud;
  final String? localReply;
}

class ChatPrivacyRouter {
  const ChatPrivacyRouter();

  static const List<String> _localOnlyTerms = <String>[
    '身体',
    '健康',
    '睡眠',
    '心率',
    '静息',
    'hrv',
    '体重',
    '体脂',
    '疲劳',
    '酸痛',
    '疼痛',
    '伤病',
    '受伤',
    '恢复',
    '准备度',
    'healthkit',
    '血压',
    '血糖',
  ];

  ChatRouteDecision route(String text, AiLocalStatusSnapshot snapshot) {
    final String normalized = text.trim().toLowerCase();
    if (_localOnlyTerms.any(normalized.contains)) {
      final String facts = snapshot.bodyFacts.isEmpty
          ? '本机暂时没有可用的身体记录。'
          : snapshot.bodyFacts.join('，');
      return ChatRouteDecision.local(
        '本机记录：$facts。这些数据只在本机处理，不会发送给云端 AI。'
        '如果疼痛明显、持续加重或影响日常活动，请停止相关训练并咨询专业人士。',
      );
    }
    if (normalized.contains('今天练什么') ||
        normalized.contains('今日训练') ||
        normalized.contains('今天的训练')) {
      return ChatRouteDecision.local(
        '今天安排：${snapshot.todayWorkoutTitle}。${snapshot.todayWorkoutSummary}。',
      );
    }
    if (normalized.contains('当前计划') ||
        normalized.contains('我的计划') ||
        normalized.contains('现在的计划')) {
      return ChatRouteDecision.local(
        snapshot.activePlanTitle.trim().isEmpty
            ? '本机暂时没有已激活的训练计划。'
            : '当前激活计划：${snapshot.activePlanTitle}。',
      );
    }
    if (normalized.contains('acwr') ||
        normalized.contains('为什么调整') ||
        normalized.contains('为什么降级')) {
      return const ChatRouteDecision.local(
        '训练调整由本机规则根据近期负荷与已确认状态生成，'
        'AI 不会静默修改计划；如有新方案，会先展示差异并由你确认。',
      );
    }
    return const ChatRouteDecision.cloud();
  }

  List<AiChatMessage> cloudHistory(List<AiChatMessage> messages) {
    final List<AiChatMessage> eligible = messages
        .where(
          (AiChatMessage item) =>
              item.cloudEligible &&
              item.status == AiChatMessageStatus.sent &&
              (item.role == AiChatMessageRole.user ||
                  item.role == AiChatMessageRole.assistant),
        )
        .toList(growable: false);
    final List<AiChatMessage> compacted = eligible.length <= 4
        ? List<AiChatMessage>.from(eligible)
        : eligible.sublist(eligible.length - 4);
    while (compacted.length > 1 &&
        compacted.fold<int>(
              0,
              (int total, AiChatMessage item) => total + item.content.length,
            ) >
            1200) {
      compacted.removeAt(0);
    }
    return List<AiChatMessage>.unmodifiable(compacted);
  }
}
