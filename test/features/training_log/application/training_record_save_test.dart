import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/training_log/application/training_log_controller.dart';
import 'package:trainflow_ai/features/training_log/application/training_record_save_request.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  ProviderContainer buildContainer() {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  TrainingRecordSaveRequest request({
    required TrainingRecordSource source,
    required String workoutDayId,
    int durationMinutes = 60,
    double? energyKcal,
    String? customActivityName,
  }) {
    return TrainingRecordSaveRequest(
      source: source,
      workoutDayId: workoutDayId,
      date: DateTime(2026, 8, 3, 18),
      activityType: customActivityName == null
          ? TrainingActivityType.strength
          : TrainingActivityType.custom,
      customActivityName: customActivityName,
      actualDurationMinutes: durationMinutes,
      completionPercentage: 100,
      rpe: 7,
      energyKcal: energyKcal,
      energySource: energyKcal == null ? null : TrainingEnergySource.manual,
    );
  }

  test('同日同一计划再次保存会更新原记录', () async {
    final ProviderContainer container = buildContainer();
    final TrainingMvpController controller =
        container.read(trainingMvpProvider.notifier);
    final String workoutDayId =
        container.read(trainingMvpProvider).todayWorkout.id;

    await controller.saveTrainingRecord(
      request(
        source: TrainingRecordSource.planned,
        workoutDayId: workoutDayId,
        durationMinutes: 50,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await controller.saveTrainingRecord(
      request(
        source: TrainingRecordSource.planned,
        workoutDayId: workoutDayId,
        durationMinutes: 65,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final List<TrainingLog> logs =
        container.read(trainingLogControllerProvider);
    expect(logs, hasLength(1));
    expect(logs.single.actualDurationMinutes, 65);
  });

  test('额外训练使用独立记录标识并允许一天保存多条', () async {
    final ProviderContainer container = buildContainer();
    final TrainingMvpController controller =
        container.read(trainingMvpProvider.notifier);

    final TrainingLog first = await controller.saveTrainingRecord(
      request(
        source: TrainingRecordSource.extra,
        workoutDayId: 'extra-running',
      ),
    );
    final TrainingLog second = await controller.saveTrainingRecord(
      request(
        source: TrainingRecordSource.extra,
        workoutDayId: 'extra-running',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(first.id, isNot(second.id));
    expect(container.read(trainingLogControllerProvider), hasLength(2));
  });

  test('字段校验失败时抛出中文错误且不保存半条记录', () async {
    final ProviderContainer container = buildContainer();
    final TrainingMvpController controller =
        container.read(trainingMvpProvider.notifier);

    await expectLater(
      controller.saveTrainingRecord(
        request(
          source: TrainingRecordSource.extra,
          workoutDayId: 'extra-custom',
          durationMinutes: 4,
          energyKcal: 6001,
          customActivityName: '  ',
        ),
      ),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('实际时长'),
        ),
      ),
    );
    expect(container.read(trainingLogControllerProvider), isEmpty);
  });
}
