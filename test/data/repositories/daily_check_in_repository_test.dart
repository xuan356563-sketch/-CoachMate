import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/daily_check_in_record.dart';
import 'package:trainflow_ai/data/repositories/daily_check_in_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('同一天重复签到只保留一条记录', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final PersistedDailyCheckInRepository repository =
        PersistedDailyCheckInRepository(storage);

    repository.record(
      localDate: DateTime(2026, 7, 18),
      confirmedAt: DateTime(2026, 7, 18, 8),
      source: DailyCheckInSource.prefilled,
    );
    final DailyCheckInWriteResult repeated = repository.record(
      localDate: DateTime(2026, 7, 18),
      confirmedAt: DateTime(2026, 7, 18, 20),
      source: DailyCheckInSource.subjectiveTired,
    );

    expect(repeated.created, isFalse);
    expect(repeated.snapshot.records, hasLength(1));
    expect(repeated.snapshot.streak.currentStreak, 1);
    expect(repeated.snapshot.streak.totalCheckInDays, 1);
  });

  test('连续签到、断签和跨月按本地日期计算', () {
    final PersistedDailyCheckInRepository repository =
        PersistedDailyCheckInRepository(InMemoryLocalStorageService());

    for (final DateTime date in <DateTime>[
      DateTime(2026, 7, 30),
      DateTime(2026, 7, 31),
      DateTime(2026, 8, 1),
      DateTime(2026, 8, 3),
    ]) {
      repository.record(
        localDate: date,
        confirmedAt: date.add(const Duration(hours: 21)),
        source: DailyCheckInSource.prefilled,
      );
    }

    final CheckInStreakState state = repository.getSnapshot().streak;
    expect(state.currentStreak, 1);
    expect(state.longestStreak, 3);
    expect(state.totalCheckInDays, 4);
    expect(state.lastCheckInDate, DateTime(2026, 8, 3));
  });

  test('7天与30天只按累计记录生成里程碑，不奖励脆弱的日连续', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final PersistedDailyCheckInRepository repository =
        PersistedDailyCheckInRepository(storage);
    final DateTime start = DateTime(2026, 6, 20);

    for (int offset = 0; offset < 30; offset += 1) {
      repository.record(
        localDate: start.add(Duration(days: offset)),
        confirmedAt: start.add(Duration(days: offset, hours: 7)),
        source: DailyCheckInSource.prefilled,
      );
    }
    repository.record(
      localDate: start.add(const Duration(days: 29)),
      confirmedAt: start.add(const Duration(days: 29, hours: 20)),
      source: DailyCheckInSource.prefilled,
    );

    final DailyCheckInSnapshot snapshot = repository.getSnapshot();
    expect(
      snapshot.celebrations.map((CheckInCelebrationReceipt item) => item.id),
      <String>['growth_days_7', 'growth_days_30'],
    );
    expect(snapshot.unseenCelebrations, hasLength(2));

    repository.markCelebrationSeen(
      'growth_days_7',
      seenAt: DateTime(2026, 7, 19),
    );
    final PersistedDailyCheckInRepository restored =
        PersistedDailyCheckInRepository(storage);
    expect(restored.getSnapshot().unseenCelebrations, hasLength(1));
  });

  test('60至365累计签到成就不要求继续保持连续', () {
    final PersistedDailyCheckInRepository repository =
        PersistedDailyCheckInRepository(InMemoryLocalStorageService());
    final DateTime start = DateTime(2025, 1, 1);

    for (int index = 0; index < 365; index += 1) {
      final DateTime date = start.add(Duration(days: index * 2));
      repository.record(
        localDate: date,
        confirmedAt: date.add(const Duration(hours: 8)),
        source: DailyCheckInSource.subjectiveTired,
      );
    }

    final DailyCheckInSnapshot snapshot = repository.getSnapshot();
    expect(snapshot.streak.currentStreak, 1);
    expect(snapshot.streak.totalCheckInDays, 365);
    expect(
      snapshot.celebrations.map((CheckInCelebrationReceipt item) => item.id),
      containsAll(<String>[
        'growth_days_60',
        'growth_days_90',
        'growth_days_180',
        'growth_days_365',
      ]),
    );
  });

  test('计划休息和安全暂停需要当天确认并保护连续成长', () {
    final PersistedDailyCheckInRepository repository =
        PersistedDailyCheckInRepository(InMemoryLocalStorageService());

    repository.record(
      localDate: DateTime(2026, 7, 18),
      confirmedAt: DateTime(2026, 7, 18, 8),
      source: DailyCheckInSource.prefilled,
    );
    repository.record(
      localDate: DateTime(2026, 7, 19),
      confirmedAt: DateTime(2026, 7, 19, 8),
      source: DailyCheckInSource.prefilled,
      continuityKind: DailyContinuityKind.plannedRest,
    );
    repository.record(
      localDate: DateTime(2026, 7, 20),
      confirmedAt: DateTime(2026, 7, 20, 8),
      source: DailyCheckInSource.subjectiveTired,
      continuityKind: DailyContinuityKind.safetyPause,
    );

    final DailyCheckInSnapshot snapshot = repository.getSnapshot();
    expect(snapshot.streak.currentStreak, 3);
    expect(
      snapshot.records
          .map((DailyCheckInRecord record) => record.continuityKind),
      <DailyContinuityKind>[
        DailyContinuityKind.standard,
        DailyContinuityKind.plannedRest,
        DailyContinuityKind.safetyPause,
      ],
    );
  });

  test('v1签到记录缺少连续性类型时按标准签到恢复', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    storage.saveJson(PersistedDailyCheckInRepository.storageKey, {
      'schemaVersion': 1,
      'records': [
        {
          'id': 'legacy-record',
          'localDate': '2026-07-18',
          'confirmedAt': '2026-07-18T08:00:00.000',
          'source': 'prefilled',
        },
      ],
      'celebrations': <Map<String, dynamic>>[],
    });

    final PersistedDailyCheckInRepository repository =
        PersistedDailyCheckInRepository(storage);

    expect(
      repository.getSnapshot().records.single.continuityKind,
      DailyContinuityKind.standard,
    );
  });
}
