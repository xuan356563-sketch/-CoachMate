import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/local/pet_database_gateway.dart';
import 'package:trainflow_ai/data/models/daily_activity_summary.dart';
import 'package:trainflow_ai/data/repositories/daily_activity_summary_repository.dart';

void main() {
  late _MemoryPetGateway gateway;
  late DailyActivitySummaryRepository repository;

  setUp(() {
    gateway = _MemoryPetGateway();
    repository = DailyActivitySummaryRepository(gateway);
  });

  test('活动摘要行与模型往返时保留空值和逐字段不可用来源', () async {
    await repository.mergeHealthKitSummary(
      _summary(
        steps: null,
        stepGoal: 6000,
        activeEnergyKcal: null,
        sources: const <DailyActivityField, ActivityFieldSource>{
          DailyActivityField.steps: ActivityFieldSource.unavailable,
          DailyActivityField.stepGoal: ActivityFieldSource.derivedGoal,
          DailyActivityField.activeEnergyKcal: ActivityFieldSource.unavailable,
        },
      ),
    );

    final DailyActivitySummary? restored = await repository.read(
      athleteProfileId: 'athlete-a',
      localDate: '2026-08-01',
    );

    expect(restored?.steps, isNull);
    expect(restored?.activeEnergyKcal, isNull);
    expect(
      restored?.sourceFor(DailyActivityField.steps),
      ActivityFieldSource.unavailable,
    );
    expect(
      restored?.sourceFor(DailyActivityField.stepGoal),
      ActivityFieldSource.derivedGoal,
    );
    expect(gateway.rows.single['steps'], isNull);
    expect(
      gateway.rows.single['field_sources_json'],
      '{"active_energy_kcal":"unavailable",'
      '"step_goal":"derived_goal","steps":"unavailable"}',
    );
  });

  test('HealthKit 新摘要不会覆盖已有的人工字段', () async {
    await repository.mergeHealthKitSummary(
      _summary(
        steps: 4000,
        exerciseMinutes: 10,
        sources: const <DailyActivityField, ActivityFieldSource>{
          DailyActivityField.steps: ActivityFieldSource.healthKit,
          DailyActivityField.exerciseMinutes: ActivityFieldSource.healthKit,
        },
      ),
    );
    await repository.saveManualOverride(
      athleteProfileId: 'athlete-a',
      localDate: '2026-08-01',
      field: DailyActivityField.steps,
      value: 8000,
      updatedAt: DateTime.utc(2026, 8, 1, 2),
    );

    final DailyActivitySummary merged = await repository.mergeHealthKitSummary(
      _summary(
        steps: 12000,
        exerciseMinutes: 25,
        syncedAt: DateTime.utc(2026, 8, 1, 3),
        sources: const <DailyActivityField, ActivityFieldSource>{
          DailyActivityField.steps: ActivityFieldSource.healthKit,
          DailyActivityField.exerciseMinutes: ActivityFieldSource.healthKit,
        },
      ),
    );

    expect(merged.steps, 8000);
    expect(
      merged.sourceFor(DailyActivityField.steps),
      ActivityFieldSource.manualOverride,
    );
    expect(merged.exerciseMinutes, 25);
    expect(
      merged.sourceFor(DailyActivityField.exerciseMinutes),
      ActivityFieldSource.healthKit,
    );
  });

  test('人工覆盖只更新目标字段并保留其他值、日期和时区上下文', () async {
    await repository.mergeHealthKitSummary(
      _summary(
        steps: 4000,
        activeEnergyKcal: 210.5,
        exerciseMinutes: 18,
        sources: const <DailyActivityField, ActivityFieldSource>{
          DailyActivityField.steps: ActivityFieldSource.healthKit,
          DailyActivityField.activeEnergyKcal: ActivityFieldSource.healthKit,
          DailyActivityField.exerciseMinutes: ActivityFieldSource.healthKit,
        },
      ),
    );

    final DailyActivitySummary updated = await repository.saveManualOverride(
      athleteProfileId: 'athlete-a',
      localDate: '2026-08-01',
      field: DailyActivityField.activeEnergyKcal,
      value: 333.5,
      updatedAt: DateTime.utc(2026, 8, 1, 2),
    );

    expect(updated.activeEnergyKcal, 333.5);
    expect(updated.steps, 4000);
    expect(updated.exerciseMinutes, 18);
    expect(updated.localDate, '2026-08-01');
    expect(updated.timeZoneName, 'Asia/Shanghai');
    expect(updated.timeZoneOffsetMinutes, 480);
    expect(
      updated.sourceFor(DailyActivityField.activeEnergyKcal),
      ActivityFieldSource.manualOverride,
    );
  });

  test('恢复自动会移除人工值，下一次 HealthKit 摘要可以重新写入', () async {
    await repository.mergeHealthKitSummary(
      _summary(
        steps: 4000,
        sources: const <DailyActivityField, ActivityFieldSource>{
          DailyActivityField.steps: ActivityFieldSource.healthKit,
        },
      ),
    );
    await repository.saveManualOverride(
      athleteProfileId: 'athlete-a',
      localDate: '2026-08-01',
      field: DailyActivityField.steps,
      value: 8000,
      updatedAt: DateTime.utc(2026, 8, 1, 2),
    );

    final DailyActivitySummary restored =
        await repository.restoreAutomaticField(
      athleteProfileId: 'athlete-a',
      localDate: '2026-08-01',
      field: DailyActivityField.steps,
      updatedAt: DateTime.utc(2026, 8, 1, 3),
    );
    final DailyActivitySummary refreshed =
        await repository.mergeHealthKitSummary(
      _summary(
        steps: 9200,
        syncedAt: DateTime.utc(2026, 8, 1, 4),
        sources: const <DailyActivityField, ActivityFieldSource>{
          DailyActivityField.steps: ActivityFieldSource.healthKit,
        },
      ),
    );

    expect(restored.steps, isNull);
    expect(
      restored.sourceFor(DailyActivityField.steps),
      ActivityFieldSource.unavailable,
    );
    expect(refreshed.steps, 9200);
    expect(
      refreshed.sourceFor(DailyActivityField.steps),
      ActivityFieldSource.healthKit,
    );
  });
}

DailyActivitySummary _summary({
  int? steps = 6000,
  int? stepGoal = 6000,
  double? activeEnergyKcal = 300,
  double? activeEnergyGoalKcal = 300,
  int? exerciseMinutes = 30,
  int? exerciseGoalMinutes = 30,
  int? standHours = 10,
  int? standGoalHours = 10,
  Map<DailyActivityField, ActivityFieldSource> sources =
      const <DailyActivityField, ActivityFieldSource>{},
  DateTime? syncedAt,
}) {
  return DailyActivitySummary(
    athleteProfileId: 'athlete-a',
    localDate: '2026-08-01',
    timeZoneName: 'Asia/Shanghai',
    timeZoneOffsetMinutes: 480,
    steps: steps,
    stepGoal: stepGoal,
    activeEnergyKcal: activeEnergyKcal,
    activeEnergyGoalKcal: activeEnergyGoalKcal,
    exerciseMinutes: exerciseMinutes,
    exerciseGoalMinutes: exerciseGoalMinutes,
    standHours: standHours,
    standGoalHours: standGoalHours,
    fieldSources: sources,
    syncedAt: syncedAt ?? DateTime.utc(2026, 8, 1, 1),
  );
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
