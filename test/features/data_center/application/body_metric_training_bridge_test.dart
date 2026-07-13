import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('身体记录控制器同步旧状态和成就并保留训练会话', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    final TrainingMvpController training =
        container.read(trainingMvpProvider.notifier);
    final TrainingMvpState before = container.read(trainingMvpProvider);
    training.startWorkoutPlayer(workoutDayId: before.todayWorkout.id);
    training.setKnowledgeSearchQuery('跑步');
    final String activeWorkoutDayId =
        container.read(trainingMvpProvider).activeWorkoutPlayerDayId!;

    final BodyMetricState bodyState =
        container.read(bodyMetricControllerProvider);
    final BodyMetric latestMetric = bodyState.latestMetric!;
    container.read(bodyMetricControllerProvider.notifier).saveManualMetric(
          weightKg: latestMetric.weightKg,
          restingHeartRate: latestMetric.restingHeartRate,
          hrvMs: latestMetric.hrvMs,
          sleepHours: latestMetric.sleepHours,
          fatigueLevel: latestMetric.fatigueLevel,
          measuredAt: latestMetric.measuredAt,
        );
    await Future<void>.delayed(Duration.zero);

    final TrainingMvpState after = container.read(trainingMvpProvider);
    expect(after.bodyMetrics.length, bodyState.metrics.length);
    expect(after.bodyMetricRevisions.length, 1);
    expect(
      after.bodyDataQualityReport.recordCount,
      after.bodyMetrics.length,
    );
    expect(after.activeWorkoutPlayerDayId, activeWorkoutDayId);
    expect(after.knowledgeSearchQuery, '跑步');
    expect(after.achievementRecordFor('body_data_first'), isNotNull);
  });

  test('截图待确认只同步旧待确认状态，确认后才同步成就', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    final TrainingMvpState initial = container.read(trainingMvpProvider);
    final int initialAchievementCount = initial.achievementRecords.length;
    container.read(bodyMetricControllerProvider.notifier).recognizeSnapshotText(
          'Apple 健康 2026-07-12\n体重 73.1\n静息心率 57\nHRV 55\n睡眠 7.5\n疲劳 3',
        );
    await Future<void>.delayed(Duration.zero);

    TrainingMvpState state = container.read(trainingMvpProvider);
    expect(state.pendingBodyMetric, isNotNull);
    expect(state.bodyMetricSnapshotStatusMessage, contains('请确认后写入'));
    expect(state.achievementRecords.length, initialAchievementCount);

    container
        .read(bodyMetricControllerProvider.notifier)
        .confirmPendingMetric();
    await Future<void>.delayed(Duration.zero);

    state = container.read(trainingMvpProvider);
    expect(state.pendingBodyMetric, isNull);
    expect(state.achievementRecordFor('body_data_first'), isNotNull);
  });
}
