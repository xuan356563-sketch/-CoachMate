import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/plan_adjustment.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/features/growth/application/training_metrics_provider.dart';
import 'package:trainflow_ai/features/training_plan/application/adjustment_proposal_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/plan_adjustment_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/training_metrics_engine.dart';

void main() {
  test('高 ACWR 只先持久化预览，确认后应用且可撤销', () async {
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
    await metrics.saveAggregate(_acwrMetric(value: 1.6));
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

    final AdjustmentProposalState initial = await container.read(
      acwrAdjustmentProposalControllerProvider.future,
    );
    final AdjustmentProposal proposal = initial.proposals.single;
    expect(proposal.status, AdjustmentProposalStatus.proposed);
    expect(proposal.workoutDayId, isNotNull);
    expect(
      container.read(planAdjustmentControllerProvider).adjustments,
      isEmpty,
    );

    await container
        .read(acwrAdjustmentProposalControllerProvider.notifier)
        .confirm(proposal.id, at: DateTime(2026, 7, 15, 13));

    AdjustmentProposalState current =
        container.read(acwrAdjustmentProposalControllerProvider).requireValue;
    expect(
      current.proposals.single.status,
      AdjustmentProposalStatus.confirmed,
    );
    PlanAdjustment adjustment =
        container.read(planAdjustmentControllerProvider).adjustments.first;
    expect(adjustment.sourceProposalId, proposal.id);
    expect(adjustment.adjustedIntensity, proposal.adjustedIntensity);
    expect(
      (await metrics.listAdjustmentProposals(athleteProfileId: 'athlete-a'))
          .single
          .status,
      AdjustmentProposalStatus.confirmed,
    );

    await container
        .read(acwrAdjustmentProposalControllerProvider.notifier)
        .undo(proposal.id, at: DateTime(2026, 7, 15, 14));

    current =
        container.read(acwrAdjustmentProposalControllerProvider).requireValue;
    expect(current.proposals.single.status, AdjustmentProposalStatus.undone);
    adjustment =
        container.read(planAdjustmentControllerProvider).adjustments.first;
    expect(adjustment.kind, PlanAdjustmentKind.restored);
    expect(adjustment.adjustedIntensity, proposal.originalIntensity);
  });

  test('没有高强度项时按不可变快照原子降低周总量并可整组撤销', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    PersistedUserProfileRepository(storage).saveProfile(
      InMemoryUserProfileRepository.defaultProfile.copyWith(
        id: 'athlete-a',
        mainSports: const <MainSport>[MainSport.strength],
        weeklyTrainingDays: 3,
      ),
    );
    final InMemoryTrainingMetricsRepository metrics =
        InMemoryTrainingMetricsRepository();
    await metrics.saveAggregate(_acwrMetric(value: 1.6));
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

    final AdjustmentProposalState initial = await container.read(
      acwrAdjustmentProposalControllerProvider.future,
    );
    final AdjustmentProposal proposal = initial.proposals.single;
    expect(proposal.workoutDayId, isNull);
    expect(proposal.workoutChanges, isNotEmpty);
    expect(
      proposal.workoutChanges.fold<int>(
        0,
        (int total, AdjustmentProposalWorkoutChange change) =>
            total + change.originalMinutes,
      ),
      proposal.originalMinutes,
    );

    await container
        .read(acwrAdjustmentProposalControllerProvider.notifier)
        .confirm(proposal.id, at: DateTime(2026, 7, 15, 13));

    AdjustmentProposalState current =
        container.read(acwrAdjustmentProposalControllerProvider).requireValue;
    expect(current.proposals.single.status, AdjustmentProposalStatus.confirmed);
    expect(current.statusMessage, contains('原子应用'));
    final List<PlanAdjustment> applied = container
        .read(planAdjustmentControllerProvider)
        .adjustments
        .where((PlanAdjustment item) => item.sourceProposalId == proposal.id)
        .toList();
    expect(applied, hasLength(proposal.workoutChanges.length));
    expect(
      applied.fold<int>(
        0,
        (int total, PlanAdjustment item) =>
            total + item.adjustedEstimatedMinutes,
      ),
      proposal.adjustedMinutes,
    );

    await container
        .read(acwrAdjustmentProposalControllerProvider.notifier)
        .undo(proposal.id, at: DateTime(2026, 7, 15, 14));

    current =
        container.read(acwrAdjustmentProposalControllerProvider).requireValue;
    expect(current.proposals.single.status, AdjustmentProposalStatus.undone);
    expect(current.statusMessage, contains('整组撤销'));
    for (final AdjustmentProposalWorkoutChange change
        in proposal.workoutChanges) {
      final PlanAdjustment latest = container
          .read(planAdjustmentControllerProvider)
          .adjustments
          .firstWhere(
            (PlanAdjustment item) => item.workoutDayId == change.workoutDayId,
          );
      expect(latest.kind, PlanAdjustmentKind.restored);
      expect(latest.adjustedEstimatedMinutes, change.originalMinutes);
    }
  });

  test('ACWR 不高于 1.5 时不生成加量或减量建议', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    PersistedUserProfileRepository(storage).saveProfile(
      InMemoryUserProfileRepository.defaultProfile.copyWith(id: 'athlete-a'),
    );
    final InMemoryTrainingMetricsRepository metrics =
        InMemoryTrainingMetricsRepository();
    await metrics.saveAggregate(_acwrMetric(value: 1.5));
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

    final AdjustmentProposalState state = await container.read(
      acwrAdjustmentProposalControllerProvider.future,
    );

    expect(state.proposals, isEmpty);
    expect(
      await metrics.listAdjustmentProposals(athleteProfileId: 'athlete-a'),
      isEmpty,
    );
  });

  test('新 ACWR 已回落时，旧的待确认建议不能再修改计划', () async {
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
    await metrics.saveAggregate(
      _acwrMetric(
        id: 'metric-high',
        value: 1.6,
        computedAt: DateTime(2026, 7, 15, 9),
      ),
    );
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
    final AdjustmentProposal oldProposal = (await container.read(
      acwrAdjustmentProposalControllerProvider.future,
    ))
        .proposals
        .single;

    await metrics.saveAggregate(
      _acwrMetric(
        id: 'metric-low',
        value: 1.2,
        computedAt: DateTime(2026, 7, 15, 11),
      ),
    );
    container.invalidate(acwrAdjustmentProposalControllerProvider);
    await container.read(acwrAdjustmentProposalControllerProvider.future);

    await container
        .read(acwrAdjustmentProposalControllerProvider.notifier)
        .confirm(oldProposal.id);

    final AdjustmentProposalState current =
        container.read(acwrAdjustmentProposalControllerProvider).requireValue;
    expect(current.statusMessage, contains('触发指标或计划已更新'));
    expect(current.proposals.single.status, AdjustmentProposalStatus.proposed);
    expect(
      container.read(planAdjustmentControllerProvider).adjustments,
      isEmpty,
    );
  });
}

MetricAggregate _acwrMetric({
  String id = 'metric-acwr',
  required double value,
  DateTime? computedAt,
}) {
  return MetricAggregate(
    id: id,
    athleteProfileId: 'athlete-a',
    metricCode: 'acwr.session_rpe',
    period: MetricPeriod.week,
    periodStart: DateTime(2026, 7, 13),
    value: value,
    unit: 'ratio',
    sampleCount: 28,
    sampleDurationSeconds: 120000,
    coverage: 1,
    status: MetricStatus.ready,
    algorithmVersion: TrainingMetricsEngine.acwrAlgorithmVersion,
    inputFingerprint: 'acwr-input',
    computedAt: computedAt ?? DateTime(2026, 7, 15, 10),
    loadMethod: LoadMethod.sessionRpe,
    metadata: const <String, Object?>{
      'windowCoverageVerified': true,
      'acuteTotal': 2100.0,
      'chronicTotal': 2800.0,
      'reason': '同口径完整窗口。',
    },
  );
}
