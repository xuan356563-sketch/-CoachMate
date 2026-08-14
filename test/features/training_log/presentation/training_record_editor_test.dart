import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/trainmate_structured_database_gateway.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/features/training_log/application/training_log_controller.dart';
import 'package:trainflow_ai/features/training_log/presentation/training_record_editor.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('设备训练热量只有点击采用后才保存来源和关联标识', (tester) async {
    final DateTime now = DateTime.now();
    final _EnergyGateway gateway = _EnergyGateway(now);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
        healthSyncStructuredDatabaseGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    final TrainingMvpState state = container.read(trainingMvpProvider);
    final WorkoutDay workout = state.activePlan.workoutDays.firstWhere(
      (WorkoutDay item) => item.trainingType == TrainingType.strength,
      orElse: () => state.todayWorkout,
    );
    gateway.discipline = _disciplineFor(workout.trainingType);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: TrainingRecordEditor(workout: workout),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('设备训练建议：321 千卡'), findsOneWidget);
    final TextField completedSets = tester.widget<TextField>(
      find.byKey(
        const ValueKey<String>(
          'workout-review-exercise-0-completed-sets-field',
        ),
      ),
    );
    expect(completedSets.controller?.text, isNotEmpty);
    await tester.tap(find.widgetWithText(TextButton, '采用'));
    await tester.pumpAndSettle();
    final TextField energyField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('training-record-energy-field')),
    );
    expect(energyField.controller?.text, '321');

    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    final TrainingLog log =
        container.read(trainingLogControllerProvider).single;
    expect(log.energyKcal, 321);
    expect(log.energySource, TrainingEnergySource.healthKitConfirmed);
    expect(log.deviceWorkoutId, 'health-workout-suggestion');
  });
}

class _EnergyGateway implements TrainMateStructuredDatabaseGateway {
  _EnergyGateway(this.now);

  final DateTime now;
  String discipline = 'other';

  @override
  Future<List<Map<String, Object?>>> listWorkoutFactRows({
    required String athleteProfileId,
    required String startedAtOrAfter,
    required String startedBefore,
  }) async {
    final String date = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return <Map<String, Object?>>[
      <String, Object?>{
        'id': 'health-workout-suggestion',
        'source_kind': 'healthKit',
        'discipline': discipline,
        'local_date': date,
        'started_at_utc': now.toUtc().toIso8601String(),
        'elapsed_duration_seconds': 60 * 60,
        'energy_kcal': 321.0,
      },
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试未实现的结构化数据库调用。');
}

String _disciplineFor(TrainingType type) {
  return switch (type) {
    TrainingType.easyRun ||
    TrainingType.tempoRun ||
    TrainingType.intervalRun ||
    TrainingType.longRun =>
      'roadRun',
    TrainingType.strength => 'strength',
    TrainingType.hyrox => 'hiit',
    TrainingType.mobility ||
    TrainingType.rehab ||
    TrainingType.rest =>
      'stretching',
    TrainingType.crossTraining => 'other',
  };
}
