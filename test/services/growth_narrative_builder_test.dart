import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/services/growth_narrative_builder.dart';

void main() {
  test('周报叙事完全本地确定，且将高负荷建议表达为待确认', () {
    final DateTime now = DateTime(2026, 7, 15);
    final MetricAggregate consistency = MetricAggregate(
      id: 'metric-1',
      athleteProfileId: 'athlete-1',
      metricCode: 'weekly_consistency',
      period: MetricPeriod.week,
      periodStart: DateTime(2026, 7, 13),
      value: 0.75,
      unit: 'ratio',
      sampleCount: 4,
      sampleDurationSeconds: 0,
      coverage: 1,
      status: MetricStatus.ready,
      algorithmVersion: 'l1-v1',
      inputFingerprint: 'fingerprint',
      computedAt: now,
    );
    final AcwrResult acwr = AcwrResult(
      status: MetricStatus.ready,
      method: LoadMethod.sessionRpe,
      ratio: 1.6,
      acuteTotal: 1200,
      chronicTotal: 3000,
      coverage: 1,
      reason: '同口径 28 天数据完整。',
    );
    final AdjustmentProposal proposal = AdjustmentProposal(
      id: 'proposal-1',
      athleteProfileId: 'athlete-1',
      planId: 'plan-1',
      workoutDayId: 'day-1',
      workoutTitle: '间歇跑',
      triggerMetricCode: 'acwr.session_rpe',
      triggerAlgorithmVersion: 'acwr-v1',
      explanation: '负荷信号偏高，建议降低下一次高强度训练。',
      originalMinutes: 60,
      adjustedMinutes: 60,
      originalIntensity: '高强度',
      adjustedIntensity: '降低一级',
      status: AdjustmentProposalStatus.proposed,
      createdAt: now,
    );
    final GrowthNarrativeBuilder builder = GrowthNarrativeBuilder();

    final String first = builder.buildWeeklyReport(
      metrics: <MetricAggregate>[consistency],
      acwr: acwr,
      proposal: proposal,
    );
    final String second = builder.buildWeeklyReport(
      metrics: <MetricAggregate>[consistency],
      acwr: acwr,
      proposal: proposal,
    );

    expect(first, second);
    expect(first, contains('本周训练执行率为 75%'));
    expect(first, contains('等待你的确认'));
    expect(first, isNot(contains('自动修改')));
    expect(first, isNot(contains('伤病预测')));
  });

  test('月报仅在满足有效日门槛时展示身体均值，并区分设备分段与正式 PB', () {
    const GrowthNarrativeBuilder builder = GrowthNarrativeBuilder();
    final String narrative = builder.buildMonthlyReport(
      metrics: const <MetricAggregate>[],
      bodyAverage: SevenDayBodyAverageResult(
        status: MetricStatus.ready,
        average: 69.3,
        dailyMedians: <DateTime, double>{
          DateTime(2026, 7, 13): 69,
          DateTime(2026, 7, 14): 69.5,
          DateTime(2026, 7, 15): 69.4,
        },
        validDayCount: 3,
        remainingDays: 0,
      ),
      bestSegment: const DeviceBestSegment(
        sourceId: 'route-1',
        distanceMeters: 5000,
        durationSeconds: 1200,
        isOfficialRaceResult: false,
      ),
    );

    expect(narrative, contains('3 个有效日'));
    expect(narrative, contains('设备记录最佳分段'));
    expect(narrative, contains('不作为正式 PB'));
  });
}
