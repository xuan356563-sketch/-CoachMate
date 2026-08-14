import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/training_log.dart';

void main() {
  test('逐组记录支持不同重量次数 RPE 和用时并可往返序列化', () {
    const ExerciseExecutionRecord record = ExerciseExecutionRecord(
      exerciseId: 'squat',
      exerciseName: '深蹲',
      plannedSetCount: 3,
      completedSetCount: 2,
      repetitionsPerSet: 0,
      weightKg: 65,
      sets: <StrengthSetExecutionRecord>[
        StrengthSetExecutionRecord(
          setIndex: 1,
          repetitions: 10,
          weightKg: 60,
          rpe: 7,
          durationSeconds: 42,
        ),
        StrengthSetExecutionRecord(
          setIndex: 2,
          repetitions: 8,
          weightKg: 65,
          rpe: 8,
          durationSeconds: 48,
        ),
      ],
    );

    final ExerciseExecutionRecord restored =
        ExerciseExecutionRecord.fromJson(record.toJson());

    expect(restored.sets, hasLength(2));
    expect(restored.sets.first.weightKg, 60);
    expect(restored.sets.last.repetitions, 8);
    expect(restored.sets.last.rpe, 8);
    expect(restored.sets.last.durationSeconds, 48);
    expect(restored.completedSetCount, 2);
    expect(restored.setSummary, contains('60.0 kg × 10'));
    expect(restored.setSummary, contains('65.0 kg × 8'));
  });

  test('旧动作级汇总仍可读取但不会伪装成真实逐组数据', () {
    final ExerciseExecutionRecord legacy =
        ExerciseExecutionRecord.fromJson(<String, dynamic>{
      'exerciseId': 'squat',
      'exerciseName': '深蹲',
      'plannedSetCount': 3,
      'completedSetCount': 3,
      'repetitionsPerSet': 8,
      'weightKg': 60,
    });

    expect(legacy.sets, isEmpty);
    expect(legacy.completedSetCount, 3);
    expect(legacy.setSummary, contains('3/3 组'));
  });

  test('落地质量只作为本地动作记录的可选字段保存', () {
    const ExerciseExecutionRecord record = ExerciseExecutionRecord(
      exerciseId: 'exercise-drop-landing',
      exerciseName: '下落着地',
      plannedSetCount: 3,
      completedSetCount: 3,
      repetitionsPerSet: 4,
      weightKg: 0,
      landingQuality: LandingQuality.stable,
    );

    final ExerciseExecutionRecord restored =
        ExerciseExecutionRecord.fromJson(record.toJson());

    expect(restored.landingQuality, LandingQuality.stable);
    expect(record.toJson()['landingQuality'], 'stable');
  });
}
