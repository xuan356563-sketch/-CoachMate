import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/growth_evidence.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/features/growth/application/growth_evidence_controller.dart';
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
