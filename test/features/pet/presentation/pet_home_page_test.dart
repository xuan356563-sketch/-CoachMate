import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/daily_activity_summary.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/features/pet/application/pet_controller.dart';
import 'package:trainflow_ai/features/pet/presentation/pet_home_page.dart';
import 'package:trainflow_ai/features/pet/presentation/illustrated_pet_renderer.dart';

void main() {
  testWidgets('伙伴首页展示阶段、来源、真实结算和完整插画语义', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            petControllerProvider.overrideWith(_ReadyPetController.new),
          ],
          child: const MaterialApp(home: PetHomePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('pet-showcase-header')),
        findsOneWidget,
      );
      expect(find.text('我的伙伴'), findsOneWidget);
      expect(find.text('萌芽体'), findsWidgets);
      expect(find.text('今日能量 138'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('主食 +100'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('主食 +100'), findsOneWidget);
      expect(find.text('步数 +20'), findsOneWidget);
      expect(find.text('站立 +8'), findsOneWidget);
      expect(find.text('运动 +10'), findsOneWidget);
      expect(find.text('消耗 +0'), findsOneWidget);
      expect(
        tester
            .widget<IllustratedPetRenderer>(
              find.byType(IllustratedPetRenderer),
            )
            .semanticLabel,
        '袋小满，萌芽体，心情开心，今日获得 138 能量，距离下一阶段 712',
      );
    } finally {
      semantics.dispose();
    }
  });
}

class _ReadyPetController extends PetController {
  @override
  Future<PetState> build() async => _state();
}

PetState _state() {
  final DateTime now = DateTime.utc(2026, 8, 2);
  final DailyActivitySummary summary = DailyActivitySummary(
    athleteProfileId: 'athlete-a',
    localDate: '2026-08-02',
    timeZoneName: 'Asia/Shanghai',
    timeZoneOffsetMinutes: 480,
    steps: 6000,
    stepGoal: 6000,
    standHours: 6,
    standGoalHours: 10,
    exerciseMinutes: 20,
    exerciseGoalMinutes: 30,
    activeEnergyKcal: null,
    activeEnergyGoalKcal: 300,
    fieldSources: const <DailyActivityField, ActivityFieldSource>{
      DailyActivityField.steps: ActivityFieldSource.healthKit,
      DailyActivityField.activeEnergyKcal: ActivityFieldSource.unavailable,
    },
    syncedAt: now,
  );
  final PetDailyEnergy energy = PetDailyEnergy(
    athleteProfileId: 'athlete-a',
    localDate: '2026-08-02',
    recipientPetId: 'pet-a',
    stepsEnergy: 20,
    standEnergy: 8,
    exerciseEnergy: 10,
    activeEnergy: 0,
    trainingEnergy: 100,
    recoveryEnergy: 0,
    calculatedTotal: 138,
    awardedTotal: 138,
    sourceSnapshot: const <String, Object?>{},
    modelVersion: 1,
    settledAt: now,
    updatedAt: now,
  );
  return PetState(
    status: PetStateStatus.ready,
    profile: PetProfile(
      athleteProfileId: 'athlete-a',
      activePetId: 'pet-a',
      firstEggSpecies: PetSpecies.balanceRaccoon,
      selectedShellId: null,
      createdAt: now,
      updatedAt: now,
    ),
    activeCompanion: PetCompanion(
      id: 'pet-a',
      athleteProfileId: 'athlete-a',
      species: PetSpecies.balanceRaccoon,
      nickname: '衡衡狸',
      unlockedAt: now,
      bornAt: now,
      selectedAccessoryId: null,
      selectedBadgeId: null,
      createdAt: now,
      updatedAt: now,
      totalEnergy: 188,
      stage: PetStage.sprout,
      partnerStars: 0,
      mood: PetMood.happy,
    ),
    todayActivitySummary: summary,
    todayEnergy: energy,
    energyHistory: <PetDailyEnergy>[energy],
    pendingSettlement: const PetPendingSettlement(
      localDate: '2026-08-02',
      result: PetSettlementResult(
        recipientPetId: 'pet-a',
        calculatedTotal: 138,
        awardedTotal: 138,
        awardedDelta: 138,
        didLockRecipient: true,
      ),
    ),
    statusMessage: '伙伴状态已就绪。',
  );
}
