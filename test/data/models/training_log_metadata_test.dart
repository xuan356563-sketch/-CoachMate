import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_log.dart';

void main() {
  test('旧训练记录缺少运动项目与热量字段时保持兼容', () {
    final TrainingLog log = TrainingLog.fromJson(<String, dynamic>{
      'id': 'legacy-log',
      'workoutDayId': 'legacy-workout',
      'date': '2026-08-03T08:00:00.000',
      'completed': true,
      'rpe': 6,
      'fatigueLevel': 6,
      'sleepQuality': 7,
      'createdAt': '2026-08-03T09:00:00.000',
    });

    expect(log.activityType, isNull);
    expect(log.customActivityName, isNull);
    expect(log.energyKcal, isNull);
    expect(log.energySource, isNull);
    expect(log.deviceWorkoutId, isNull);
  });

  test('确认后的设备热量与运动项目可以往返序列化', () {
    final TrainingLog log = TrainingLog(
      id: 'health-confirmed-log',
      workoutDayId: 'workout-running',
      date: DateTime(2026, 8, 3, 8),
      completed: true,
      rpe: 7,
      fatigueLevel: 7,
      sleepQuality: 7,
      painNote: null,
      userNote: null,
      createdAt: DateTime(2026, 8, 3, 9),
      activityType: TrainingActivityType.running,
      energyKcal: 371.5,
      energySource: TrainingEnergySource.healthKitConfirmed,
      deviceWorkoutId: 'health-workout-1',
    );

    final TrainingLog restored = TrainingLog.fromJson(log.toJson());

    expect(restored.activityType, TrainingActivityType.running);
    expect(restored.energyKcal, 371.5);
    expect(
      restored.energySource,
      TrainingEnergySource.healthKitConfirmed,
    );
    expect(restored.deviceWorkoutId, 'health-workout-1');
    expect(restored.sessionReviewSummary, contains('跑步'));
    expect(restored.sessionReviewSummary, contains('372 千卡'));
  });

  test('自定义运动名称保留且越界热量不会被伪装为有效值', () {
    final TrainingLog log = TrainingLog.fromJson(<String, dynamic>{
      'id': 'custom-log',
      'workoutDayId': 'extra-workout',
      'date': '2026-08-03T08:00:00.000',
      'completed': true,
      'rpe': 5,
      'fatigueLevel': 5,
      'sleepQuality': 7,
      'createdAt': '2026-08-03T09:00:00.000',
      'activityType': 'custom',
      'customActivityName': '  攀树训练  ',
      'energyKcal': 6000,
      'energySource': 'manual',
    });

    expect(log.activityType, TrainingActivityType.custom);
    expect(log.customActivityName, '攀树训练');
    expect(log.energyKcal, isNull);
    expect(log.energySource, isNull);
  });
}
