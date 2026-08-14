import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/features/training_log/application/training_energy_suggestion_service.dart';

void main() {
  final TrainingEnergySuggestionService service =
      TrainingEnergySuggestionService();

  Map<String, Object?> row({
    required String id,
    required String source,
    required String discipline,
    required String startedAt,
    required int durationSeconds,
    required double energyKcal,
  }) {
    return <String, Object?>{
      'id': id,
      'source_kind': source,
      'discipline': discipline,
      'local_date': '2026-08-03',
      'started_at_utc': startedAt,
      'elapsed_duration_seconds': durationSeconds,
      'energy_kcal': energyKcal,
    };
  }

  test('只从已同步的 HealthKit 训练给出热量建议', () {
    final TrainingEnergySuggestion? suggestion = service.select(
      rows: <Map<String, Object?>>[
        row(
          id: 'local',
          source: 'local_sessionReview',
          discipline: 'roadRun',
          startedAt: '2026-08-03T15:00:00.000Z',
          durationSeconds: 3600,
          energyKcal: 300,
        ),
        row(
          id: 'health',
          source: 'healthKit',
          discipline: 'roadRun',
          startedAt: '2026-08-03T15:05:00.000Z',
          durationSeconds: 3900,
          energyKcal: 371,
        ),
      ],
      activityType: TrainingActivityType.running,
      localDate: DateTime(2026, 8, 3),
      expectedStart: DateTime.utc(2026, 8, 3, 15),
      expectedDurationMinutes: 65,
    );

    expect(suggestion?.workoutId, 'health');
    expect(suggestion?.energyKcal, 371);
  });

  test('多个候选时选择开始时间和时长综合差异最小的唯一记录', () {
    final TrainingEnergySuggestion? suggestion = service.select(
      rows: <Map<String, Object?>>[
        row(
          id: 'far',
          source: 'healthKit',
          discipline: 'strength',
          startedAt: '2026-08-03T10:00:00.000Z',
          durationSeconds: 7200,
          energyKcal: 600,
        ),
        row(
          id: 'near',
          source: 'healthKit',
          discipline: 'strength',
          startedAt: '2026-08-03T15:10:00.000Z',
          durationSeconds: 3500,
          energyKcal: 280,
        ),
      ],
      activityType: TrainingActivityType.strength,
      localDate: DateTime(2026, 8, 3),
      expectedStart: DateTime.utc(2026, 8, 3, 15),
      expectedDurationMinutes: 60,
    );

    expect(suggestion?.workoutId, 'near');
  });

  test('类型不相容或最优候选并列时不提供不可靠建议', () {
    final Map<String, Object?> first = row(
      id: 'first',
      source: 'healthKit',
      discipline: 'roadRun',
      startedAt: '2026-08-03T14:50:00.000Z',
      durationSeconds: 3600,
      energyKcal: 300,
    );
    final Map<String, Object?> second = row(
      id: 'second',
      source: 'healthKit',
      discipline: 'roadRun',
      startedAt: '2026-08-03T15:10:00.000Z',
      durationSeconds: 3600,
      energyKcal: 310,
    );

    expect(
      service.select(
        rows: <Map<String, Object?>>[first],
        activityType: TrainingActivityType.swimming,
        localDate: DateTime(2026, 8, 3),
        expectedStart: DateTime.utc(2026, 8, 3, 15),
        expectedDurationMinutes: 60,
      ),
      isNull,
    );
    expect(
      service.select(
        rows: <Map<String, Object?>>[first, second],
        activityType: TrainingActivityType.running,
        localDate: DateTime(2026, 8, 3),
        expectedStart: DateTime.utc(2026, 8, 3, 15),
        expectedDurationMinutes: 60,
      ),
      isNull,
    );
  });
}
