import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/health_snapshot.dart';
import 'package:trainflow_ai/data/repositories/health_snapshot_repository.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway_contract.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('首次写入分层权限时保留旧版健康快照并归属当前运动员', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final DateTime syncedAt = DateTime.utc(2026, 7, 14, 10);
    storage.saveJson(HealthSnapshotRepository.storageKey, <String, dynamic>{
      'snapshots': <Map<String, dynamic>>[
        HealthSnapshot(
          id: 'legacy-snapshot',
          date: DateTime(2026, 7, 14),
          sleepHours: 7.5,
          restingHeartRate: 56,
          hrvMs: 58,
          weightKg: null,
          bodyFatPercentage: null,
          syncedAt: syncedAt,
        ).toJson(),
      ],
      'lastSync': syncedAt.toIso8601String(),
    });
    final HealthSnapshotRepository repository =
        HealthSnapshotRepository(storage);

    repository.saveAuthorization(
      athleteId: 'athlete-a',
      stage: HealthPermissionStage.analysis,
      state: HealthAuthorizationState.undetermined,
    );

    expect(repository.listSnapshots(athleteId: 'athlete-a'), hasLength(1));
    expect(repository.listSnapshots(athleteId: 'athlete-b'), isEmpty);
    expect(
      repository.getLastSync(
        athleteId: 'athlete-a',
        stage: HealthPermissionStage.analysis,
      ),
      syncedAt,
    );
  });

  test('健康快照和同步时间按运动员及权限阶段隔离', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final HealthSnapshotRepository repository =
        HealthSnapshotRepository(storage);
    final DateTime syncedAt = DateTime.utc(2026, 7, 15, 12);

    repository.save(
      athleteId: 'athlete-a',
      stage: HealthPermissionStage.analysis,
      snapshots: <HealthSnapshot>[
        HealthSnapshot(
          id: 'snapshot-a',
          date: DateTime(2026, 7, 15),
          sleepHours: 8,
          restingHeartRate: 55,
          hrvMs: 60,
          weightKg: null,
          bodyFatPercentage: null,
          syncedAt: syncedAt,
        ),
      ],
      syncedAt: syncedAt,
    );

    expect(repository.listSnapshots(athleteId: 'athlete-a'), hasLength(1));
    expect(repository.listSnapshots(athleteId: 'athlete-b'), isEmpty);
    expect(
      repository.getLastSync(
        athleteId: 'athlete-a',
        stage: HealthPermissionStage.analysis,
      ),
      syncedAt,
    );
    expect(
      repository.getLastSync(
        athleteId: 'athlete-a',
        stage: HealthPermissionStage.body,
      ),
      isNull,
    );
  });

  test('清除一个运动员不会删除另一个运动员的健康数据', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final HealthSnapshotRepository repository =
        HealthSnapshotRepository(storage);
    final DateTime now = DateTime.utc(2026, 7, 15);

    for (final String athleteId in <String>['athlete-a', 'athlete-b']) {
      repository.save(
        athleteId: athleteId,
        stage: HealthPermissionStage.body,
        snapshots: <HealthSnapshot>[
          HealthSnapshot(
            id: 'snapshot-$athleteId',
            date: DateTime(2026, 7, 15),
            sleepHours: null,
            restingHeartRate: null,
            hrvMs: null,
            weightKg: 70,
            bodyFatPercentage: 18,
            syncedAt: now,
          ),
        ],
        syncedAt: now,
      );
    }

    repository.clearAthlete('athlete-a');

    expect(repository.listSnapshots(athleteId: 'athlete-a'), isEmpty);
    expect(repository.listSnapshots(athleteId: 'athlete-b'), hasLength(1));
  });

  test('删除来源会撤销关联摘要，旧版无来源摘要也不保留陈旧值', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final HealthSnapshotRepository repository =
        HealthSnapshotRepository(storage);
    final DateTime now = DateTime.utc(2026, 7, 15);
    repository.save(
      athleteId: 'athlete-a',
      stage: HealthPermissionStage.analysis,
      snapshots: <HealthSnapshot>[
        HealthSnapshot(
          id: 'linked',
          date: DateTime(2026, 7, 15),
          sleepHours: null,
          restingHeartRate: 58,
          hrvMs: null,
          weightKg: null,
          bodyFatPercentage: null,
          syncedAt: now,
          sourceIds: const <String>['source-deleted'],
          sourceLineageVersion: 2,
        ),
        HealthSnapshot(
          id: 'kept',
          date: DateTime(2026, 7, 14),
          sleepHours: null,
          restingHeartRate: 60,
          hrvMs: null,
          weightKg: null,
          bodyFatPercentage: null,
          syncedAt: now,
          sourceIds: const <String>['source-kept'],
          sourceLineageVersion: 2,
        ),
        HealthSnapshot(
          id: 'legacy-without-lineage',
          date: DateTime(2026, 7, 13),
          sleepHours: 7,
          restingHeartRate: null,
          hrvMs: null,
          weightKg: null,
          bodyFatPercentage: null,
          syncedAt: now,
        ),
        HealthSnapshot(
          id: 'legacy-with-source-app-id',
          date: DateTime(2026, 7, 12),
          sleepHours: null,
          restingHeartRate: 62,
          hrvMs: null,
          weightKg: null,
          bodyFatPercentage: null,
          syncedAt: now,
          // 旧版本曾把来源应用 ID 当成样本 UUID，删除时不能继续保留。
          sourceIds: const <String>['com.example.watch'],
        ),
      ],
      syncedAt: now,
    );

    final List<HealthSnapshot> remaining = repository.removeDeletedSources(
      athleteId: 'athlete-a',
      deletedSourceIds: const <String>{'source-deleted'},
    );

    expect(remaining.map((HealthSnapshot item) => item.id), <String>['kept']);
    expect(
      repository
          .listSnapshots(athleteId: 'athlete-a')
          .map((HealthSnapshot item) => item.id),
      <String>['kept'],
    );
  });
}
