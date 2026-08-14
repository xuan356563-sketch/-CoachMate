import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/ai_chat.dart';
import 'package:trainflow_ai/features/ai_center/application/chat_privacy_router.dart';

void main() {
  const ChatPrivacyRouter router = ChatPrivacyRouter();
  final AiLocalStatusSnapshot snapshot = AiLocalStatusSnapshot(
    todayWorkoutTitle: '轻松跑',
    todayWorkoutSummary: '30 分钟，低强度',
    activePlanTitle: '四周基础周期',
    bodyFacts: const <String>['睡眠 7.2 小时', '疲劳 6/10', '疼痛 2/10'],
    bodyUpdatedAt: DateTime(2026, 7, 27, 8),
  );

  test('身体状态问题只在本地回答', () {
    final ChatRouteDecision decision =
        router.route('结合我的 HRV 和疼痛看看今天怎么练', snapshot);

    expect(decision.sendToCloud, isFalse);
    expect(decision.localReply, contains('只在本机'));
    expect(decision.localReply, contains('疼痛 2/10'));
  });

  test('普通训练问题可以发送，但上下文不包含本地健康字段', () {
    final ChatRouteDecision decision = router.route('帮我解释今天训练的重点', snapshot);

    expect(decision.sendToCloud, isTrue);
    expect(decision.localReply, isNull);
  });

  test('今日训练和当前计划查询直接在本地回答', () {
    final ChatRouteDecision today = router.route('今天练什么', snapshot);
    final ChatRouteDecision plan = router.route('我的当前计划是什么', snapshot);

    expect(today.sendToCloud, isFalse);
    expect(today.localReply, contains('轻松跑'));
    expect(today.localReply, contains('30 分钟'));
    expect(plan.sendToCloud, isFalse);
    expect(plan.localReply, contains('四周基础周期'));
  });

  test('云端历史只保留最近四条且正文不超过 1200 字符', () {
    final List<AiChatMessage> messages = List<AiChatMessage>.generate(
      12,
      (int index) => AiChatMessage(
        id: '$index',
        role: index == 5
            ? AiChatMessageRole.local
            : index.isEven
                ? AiChatMessageRole.user
                : AiChatMessageRole.assistant,
        content: '消息 $index ${'训练' * 120}',
        createdAt: DateTime(2026, 7, 27, 8, index),
        status: AiChatMessageStatus.sent,
        cloudEligible: index != 5,
      ),
    );

    final List<AiChatMessage> cloud = router.cloudHistory(messages);

    expect(cloud.length, lessThanOrEqualTo(4));
    expect(
      cloud.fold<int>(0, (int total, AiChatMessage item) => total + item.content.length),
      lessThanOrEqualTo(1200),
    );
    expect(
        cloud.any((AiChatMessage item) => item.role == AiChatMessageRole.local),
        isFalse);
    expect(cloud.last.content, startsWith('消息 11'));
  });
}
