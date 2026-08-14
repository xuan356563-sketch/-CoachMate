import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/repositories/health_snapshot_repository.dart';
import 'package:trainflow_ai/data/repositories/training_schedule_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('所有日程与健康仓库键都在设备存储白名单中', () {
    expect(
      SharedPreferencesLocalStorageService.allowedKeys,
      containsAll(<String>[
        TrainingScheduleRepository.availabilityStorageKey,
        TrainingScheduleRepository.scheduleStorageKey,
        HealthSnapshotRepository.storageKey,
      ]),
    );
  });
}
