import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/body_metric_goal.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/services/body_metric_goal_service.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/features/data_center/data_center_page.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  final now = DateTime(2026, 9, 19, 12);
  BodyMetric metric(int days,
          {double weight = 70,
          int heart = 50,
          int hrv = 70,
          Set<String>? fields,
          bool verified = true}) =>
      BodyMetric.fromJson({
        'id': 'synthetic-$days',
        'measuredAt': now.subtract(Duration(days: days)).toIso8601String(),
        'source': 'manual',
        'sourceVerified': verified,
        'weightKg': weight,
        'restingHeartRate': heart,
        'hrvMs': hrv,
        if (fields != null) 'recordedFields': fields.toList(),
      });
  BodyMetricGoalReport report(List<BodyMetric> records) =>
      BodyMetricGoalService().buildReport(
          bodyMetrics: records,
          now: now,
          profile: InMemoryUserProfileRepository.defaultProfile);
  BodyMetricGoal goal(List<BodyMetric> records, BodyMetricGoalType type) =>
      report(records).goals.firstWhere((g) => g.type == type);

  test('窗口含第七日零点，排除更早与今日未来，累计日单独统计', () {
    BodyMetric at(DateTime date) => BodyMetric.fromJson(
        {...metric(0).toJson(), 'measuredAt': date.toIso8601String()});
    final records = [
      at(DateTime(2026, 9, 13)),
      at(DateTime(2026, 9, 12, 23, 59, 59)),
      at(now.add(const Duration(minutes: 1)))
    ];
    final result = goal(records, BodyMetricGoalType.weight);
    expect(result.guidance, contains('2026-09-13 至 2026-09-19'));
    expect(result.guidance, contains('1/7 日'));
    expect(
        goal(records, BodyMetricGoalType.consistency).currentLabel, '2 个自然日');
  });
  test('字段单独取当天最近有效值，缺失的较新项不会替代真实观测', () {
    final earlier = BodyMetric.fromJson({
      ...metric(0, weight: 69, heart: 61).toJson(),
      'measuredAt': now.subtract(const Duration(hours: 1)).toIso8601String()
    });
    final records = [
      earlier,
      metric(0, weight: 71, fields: {'weightKg'})
    ];
    expect(goal(records, BodyMetricGoalType.weight).currentLabel, '71.0 kg');
    expect(goal(records, BodyMetricGoalType.restingHeartRate).currentLabel,
        '61.0 bpm');
    expect(
        goal(records, BodyMetricGoalType.consistency).currentLabel, '1 个自然日');
  });
  test('运动和档案体重变化不自动设置个人减重目标', () {
    for (final sport in [
      MainSport.marathon,
      MainSport.trailRunning,
      MainSport.strength,
      MainSport.hyrox
    ]) {
      final result = BodyMetricGoalService().buildReport(
          bodyMetrics: [metric(0)],
          now: now,
          profile: InMemoryUserProfileRepository.defaultProfile
              .copyWith(mainSports: [sport], weightKg: 100));
      final weight = result.goals.first;
      expect(weight.isReference, isTrue);
      expect(weight.targetLabel, '下降 5%（内置参考）');
      expect(weight.targetLabel, isNot(contains('95')));
      expect(weight.achieved, isFalse);
    }
  });
  test('重复构建不改输入顺序、数据或来源', () {
    final records = [
      metric(2),
      metric(0),
      metric(1, fields: {'weightKg'})
    ];
    final before = records.map((m) => m.toJson()).toList();
    report(records);
    report(records);
    expect(records.map((m) => m.toJson()).toList(), before);
  });
  for (final scale in [1.0, 1.5]) {
    testWidgets('窄屏 $scale 倍字体明确参考身份，浏览不写记录或计划', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = InMemoryLocalStorageService();
      final today = DateTime.now();
      PersistedBodyMetricRepository(storage).saveMetric(BodyMetric.fromJson({
        ...metric(0, fields: {'weightKg'}).toJson(),
        'measuredAt': today.toIso8601String()
      }));
      final before = storage.readJson('trainflow.body_metrics.v1');
      final container = ProviderContainer(
          overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
      addTearDown(container.dispose);
      final plan = container.read(trainingMvpProvider).activePlan.toJson();
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const Scaffold(body: DataCenterPage()))));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('指标参考与记录'), 450,
          scrollable: find.byType(Scrollable).first, maxScrolls: 30);
      await tester.pumpAndSettle();
      expect(find.text('非个人目标'), findsNWidgets(3));
      expect(find.descendant(of: find.byKey(const ValueKey('body-goals')),
          matching: find.text('无有效记录')), findsNWidgets(2));
      expect(find.text('0/4 达成'), findsNothing);
      expect(find.text('已达到心肺适应里程碑'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(storage.readJson('trainflow.body_metrics.v1'), before);
      expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
      expect(container.read(trainingMvpProvider).activePlan.toJson(), plan);
    });
  }

  test('固定参考数值不能充当个人目标或已达成的健康改善', () {
    final result = report(List.generate(7, (i) => metric(i, weight: 50)));
    for (final item in result.goals
        .where((g) => g.type != BodyMetricGoalType.consistency)) {
      expect(item.achieved, isFalse);
      expect(item.progress, 0);
      expect(item.milestoneLabel, contains('未设置个人目标'));
      expect(item.guidance, isNot(contains('心肺适应')));
    }
    expect(result.achievedCount, 0);
  });
  test('缺失与继承值不能变成心率目标达成', () {
    final result = goal([
      metric(0, fields: {'weightKg'})
    ], BodyMetricGoalType.restingHeartRate);
    expect(result.currentLabel, '无有效记录');
    expect(result.achieved, isFalse);
    expect(result.guidance, contains('0/7 日'));
  });
  test('当前均值取七个自然日有效字段，不取最近七条历史记录', () {
    final result = goal([
      metric(0, weight: 72),
      ...List.generate(7, (i) => metric(i + 20, weight: 50))
    ], BodyMetricGoalType.weight);
    expect(result.currentLabel, '72.0 kg');
    expect(result.guidance, contains('1/7 日'));
  });
  test('未知来源未来和无有效字段不参与当前统计及累计日', () {
    final records = [
      metric(-1),
      metric(0, verified: false),
      metric(1, fields: {})
    ];
    expect(goal(records, BodyMetricGoalType.weight).currentLabel, '无有效记录');
    expect(
        goal(records, BodyMetricGoalType.consistency).currentLabel, '0 个自然日');
  });
  test('同日重复不增加累计天数', () {
    final result = goal(
        List.generate(14, (_) => metric(0)), BodyMetricGoalType.consistency);
    expect(result.currentLabel, '1 个自然日');
    expect(result.achieved, isFalse);
    expect(result.progress, closeTo(1 / 14, 0.001));
  });
  test('零散十四日只能说明累计，不能宣称连续两周', () {
    final result = goal(List.generate(14, (i) => metric(i * 3)),
        BodyMetricGoalType.consistency);
    expect(result.currentLabel, '14 个自然日');
    expect(result.achieved, isTrue);
    expect(result.title, '累计记录日');
    expect(result.milestoneLabel, isNot(contains('趋势判断基础')));
    expect(result.guidance, contains('不代表连续'));
  });
  test('跨数月体重差不冒充本周速度或触发饮食指令', () {
    final result = report([metric(0, weight: 69), metric(90, weight: 72)]);
    expect(result.hasProtectionWarning, isFalse);
    expect(result.protectionMessage, isNot(contains('速度偏快')));
    expect(result.protectionMessage, contains('趋势洞察'));
  });
  test('无数据不显示虚构达成比例或强迫不完整快录', () {
    final result = report([]);
    expect(result.achievedCount, 0);
    expect(result.summary, contains('未设置个人身体指标目标'));
    expect(result.summary, isNot(contains('10 秒快录')));
  });
  test('输入顺序不影响当前均值，字段各自去重', () {
    final records = [
      metric(2, weight: 68),
      metric(0, weight: 72),
      metric(1, weight: 70)
    ];
    final a = goal(records, BodyMetricGoalType.weight);
    final b = goal(records.reversed.toList(), BodyMetricGoalType.weight);
    expect(a.currentLabel, b.currentLabel);
    expect(a.currentLabel, '70.0 kg');
    expect(a.guidance, contains('3/7 日'));
    expect(a.guidance, contains('手动录入'));
  });
}
