import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/features/training_log/application/training_log_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  ProviderContainer createContainer(InMemoryLocalStorageService storage) {
    return ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
  }

  TrainingLog createLog(String id, DateTime createdAt) {
    return TrainingLog(
      id: id,
      workoutDayId: 'workout-test',
      date: createdAt,
      completed: true,
      rpe: 6,
      fatigueLevel: 6,
      sleepQuality: 7,
      painNote: null,
      userNote: '训练日志 $id',
      createdAt: createdAt,
    );
  }

  test('初始状态为空，保存后按时间排序并可重新读取', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer first = createContainer(storage);
    expect(first.read(trainingLogControllerProvider), isEmpty);

    final TrainingLogController controller =
        first.read(trainingLogControllerProvider.notifier);
    controller.save(createLog('earlier', DateTime(2026, 7, 12, 8)));
    controller.save(createLog('later', DateTime(2026, 7, 12, 9)));
    expect(first.read(trainingLogControllerProvider).first.id, 'later');
    first.dispose();

    final ProviderContainer restored = createContainer(storage);
    addTearDown(restored.dispose);
    expect(restored.read(trainingLogControllerProvider), hasLength(2));
    expect(restored.read(trainingLogControllerProvider).first.id, 'later');
  });

  test('相同日志 ID 会更新且可以清除', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = createContainer(storage);
    addTearDown(container.dispose);
    final TrainingLogController controller =
        container.read(trainingLogControllerProvider.notifier);

    controller.save(createLog('same', DateTime(2026, 7, 12, 8)));
    controller.save(createLog('same', DateTime(2026, 7, 12, 9)));
    expect(container.read(trainingLogControllerProvider), hasLength(1));
    expect(
      container.read(trainingLogControllerProvider).single.createdAt.hour,
      9,
    );

    controller.clear();
    expect(container.read(trainingLogControllerProvider), isEmpty);
    expect(PersistedLocalStorageProbe(storage).logCount, 0);
  });
}

class PersistedLocalStorageProbe {
  final InMemoryLocalStorageService storage;

  const PersistedLocalStorageProbe(this.storage);

  int get logCount {
    final Map<String, dynamic>? data =
        storage.readJson('trainflow.training_logs.v1');
    return (data?['logs'] as List<dynamic>? ?? const []).length;
  }
}
