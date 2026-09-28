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

  test('三个固定训练问题映射为结构化云端意图', () {
    expect(
      router.route('解释今天训练重点', snapshot).cloudIntent,
      AiChatCloudIntent.explainTodayTraining,
    );
    expect(
      router.route('解释当前计划安排', snapshot).cloudIntent,
      AiChatCloudIntent.explainPlanStructure,
    );
    expect(
      router.route('解释训练动作重点', snapshot).cloudIntent,
      AiChatCloudIntent.explainTrainingFocus,
    );
  });

  test('任意自由文本只保留在本机', () {
    final ChatRouteDecision decision = router.route('怎样提高长距离配速', snapshot);

    expect(decision.sendToCloud, isFalse);
    expect(decision.localReply, contains('没有发送给云端'));
  });

  test('遗漏关键词的常见健康表达也不进入云端', () {
    for (final String text in <String>['膝盖不舒服', '胸闷眩晕', '血糖偏高']) {
      final ChatRouteDecision decision = router.route(text, snapshot);
      expect(decision.sendToCloud, isFalse, reason: text);
      expect(decision.cloudIntent, isNull, reason: text);
    }
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
}
