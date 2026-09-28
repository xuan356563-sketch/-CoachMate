import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/growth_evidence.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/seed/seed_training_plans.dart';
import 'package:trainflow_ai/features/growth/application/growth_evidence_controller.dart';
import 'package:trainflow_ai/plugins/application/feature_access.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';


import 'package:trainflow_ai/data/models/health_snapshot.dart';
import 'package:trainflow_ai/data/repositories/health_snapshot_repository.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

class _NoopHealthDataGateway extends HealthDataGateway {
  @override
  bool get isSupported => true;

  @override
  Future<HealthAuthorizationResult> requestAuthorization({
    required HealthPermissionStage stage,
    required String athleteId,
  }) async =>
      HealthAuthorizationResult(
        stage: stage,
        state: HealthAuthorizationState.undetermined,
        requestCompleted: false,
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

void main() {
  test('不完整健康快照不会被补零或沿用旧值后写入身体记录', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
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
        healthDataGatewayProvider.overrideWithValue(_NoopHealthDataGateway()),
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

  for (final bool repositoryFails in [false, true]) {
    test(repositoryFails ? '成长停用时迟到的真实仓储错误仍原样上抛' : '真实成长停用后的旧对账被识别为生命周期失效', () async {
      final runtime = PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
      await runtime.initialize();
      final repository = _GatedEvidenceRepository();
      final container = ProviderContainer(overrides: [
        pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
        growthEvidenceRepositoryProvider.overrideWithValue(repository),
        localStorageServiceProvider.overrideWithValue(InMemoryLocalStorageService()),
      ]);
      addTearDown(container.dispose);
      final pending = container.read(growthEvidenceControllerProvider.notifier).reconcile(
        profile: InMemoryUserProfileRepository.defaultProfile,
        logs: const [],
        bodyMetrics: const [],
        painLogs: const [],
        workoutsById: const {},
        fallbackWorkout: seedTrainingPlans.first.workoutDays.first,
      );
      final outcome = pending.then<Object?>((_) => null, onError: (Object error) => error);
      await repository.entered.future;
      await runtime.disable('feature.growth');
      final failure = StateError('训练事实仓储读取失败。');
      if (repositoryFails) {
        repository.result.completeError(failure);
      } else {
        repository.result.complete(const []);
      }
      final error = await outcome;
      expect(error, isNotNull);
      expect(isFeatureOperationInvalidation(error!), !repositoryFails);
      if (repositoryFails) {
        expect(error, same(failure));
      } else {
        expect(error, isA<FeatureOperationInvalidation>());
      }
    });
  }

  test('后台成长对账只消费明确的功能操作失效错误', () {
    expect(
      isFeatureOperationInvalidation(
        FeatureOperationInvalidation.accountChanged(),
      ),
      isTrue,
    );
    expect(
      isFeatureOperationInvalidation(
        FeatureOperationInvalidation.sourcesChanged(),
      ),
      isTrue,
    );
    expect(
      isFeatureOperationInvalidation(StateError('训练事实仓储读取失败。')),
      isFalse,
    );
    expect(isFeatureOperationInvalidation(Exception('未知业务失败。')), isFalse);
    expect(isFeatureOperationInvalidation(
      StateError('账户已变化，本次操作结果已失效，请重新操作。')),
      isFalse, reason: '仅凭仓储错误文案相同不能吞掉真实错误。');
  });
}

class _GatedEvidenceRepository implements GrowthEvidenceRepository {
  final entered = Completer<void>();
  final result = Completer<List<GrowthEvidenceEvent>>();

  @override
  Future<List<GrowthEvidenceEvent>> listEvents({
    required String athleteProfileId,
    bool includeRevoked = false,
    int limit = 30,
    int offset = 0,
  }) {
    entered.complete();
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('失效后不应再读写成长仓储。');
}
