import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/models/daily_activity_summary.dart';
import 'package:trainflow_ai/data/models/daily_adjustment.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/repositories/daily_activity_summary_repository.dart';
import 'package:trainflow_ai/data/repositories/daily_context_repository.dart';
import 'package:trainflow_ai/data/repositories/training_log_repository.dart';
import 'package:trainflow_ai/features/daily_adjustment/application/daily_adjustment_controller.dart';
import 'package:trainflow_ai/features/pet/application/daily_activity_sync_controller.dart';
import 'package:trainflow_ai/features/pet/application/pet_controller.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/features/training_log/application/training_log_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';

void main() {
  group('PetController 可用状态与首蛋', () {
    test('无宠物网关时区分存储不可用和只读恢复', () async {
      final ProviderContainer unavailable = ProviderContainer(
        overrides: [
          petDatabaseGatewayProvider.overrideWithValue(null),
          localStorageServiceProvider.overrideWithValue(
            InMemoryLocalStorageService(),
          ),
        ],
      );
      addTearDown(unavailable.dispose);

      expect(
        (await unavailable.read(petControllerProvider.future)).status,
        PetStateStatus.storageUnavailable,
      );

      final ProviderContainer readOnly = ProviderContainer(
        overrides: [
          petDatabaseGatewayProvider.overrideWithValue(null),
          localStorageServiceProvider.overrideWithValue(
            const ReadOnlyRecoveryLocalStorageService(),
          ),
        ],
      );
      addTearDown(readOnly.dispose);

      expect(
        (await readOnly.read(petControllerProvider.future)).status,
        PetStateStatus.readOnly,
      );
    });

    test('未选蛋时进入首蛋态，选择袋小满后进入可用态', () async {
      final _MemoryPetGateway gateway = _MemoryPetGateway();
      final _MutablePetTime time = _MutablePetTime(
        _time(localDate: '2026-08-01'),
      );
      final ProviderContainer container = _container(gateway, time: time);
      addTearDown(container.dispose);

      expect(
        (await container.read(petControllerProvider.future)).status,
        PetStateStatus.needsFirstEgg,
      );

      await container
          .read(petControllerProvider.notifier)
          .chooseFirstEgg(PetSpecies.balanceRaccoon);

      final PetState state = container.read(petControllerProvider).requireValue;
      expect(state.status, PetStateStatus.ready);
      expect(state.profile?.firstEggSpecies, PetSpecies.balanceRaccoon);
      expect(state.activeCompanion?.species, PetSpecies.balanceRaccoon);
      expect(state.activeCompanion?.nickname, '袋小满');
    });
  });

  group('PetController 幂等结算', () {
    test('活动摘要变更信号会自动触发当日幂等结算', () async {
      final _MemoryPetGateway gateway = _MemoryPetGateway();
      final _MutablePetTime time = _MutablePetTime(
        _time(localDate: '2026-08-01'),
      );
      final ProviderContainer container = _container(gateway, time: time);
      addTearDown(container.dispose);
      await container.read(petControllerProvider.future);
      await container
          .read(petControllerProvider.notifier)
          .chooseFirstEgg(PetSpecies.balanceRaccoon);
      await _saveSummary(gateway, _summary40(localDate: '2026-08-01'));

      final Completer<PetState> settled = Completer<PetState>();
      final ProviderSubscription<AsyncValue<PetState>> subscription =
          container.listen<AsyncValue<PetState>>(
        petControllerProvider,
        (_, AsyncValue<PetState> next) {
          final PetState? value = next.value;
          if (!settled.isCompleted && value?.todayEnergy?.awardedTotal == 40) {
            settled.complete(value);
          }
        },
      );
      addTearDown(subscription.close);

      container
          .read(dailyActivityEnergyRefreshSignalProvider.notifier)
          .requestRefresh();

      final PetState state = await settled.future.timeout(
        const Duration(seconds: 2),
      );
      expect(state.todayEnergy?.awardedTotal, 40);
      expect(state.pendingSettlement?.awardedDelta, 40);
    });

    test('40 日常加首次有效训练得到 140，重复和额外训练不重复加分', () async {
      final _MemoryPetGateway gateway = _MemoryPetGateway();
      final _MutablePetTime time = _MutablePetTime(
        _time(localDate: '2026-08-01'),
      );
      final InMemoryTrainingLogRepository logs =
          InMemoryTrainingLogRepository();
      final ProviderContainer container = _container(
        gateway,
        time: time,
        trainingLogs: logs,
      );
      addTearDown(container.dispose);
      await container.read(petControllerProvider.future);
      final PetController controller =
          container.read(petControllerProvider.notifier);
      await controller.chooseFirstEgg(PetSpecies.balanceRaccoon);
      await _saveSummary(gateway, _summary40(localDate: '2026-08-01'));
      logs.saveLog(_trainingLog(id: 'first', localDate: '2026-08-01'));

      await controller.refreshToday();

      PetState state = container.read(petControllerProvider).requireValue;
      expect(state.todayEnergy?.calculatedTotal, 140);
      expect(state.todayEnergy?.awardedTotal, 140);
      expect(state.pendingSettlement?.awardedDelta, 140);
      expect(gateway.energyRows, hasLength(1));

      await controller.refreshToday();
      expect(gateway.lastSettlementResult?.awardedDelta, 0);
      expect(
        container
            .read(petControllerProvider)
            .requireValue
            .pendingSettlement
            ?.awardedDelta,
        140,
        reason: '未确认的正差额不能被一次零差额刷新静默清掉',
      );

      controller.acknowledgeSettlement();
      logs.saveLog(_trainingLog(id: 'second', localDate: '2026-08-01'));
      await controller.refreshToday();

      state = container.read(petControllerProvider).requireValue;
      expect(state.todayEnergy?.awardedTotal, 140);
      expect(gateway.lastSettlementResult?.awardedDelta, 0);
      expect(state.pendingSettlement, isNull);
    });

    test('恢复 60 与训练 100 取高，不相加为 160', () async {
      final _MemoryPetGateway gateway = _MemoryPetGateway();
      final _MutablePetTime time = _MutablePetTime(
        _time(localDate: '2026-08-02'),
      );
      final InMemoryTrainingLogRepository logs =
          InMemoryTrainingLogRepository();
      final InMemoryDailyContextRepository daily =
          InMemoryDailyContextRepository();
      daily.saveContext(
        _contextWithFacts(<AppliedDailyDecisionFact>[
          AppliedDailyDecisionFact(
            localDate: '2026-08-02',
            decisionType: TrainingDecisionType.recovery,
            confirmedAt: DateTime.utc(2026, 8, 2, 2),
          ),
        ]),
      );
      final ProviderContainer container = _container(
        gateway,
        time: time,
        trainingLogs: logs,
        dailyContext: daily,
      );
      addTearDown(container.dispose);
      await container.read(petControllerProvider.future);
      final PetController controller =
          container.read(petControllerProvider.notifier);
      await controller.chooseFirstEgg(PetSpecies.balanceRaccoon);

      await controller.refreshToday();
      expect(gateway.energyFor('2026-08-02')?['awarded_total'], 60);
      expect(gateway.energyFor('2026-08-02')?['recovery_energy'], 60);

      logs.saveLog(_trainingLog(id: 'training', localDate: '2026-08-02'));
      await controller.refreshToday();

      expect(gateway.energyFor('2026-08-02')?['calculated_total'], 100);
      expect(gateway.energyFor('2026-08-02')?['awarded_total'], 100);
      expect(gateway.energyFor('2026-08-02')?['training_energy'], 100);
      expect(gateway.energyFor('2026-08-02')?['recovery_energy'], 0);
      expect(gateway.lastSettlementResult?.awardedDelta, 40);
    });

    test('切换伙伴不移动当日接收者，次日才使用新伙伴', () async {
      final _MemoryPetGateway gateway = _MemoryPetGateway();
      final _MutablePetTime time = _MutablePetTime(
        _time(localDate: '2026-08-03'),
      );
      final ProviderContainer container = _container(gateway, time: time);
      addTearDown(container.dispose);
      await container.read(petControllerProvider.future);
      final PetController controller =
          container.read(petControllerProvider.notifier);
      await controller.chooseFirstEgg(PetSpecies.balanceRaccoon);
      final String firstPetId = container
          .read(petControllerProvider)
          .requireValue
          .activeCompanion!
          .id;
      await _saveSummary(gateway, _summary40(localDate: '2026-08-03'));
      await controller.refreshToday();
      await gateway.insertUnlockedPet(
        _petWrite(
          petId: 'pet-wind-fox',
          species: PetSpecies.windFox,
          now: DateTime.utc(2026, 8, 3, 2),
        ),
      );

      await controller.switchActivePet('pet-wind-fox');

      expect(
        gateway.energyFor('2026-08-03')?['recipient_pet_id'],
        firstPetId,
      );
      expect(
        container.read(petControllerProvider).requireValue.profile?.activePetId,
        'pet-wind-fox',
      );

      time.value = _time(localDate: '2026-08-04');
      await _saveSummary(gateway, _summary40(localDate: '2026-08-04'));
      await controller.refreshToday();

      expect(
        gateway.energyFor('2026-08-04')?['recipient_pet_id'],
        'pet-wind-fox',
      );
    });

    test('普通 HealthKit 下调只降低计算值，不回收已发放能量', () async {
      final _MemoryPetGateway gateway = _MemoryPetGateway();
      final _MutablePetTime time = _MutablePetTime(
        _time(localDate: '2026-08-05'),
      );
      final ProviderContainer container = _container(gateway, time: time);
      addTearDown(container.dispose);
      await container.read(petControllerProvider.future);
      final PetController controller =
          container.read(petControllerProvider.notifier);
      await controller.chooseFirstEgg(PetSpecies.balanceRaccoon);
      await _saveSummary(gateway, _summary40(localDate: '2026-08-05'));
      await controller.refreshToday();
      controller.acknowledgeSettlement();

      await _saveSummary(
        gateway,
        _summary40(localDate: '2026-08-05', zeroActivity: true),
      );
      await controller.refreshToday();

      final PetState state = container.read(petControllerProvider).requireValue;
      expect(state.todayEnergy?.calculatedTotal, 0);
      expect(state.todayEnergy?.awardedTotal, 40);
      expect(gateway.lastSettlementResult?.awardedDelta, 0);
      expect(state.pendingSettlement, isNull);
    });
  });

  group('PetController 历史补算与时区锁定', () {
    test('摘要、训练和恢复日期并集都补算，晚到摘要仍写回原自然日', () async {
      final _MemoryPetGateway gateway = _MemoryPetGateway();
      final _MutablePetTime time = _MutablePetTime(
        _time(localDate: '2026-08-10'),
      );
      final InMemoryTrainingLogRepository logs = InMemoryTrainingLogRepository()
        ..saveLog(_trainingLog(id: 'history', localDate: '2026-08-02'));
      final InMemoryDailyContextRepository daily =
          InMemoryDailyContextRepository()
            ..saveContext(
              _contextWithFacts(<AppliedDailyDecisionFact>[
                AppliedDailyDecisionFact(
                  localDate: '2026-08-03',
                  decisionType: TrainingDecisionType.rest,
                  confirmedAt: DateTime.utc(2026, 8, 3, 3),
                ),
              ]),
            );
      final ProviderContainer container = _container(
        gateway,
        time: time,
        trainingLogs: logs,
        dailyContext: daily,
      );
      addTearDown(container.dispose);
      await container.read(petControllerProvider.future);
      final PetController controller =
          container.read(petControllerProvider.notifier);
      await controller.chooseFirstEgg(PetSpecies.balanceRaccoon);
      await _saveSummary(gateway, _summary40(localDate: '2026-08-01'));

      await controller.reconcileKnownDates();

      expect(gateway.energyDates, <String>[
        '2026-08-01',
        '2026-08-02',
        '2026-08-03',
      ]);
      expect(gateway.energyFor('2026-08-01')?['awarded_total'], 40);
      expect(gateway.energyFor('2026-08-02')?['awarded_total'], 100);
      expect(gateway.energyFor('2026-08-03')?['awarded_total'], 60);

      await _saveSummary(gateway, _summary40(localDate: '2026-07-30'));
      await controller.reconcileKnownDates();

      expect(gateway.energyDates, contains('2026-07-30'));
      expect(gateway.energyFor('2026-07-30')?['awarded_total'], 40);
    });

    test('旧账本保留首次固化时区，系统时区变化不移动历史日期', () async {
      final _MemoryPetGateway gateway = _MemoryPetGateway();
      final _MutablePetTime time = _MutablePetTime(
        _time(
          localDate: '2026-08-06',
          timeZoneName: 'Asia/Shanghai',
          timeZoneOffsetMinutes: 480,
        ),
      );
      final ProviderContainer container = _container(gateway, time: time);
      addTearDown(container.dispose);
      await container.read(petControllerProvider.future);
      final PetController controller =
          container.read(petControllerProvider.notifier);
      await controller.chooseFirstEgg(PetSpecies.balanceRaccoon);
      await _saveSummary(
        gateway,
        _summary40(
          localDate: '2026-08-06',
          timeZoneName: 'Asia/Shanghai',
          timeZoneOffsetMinutes: 480,
        ),
      );
      await controller.refreshToday();
      final String originalPetId =
          gateway.energyFor('2026-08-06')!['recipient_pet_id']! as String;

      time.value = _time(
        localDate: '2026-08-06',
        timeZoneName: 'America/Los_Angeles',
        timeZoneOffsetMinutes: -420,
      );
      await _saveSummary(
        gateway,
        _summary40(
          localDate: '2026-08-06',
          timeZoneName: 'America/Los_Angeles',
          timeZoneOffsetMinutes: -420,
        ),
      );
      await controller.refreshToday();

      expect(gateway.energyDates, <String>['2026-08-06']);
      expect(
        gateway.energyFor('2026-08-06')?['recipient_pet_id'],
        originalPetId,
      );
      final Map<String, dynamic> snapshot = jsonDecode(
        gateway.energyFor('2026-08-06')!['source_snapshot_json']! as String,
      ) as Map<String, dynamic>;
      expect(snapshot['timeZoneName'], 'Asia/Shanghai');
      expect(snapshot['timeZoneOffsetMinutes'], 480);
    });
  });

  test('结算失败只更新宠物状态，不向调用方抛出', () async {
    final _MemoryPetGateway gateway = _MemoryPetGateway();
    final _MutablePetTime time = _MutablePetTime(
      _time(localDate: '2026-08-07'),
    );
    final ProviderContainer container = _container(gateway, time: time);
    addTearDown(container.dispose);
    await container.read(petControllerProvider.future);
    final PetController controller =
        container.read(petControllerProvider.notifier);
    await controller.chooseFirstEgg(PetSpecies.balanceRaccoon);
    await _saveSummary(gateway, _summary40(localDate: '2026-08-07'));
    gateway.failSettlement = true;

    await expectLater(controller.refreshToday(), completes);

    final PetState state = container.read(petControllerProvider).requireValue;
    expect(state.status, PetStateStatus.ready);
    expect(state.statusMessage, contains('失败'));
  });

  test('停用清理能量订阅，再启用只恢复一份且停用 build 不补算', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final _MemoryPetGateway gateway = _MemoryPetGateway();
    final _MutablePetTime time = _MutablePetTime(
      _time(localDate: '2026-09-04'),
    );
    final ProviderContainer container = _container(
      gateway,
      time: time,
      runtime: runtime,
    );
    addTearDown(container.dispose);
    await container.read(petControllerProvider.future);
    final ProviderSubscription<AsyncValue<PetState>> keepAlive =
        container.listen(petControllerProvider, (_, __) {});
    addTearDown(keepAlive.close);
    await container
        .read(petControllerProvider.notifier)
        .chooseFirstEgg(PetSpecies.balanceRaccoon);

    await runtime.disable('feature.pet');
    final int beforePausedSignal = gateway.settlementWrites.length;
    container
        .read(dailyActivityEnergyRefreshSignalProvider.notifier)
        .requestRefresh();
    await Future<void>.delayed(Duration.zero);
    expect(gateway.settlementWrites, hasLength(beforePausedSignal));

    await runtime.enable('feature.pet');
    await container.pump();
    await container.read(petControllerProvider.future);
    await _pumpEvents();
    final int beforeFirstSignal = gateway.settlementWrites.length;
    container
        .read(dailyActivityEnergyRefreshSignalProvider.notifier)
        .requestRefresh();
    await _pumpUntil(
      () => gateway.settlementWrites.length > beforeFirstSignal,
    );
    expect(gateway.settlementWrites, hasLength(beforeFirstSignal + 1));

    await runtime.disable('feature.pet');
    final int beforeSecondPause = gateway.settlementWrites.length;
    container
        .read(dailyActivityEnergyRefreshSignalProvider.notifier)
        .requestRefresh();
    await Future<void>.delayed(Duration.zero);
    expect(gateway.settlementWrites, hasLength(beforeSecondPause));

    await runtime.enable('feature.pet');
    await container.pump();
    await container.read(petControllerProvider.future);
    await _pumpEvents();
    container
        .read(dailyActivityEnergyRefreshSignalProvider.notifier)
        .requestRefresh();
    await _pumpUntil(
      () => gateway.settlementWrites.length > beforeSecondPause,
    );
    expect(gateway.settlementWrites, hasLength(beforeSecondPause + 1));

    await runtime.disable('feature.pet');
    final int beforeDisabledBuild = gateway.settlementWrites.length;
    container.invalidate(petControllerProvider);
    final PetState disabled =
        await container.read(petControllerProvider.future);
    expect(disabled.status, PetStateStatus.ready);
    expect(disabled.statusMessage, contains('已暂停'));
    expect(gateway.settlementWrites, hasLength(beforeDisabledBuild));
  });
}

ProviderContainer _container(
  _MemoryPetGateway gateway, {
  required _MutablePetTime time,
  InMemoryTrainingLogRepository? trainingLogs,
  InMemoryDailyContextRepository? dailyContext,
  PluginRuntime? runtime,
}) {
  return ProviderContainer(
    overrides: [
      petDatabaseGatewayProvider.overrideWithValue(gateway),
      healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
      petLocalDayContextProvider.overrideWithValue(time.call),
      trainingLogRepositoryProvider.overrideWithValue(
        trainingLogs ?? InMemoryTrainingLogRepository(),
      ),
      dailyContextRepositoryProvider.overrideWithValue(
        dailyContext ?? InMemoryDailyContextRepository(),
      ),
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      if (runtime != null) pluginRuntimeProvider.overrideWith((ref) => runtime),
    ],
  );
}

Future<void> _pumpUntil(bool Function() condition) async {
  for (int attempt = 0; attempt < 50 && !condition(); attempt += 1) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

Future<void> _pumpEvents() async {
  for (int attempt = 0; attempt < 10; attempt += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _MutablePetTime {
  _MutablePetTime(this.value);

  PetLocalDayContext value;

  PetLocalDayContext call() => value;
}

PetLocalDayContext _time({
  required String localDate,
  String timeZoneName = 'Asia/Shanghai',
  int timeZoneOffsetMinutes = 480,
}) {
  final DateTime parsed = DateTime.parse(localDate);
  return PetLocalDayContext(
    now: DateTime.utc(parsed.year, parsed.month, parsed.day, 4),
    localDate: localDate,
    timeZoneName: timeZoneName,
    timeZoneOffsetMinutes: timeZoneOffsetMinutes,
  );
}

Future<void> _saveSummary(
  PetDatabaseGateway gateway,
  DailyActivitySummary summary,
) {
  return DailyActivitySummaryRepository(gateway).mergeHealthKitSummary(summary);
}

DailyActivitySummary _summary40({
  required String localDate,
  bool zeroActivity = false,
  String timeZoneName = 'Asia/Shanghai',
  int timeZoneOffsetMinutes = 480,
}) {
  return DailyActivitySummary(
    athleteProfileId: 'athlete-a',
    localDate: localDate,
    timeZoneName: timeZoneName,
    timeZoneOffsetMinutes: timeZoneOffsetMinutes,
    steps: zeroActivity ? 0 : 6000,
    stepGoal: 6000,
    standHours: zeroActivity ? 0 : 10,
    standGoalHours: 10,
    exerciseMinutes: zeroActivity ? 0 : 10,
    exerciseGoalMinutes: 30,
    activeEnergyKcal: 0,
    activeEnergyGoalKcal: 300,
    fieldSources: const <DailyActivityField, ActivityFieldSource>{
      DailyActivityField.steps: ActivityFieldSource.healthKit,
      DailyActivityField.stepGoal: ActivityFieldSource.derivedGoal,
      DailyActivityField.standHours: ActivityFieldSource.healthKit,
      DailyActivityField.standGoalHours: ActivityFieldSource.derivedGoal,
      DailyActivityField.exerciseMinutes: ActivityFieldSource.healthKit,
      DailyActivityField.exerciseGoalMinutes: ActivityFieldSource.derivedGoal,
      DailyActivityField.activeEnergyKcal: ActivityFieldSource.healthKit,
      DailyActivityField.activeEnergyGoalKcal: ActivityFieldSource.derivedGoal,
    },
    syncedAt: DateTime.utc(2026, 8, 1, 1),
  );
}

TrainingLog _trainingLog({
  required String id,
  required String localDate,
}) {
  final DateTime parsed = DateTime.parse(localDate);
  final DateTime date = DateTime(parsed.year, parsed.month, parsed.day, 9);
  return TrainingLog(
    id: id,
    workoutDayId: 'workout-a',
    date: date,
    completed: false,
    rpe: 6,
    fatigueLevel: 5,
    sleepQuality: 7,
    painNote: null,
    userNote: null,
    createdAt: date,
    kind: TrainingLogKind.sessionReview,
    completionPercentage: 50,
  );
}

DailyAdjustmentContext _contextWithFacts(
  List<AppliedDailyDecisionFact> facts,
) {
  return DailyAdjustmentContext(
    availableMinutes: 30,
    workStress: WorkStressLevel.normal,
    environment: TrainingEnvironment.home,
    weather: WeatherCondition.good,
    statusMessage: '测试上下文',
    appliedDecisions: facts,
  );
}

PetCollectionWrite _petWrite({
  required String petId,
  required PetSpecies species,
  required DateTime now,
}) {
  return PetCollectionWrite(
    petId: petId,
    athleteProfileId: 'athlete-a',
    species: species,
    nickname: '风步狐',
    unlockedAt: now,
    bornAt: now,
    createdAt: now,
    updatedAt: now,
  );
}

class _MemoryPetGateway implements PetDatabaseGateway {
  final Map<String, Map<String, Object?>> profiles =
      <String, Map<String, Object?>>{};
  final List<Map<String, Object?>> collectionRows = <Map<String, Object?>>[];
  final List<Map<String, Object?>> summaryRows = <Map<String, Object?>>[];
  final List<Map<String, Object?>> energyRows = <Map<String, Object?>>[];
  final List<PetSettlementWrite> settlementWrites = <PetSettlementWrite>[];

  bool failSettlement = false;
  PetSettlementResult? lastSettlementResult;

  List<String> get energyDates {
    final List<String> values = energyRows
        .map((Map<String, Object?> row) => row['local_date']! as String)
        .toList();
    values.sort();
    return values;
  }

  Map<String, Object?>? energyFor(String localDate) {
    for (final Map<String, Object?> row in energyRows) {
      if (row['local_date'] == localDate) return row;
    }
    return null;
  }

  @override
  Future<void> chooseFirstEgg(PetFirstEggWrite write) async {
    if (profiles.containsKey(write.companion.athleteProfileId)) {
      throw StateError('当前账号已经完成首蛋选择');
    }
    collectionRows.add(_collectionRow(write.companion));
    profiles[write.companion.athleteProfileId] = <String, Object?>{
      'athlete_profile_id': write.companion.athleteProfileId,
      'active_pet_id': write.companion.petId,
      'first_egg_species_id': write.companion.species.id,
      'selected_shell_id': write.selectedShellId,
      'created_at': write.companion.createdAt.toIso8601String(),
      'updated_at': write.companion.updatedAt.toIso8601String(),
    };
  }

  @override
  Future<void> insertUnlockedPet(PetCollectionWrite write) async {
    collectionRows.add(_collectionRow(write));
  }

  @override
  Future<List<Map<String, Object?>>> listPetCollectionRows(
    String athleteProfileId,
  ) async {
    return collectionRows
        .where(
          (Map<String, Object?> row) =>
              row['athlete_profile_id'] == athleteProfileId,
        )
        .map(Map<String, Object?>.from)
        .toList(growable: false);
  }

  @override
  Future<Map<String, Object?>?> readPetProfileRow(
    String athleteProfileId,
  ) async {
    final Map<String, Object?>? row = profiles[athleteProfileId];
    return row == null ? null : Map<String, Object?>.from(row);
  }

  @override
  Future<void> switchActivePet({
    required String athleteProfileId,
    required String petId,
    required DateTime updatedAt,
  }) async {
    final Map<String, Object?>? profile = profiles[athleteProfileId];
    if (profile == null) throw StateError('当前账号尚未完成首蛋选择');
    profile
      ..['active_pet_id'] = petId
      ..['updated_at'] = updatedAt.toUtc().toIso8601String();
  }

  @override
  Future<Map<String, Object?>?> readDailyActivitySummaryRow({
    required String athleteProfileId,
    required String localDate,
  }) async {
    for (final Map<String, Object?> row in summaryRows) {
      if (row['athlete_profile_id'] == athleteProfileId &&
          row['local_date'] == localDate) {
        return Map<String, Object?>.from(row);
      }
    }
    return null;
  }

  @override
  Future<List<Map<String, Object?>>> listDailyActivitySummaryRows(
    String athleteProfileId,
  ) async {
    final List<Map<String, Object?>> values = summaryRows
        .where(
          (Map<String, Object?> row) =>
              row['athlete_profile_id'] == athleteProfileId,
        )
        .map(Map<String, Object?>.from)
        .toList();
    values.sort(
      (Map<String, Object?> left, Map<String, Object?> right) =>
          '${right['local_date']}'.compareTo('${left['local_date']}'),
    );
    return values;
  }

  @override
  Future<void> upsertDailyActivitySummaryRow(
    Map<String, Object?> row,
  ) async {
    summaryRows.removeWhere(
      (Map<String, Object?> item) =>
          item['athlete_profile_id'] == row['athlete_profile_id'] &&
          item['local_date'] == row['local_date'],
    );
    summaryRows.add(Map<String, Object?>.from(row));
  }

  @override
  Future<Map<String, Object?>?> readPetDailyEnergyRow({
    required String athleteProfileId,
    required String localDate,
  }) async {
    for (final Map<String, Object?> row in energyRows) {
      if (row['athlete_profile_id'] == athleteProfileId &&
          row['local_date'] == localDate) {
        return Map<String, Object?>.from(row);
      }
    }
    return null;
  }

  @override
  Future<List<Map<String, Object?>>> listPetDailyEnergyRows({
    required String athleteProfileId,
    String? recipientPetId,
  }) async {
    final List<Map<String, Object?>> values = energyRows
        .where(
          (Map<String, Object?> row) =>
              row['athlete_profile_id'] == athleteProfileId &&
              (recipientPetId == null ||
                  row['recipient_pet_id'] == recipientPetId),
        )
        .map(Map<String, Object?>.from)
        .toList();
    values.sort(
      (Map<String, Object?> left, Map<String, Object?> right) =>
          '${right['local_date']}'.compareTo('${left['local_date']}'),
    );
    return values;
  }

  @override
  Future<PetSettlementResult> settleDay(PetSettlementWrite write) async {
    settlementWrites.add(write);
    if (failSettlement) throw StateError('模拟宠物结算失败');
    final String athleteProfileId =
        write.summary?.athleteProfileId ?? write.athleteProfileId!;
    final String localDate = write.summary?.localDate ?? write.localDate!;
    if (write.summary != null) {
      await upsertDailyActivitySummaryRow(
        _summaryRow(write.summary!, updatedAt: write.settledAt),
      );
    }
    final Map<String, Object?>? old = energyFor(localDate);
    if (old == null && write.breakdown.total == 0) {
      return lastSettlementResult = const PetSettlementResult(
        recipientPetId: null,
        calculatedTotal: 0,
        awardedTotal: 0,
        awardedDelta: 0,
        didLockRecipient: false,
      );
    }
    final String recipientPetId =
        old?['recipient_pet_id'] as String? ?? write.activePetId;
    final int previousAwarded = (old?['awarded_total'] as num?)?.toInt() ?? 0;
    final int awardedTotal =
        write.mode == PetSettlementMode.explicitHealthDeletion
            ? write.breakdown.total
            : math.max(previousAwarded, write.breakdown.total);
    final int awardedDelta = math.max(0, awardedTotal - previousAwarded);
    final Map<String, Object?> row = <String, Object?>{
      'athlete_profile_id': athleteProfileId,
      'local_date': localDate,
      'recipient_pet_id': recipientPetId,
      'steps_energy': write.breakdown.stepsEnergy,
      'stand_energy': write.breakdown.standEnergy,
      'exercise_energy': write.breakdown.exerciseEnergy,
      'active_energy': write.breakdown.activeEnergy,
      'training_energy': write.breakdown.trainingEnergy,
      'recovery_energy': write.breakdown.recoveryEnergy,
      'calculated_total': write.breakdown.total,
      'awarded_total': awardedTotal,
      'source_snapshot_json': jsonEncode(write.sourceSnapshot),
      'model_version': write.modelVersion,
      'settled_at':
          old?['settled_at'] ?? write.settledAt.toUtc().toIso8601String(),
      'updated_at': write.settledAt.toUtc().toIso8601String(),
    };
    energyRows.removeWhere(
      (Map<String, Object?> item) =>
          item['athlete_profile_id'] == athleteProfileId &&
          item['local_date'] == localDate,
    );
    energyRows.add(row);
    return lastSettlementResult = PetSettlementResult(
      recipientPetId: recipientPetId,
      calculatedTotal: write.breakdown.total,
      awardedTotal: awardedTotal,
      awardedDelta: awardedDelta,
      didLockRecipient: old == null,
    );
  }
}

Map<String, Object?> _collectionRow(PetCollectionWrite write) {
  return <String, Object?>{
    'pet_id': write.petId,
    'athlete_profile_id': write.athleteProfileId,
    'species_id': write.species.id,
    'nickname': write.nickname,
    'unlocked_at': write.unlockedAt.toIso8601String(),
    'born_at': write.bornAt.toIso8601String(),
    'selected_accessory_id': write.selectedAccessoryId,
    'selected_badge_id': write.selectedBadgeId,
    'created_at': write.createdAt.toIso8601String(),
    'updated_at': write.updatedAt.toIso8601String(),
  };
}

Map<String, Object?> _summaryRow(
  DailyActivitySummary summary, {
  required DateTime updatedAt,
}) {
  return <String, Object?>{
    'athlete_profile_id': summary.athleteProfileId,
    'local_date': summary.localDate,
    'time_zone_name': summary.timeZoneName,
    'time_zone_offset_minutes': summary.timeZoneOffsetMinutes,
    'steps': summary.steps,
    'step_goal': summary.stepGoal,
    'active_energy_kcal': summary.activeEnergyKcal,
    'active_energy_goal_kcal': summary.activeEnergyGoalKcal,
    'exercise_minutes': summary.exerciseMinutes,
    'exercise_goal_minutes': summary.exerciseGoalMinutes,
    'stand_hours': summary.standHours,
    'stand_goal_hours': summary.standGoalHours,
    'field_sources_json': jsonEncode(<String, String>{
      for (final MapEntry<DailyActivityField, ActivityFieldSource> entry
          in summary.fieldSources.entries)
        entry.key.id: entry.value.id,
    }),
    'synced_at': summary.syncedAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}
