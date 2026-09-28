import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainflow_ai/features/dashboard/today_training_page.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import '../../support/test_harness.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/daily_check_in_record.dart';
import 'package:trainflow_ai/data/models/health_snapshot.dart';
import 'package:trainflow_ai/features/dashboard/widgets/today_health_overview.dart';

void main() {
  final now = DateTime(2026, 9, 20, 12);
  BodyMetric body({Map<String, dynamic> changes = const {}}) =>
      BodyMetric.fromJson({
        'id': 'synthetic-body',
        'measuredAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
        'source': 'manual',
        'sleepHours': 7.0,
        'restingHeartRate': 60,
        'hrvMs': 50,
        ...changes,
      });
  HealthSnapshot snapshot({
    DateTime? date,
    DateTime? syncedAt,
    double? sleep = 8,
    int? heart = 55,
    int? hrv = 65,
    int lineage = 2,
    List<String> ids = const ['synthetic-sample'],
  }) =>
      HealthSnapshot(
        id: 'synthetic-snapshot',
        date: date ?? DateTime(2026, 9, 20),
        syncedAt: syncedAt ?? now.subtract(const Duration(minutes: 1)),
        sleepHours: sleep,
        restingHeartRate: heart,
        hrvMs: hrv,
        weightKg: null,
        bodyFatPercentage: null,
        sourceIds: ids,
        sourceLineageVersion: lineage,
      );
  TodayHealthOverviewData overview({
    List<HealthSnapshot> snapshots = const [],
    BodyMetric? metric,
    DateTime? evaluatedAt,
  }) =>
      TodayHealthOverviewData.fromSources(
        activitySummaries: const [],
        healthSnapshots: snapshots,
        latestBodyMetric: metric,
        checkInStreak: const CheckInStreakState.empty(),
        activityStatusMessage: '合成测试',
        now: evaluatedAt ?? now,
      );
  void expectMissing(TodayHealthOverviewData result) {
    expect(result.sleepHours, isNull);
    expect(result.restingHeartRate, isNull);
    expect(result.hrvMs, isNull);
  }

  test('当日有样本血缘的健康摘要优先，身体数据逐字段回退', () {
    final result =
        overview(snapshots: [snapshot(heart: null, hrv: 0)], metric: body());
    expect(result.sleepHours, 8);
    expect(result.restingHeartRate, 60);
    expect(result.hrvMs, 50);
  });
  test('只有旧日或未来日数据时三项保持缺失', () {
    expectMissing(overview(
        snapshots: [
          snapshot(date: DateTime(2026, 9, 19)),
          snapshot(date: DateTime(2026, 9, 21)),
        ],
        metric: body(
            changes: {'measuredAt': DateTime(2026, 9, 19).toIso8601String()})));
  });
  for (final changes in [
    {'source': 'unknown'},
    {'sourceVerified': false},
    {
      'recordedFields': ['weightKg']
    },
    {'measuredAt': now.add(const Duration(seconds: 1)).toIso8601String()},
  ]) {
    test('身体记录来源、实际字段或时间无效不能回退：$changes', () {
      expectMissing(overview(metric: body(changes: changes)));
    });
  }
  for (final invalid in [
    snapshot(lineage: 1),
    snapshot(ids: []),
    snapshot(ids: [' ']),
    snapshot(syncedAt: now.add(const Duration(seconds: 1))),
    snapshot(syncedAt: DateTime.fromMillisecondsSinceEpoch(0)),
    snapshot(syncedAt: DateTime(2026, 9, 19, 23)),
  ]) {
    test(
        '无法确认来源或同步时间异常的摘要不作为今日观测：${invalid.syncedAt}/${invalid.sourceLineageVersion}/${invalid.sourceIds}',
        () {
      expectMissing(overview(snapshots: [invalid]));
    });
  }
  test('最新同日摘要缺项不能从较旧同步结果复活字段', () {
    final result = overview(snapshots: [
      snapshot(syncedAt: now.subtract(const Duration(hours: 2))),
      snapshot(sleep: null, heart: null, hrv: null),
    ]);
    expectMissing(result);
  });
  test('最近摘要来源不明时也不能回退到较旧摘要', () {
    expectMissing(overview(snapshots: [
      snapshot(syncedAt: now.subtract(const Duration(hours: 2))),
      snapshot(lineage: 1),
    ]));
  });
  test('零、负数和非有限数不显示为恢复观测', () {
    for (final value in [0.0, -1.0, double.nan, double.infinity]) {
      expectMissing(
          overview(snapshots: [snapshot(sleep: value, heart: 0, hrv: -1)]));
    }
  });
  test('同一时刻的 UTC 与本地表示得到相同今日数据', () {
    final result = overview(
      evaluatedAt: now.toUtc(),
      snapshots: [snapshot(date: DateTime(2026, 9, 20).toUtc())],
      metric: body(changes: {'measuredAt': now.toUtc().toIso8601String()}),
    );
    expect(result.sleepHours, 8);
    expect(result.restingHeartRate, 55);
    expect(result.hrvMs, 65);
  });

  test('混合来源逐项标注日期，样本标识不进入展示', () {
    final result = overview(
        snapshots: [snapshot(heart: null, hrv: null)],
        metric: body(changes: {
          'recordedFields': ['restingHeartRate']
        }));
    expect(result.recoveryEvidence, contains('睡眠：2026-09-20 · Apple 健康摘要'));
    expect(result.recoveryEvidence, contains('静息心率：2026-09-20 · 手动录入'));
    expect(result.recoveryEvidence, contains('HRV：今日无可用记录'));
    expect(result.recoveryEvidence, contains('记录不等于今日状态已确认'));
    expect(result.recoveryEvidence, isNot(contains('synthetic-sample')));
  });

  test('本地日晚间的 UTC 表示和跨午夜缺失边界', () {
    final evening = DateTime(2026, 9, 20, 23, 59);
    final metric =
        body(changes: {'measuredAt': evening.toUtc().toIso8601String()});
    expect(
        overview(metric: metric, evaluatedAt: evening.toUtc()).sleepHours, 7);
    expectMissing(overview(
        metric: metric, evaluatedAt: evening.add(const Duration(minutes: 2))));
  });

  testWidgets('首页健康概览读取当日记录，不被未来新记录遮住，浏览不写入', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final current = DateTime.now();
    final storage = InMemoryLocalStorageService();
    storage.saveJson('trainflow.body_metrics.v1', {
      'metrics': [
        body(changes: {
          'id': 'current',
          'measuredAt': current.toIso8601String()
        }).toJson(),
        body(changes: {
          'id': 'future',
          'measuredAt': current.add(const Duration(days: 1)).toIso8601String(),
          'sleepHours': 12
        }).toJson(),
      ]
    });
    final before = storage.readJson('trainflow.body_metrics.v1');
    await tester.pumpWidget(TestHarness(storageService: storage).buildApp(
        const MaterialApp(home: Scaffold(body: TodayTrainingPage()))));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TodayTrainingPage)));
    final plan = container.read(trainingMvpProvider).activePlan.toJson();
    final data = tester
        .widget<TodayHealthOverview>(find.byType(TodayHealthOverview))
        .data;
    expect(data.sleepHours, 7);
    expect(data.restingHeartRate, 60);
    expect(data.hrvMs, 50);
    expect(data.recoveryEvidence, contains('手动录入'));
    await tester.pumpAndSettle();
    expect(storage.readJson('trainflow.body_metrics.v1'), before);
    expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
    expect(container.read(trainingMvpProvider).activePlan.toJson(), plan);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 宽两倍字号恢复卡可查看缺失说明并进入签到', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = false;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: Scaffold(
          body: SingleChildScrollView(
              child: Padding(
        padding: const EdgeInsets.all(20),
        child: TodayHealthOverview(
          data: overview(),
          now: now,
          onOpenActivitySettings: () {},
          onOpenCheckIn: () => opened = true,
        ),
      ))),
    )));
    await tester.ensureVisible(find.text('睡眠与恢复'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final explanation = find.textContaining('HRV：今日无可用记录');
    await tester.ensureVisible(explanation);
    await tester.pumpAndSettle();
    expect(explanation.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('睡眠与恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('睡眠与恢复'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });
}
