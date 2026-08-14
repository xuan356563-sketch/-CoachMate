import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/health_snapshot.dart';
import 'package:trainflow_ai/data/repositories/health_snapshot_repository.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('不完整健康快照不会被补零或沿用旧值后写入身体记录', () async {
    final InMemoryLocalStorageService storage =
        InMemoryLocalStorageService();
    final HealthSnapshotRepository repository =
        HealthSnapshotRepository(storage);
    repository.save(
      athleteId: 'user-local-demo',
      stage: HealthPermissionStage.analysis,
      snapshots: <HealthSnapshot>[
        HealthSnapshot(
          id: 'health-partial-snapshot',
          date: DateTime(2026, 7, 15),
          sleepHours: null,
          restingHeartRate: 58,
          hrvMs: null,
          weightKg: null,
          bodyFatPercentage: null,
          syncedAt: DateTime(2026, 7, 15, 8),
        ),
      ],
      syncedAt: DateTime(2026, 7, 15, 8),
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    final int bodyMetricCountBefore =
        container.read(trainingMvpProvider).bodyMetrics.length;
    await container.read(healthSyncControllerProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(trainingMvpProvider).bodyMetrics,
      hasLength(bodyMetricCountBefore),
      reason: '健康事实缺字段时只能降级单项指标，不能构造身体记录。',
    );
  });
}
