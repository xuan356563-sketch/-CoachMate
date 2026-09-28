import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/growth_evidence.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/features/growth/application/growth_evidence_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('删除健康数据只撤销健康来源证据并重算当前有效 XP', () async {
    final PersistedGrowthEvidenceRepository repository =
        PersistedGrowthEvidenceRepository(InMemoryLocalStorageService());
    await repository.saveEvent(
      _event(
        eventId: 'health:1',
        sourceTable: 'health_snapshots',
        sourceId: 'snapshot-1',
      ),
    );
    await repository.saveEvent(
      _event(
        eventId: 'training:1',
        sourceTable: 'training_logs',
        sourceId: 'log-1',
      ),
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        growthEvidenceRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final int revoked = await container
        .read(growthEvidenceControllerProvider.notifier)
        .revokeHealthSources(athleteProfileId: 'athlete-1');

    expect(revoked, 1);
    final List<GrowthEvidenceEvent> active = await repository.listEvents(
      athleteProfileId: 'athlete-1',
    );
    expect(active.map((GrowthEvidenceEvent event) => event.eventId),
        <String>['training:1']);
    expect(
      container.read(growthEvidenceControllerProvider).statusMessage,
      contains('当前有效 XP 已重算'),
    );
    final GrowthLevelState level = await repository.readLevelState('athlete-1');
    expect(level.peakXp, 20, reason: '删除健康数据后不能保留由该来源抬高的历史峰值。');
  });

  test('成长与周报停用后两个来源撤销只刷新历史且不锁定或保存周报', () async {
    final PluginRuntime runtime = await _runtime();
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final _CountingGrowthEvidenceRepository repository =
        _CountingGrowthEvidenceRepository(storage);
    await repository.saveEvent(
      _event(
        eventId: 'health:disabled',
        sourceTable: 'health_snapshots',
        sourceId: 'snapshot-disabled',
      ),
    );
    await repository.saveEvent(
      _event(
        eventId: 'training:disabled',
        sourceTable: 'training_logs',
        sourceId: 'log-disabled',
      ),
    );
    await repository.saveWeeklyReport(_unlockedReport());
    repository.reportWrites = 0;
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      growthEvidenceRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    final GrowthEvidenceController controller =
        container.read(growthEvidenceControllerProvider.notifier);
    await runtime.disable('feature.weekly_report');
    await runtime.disable('feature.growth');

    expect(
      await controller.revokeHealthSources(athleteProfileId: 'athlete-1'),
      1,
    );
    GrowthEvidenceState state =
        container.read(growthEvidenceControllerProvider);
    expect(
      state.events
          .singleWhere((event) => event.eventId == 'health:disabled')
          .isRevoked,
      isTrue,
    );
    expect(state.weeklyReports.single.lockedAt, isNull);
    expect(repository.reportWrites, 0);

    await controller.revokeTrainingLog(
      athleteProfileId: 'athlete-1',
      logId: 'log-disabled',
    );
    state = container.read(growthEvidenceControllerProvider);
    expect(
      state.events
          .singleWhere((event) => event.eventId == 'training:disabled')
          .isRevoked,
      isTrue,
    );
    expect(state.statusMessage, contains('成长证据已撤销'));
    expect(state.weeklyReports.single.lockedAt, isNull);
    expect(repository.reportWrites, 0);
    expect(
      (await repository.listWeeklyReports(athleteProfileId: 'athlete-1'))
          .single
          .lockedAt,
      isNull,
    );
  });

  test('成长启用时来源撤销刷新仍会锁定已结束的周报', () async {
    final PluginRuntime runtime = await _runtime();
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final _CountingGrowthEvidenceRepository repository =
        _CountingGrowthEvidenceRepository(storage);
    await repository.saveEvent(
      _event(
        eventId: 'training:enabled',
        sourceTable: 'training_logs',
        sourceId: 'log-enabled',
      ),
    );
    await repository.saveWeeklyReport(_unlockedReport());
    repository.reportWrites = 0;
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      growthEvidenceRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);

    await container
        .read(growthEvidenceControllerProvider.notifier)
        .revokeTrainingLog(
          athleteProfileId: 'athlete-1',
          logId: 'log-enabled',
        );

    expect(repository.reportWrites, 1);
    expect(
      container
          .read(growthEvidenceControllerProvider)
          .weeklyReports
          .single
          .isLocked,
      isTrue,
    );
  });
}

Future<PluginRuntime> _runtime() async {
  final PluginRuntime runtime =
      PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
  await runtime.initialize();
  return runtime;
}

WeeklyGrowthReport _unlockedReport() => WeeklyGrowthReport(
      id: 'weekly-growth:athlete-1:2026-07-13',
      athleteProfileId: 'athlete-1',
      weekKey: '2026-07-13',
      weekStartsOn: DateTime(2026, 7, 13),
      weekEndsOn: DateTime(2026, 7, 19),
      generatedAt: DateTime(2026, 7, 19),
      lockedAt: null,
      regeneratedAt: null,
      consecutiveTrainingDays: 1,
      runningDistanceKm: 5,
      strengthSessionCount: 0,
      completionRate: 1,
      trainingLoad: 100,
      growthIndex: 60,
      availableIndexDimensions: 2,
      recoverySummary: '历史恢复摘要',
      evidenceEventIds: const <String>[],
      modelVersion: 1,
    );

class _CountingGrowthEvidenceRepository
    extends PersistedGrowthEvidenceRepository {
  _CountingGrowthEvidenceRepository(super.storageService);

  int reportWrites = 0;

  @override
  Future<void> saveWeeklyReport(WeeklyGrowthReport report) {
    reportWrites += 1;
    return super.saveWeeklyReport(report);
  }
}

GrowthEvidenceEvent _event({
  required String eventId,
  required String sourceTable,
  required String sourceId,
}) {
  final DateTime occurredAt = DateTime(2026, 7, 15, 8);
  return GrowthEvidenceEvent(
    eventId: eventId,
    athleteProfileId: 'athlete-1',
    eventType: sourceTable == 'training_logs'
        ? GrowthEventType.training
        : GrowthEventType.health,
    title: '测试证据',
    description: '用于验证健康数据删除边界。',
    occurredAt: occurredAt,
    occurredOn: DateTime(2026, 7, 15),
    timeZoneOffsetMinutes: -420,
    timeZoneName: 'America/Los_Angeles',
    sourceTable: sourceTable,
    sourceId: sourceId,
    xpComponents: const <GrowthXpComponent>[
      GrowthXpComponent(
        type: GrowthXpComponentType.completion,
        amount: 20,
        reason: '有效事实',
      ),
    ],
    impacts: const <GrowthImpact>[],
    confidence: GrowthConfidence.high,
    missingData: const <String>[],
    inputSnapshot: const <String, dynamic>{},
    modelVersion: 1,
    createdAt: occurredAt,
    updatedAt: occurredAt,
  );
}
