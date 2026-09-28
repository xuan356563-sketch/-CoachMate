import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/core/widgets/trainmate_showcase_widgets.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/daily_check_in.dart';
import 'package:trainflow_ai/data/models/pain_log.dart';
import 'package:trainflow_ai/features/dashboard/today_training_page.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/daily_check_in_service.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import '../../support/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  setUp(() => now = DateTime.now());
  Map<String, dynamic> raw({Map<String, dynamic> changes = const {}}) => {
        'id': 'synthetic-check-in',
        'measuredAt': now.toIso8601String(),
        'source': 'manual',
        'weightKg': 70,
        'sleepHours': 7.0,
        'hrvMs': 50,
        'fatigueLevel': 0,
        'sorenessLevel': 0,
        'moodLabel': '截图识别',
        ...changes,
      };
  DailyCheckInSummary summary(BodyMetric? metric, {PainLog? pain}) =>
      DailyCheckInService().buildSummary(
          latestBodyMetric: metric,
          latestPainLog: pain,
          starterProgramStreak: 10,
          highConfidenceInsightCount: 3,
          readinessLabel: '合成估算',
          readinessScore: 90,
          trainingStatusLabel: '维持中',
          reminderTimeLabel: '20:30');
  DailyCheckInPrompt prompt(DailyCheckInSummary s, String label) =>
      s.prompts.singleWhere((p) => p.label == label);

  test('昨日身体记录不显示成今日数值或稳定默认值', () {
    final metric = BodyMetric.fromJson(raw(changes: {
      'measuredAt': now.subtract(const Duration(days: 1)).toIso8601String(),
      'fatigueLevel': 9,
    }));
    final result = summary(metric);
    for (final label in ['睡眠', 'HRV', '疲劳']) {
      expect(prompt(result, label).value, '未记录');
      expect(prompt(result, label).sourceLabel, contains('历史记录'));
      expect(prompt(result, label).sourceLabel,
          contains(metric.measuredDateLabel));
    }
    expect(result.requiredQuestionCount, 5);
    expect(prompt(result, '疲劳').priorityRank, 2);
    // 本批保留原预填操作的可用条件；展示不代替用户提交确认。
    expect(result.canUseYesterday, isTrue);
  });

  for (final changes in [
    <String, dynamic>{'source': 'unknown'},
    <String, dynamic>{'sourceVerified': false},
    <String, dynamic>{
      'recordedFields': ['weightKg']
    },
  ]) {
    test('未知来源或继承字段不显示成已确认输入：$changes', () {
      final result = summary(BodyMetric.fromJson(raw(changes: changes)));
      for (final label in ['睡眠', 'HRV', '疲劳']) {
        expect(prompt(result, label).value, '未记录');
        expect(prompt(result, label).sourceLabel, isNot('今天确认'));
      }
      expect(result.requiredQuestionCount, 5);
      expect(result.canUseYesterday, isFalse);
    });
  }

  test('未来时刻的数据不得影响当前排序或预填可用性', () {
    final result = summary(BodyMetric.fromJson(raw(changes: {
      'measuredAt': now.add(const Duration(hours: 1)).toIso8601String(),
      'fatigueLevel': 9,
    })));
    expect(prompt(result, '疲劳').value, '未记录');
    expect(prompt(result, '疲劳').priorityRank, 2);
    expect(prompt(result, '疲劳').sourceLabel, contains('未来'));
    expect(result.canUseYesterday, isFalse);
  });

  test('当日合法零值仍展示，标签区分记录与确认', () {
    final result = summary(BodyMetric.fromJson(raw()));
    expect(prompt(result, '疲劳').value, '0/10');
    expect(prompt(result, '疲劳').sourceLabel, contains('当日记录'));
    expect(prompt(result, '疲劳').sourceLabel, contains('手动录入'));
    expect(prompt(result, '疲劳').sourceLabel, contains('待复核'));
    expect(result.requiredQuestionCount, 2);
  });

  test('旧疼痛保留提示和优先级，但不得称为今日确认', () {
    final pain = PainLog(
        id: 'synthetic-pain',
        bodyPart: '膝',
        painLevel: 8,
        timing: PainTiming.ongoing,
        note: '',
        date: now.subtract(const Duration(days: 2)),
        createdAt: now.subtract(const Duration(days: 2)));
    final result = prompt(summary(null, pain: pain), '疼痛');
    expect(result.value, '膝 8/10');
    expect(result.priorityRank, 1);
    expect(result.sourceLabel, contains('历史记录'));
    expect(result.sourceLabel, contains('待复核'));
    expect(prompt(summary(null), '疼痛').sourceLabel, contains('待确认'));
  });

  Future<(ProviderContainer, InMemoryLocalStorageService)> page(
      WidgetTester tester, List<Map<String, dynamic>> records) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = InMemoryLocalStorageService();
    storage.saveJson('trainflow.body_metrics.v1', {'metrics': records});
    await tester.pumpWidget(TestHarness(storageService: storage).buildApp(
        MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.noScaling),
                child: child!),
            home: const Scaffold(body: TodayTrainingPage()))));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TodayTrainingPage)));
    return (container, storage);
  }

  Map<String, String> strip(WidgetTester tester) => {
        for (final item in tester
            .widget<TrainMateStatusStrip>(find.byType(TrainMateStatusStrip))
            .metrics)
          item.label: item.value,
      };

  for (final scenario in ['yesterday', 'future', 'unknown', 'partial']) {
    testWidgets('今日状态条不使用过期、未来、未知或继承值：$scenario', (tester) async {
      final record = raw(
          changes: switch (scenario) {
        'yesterday' => {
            'measuredAt':
                now.subtract(const Duration(days: 1)).toIso8601String()
          },
        'future' => {
            'measuredAt': now.add(const Duration(hours: 1)).toIso8601String()
          },
        'unknown' => {'source': 'unknown'},
        _ => {
            'recordedFields': ['weightKg']
          },
      });
      final (container, storage) = await page(tester, [record]);
      final before = storage.readJson('trainflow.body_metrics.v1');
      final plan = container.read(trainingMvpProvider).activePlan.toJson();
      final values = strip(tester);
      expect(values['睡眠'], '待记录');
      expect(values['疲劳'], '待记录');
      expect(values['酸痛'], '待记录');
      if (scenario != 'partial') expect(values['记录标签'], '待记录');
      expect(storage.readJson('trainflow.body_metrics.v1'), before);
      expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
      expect(container.read(trainingMvpProvider).activePlan.toJson(), plan);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('未来记录不能遮住当日可信记录，首页与签到口径一致', (tester) async {
    final (container, _) = await page(tester, [
      raw(changes: {
        'id': 'future',
        'measuredAt': now.add(const Duration(days: 1)).toIso8601String(),
        'fatigueLevel': 9
      }),
      raw(),
    ]);
    expect(strip(tester)['疲劳'], '0/10');
    expect(strip(tester)['睡眠'], '7.0h');
    expect(strip(tester)['记录标签'], '截图识别');
    expect(strip(tester).containsKey('心情'), isFalse);
    expect(
        prompt(container.read(trainingMvpProvider).dailyCheckInSummary, '疲劳')
            .value,
        '0/10');
    expect(tester.takeException(), isNull);
  });

  testWidgets('实际状态条在窄屏大字下可读，不依赖首页其他卡片布局', (tester) async {
    await page(tester, [raw()]);
    final actual =
        tester.widget<TrainMateStatusStrip>(find.byType(TrainMateStatusStrip));
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(body: SingleChildScrollView(child: actual))));
    await tester.pumpAndSettle();
    for (final text in ['睡眠 7.0h', '疲劳 0/10', '酸痛 0/10', '记录标签 截图识别']) {
      await tester.scrollUntilVisible(find.text(text), 160,
          scrollable: find.descendant(
              of: find.byType(TrainMateStatusStrip),
              matching: find.byType(Scrollable)));
      await tester.pumpAndSettle();
      expect(find.text(text).hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  test('本地自然日与 UTC 表示一致，跨午夜和未来秒边界严格处理', () {
    final anchor = DateTime(2026, 9, 20, 0, 10);
    DailyCheckInSummary evaluate(DateTime date) =>
        DailyCheckInService().buildSummary(
            latestBodyMetric: BodyMetric.fromJson(
                raw(changes: {'measuredAt': date.toIso8601String()})),
            latestPainLog: null,
            starterProgramStreak: 10,
            highConfidenceInsightCount: 3,
            readinessLabel: '合成估算',
            readinessScore: 90,
            trainingStatusLabel: '维持中',
            reminderTimeLabel: '20:30',
            evaluatedAt: anchor);
    for (final date in [anchor, anchor.toUtc()]) {
      expect(prompt(evaluate(date), '疲劳').value, '0/10');
      expect(prompt(evaluate(date), '疲劳').sourceLabel, contains('2026-09-20'));
    }
    expect(
        prompt(evaluate(anchor.subtract(const Duration(minutes: 11))), '疲劳')
            .value,
        '未记录');
    expect(prompt(evaluate(anchor.add(const Duration(seconds: 1))), '疲劳').value,
        '未记录');
  });

  test('缺失与无效数值不等于低值，当日真实值变化仍改变原规则排序', () {
    for (final change in [
      <String, dynamic>{'fatigueLevel': null, 'sleepHours': 0, 'hrvMs': 0},
      <String, dynamic>{'fatigueLevel': -1, 'sleepHours': -1, 'hrvMs': -1},
    ]) {
      final result = summary(BodyMetric.fromJson(raw(changes: change)));
      for (final label in ['睡眠', 'HRV', '疲劳']) {
        expect(prompt(result, label).value, '未记录');
      }
      expect(prompt(result, '睡眠').priorityReason, contains('缺少当日'));
    }
    final result =
        summary(BodyMetric.fromJson(raw(changes: {'fatigueLevel': 8})));
    expect(prompt(result, '疲劳').value, '8/10');
    expect(prompt(result, '疲劳').priorityRank, 1);
  });
}
