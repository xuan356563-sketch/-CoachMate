import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/features/training_plan/application/adjustment_proposal_controller.dart';

void main() {
  test('建议在确认前不投影，确认和撤销均保留可审计状态', () {
    final _FakeProjection projection = _FakeProjection();
    final AdjustmentProposalController controller =
        AdjustmentProposalController(projection: projection);
    final AdjustmentProposal proposal = AdjustmentProposal(
      id: 'proposal-1',
      athleteProfileId: 'athlete-1',
      planId: 'plan-1',
      workoutDayId: 'day-1',
      workoutTitle: '间歇跑',
      triggerMetricCode: 'acwr.session_rpe',
      triggerAlgorithmVersion: 'acwr-v1',
      explanation: '负荷偏高，建议降低一级。',
      originalMinutes: 60,
      adjustedMinutes: 60,
      originalIntensity: '高强度',
      adjustedIntensity: '降低一级',
      status: AdjustmentProposalStatus.proposed,
      createdAt: DateTime(2026, 7, 15),
    );

    controller.propose(proposal);
    expect(projection.confirmedIds, isEmpty);
    expect(controller.state.proposals.single.status,
        AdjustmentProposalStatus.proposed);

    controller.confirm('proposal-1', at: DateTime(2026, 7, 15, 10));
    expect(projection.confirmedIds, <String>['proposal-1']);
    expect(controller.state.proposals.single.status,
        AdjustmentProposalStatus.confirmed);

    controller.undo('proposal-1', at: DateTime(2026, 7, 15, 11));
    expect(projection.undoneIds, <String>['proposal-1']);
    expect(controller.state.proposals.single.status,
        AdjustmentProposalStatus.undone);
  });
}

class _FakeProjection implements AdjustmentPlanProjection {
  final List<String> confirmedIds = <String>[];
  final List<String> undoneIds = <String>[];

  @override
  void confirm(AdjustmentProposal proposal) {
    confirmedIds.add(proposal.id);
  }

  @override
  void undo(AdjustmentProposal proposal) {
    undoneIds.add(proposal.id);
  }
}
