import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/growth_evidence.dart';
import 'package:trainflow_ai/features/growth/application/growth_evidence_controller.dart';

void main() {
  test('只确认当前成长回执，旧事件 ID 不会误清除新回执', () {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        growthEvidenceControllerProvider.overrideWith(
          _ReceiptGrowthEvidenceController.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    final GrowthEvidenceController controller =
        container.read(growthEvidenceControllerProvider.notifier);

    controller.acknowledgeLatestReceipt('旧事件');
    expect(
      container.read(growthEvidenceControllerProvider).latestReceipt,
      isNotNull,
    );

    controller.acknowledgeLatestReceipt('新事件');
    expect(
      container.read(growthEvidenceControllerProvider).latestReceipt,
      isNull,
    );
  });
}

class _ReceiptGrowthEvidenceController extends GrowthEvidenceController {
  @override
  GrowthEvidenceState build() {
    final DateTime occurredAt = DateTime(2026, 7, 27, 9);
    final GrowthEvidenceEvent event = GrowthEvidenceEvent(
      eventId: '新事件',
      athleteProfileId: '测试运动员',
      eventType: GrowthEventType.training,
      title: '完成训练',
      description: '用于测试回执确认。',
      occurredAt: occurredAt,
      occurredOn: DateTime(2026, 7, 27),
      timeZoneOffsetMinutes: -420,
      timeZoneName: 'America/Los_Angeles',
      sourceTable: 'training_logs',
      sourceId: '训练记录',
      xpComponents: const <GrowthXpComponent>[],
      impacts: const <GrowthImpact>[],
      confidence: GrowthConfidence.high,
      missingData: const <String>[],
      inputSnapshot: const <String, dynamic>{},
      modelVersion: 1,
      createdAt: occurredAt,
      updatedAt: occurredAt,
    );
    return GrowthEvidenceState(
      athleteProfileId: '测试运动员',
      events: <GrowthEvidenceEvent>[event],
      levelState: const GrowthLevelState(peakXp: 10, peakLevel: 1),
      weeklyReports: const <WeeklyGrowthReport>[],
      latestReceipt: TrainingGrowthReceipt(
        event: event,
        awardedXp: 10,
        longTermMeaning: '形成长期训练证据。',
        message: '本次训练已记录。',
      ),
      statusMessage: '成长回执已生成。',
      isSynchronizing: false,
    );
  }
}
