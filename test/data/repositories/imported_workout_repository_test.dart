import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/imported_workout.dart';
import 'package:trainflow_ai/data/repositories/imported_workout_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('删除路线形状保留训练摘要并可在重启后恢复', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final PersistedImportedWorkoutRepository repository =
        PersistedImportedWorkoutRepository(storage);
    repository.saveWorkout(
      ImportedWorkout(
        id: 'gpx-1',
        source: ImportedWorkoutSource.gpx,
        title: '测试跑步',
        startedAt: DateTime(2026, 7, 20),
        distanceKm: 5,
        durationMinutes: 30,
        elevationGainMeters: 20,
        averageHeartRate: 140,
        trainingEffect: TrainingEffectLabel.aerobic,
        sourceFingerprint: 'gpx:test',
        routeShape: const <RouteShapePoint>[
          RouteShapePoint(x: 0, y: 0, progress: 0, segmentIndex: 0),
          RouteShapePoint(x: 1, y: 1, progress: 1, segmentIndex: 0),
        ],
      ),
    );

    final bool removed = repository.removeRouteShape('gpx-1');
    final PersistedImportedWorkoutRepository restored =
        PersistedImportedWorkoutRepository(storage);

    expect(removed, isTrue);
    expect(restored.listWorkouts().single.title, '测试跑步');
    expect(restored.listWorkouts().single.routeShape, isEmpty);
    expect(restored.listWorkouts().single.distanceKm, 5);
  });
}
