import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/features/pet/application/pet_controller.dart';
import 'package:trainflow_ai/features/pet/presentation/pet_home_page.dart';

void main() {
  testWidgets('M1 首蛋页只开放袋小满并在选择后进入伙伴首页', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          petControllerProvider.overrideWith(_FirstEggPetController.new),
        ],
        child: const MaterialApp(home: PetHomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('选择第一颗伙伴蛋'), findsOneWidget);
    expect(find.text('袋小满'), findsWidgets);
    expect(find.textContaining('其余五种伙伴将在下一里程碑开放'), findsOneWidget);
    expect(find.text('风步狐'), findsNothing);
    expect(
      find.byKey(
        const ValueKey<String>('mate-companion-pattern_egg-waiting'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('mate-companion-pattern_egg-calm'),
      ),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(FilledButton, '选择袋小满'));
    await tester.pumpAndSettle();

    expect(find.text('我的伙伴'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('袋小满')), findsWidgets);
  });

  testWidgets('存储不可用时只显示说明且不提供选蛋写操作', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          petControllerProvider.overrideWith(
            _UnavailablePetController.new,
          ),
        ],
        child: const MaterialApp(home: PetHomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('本地存储暂不可用'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '选择袋小满'), findsNothing);
  });
}

class _FirstEggPetController extends PetController {
  @override
  Future<PetState> build() async => PetState.needsFirstEgg();

  @override
  Future<void> chooseFirstEgg(PetSpecies species) async {
    state = AsyncData<PetState>(_readyPetState());
  }
}

class _UnavailablePetController extends PetController {
  @override
  Future<PetState> build() async => PetState.storageUnavailable();
}

PetState _readyPetState() {
  final DateTime now = DateTime.utc(2026, 8, 2);
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
      totalEnergy: 0,
      stage: PetStage.patternEgg,
      partnerStars: 0,
      mood: PetMood.calm,
    ),
    todayActivitySummary: null,
    todayEnergy: null,
    energyHistory: const <PetDailyEnergy>[],
    pendingSettlement: null,
    statusMessage: '伙伴状态已就绪。',
  );
}
