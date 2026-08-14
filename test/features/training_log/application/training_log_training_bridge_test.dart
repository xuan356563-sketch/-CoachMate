import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/pet/application/daily_activity_sync_controller.dart';
import 'package:trainflow_ai/features/pet/application/pet_controller.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/features/training_log/application/training_log_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('手动日志与跟练日志写入独立控制器并同步旧训练状态', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final TrainingMvpController training =
        container.read(trainingMvpProvider.notifier);

    training.saveTodayLog(completed: true, rpe: 6, userNote: '桥接测试');
    expect(container.read(trainingLogControllerProvider), hasLength(1));
    expect(container.read(trainingMvpProvider).logs, hasLength(1));

    training.startWorkoutPlayer(
      workoutDayId: container.read(trainingMvpProvider).todayWorkout.id,
    );
    training.completeWorkoutPlayerStep();
    await Future<void>.delayed(Duration.zero);

    final TrainingMvpState state = container.read(trainingMvpProvider);
    expect(container.read(trainingLogControllerProvider), hasLength(2));
    expect(state.logs, hasLength(2));
    expect(state.logs.first.userNote, startsWith('[跟练执行]'));
    expect(state.coachAdvices, isNotEmpty);
    expect(state.achievementRecords, isNotEmpty);
  });

  test('保存有效训练反馈后非阻断刷新宠物，结算失败仍保留训练记录', () async {
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
    final TrainingMvpController training =
        container.read(trainingMvpProvider.notifier);

    training.saveWorkoutSessionReview(
      actualDurationMinutes: 30,
      completionPercentage: 50,
      rpe: 6,
      averageHeartRate: 140,
      averagePaceSecondsPerKm: 360,
      plannedSetCount: 4,
      completedSetCount: 2,
      userNote: '宠物刷新失败仍应保留',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(gateway.settlementAttempts, 1);
    expect(container.read(trainingLogControllerProvider), hasLength(1));
    expect(container.read(trainingMvpProvider).logs, hasLength(1));
    expect(
      container.read(trainingMvpProvider).logs.single.userNote,
      '宠物刷新失败仍应保留',
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
