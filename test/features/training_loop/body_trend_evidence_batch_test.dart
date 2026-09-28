import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/body_trend_insight.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/services/body_trend_insight_service.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/features/data_center/data_center_page.dart';

void main() {
  final now = DateTime(2026, 9, 19, 12);
  BodyMetric metric(int days,
          {double weight = 70,
          int heart = 60,
          int hrv = 50,
          double sleep = 7,
          bool verified = true,
          Set<String>? fields}) =>
      BodyMetric(
          id: 'synthetic-$days-$weight',
          measuredAt: now.subtract(Duration(days: days)),
          weightKg: weight,
          bodyFatPercentage: 18,
          restingHeartRate: heart,
          hrvMs: hrv,
          sleepHours: sleep,
          fatigueLevel: 3,
          sorenessLevel: 2,
          moodLabel: '合成',
          source: BodyMetricSource.manual,
          note: '合成测试',
          sourceVerified: verified,
          recordedFields: fields);
  BodyTrendInsightReport report(List<BodyMetric> metrics, {int days = 7}) =>
      BodyTrendInsightService().buildReport(
          bodyMetrics: metrics,
          profile: InMemoryUserProfileRepository.defaultProfile,
          acuteLoadScore: 0,
          now: now,
          windowDays: days);
  String overlays(BodyTrendInsightReport result) =>
      result.overlays.map((e) => e.description).join('；');

  test('自然日边界与同日未来时刻严格排除', () {
    BodyMetric at(DateTime date) => BodyMetric.fromJson(
        {...metric(0).toJson(), 'measuredAt': date.toIso8601String()});
    final result = report([
      at(DateTime(2026, 9, 13)),
      at(DateTime(2026, 9, 12, 23, 59, 59)),
      at(now.add(const Duration(minutes: 1)))
    ]);
    expect(result.weightTrendDetail, contains('2026-09-13 至 2026-09-19'));
    expect(result.weightTrendDetail, contains('1 个自然日'));
  });
  test('均值只取三个配对日，单边极值不污染叠加规则且原记录不变', () {
    final records = [
      ...List.generate(3, metric),
      metric(3, hrv: 1, fields: {'hrvMs'})
    ];
    final original = records.map((m) => m.toJson()).toList();
    final result = report(records);
    expect(overlays(result), contains('HRV 4 日、睡眠 3 日，同日配对 3 日'));
    expect(overlays(result), contains('HRV 50.0 ms'));
    expect(overlays(result), contains('未触发'));
    expect(records.map((m) => m.toJson()).toList(), original);
  });
  test('旧工程分界保留触发差异，但不生成降强度处方', () {
    final result =
        report(List.generate(3, (i) => metric(i, heart: 66, sleep: 5)));
    expect(overlays(result), contains('≥64'));
    expect(overlays(result), contains('）触发'));
    expect(overlays(result), isNot(contains('下一课先降强度')));
  });
  testWidgets('窄屏放大文字可阅读趋势证据，浏览不写本机文档', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = InMemoryLocalStorageService();
    final repository = PersistedBodyMetricRepository(storage);
    final today = DateTime.now();
    for (var i = 0; i < 3; i++) {
      repository.saveMetric(BodyMetric.fromJson({
        ...metric(i, fields: {'weightKg'}).toJson(),
        'measuredAt': today.subtract(Duration(days: i)).toIso8601String()
      }));
    }
    final before = storage.readJson('trainflow.body_metrics.v1');
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!),
            home: const Scaffold(body: DataCenterPage()))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('趋势洞察'), 600,
        scrollable: find.byType(Scrollable).first, maxScrolls: 60);
    await tester.pumpAndSettle();
    expect(find.textContaining('体重 3 个自然日有效记录'), findsOneWidget);
    expect(find.textContaining('HRV 0 日'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(storage.readJson('trainflow.body_metrics.v1'), before);
    expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
  });

  test('无数据和单日不能得出稳定或减脂安全结论', () {
    for (final records in [
      <BodyMetric>[],
      [metric(0)]
    ]) {
      final result = report(records);
      expect(result.weightTrendLabel, '无法评估');
      expect(result.fatLossProtectionLabel, '无法评估');
      expect(overlays(result), isNot(contains('可以维持')));
      expect(overlays(result), isNot(contains('恢复基础稳定')));
    }
  });
  test('重复同日不能制造三个样本日和短期趋势', () {
    final result = report([metric(0), metric(0), metric(0)]);
    expect(result.weightTrendLabel, '无法评估');
    expect(result.weightTrendDetail, contains('1 个自然日'));
  });
  test('未来陈旧和未知来源不能成为当前窗口事实', () {
    final result = report([metric(-1), metric(10), metric(1, verified: false)]);
    expect(result.weightTrendLabel, '无法评估');
    expect(result.weightTrendDetail, contains('0 个自然日'));
    expect(result.weightTrendDetail, contains('不纳入'));
  });
  test('继承值不进入均值或恢复叠加', () {
    final result =
        report(List.generate(3, (i) => metric(i, fields: {'weightKg'})));
    expect(result.weightTrendLabel, '基本稳定');
    expect(overlays(result), contains('静息心率 0 日'));
    expect(overlays(result), contains('HRV 0 日'));
    expect(overlays(result), isNot(contains('均值 50')));
    expect(overlays(result), contains('无法评估'));
  });
  test('叠加只使用同日成对有效指标，不拼接不同日', () {
    final result = report([
      metric(0, fields: {'hrvMs'}),
      metric(1, fields: {'sleepHours'}),
      metric(2, fields: {'hrvMs'}),
      metric(3, fields: {'sleepHours'}),
    ]);
    expect(overlays(result), contains('HRV 2 日'));
    expect(overlays(result), contains('睡眠 2 日'));
    expect(overlays(result), contains('同日配对 0 日'));
    expect(overlays(result), isNot(contains('恢复基础稳定')));
  });
  test('三日记录显示事实窗口来源和真实差值，不推断训练改善', () {
    final result = report([
      metric(0, weight: 68, heart: 55),
      metric(1, weight: 69, heart: 58),
      metric(2, weight: 70, heart: 61)
    ]);
    expect(result.weightTrendLabel, '下降');
    expect(result.weightTrendDetail, contains('-2.0 kg'));
    expect(result.weightTrendDetail, contains('3 个自然日'));
    expect(result.weightTrendDetail, contains('手动录入'));
    expect(result.milestoneDetail, isNot(contains('有氧基础可能改善')));
    expect(result.fatLossProtectionDetail, contains('工程估算'));
  });
  test('变化的真实输入影响分项结论，保持原变化幅度分界', () {
    expect(
        report([metric(0, weight: 70.6), metric(1), metric(2)])
            .weightTrendLabel,
        '上升');
    expect(
        report([metric(0, weight: 69.4), metric(1), metric(2)])
            .weightTrendLabel,
        '下降');
    expect(
        report([metric(0, weight: 70.2), metric(1), metric(2)])
            .weightTrendLabel,
        '基本稳定');
  });
  test('同日多个值取最新有效项，不按条数加权', () {
    final earlier = BodyMetric.fromJson({
      ...metric(0, weight: 80).toJson(),
      'measuredAt': now.subtract(const Duration(hours: 1)).toIso8601String()
    });
    final result = report([metric(0), earlier, metric(1), metric(2)]);
    expect(result.weightTrendLabel, '基本稳定');
    expect(result.weightTrendDetail, contains('3 个自然日'));
  });
  test('三种窗口排除窗口外记录，旧记录不挪动当前窗口', () {
    for (final days in [7, 30, 90]) {
      final result = report(
          [metric(days + 1), metric(days + 2), metric(days + 3)],
          days: days);
      expect(result.weightTrendLabel, '无法评估');
      expect(result.weightTrendDetail, contains('0 个自然日'));
    }
  });
  test('零值与非有限数不能充当有效身体观测', () {
    final result = report(List.generate(
        3, (i) => metric(i, weight: double.nan, heart: 0, hrv: 0, sleep: 0)));
    expect(result.weightTrendLabel, '无法评估');
    expect(overlays(result), contains('HRV 0 日'));
    expect(overlays(result), isNot(contains('NaN')));
  });
  test('零急性负荷缺少样本元数据，不能解释为已观测训练负荷', () {
    final result = report(List.generate(3, metric));
    expect(overlays(result), contains('负荷样本依据未提供'));
    expect(overlays(result), isNot(contains('当前急性负荷 0')));
  });
}
