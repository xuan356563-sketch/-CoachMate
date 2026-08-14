import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/growth_evidence.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/features/growth/growth_evidence_page.dart';
import 'package:trainflow_ai/features/weekly_report/weekly_report_page.dart';

void main() {
  testWidgets('进步页没有手表数据时仍显示 L2/L3 和积累说明', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GrowthMetricsOverview(
              metrics: AsyncData<List<MetricAggregate>>(<MetricAggregate>[]),
            ),
          ),
        ),
      ),
    );

    expect(find.text('训练适应（L2）'), findsOneWidget);
    expect(find.text('长期结果（L3）'), findsOneWidget);
    expect(find.textContaining('无手表也可继续使用计划'), findsOneWidget);
    expect(find.textContaining('数据积累中'), findsWidgets);
    expect(find.textContaining('身体慢变量仅在月报'), findsOneWidget);
  });

  testWidgets('进步指标逐项显示剩余量和失效状态', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GrowthMetricsOverview(
              metrics: AsyncData<List<MetricAggregate>>(
                <MetricAggregate>[
                  _metric(
                    id: 'same-pace',
                    metricCode: 'same_pace_heart_rate',
                    status: MetricStatus.accumulating,
                    metadata: const <String, Object?>{'remainingMinutes': 2},
                  ),
                  _metric(
                    id: 'body-weight',
                    metricCode: 'body_weight_7d',
                    status: MetricStatus.invalidated,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('还需 2 分钟'), findsOneWidget);
    expect(find.textContaining('等待重算'), findsOneWidget);
  });

  testWidgets('周报兼容摘要只使用训练执行指数和本周有效训练日语义', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeeklyGrowthCompatibilitySummary(
            report: _weeklyReport(),
            effectiveTrainingDays: 2,
          ),
        ),
      ),
    );

    expect(find.text('训练执行指数'), findsOneWidget);
    expect(find.text('本周有效训练日'), findsOneWidget);
    expect(find.textContaining('成长指数'), findsNothing);
    expect(find.textContaining('连续'), findsNothing);
  });

  testWidgets('周报仓库没有修订时显示数据积累和兼容层说明', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LocalReportRevisionCard(
            reports: AsyncData<List<ReportRevision>>(<ReportRevision>[]),
          ),
        ),
      ),
    );

    expect(find.text('本地确定性周报'), findsOneWidget);
    expect(find.textContaining('数据积累中'), findsWidgets);
    expect(find.textContaining('兼容摘要'), findsOneWidget);
  });

  testWidgets('本地报告生成被拒绝时在卡片内显示中文提示', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalReportRevisionCard(
            reports: const AsyncData<List<ReportRevision>>(<ReportRevision>[]),
            onGenerate: () async {
              throw StateError('指标仍在积累，不能生成空报告修订。');
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('生成新的本地修订'));
    await tester.pumpAndSettle();

    expect(find.textContaining('指标仍在积累'), findsOneWidget);
  });

  testWidgets('本地报告输入未变化时不重复生成修订', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalReportRevisionCard(
            reports: const AsyncData<List<ReportRevision>>(<ReportRevision>[]),
            onGenerate: () async => false,
          ),
        ),
      ),
    );

    await tester.tap(find.text('生成新的本地修订'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未重复生成'), findsOneWidget);
  });
}

MetricAggregate _metric({
  required String id,
  required String metricCode,
  required MetricStatus status,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return MetricAggregate(
    id: id,
    athleteProfileId: 'athlete-1',
    metricCode: metricCode,
    period: MetricPeriod.week,
    periodStart: DateTime(2026, 7, 13),
    value: null,
    unit: '',
    sampleCount: 0,
    sampleDurationSeconds: 0,
    coverage: 0,
    status: status,
    algorithmVersion: 'test-v1',
    inputFingerprint: 'input-$id',
    computedAt: DateTime(2026, 7, 15),
    metadata: metadata,
  );
}

WeeklyGrowthReport _weeklyReport() {
  return WeeklyGrowthReport(
    id: 'legacy-week-1',
    athleteProfileId: 'athlete-1',
    weekKey: '2026-07-13',
    weekStartsOn: DateTime(2026, 7, 13),
    weekEndsOn: DateTime(2026, 7, 19),
    generatedAt: DateTime(2026, 7, 20),
    lockedAt: null,
    regeneratedAt: null,
    consecutiveTrainingDays: 2,
    runningDistanceKm: 10,
    strengthSessionCount: 1,
    completionRate: 0.75,
    trainingLoad: 320,
    growthIndex: 72,
    availableIndexDimensions: 3,
    recoverySummary: '兼容摘要',
    evidenceEventIds: const <String>[],
    modelVersion: 1,
  );
}
