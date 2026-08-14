import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_log.dart';

void main() {
  test('训练感受与专注质量可序列化并兼容恢复', () {
    final DateTime now = DateTime(2026, 7, 27, 8);
    final TrainingLog source = TrainingLog(
      id: 'log-psych',
      workoutDayId: 'day-1',
      date: now,
      completed: true,
      rpe: 6,
      fatigueLevel: 5,
      sleepQuality: 7,
      painNote: null,
      userNote: null,
      createdAt: now,
      sessionFeel: SessionFeel.good,
      focusQuality: 4,
    );

    final TrainingLog restored = TrainingLog.fromJson(source.toJson());

    expect(restored.sessionFeel, SessionFeel.good);
    expect(restored.focusQuality, 4);
    expect(restored.toJson()['sessionFeel'], 'good');
    expect(restored.toJson()['focusQuality'], 4);
  });

  test('旧训练记录缺少心理字段时保持为空，不伪造中间值', () {
    final TrainingLog restored = TrainingLog.fromJson(<String, dynamic>{
      'id': 'legacy',
      'workoutDayId': 'day-1',
      'date': '2026-07-27T08:00:00.000',
      'createdAt': '2026-07-27T08:00:00.000',
      'completed': true,
      'rpe': 6,
      'fatigueLevel': 5,
      'sleepQuality': 7,
    });

    expect(restored.sessionFeel, isNull);
    expect(restored.focusQuality, isNull);
  });

  test('越界专注质量按未采集处理', () {
    final TrainingLog restored = TrainingLog.fromJson(<String, dynamic>{
      'focusQuality': 9,
    });

    expect(restored.focusQuality, isNull);
  });
}
