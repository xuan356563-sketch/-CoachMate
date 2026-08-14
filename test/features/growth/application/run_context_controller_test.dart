import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/local/trainmate_structured_database_gateway.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/features/growth/application/run_context_controller.dart';
import 'package:trainflow_ai/features/growth/growth_evidence_page.dart';
import 'package:trainflow_ai/services/local_report_generation_coordinator.dart';

void main() {
  test('待确认事实解析保留日期、距离和时长摘要', () {
    final RunContextReviewItem item = RunContextReviewItem.fromRow(
      <String, Object?>{
        'id': 'workout-a',
        'started_at_utc': '2026-07-15T08:00:00.000Z',
        'local_date': '2026-07-15',
        'distance_meters': 10000,
        'active_duration_seconds': 3600,
        'source_bundle_id': 'com.apple.health',
        'source_product_type': 'Watch',
      },
    );

    expect(item.workoutId, 'workout-a');
    expect(item.localDate, DateTime(2026, 7, 15));
    expect(item.distanceMeters, 10000);
    expect(item.durationSeconds, 3600);
  });

  testWidgets('用户确认越野跑后只保存明确选择，不自动猜测', (WidgetTester tester) async {
    final _FakeRunContextDatabase database = _FakeRunContextDatabase();
    final RunContextConfirmationService service = RunContextConfirmationService(
      database: database,
      metricsPipeline: null,
      reportCoordinator: LocalReportGenerationCoordinator(
        repository: InMemoryTrainingMetricsRepository(),
      ),
      clock: () => DateTime.utc(2026, 7, 16),
    );
    final RunContextReviewItem item = RunContextReviewItem(
      workoutId: 'workout-a',
      startedAt: DateTime.utc(2026, 7, 15, 8),
      localDate: DateTime(2026, 7, 15),
      distanceMeters: 10000,
      durationSeconds: 3600,
      sourceBundleId: 'com.apple.health',
      sourceProductType: 'Watch',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runContextConfirmationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RunContextReviewCard(
                athleteProfileId: 'athlete-a',
                reviews: AsyncData<List<RunContextReviewItem>>(
                    <RunContextReviewItem>[item]),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('不会把训练猜成'), findsOneWidget);
    await tester.tap(find.text('越野跑'));
    await tester.pumpAndSettle();

    expect(database.confirmations, hasLength(1));
    expect(database.confirmations.single.runContext, 'trail');
    expect(database.confirmations.single.workoutId, 'workout-a');
    expect(find.textContaining('已确认为越野跑'), findsOneWidget);
  });
}

class _FakeRunContextDatabase implements RunContextDatabaseGateway {
  final List<({String workoutId, String runContext})> confirmations =
      <({String workoutId, String runContext})>[];

  @override
  Future<void> confirmRunningWorkoutContext({
    required String athleteProfileId,
    required String workoutId,
    required String runContext,
    required DateTime confirmedAt,
  }) async {
    confirmations.add((workoutId: workoutId, runContext: runContext));
  }

  @override
  Future<List<Map<String, Object?>>> listRunningWorkoutsNeedingContext({
    required String athleteProfileId,
    int limit = 20,
  }) async =>
      const <Map<String, Object?>>[];
}
