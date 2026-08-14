import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/core/theme/tdesign_theme.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/pet/application/pet_controller.dart';
import 'package:trainflow_ai/features/pet/presentation/pixel_pet_renderer.dart';
import 'package:trainflow_ai/features/pet/presentation/widgets/pet_training_receipt.dart';
import 'package:trainflow_ai/features/workout_player/workout_player_page.dart';

void main() {
  testWidgets('有效训练结算卡只展示真实正差额并由用户确认消费', (tester) async {
    bool acknowledged = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PetTrainingReceiptCard(
            settlement: const PetPendingSettlement(
              localDate: '2026-08-02',
              result: PetSettlementResult(
                recipientPetId: 'pet-a',
                calculatedTotal: 140,
                awardedTotal: 140,
                awardedDelta: 40,
                didLockRecipient: false,
              ),
            ),
            hasValidTraining: true,
            onAcknowledged: () => acknowledged = true,
          ),
        ),
      ),
    );

    expect(find.text('伙伴主食 +40'), findsOneWidget);
    expect(find.textContaining('+100'), findsNothing);
    expect(petReceiptAnimationDuration,
        lessThanOrEqualTo(const Duration(seconds: 2)));

    await tester.tap(find.widgetWithText(FilledButton, '收下奖励'));
    expect(acknowledged, isTrue);
  });

  testWidgets('49% 或没有正差额时不展示训练结算卡', (tester) async {
    const PetPendingSettlement settlement = PetPendingSettlement(
      localDate: '2026-08-02',
      result: PetSettlementResult(
        recipientPetId: 'pet-a',
        calculatedTotal: 100,
        awardedTotal: 100,
        awardedDelta: 100,
        didLockRecipient: true,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PetTrainingReceiptCard(
            settlement: settlement,
            hasValidTraining: false,
            onAcknowledged: _noop,
          ),
        ),
      ),
    );
    expect(find.textContaining('伙伴主食'), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PetTrainingReceiptCard(
            settlement: null,
            hasValidTraining: true,
            onAcknowledged: _noop,
          ),
        ),
      ),
    );
    expect(find.textContaining('伙伴主食'), findsNothing);
  });

  testWidgets('训练执行页没有宠物渲染器、结算卡或伙伴能量文案', (tester) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(trainingMvpProvider.notifier)
        .startWorkoutPlayer(workoutDayId: 'workout-week1-day2');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: const WorkoutPlayerPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PixelPetRenderer), findsNothing);
    expect(find.byType(PetTrainingReceiptCard), findsNothing);
    expect(find.textContaining('伙伴能量'), findsNothing);
  });
}

void _noop() {}
