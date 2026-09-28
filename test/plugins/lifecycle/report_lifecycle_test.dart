import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/models/growth_evidence.dart';
import 'package:trainflow_ai/data/models/weekly_report.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/data/repositories/weekly_report_repository.dart';
import 'package:trainflow_ai/features/growth/application/growth_evidence_controller.dart';
import 'package:trainflow_ai/features/growth/application/growth_metrics_controller.dart';
import 'package:trainflow_ai/features/growth/application/training_metrics_provider.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/history/core_history.dart';
import 'package:trainflow_ai/services/local_report_generation_coordinator.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('报告生成与保存服务深层受控，停用后历史仍可读', () async {
    final PluginRuntime runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    final InMemoryTrainingMetricsRepository repository =
        InMemoryTrainingMetricsRepository();
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final PersistedGrowthEvidenceRepository growthRepository =
        PersistedGrowthEvidenceRepository(storage);
    final DateTime weekStart = DateTime(2026, 8, 24);
    PersistedWeeklyReportRepository(storage).saveReport(WeeklyReport(
      id: 'legacy-weekly-report',
      weekLabel: '2026-08-24',
      generatedAt: DateTime(2026, 8, 31),
      completedWorkouts: 3,
      plannedWorkouts: 4,
      completionRate: 0.75,
      loadTrendLabel: '稳定',
      decisionReview: '保持当前节奏',
      recoverySummary: '恢复稳定',
      highlights: const <String>['完成三次训练'],
      nextWeekFocus: const <String>['继续稳定执行'],
    ));
    await growthRepository.saveWeeklyReport(WeeklyGrowthReport(
      id: 'growth-weekly-report',
      athleteProfileId: 'athlete-a',
      weekKey: '2026-08-24',
      weekStartsOn: weekStart,
      weekEndsOn: DateTime(2026, 8, 30),
      generatedAt: DateTime(2026, 8, 31),
      lockedAt: DateTime(2026, 8, 31),
      regeneratedAt: null,
      consecutiveTrainingDays: 3,
      runningDistanceKm: 12,
      strengthSessionCount: 1,
      completionRate: 0.75,
      trainingLoad: 180,
      growthIndex: 72,
      availableIndexDimensions: 4,
      recoverySummary: '恢复稳定',
      evidenceEventIds: const <String>[],
      modelVersion: 1,
    ));
    await repository.saveAggregate(MetricAggregate(
      id: 'weekly-metric',
      athleteProfileId: 'athlete-a',
      metricCode: 'weekly_consistency',
      period: MetricPeriod.week,
      periodStart: weekStart,
      value: 0.8,
      unit: 'ratio',
      sampleCount: 3,
      sampleDurationSeconds: 0,
      coverage: 1,
      status: MetricStatus.ready,
      algorithmVersion: 'test-v1',
      inputFingerprint: 'input-v1',
      computedAt: DateTime(2026, 8, 31),
    ));
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      trainingMetricsRepositoryProvider.overrideWithValue(repository),
      growthEvidenceRepositoryProvider.overrideWithValue(growthRepository),
    ]);
    addTearDown(container.dispose);
    final GrowthMetricsController reports =
        container.read(growthMetricsControllerProvider);
    final LocalReportGenerationCoordinator coordinator =
        container.read(localReportGenerationCoordinatorProvider);
    expect(
      runtime
          .service('feature.weekly_report')!
          .read<GrowthMetricsController>('reportGenerator'),
      same(reports),
    );
    expect(
      runtime
          .service('feature.weekly_report')!
          .read<LocalReportGenerationCoordinator>('coordinator'),
      same(coordinator),
    );
    await reports.loadPeriod(
      athleteProfileId: 'athlete-a',
      period: MetricPeriod.week,
      periodStart: weekStart,
    );
    await reports.generateWeeklyReport();

    await runtime.disable('feature.weekly_report');
    await runtime.disable('feature.growth');
    await reports.loadPeriod(
      athleteProfileId: 'athlete-a',
      period: MetricPeriod.week,
      periodStart: weekStart,
    );
    expect(reports.state.reports, hasLength(1));
    await expectLater(reports.generateWeeklyReport(), throwsStateError);
    await expectLater(
      coordinator.ensureClosedPeriod(
        athleteProfileId: 'athlete-a',
        period: MetricPeriod.week,
        periodStart: weekStart,
      ),
      throwsStateError,
    );
    expect(
      await repository.listReportRevisions(
        athleteProfileId: 'athlete-a',
        period: MetricPeriod.week,
        periodStart: weekStart,
      ),
      hasLength(1),
    );
    final CoreHistory history = container.read(coreHistoryProvider);
    expect(history.listWeeklyReports().single.id, 'legacy-weekly-report');
    expect(
      (await history.listReportRevisions(
        athleteProfileId: 'athlete-a',
        period: MetricPeriod.week,
        periodStart: weekStart,
      ))
          .single
          .revision,
      1,
    );
    expect(
      (await history.listGrowthReports(athleteProfileId: 'athlete-a'))
          .single
          .id,
      'growth-weekly-report',
    );

    await runtime.enable('feature.growth');
    await runtime.enable('feature.weekly_report');
    await container.pump();
    expect(
      runtime
          .service('feature.weekly_report')!
          .read<GrowthMetricsController>('reportGenerator'),
      same(reports),
    );
    final ReportRevision second = await reports.generateWeeklyReport();
    expect(second.revision, 2);
  });
}
