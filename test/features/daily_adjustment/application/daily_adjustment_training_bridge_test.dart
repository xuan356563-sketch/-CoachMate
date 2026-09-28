import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/models/daily_adjustment.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/features/daily_adjustment/daily_adjustment_page.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/daily_adjustment/application/daily_adjustment_controller.dart';
import 'package:trainflow_ai/features/pet/application/daily_activity_sync_controller.dart';
import 'package:trainflow_ai/features/pet/application/pet_controller.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('每日调整控制器同步旧训练状态并保留跟练会话', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    final TrainingMvpController trainingController =
        container.read(trainingMvpProvider.notifier);
    trainingController.startWorkoutPlayer(workoutDayId: 'workout-week1-day2');
    await trainingController.completeWorkoutPlayerStep();
    trainingController.setKnowledgeSearchQuery('跑步');
    final TrainingMvpState sessionState = container.read(trainingMvpProvider);
    final DailyAdjustmentController dailyController =
        container.read(dailyAdjustmentControllerProvider.notifier);

    await dailyController.setDailyAvailableMinutes(20);
    await dailyController.setDailyWorkStress(WorkStressLevel.high);
    await dailyController.setDailyTrainingEnvironment(TrainingEnvironment.home);
    await dailyController.setDailyWeather(WeatherCondition.rain);
    await Future<void>.delayed(Duration.zero);

    TrainingMvpState state = container.read(trainingMvpProvider);
    expect(state.dailyAvailableMinutesOverride, 20);
    expect(state.dailyWorkStress, WorkStressLevel.high);
    expect(state.dailyTrainingEnvironment, TrainingEnvironment.home);
    expect(state.dailyWeather, WeatherCondition.rain);
    expect(state.dailyAdjustmentDecision.availableMinutes, 20);
    expect(state.dailyAdjustmentDecision.workStress, WorkStressLevel.high);
    expect(state.dailyAdjustmentDecision.environment, TrainingEnvironment.home);
    expect(state.dailyAdjustmentDecision.weather, WeatherCondition.rain);

    await dailyController
        .applyDailyAdjustmentDecision(state.dailyAdjustmentDecision);
    await Future<void>.delayed(Duration.zero);

    state = container.read(trainingMvpProvider);
    expect(
      state.dailyAdjustmentStatusMessage,
      container.read(dailyAdjustmentControllerProvider).statusMessage,
    );
    expect(state.dailyAdjustmentDecision.availableMinutes, 20);
    expect(state.dailyAdjustmentDecision.workStress, WorkStressLevel.high);
    expect(
        state.activeWorkoutPlayerDayId, sessionState.activeWorkoutPlayerDayId);
    expect(state.workoutPlayerStepIndex, sessionState.workoutPlayerStepIndex);
    expect(state.workoutPlayerEvents, sessionState.workoutPlayerEvents);
    expect(state.logs, sessionState.logs);
    expect(state.knowledgeSearchQuery, sessionState.knowledgeSearchQuery);
  });

  testWidgets('页面确认每日调整后非阻断刷新宠物，结算失败不回滚原业务', (WidgetTester tester) async {
    final _FailingPetGateway gateway = _FailingPetGateway();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
        petDatabaseGatewayProvider.overrideWithValue(gateway),
        healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(petControllerProvider.future);
    final String originalStatus =
        container.read(trainingMvpProvider).dailyAdjustmentStatusMessage;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DailyAdjustmentPage()),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('记录今日建议'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录今日建议'));
    await tester.pump();
    await tester.pump();

    expect(gateway.settlementAttempts, 1);
    expect(
      container.read(trainingMvpProvider).dailyAdjustmentStatusMessage,
      isNot(originalStatus),
    );
    expect(
      container.read(dailyAdjustmentControllerProvider).statusMessage,
      contains('建议已记录，计划未改变'),
    );
    final PetState petState =
        container.read(petControllerProvider).requireValue;
    expect(petState.status, PetStateStatus.ready);
    expect(petState.statusMessage, contains('失败'));
  });
}

class _FailingPetGateway implements PetDatabaseGateway {
  int settlementAttempts = 0;

  @override
  Future<Map<String, Object?>?> readPetProfileRow(
    String athleteProfileId,
  ) async {
    return <String, Object?>{
      'athlete_profile_id': athleteProfileId,
      'active_pet_id': 'pet-a',
      'first_egg_species_id': PetSpecies.balanceRaccoon.id,
      'selected_shell_id': null,
      'created_at': '2026-08-01T00:00:00.000Z',
      'updated_at': '2026-08-01T00:00:00.000Z',
    };
  }

  @override
  Future<List<Map<String, Object?>>> listPetCollectionRows(
    String athleteProfileId,
  ) async {
    return <Map<String, Object?>>[
      <String, Object?>{
        'pet_id': 'pet-a',
        'athlete_profile_id': athleteProfileId,
        'species_id': PetSpecies.balanceRaccoon.id,
        'nickname': '衡衡狸',
        'unlocked_at': '2026-08-01T00:00:00.000Z',
        'born_at': '2026-08-01T00:00:00.000Z',
        'selected_accessory_id': null,
        'selected_badge_id': null,
        'created_at': '2026-08-01T00:00:00.000Z',
        'updated_at': '2026-08-01T00:00:00.000Z',
      },
    ];
  }

  @override
  Future<List<Map<String, Object?>>> listDailyActivitySummaryRows(
    String athleteProfileId,
  ) async =>
      const <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>?> readDailyActivitySummaryRow({
    required String athleteProfileId,
    required String localDate,
  }) async =>
      null;

  @override
  Future<List<Map<String, Object?>>> listPetDailyEnergyRows({
    required String athleteProfileId,
    String? recipientPetId,
  }) async =>
      const <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>?> readPetDailyEnergyRow({
    required String athleteProfileId,
    required String localDate,
  }) async =>
      null;

  @override
  Future<PetSettlementResult> settleDay(PetSettlementWrite write) async {
    settlementAttempts += 1;
    throw StateError('模拟宠物结算失败');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
