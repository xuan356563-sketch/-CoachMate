import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/core/theme/tdesign_theme.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/features/growth/application/training_metrics_provider.dart';
import 'package:trainflow_ai/features/training_plan/application/adjustment_proposal_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/plan_adjustment_controller.dart';
import 'package:trainflow_ai/features/training_plan/plan_list_page.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/training_metrics_engine.dart';

void main() {
  testWidgets('计划页展示待确认差异，用户确认后才写入计划调整', (WidgetTester tester) async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    PersistedUserProfileRepository(storage).saveProfile(
      InMemoryUserProfileRepository.defaultProfile.copyWith(
        id: 'athlete-a',
        mainSports: const <MainSport>[MainSport.marathon],
        weeklyTrainingDays: 4,
      ),
    );
    final InMemoryTrainingMetricsRepository metrics =
        InMemoryTrainingMetricsRepository();
    await metrics.saveAggregate(_metric());
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        trainingMetricsRepositoryProvider.overrideWithValue(metrics),
        acwrAdjustmentNowProvider.overrideWithValue(
          DateTime(2026, 7, 15, 12),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: const PlanListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('待确认的负荷调整'), findsOneWidget);
    expect(find.text('确认应用'), findsOneWidget);
    expect(
      container.read(planAdjustmentControllerProvider).adjustments,
      isEmpty,
    );

    await tester.ensureVisible(find.text('确认应用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();

    expect(find.text('已应用'), findsOneWidget);
    expect(find.text('撤销本次调整'), findsOneWidget);
    expect(
      container.read(planAdjustmentControllerProvider).adjustments,
      hasLength(1),
    );
  });
}

MetricAggregate _metric() {
  return MetricAggregate(
    id: 'metric-acwr-ui',
    athleteProfileId: 'athlete-a',
    metricCode: 'acwr.session_rpe',
    period: MetricPeriod.week,
    periodStart: DateTime(2026, 7, 13),
    value: 1.6,
    unit: 'ratio',
    sampleCount: 28,
    sampleDurationSeconds: 120000,
    coverage: 1,
    status: MetricStatus.ready,
    algorithmVersion: TrainingMetricsEngine.acwrAlgorithmVersion,
    inputFingerprint: 'acwr-input',
    computedAt: DateTime(2026, 7, 15, 10),
    loadMethod: LoadMethod.sessionRpe,
    metadata: const <String, Object?>{
      'windowCoverageVerified': true,
      'acuteTotal': 2100.0,
      'chronicTotal': 2800.0,
      'reason': '同口径完整窗口。',
    },
  );
}
