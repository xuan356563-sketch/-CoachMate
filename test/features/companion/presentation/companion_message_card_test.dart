import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/companion/domain/companion_models.dart';
import 'package:trainflow_ai/features/companion/presentation/companion_feed_page.dart';

void main() {
  testWidgets('消息卡显示可追溯事实、推算标识和中性今天算了入口', (WidgetTester tester) async {
    CompanionAction? selected;
    final CompanionMessage message = CompanionMessage(
      messageId: 'message-1',
      athleteProfileId: 'athlete-1',
      localDate: '2026-08-11',
      intent: CompanionIntent.missedWorkout,
      copyVariantId: 'mw-03',
      relationshipState: RelationshipState.slipping,
      deliveryKind: CompanionDeliveryKind.proactive,
      privacyLevel: PrivacyLevel.l0,
      body: '还有个 5 分钟版，做不做都行。',
      facts: const <CompanionFact>[
        CompanionFact(
          label: '今日计划',
          value: '30 分钟',
          source: CompanionFactSource.derived,
        ),
      ],
      actions: const <CompanionAction>[
        CompanionAction(
          actionId: 'dismiss-today',
          label: '今天算了',
          kind: CompanionActionKind.dismiss,
          effect: CompanionActionEffect.recordDismissal,
        ),
      ],
      createdAt: DateTime(2026, 8, 11),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CompanionMessageCard(
          message: message,
          onAction: (CompanionAction action) => selected = action,
        ),
      ),
    ));

    expect(find.text('还有个 5 分钟版，做不做都行。'), findsOneWidget);
    expect(find.textContaining('今日计划 30 分钟 · 推算'), findsOneWidget);
    expect(find.text('今天算了'), findsOneWidget);
    await tester.tap(find.text('今天算了'));
    expect(selected?.actionId, 'dismiss-today');
  });
}
