import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/models/daily_activity_summary.dart';
import 'package:trainflow_ai/features/pet/application/daily_activity_sync_controller.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway_contract.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';

void main() {
  test('首次同步缺少活动目标时保存 6000、10、30、300 默认目标', () async {
    final _FakeActivityGateway health = _FakeActivityGateway(
      summaries: <HealthDailyActivitySummaryPayload>[
        _payload(localDate: '2026-07-14', steps: 4200),
      ],
    );
    final _MemoryPetGateway database = _MemoryPetGateway();
    final ProviderContainer container = _container(health, database);
    addTearDown(container.dispose);
    await container.read(dailyActivitySyncControllerProvider.future);

    await container
        .read(dailyActivitySyncControllerProvider.notifier)
        .refresh();

    final DailyActivitySummary latest = container
        .read(dailyActivitySyncControllerProvider)
        .requireValue
        .latest!;
    expect(latest.stepGoal, 6000);
    expect(latest.standGoalHours, 10);
    expect(latest.exerciseGoalMinutes, 30);
    expect(latest.activeEnergyGoalKcal, 300);
    for (final DailyActivityField field in <DailyActivityField>[
      DailyActivityField.stepGoal,
      DailyActivityField.standGoalHours,
      DailyActivityField.exerciseGoalMinutes,
      DailyActivityField.activeEnergyGoalKcal,
    ]) {
      expect(latest.sourceFor(field), ActivityFieldSource.derivedGoal);
    }
  });

  test('14 天建议只展示，用户确认单项后才以人工来源持久化', () async {
    final _FakeActivityGateway health = _FakeActivityGateway(
      summaries: List<HealthDailyActivitySummaryPayload>.generate(
        14,
        (int index) => _payload(
          localDate: '2026-07-${(index + 1).toString().padLeft(2, '0')}',
          steps: 5000 + index * 200,
          standHours: 8 + index % 3,
          exerciseMinutes: 20 + index,
          activeEnergyKcal: 250 + index * 10,
        ),
      ),
    );
    final _MemoryPetGateway database = _MemoryPetGateway();
    final ProviderContainer container = _container(health, database);
    addTearDown(container.dispose);
    await container.read(dailyActivitySyncControllerProvider.future);

    await container
        .read(dailyActivitySyncControllerProvider.notifier)
        .refresh();

    final DailyActivitySyncState before =
        container.read(dailyActivitySyncControllerProvider).requireValue;
    expect(before.suggestedGoals, isNotNull);
    expect(
      before.latest!.sourceFor(DailyActivityField.stepGoal),
      ActivityFieldSource.derivedGoal,
    );

    await container
        .read(dailyActivitySyncControllerProvider.notifier)
        .setManualGoal(
          DailyActivityField.stepGoal,
          before.suggestedGoals!.stepGoal,
        );

    final DailyActivitySummary confirmed = container
        .read(dailyActivitySyncControllerProvider)
        .requireValue
        .latest!;
    expect(confirmed.stepGoal, before.suggestedGoals!.stepGoal);
    expect(
      confirmed.sourceFor(DailyActivityField.stepGoal),
      ActivityFieldSource.manualOverride,
    );
    expect(
      confirmed.sourceFor(DailyActivityField.standGoalHours),
      ActivityFieldSource.derivedGoal,
    );
  });

  test('人工活动值优先于后续 HealthKit，重复刷新不会生成重复自然日', () async {
    final _FakeActivityGateway health = _FakeActivityGateway(
      summaries: <HealthDailyActivitySummaryPayload>[
        _payload(localDate: '2026-07-14', steps: 4000),
      ],
    );
    final _MemoryPetGateway database = _MemoryPetGateway();
    final ProviderContainer container = _container(health, database);
    addTearDown(container.dispose);
    await container.read(dailyActivitySyncControllerProvider.future);
    final DailyActivitySyncController controller =
        container.read(dailyActivitySyncControllerProvider.notifier);
    await controller.refresh();
    await controller.setManualValue(DailyActivityField.steps, 8000);
    health.summaries = <HealthDailyActivitySummaryPayload>[
      _payload(localDate: '2026-07-14', steps: 12000),
    ];

    await controller.refresh();
    await controller.refresh();

    final DailyActivitySyncState state =
        container.read(dailyActivitySyncControllerProvider).requireValue;
    expect(state.summaries, hasLength(1));
    expect(state.latest!.steps, 8000);
    expect(
      state.latest!.sourceFor(DailyActivityField.steps),
      ActivityFieldSource.manualOverride,
    );
    expect(database.rows, hasLength(1));
  });

  test('恢复自动同步只恢复指定字段并保留其他人工覆盖', () async {
    final _FakeActivityGateway health = _FakeActivityGateway(
      summaries: <HealthDailyActivitySummaryPayload>[
        _payload(
          localDate: '2026-07-14',
          steps: 4000,
          exerciseMinutes: 20,
        ),
      ],
    );
    final _MemoryPetGateway database = _MemoryPetGateway();
    final ProviderContainer container = _container(health, database);
    addTearDown(container.dispose);
    await container.read(dailyActivitySyncControllerProvider.future);
    final DailyActivitySyncController controller =
        container.read(dailyActivitySyncControllerProvider.notifier);
    await controller.refresh();
    await controller.setManualValue(DailyActivityField.steps, 8000);
    await controller.setManualValue(DailyActivityField.exerciseMinutes, 40);
    health.summaries = <HealthDailyActivitySummaryPayload>[
      _payload(
        localDate: '2026-07-14',
        steps: 9200,
        exerciseMinutes: 25,
      ),
    ];

    await controller.restoreAutomatic(DailyActivityField.steps);

    final DailyActivitySummary latest = container
        .read(dailyActivitySyncControllerProvider)
        .requireValue
        .latest!;
    expect(latest.steps, 9200);
    expect(
      latest.sourceFor(DailyActivityField.steps),
      ActivityFieldSource.healthKit,
    );
    expect(latest.exerciseMinutes, 40);
    expect(
      latest.sourceFor(DailyActivityField.exerciseMinutes),
      ActivityFieldSource.manualOverride,
    );
  });

  test('非 iOS 空 payload 保持空摘要且不把未授权伪装成零', () async {
    final _FakeActivityGateway health = _FakeActivityGateway(
      supported: false,
    );
    final ProviderContainer container = _container(
      health,
      _MemoryPetGateway(),
    );
    addTearDown(container.dispose);
    await container.read(dailyActivitySyncControllerProvider.future);

    await container
        .read(dailyActivitySyncControllerProvider.notifier)
        .refresh();

    final DailyActivitySyncState state =
        container.read(dailyActivitySyncControllerProvider).requireValue;
    expect(state.supported, isFalse);
    expect(state.summaries, isEmpty);
    expect(state.latest, isNull);
    expect(state.statusMessage, contains('不支持'));
  });
}

ProviderContainer _container(
  _FakeActivityGateway health,
  _MemoryPetGateway database,
) {
  return ProviderContainer(overrides: [
    healthDataGatewayProvider.overrideWithValue(health),
    healthSyncAthleteIdProvider.overrideWithValue('athlete-a'),
    petDatabaseGatewayProvider.overrideWithValue(database),
    dailyActivitySyncClockProvider.overrideWithValue(
      () => DateTime(2026, 7, 14, 12),
    ),
  ]);
}

HealthDailyActivitySummaryPayload _payload({
  required String localDate,
  required int steps,
  int standHours = 9,
  int exerciseMinutes = 24,
  double activeEnergyKcal = 280,
}) {
  return HealthDailyActivitySummaryPayload(
    localDate: localDate,
    timeZoneName: 'Asia/Shanghai',
    timeZoneOffsetMinutes: 480,
    steps: steps,
    activeEnergyKcal: activeEnergyKcal,
    exerciseMinutes: exerciseMinutes,
    standHours: standHours,
    availableFields: const <String>{
      'steps',
      'activeEnergyKcal',
      'exerciseMinutes',
      'standHours',
    },
    syncedAt: DateTime.utc(2026, 7, 14, 4),
  );
}

class _FakeActivityGateway extends HealthDataGateway {
  _FakeActivityGateway({
    this.supported = true,
    this.summaries = const <HealthDailyActivitySummaryPayload>[],
  });

  final bool supported;
  List<HealthDailyActivitySummaryPayload> summaries;

  @override
  bool get isSupported => supported;

  @override
  Future<List<HealthDailyActivitySummaryPayload>> fetchDailyActivitySummaries({
    required DateTime start,
    required DateTime end,
  }) async =>
      List<HealthDailyActivitySummaryPayload>.from(summaries);

  @override
  Future<HealthAuthorizationResult> requestAuthorization({
    required HealthPermissionStage stage,
    required String athleteId,
  }) async =>
      HealthAuthorizationResult(
        stage: stage,
        state: supported
            ? HealthAuthorizationState.undetermined
            : HealthAuthorizationState.unavailable,
        requestCompleted: supported,
      );

  @override
  Future<HealthForegroundSyncResult> fetchForeground({
    required HealthPermissionStage stage,
    required String athleteId,
    required DateTime start,
    required DateTime end,
  }) async =>
      const HealthForegroundSyncResult();

  @override
  Future<List<HealthSyncBatch>> drainPendingBatches({int limit = 20}) async =>
      const <HealthSyncBatch>[];

  @override
  Future<void> acknowledgeBatch(String batchId) async {}

  @override
  Future<void> clearPendingBatches({required String athleteId}) async {}
}

class _MemoryPetGateway implements PetDatabaseGateway {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>?> readDailyActivitySummaryRow({
    required String athleteProfileId,
    required String localDate,
  }) async {
    for (final Map<String, Object?> row in rows) {
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
    final List<Map<String, Object?>> result = rows
        .where(
          (Map<String, Object?> row) =>
              row['athlete_profile_id'] == athleteProfileId,
        )
        .map(Map<String, Object?>.from)
        .toList();
    result.sort(
      (Map<String, Object?> left, Map<String, Object?> right) =>
          '${right['local_date']}'.compareTo('${left['local_date']}'),
    );
    return result;
  }

  @override
  Future<void> upsertDailyActivitySummaryRow(
    Map<String, Object?> incoming,
  ) async {
    rows.removeWhere(
      (Map<String, Object?> row) =>
          row['athlete_profile_id'] == incoming['athlete_profile_id'] &&
          row['local_date'] == incoming['local_date'],
    );
    rows.add(Map<String, Object?>.from(incoming));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
