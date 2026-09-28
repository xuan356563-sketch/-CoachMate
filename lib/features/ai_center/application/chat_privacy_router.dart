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
  const ChatRouteDecision.cloud(this.cloudIntent)
      : sendToCloud = true,
        localReply = null;

  const ChatRouteDecision.local(this.localReply)
      : sendToCloud = false,
        cloudIntent = null;

  final bool sendToCloud;
  final String? localReply;
  final AiChatCloudIntent? cloudIntent;
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
    '膝',
    '腰',
    '肩',
    '踝',
    '胸闷',
    '眩晕',
    '头晕',
    '不舒服',
  ];

  static const Map<String, AiChatCloudIntent> _cloudCommands =
      <String, AiChatCloudIntent>{
    '解释今天训练重点': AiChatCloudIntent.explainTodayTraining,
    '今天训练重点': AiChatCloudIntent.explainTodayTraining,
    '解释当前计划安排': AiChatCloudIntent.explainPlanStructure,
    '当前计划安排': AiChatCloudIntent.explainPlanStructure,
    '解释训练动作重点': AiChatCloudIntent.explainTrainingFocus,
    '训练动作重点': AiChatCloudIntent.explainTrainingFocus,
  };

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
    final String command = normalized.replaceAll(
      RegExp(r'[\s，。！？!?]+'),
      '',
    );
    final AiChatCloudIntent? cloudIntent = _cloudCommands[command];
    if (cloudIntent != null) {
      return ChatRouteDecision.cloud(cloudIntent);
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
    return const ChatRouteDecision.local(
      '这段自由文本已保留在本机，没有发送给云端。'
      '如需云端解释，请选择“解释今天训练重点”“解释当前计划安排”或“解释训练动作重点”。',
    );
  }
}
