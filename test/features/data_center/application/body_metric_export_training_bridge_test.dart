import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_export_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('导出审计同步旧训练状态并保留跟练会话', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final TrainingMvpController training =
        container.read(trainingMvpProvider.notifier);
    training.startWorkoutPlayer(
      workoutDayId: container.read(trainingMvpProvider).todayWorkout.id,
    );
    training.setKnowledgeSearchQuery('跑步');
    final TrainingMvpState before = container.read(trainingMvpProvider);

    await container
        .read(bodyMetricExportControllerProvider.notifier)
        .recordJsonExport(before.bodyMetricJsonExport);
    await Future<void>.delayed(Duration.zero);

    final TrainingMvpState after = container.read(trainingMvpProvider);
    expect(after.bodyMetricExportRecords, hasLength(1));
    expect(after.bodyMetricExportStatusMessage, contains('已登记 JSON 导出'));
    expect(after.activeWorkoutPlayerDayId, before.activeWorkoutPlayerDayId);
    expect(after.knowledgeSearchQuery, before.knowledgeSearchQuery);
  });
}
