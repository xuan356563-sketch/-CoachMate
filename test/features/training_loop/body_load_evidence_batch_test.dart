import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/profile/widgets/training_load_card.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late TrainingMvpState base;
  late DateTime today;
  setUp(() {
    container = ProviderContainer(overrides: [
      localStorageServiceProvider
          .overrideWithValue(InMemoryLocalStorageService()),
    ]);
    final state = container.read(trainingMvpProvider);
    base = state.copyWith(
        bodyMetrics: [],
        logs: [],
        profile: state.profile
            .copyWith(weeklyTrainingDays: 3, dailyAvailableMinutes: 60));
    final now = DateTime.now();
    today = DateTime(now.year, now.month, now.day);
  });
  tearDown(() => container.dispose());
  BodyMetric metric({int days = 1, Map<String, dynamic> changes = const {}}) =>
      BodyMetric.fromJson({
        'id': 'synthetic-load-$days',
        'measuredAt': DateTime(today.year, today.month, today.day - days)
            .toIso8601String(),
        'source': 'manual',
        'weightKg': 70,
        'bodyFatPercentage': 18,
        'restingHeartRate': 60,
        'hrvMs': 40,
        'sleepHours': 6,
        'fatigueLevel': 4,
        'sorenessLevel': 3,
        ...changes,
      });
  List<List<Object>> curve(TrainingMvpState state) => [
        for (final point in state.trainingLoadCurvePoints)
          [
            point.label,
            point.dailyLoadScore,
            point.ctlScore,
            point.atlScore,
            point.tsbScore
          ]
      ];

  for (final changes in [
    <String, dynamic>{'source': 'unknown'},
    <String, dynamic>{'sourceVerified': false},
    <String, dynamic>{
      'recordedFields': ['weightKg']
    },
    <String, dynamic>{'recordedFields': []},
  ]) {
    test('无负荷身体证据不改变任何曲线点：$changes', () {
      expect(curve(base.copyWith(bodyMetrics: [metric(changes: changes)])),
          curve(base));
    });
  }

  test('未来身体记录不推移曲线，窗口外旧记录不改当前估算', () {
    for (final days in [-20, -1, 30]) {
      expect(
          curve(base.copyWith(bodyMetrics: [metric(days: days)])), curve(base));
    }
    final laterToday = metric(days: 0, changes: {
      'measuredAt':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    });
    expect(curve(base.copyWith(bodyMetrics: [laterToday])), curve(base));
  });

  test('各项只使用实际字段，缺失 HRV 睡眠不按零增加惩罚', () {
    final scenarios = <Map<String, dynamic>, double>{
      {
        'recordedFields': ['fatigueLevel']
      }: 24,
      {
        'recordedFields': ['sorenessLevel'],
        'sorenessLevel': 6
      }: 24,
      {
        'recordedFields': ['sleepHours']
      }: 18,
      {
        'recordedFields': ['hrvMs']
      }: 18,
      {
        'recordedFields': ['fatigueLevel'],
        'fatigueLevel': 0
      }: 18,
    };
    for (final entry in scenarios.entries) {
      final state = base.copyWith(bodyMetrics: [metric(changes: entry.key)]);
      expect(state.trainingLoadCurvePoints[12].dailyLoadScore, entry.value);
    }
    final missing = BodyMetric.fromJson({
      'id': 'sparse',
      'source': 'manual',
      'measuredAt': metric().measuredAt.toIso8601String(),
      'fatigueLevel': 4,
    });
    expect(
        base
            .copyWith(bodyMetrics: [missing])
            .trainingLoadCurvePoints[12]
            .dailyLoadScore,
        24);
  });

  test('旧无效数值不制造估算；合法零值保留既有工程下限', () {
    final invalid = metric(changes: {
      'fatigueLevel': -1,
      'sorenessLevel': 11,
      'sleepHours': 0,
      'hrvMs': 0
    });
    expect(curve(base.copyWith(bodyMetrics: [invalid])), curve(base));
    final zeros = metric(changes: {
      'fatigueLevel': 0,
      'sorenessLevel': 0,
      'recordedFields': ['fatigueLevel', 'sorenessLevel']
    });
    expect(
        base
            .copyWith(bodyMetrics: [zeros])
            .trainingLoadCurvePoints[12]
            .dailyLoadScore,
        18);
  });

  test('完整有效资料沿用既有系数和 EWMA，只有元数据不改课程', () {
    final state = base.copyWith(bodyMetrics: [metric(days: 0)]);
    final points = state.trainingLoadCurvePoints;
    expect(points, hasLength(14));
    expect(points.take(13).map((p) => p.dailyLoadScore), everyElement(0));
    expect(points.last.dailyLoadScore, 58);
    // 档案初值 135，加 HRV 32、减疲劳 28；十三个空日后第十四日估算 58。
    expect(points.last.ctlScore,
        closeTo(139 * math.pow(41 / 42, 14) + 58 / 42, 1e-9));
    expect(points.last.atlScore,
        closeTo(139 * .85 * math.pow(6 / 7, 14) + 58 / 7, 1e-9));
    expect(state.activePlan.toJson(), base.activePlan.toJson());
    expect(state.logs, isEmpty);
  });

  test('同日按时间取最近有相关证据记录，不依赖列表顺序或继承体重记录', () {
    final earlier = metric();
    final later = metric(changes: {
      'measuredAt':
          earlier.measuredAt.add(const Duration(hours: 1)).toIso8601String(),
      'fatigueLevel': 8,
      'recordedFields': ['fatigueLevel'],
    });
    final weight = metric(changes: {
      'measuredAt':
          earlier.measuredAt.add(const Duration(hours: 2)).toIso8601String(),
      'recordedFields': ['weightKg'],
    });
    for (final records in [
      [earlier, later, weight],
      [weight, later, earlier]
    ]) {
      expect(
          base
              .copyWith(bodyMetrics: records)
              .trainingLoadCurvePoints[12]
              .dailyLoadScore,
          48);
    }
    final local = metric(changes: {
      'measuredAt': DateTime(today.year, today.month, today.day - 1, 20)
          .toIso8601String(),
    });
    final utc = metric(changes: {
      'measuredAt': local.measuredAt.toUtc().toIso8601String(),
    });
    expect(curve(base.copyWith(bodyMetrics: [utc])),
        curve(base.copyWith(bodyMetrics: [local])));
  });

  test('训练日志仍优先于身体估算，改变真实身体数据会改变无日志日结果', () {
    final log = TrainingLog(
        id: 'synthetic',
        workoutDayId: base.todayWorkout.id,
        date: metric().measuredAt,
        completed: true,
        rpe: 5,
        fatigueLevel: 3,
        sleepQuality: 7,
        painNote: null,
        userNote: '合成',
        createdAt: metric().measuredAt);
    final logged = base.copyWith(logs: [log]);
    expect(
        logged
            .copyWith(bodyMetrics: [metric()])
            .trainingLoadCurvePoints[12]
            .dailyLoadScore,
        logged.trainingLoadCurvePoints[12].dailyLoadScore);
    expect(
        base
            .copyWith(bodyMetrics: [metric()])
            .trainingLoadCurvePoints[12]
            .dailyLoadScore,
        isNot(base
            .copyWith(bodyMetrics: [
              metric(changes: {'fatigueLevel': 8})
            ])
            .trainingLoadCurvePoints[12]
            .dailyLoadScore));
  });

  test('当日已确认时，未知历史不改变训练状态、原因或有效计划', () {
    final current = metric(days: 0, changes: {
      'fatigueLevel': 0,
      'hrvMs': 70,
      'sleepHours': 8,
      'sorenessLevel': 0,
    });
    final confirmed = base.copyWith(
        profileCompleted: true,
        dailyStatusConfirmedAt: DateTime.now(),
        bodyMetrics: [current]);
    expect(confirmed.readinessScore, isNotNull);
    final changed = confirmed.copyWith(bodyMetrics: [
      current,
      for (var day = 1; day < 14; day++)
        metric(days: day, changes: {
          'sourceVerified': false,
          'fatigueLevel': 10,
          'sorenessLevel': 10,
        }),
    ]);
    expect(curve(changed), curve(confirmed));
    expect(changed.trainingStatusLabel, confirmed.trainingStatusLabel);
    expect(changed.trainingStatusReason, confirmed.trainingStatusReason);
    expect(changed.activePlan.toJson(), confirmed.activePlan.toJson());
  });

  testWidgets('负荷卡明确工程估算、身体代理与缺失边界，不宣称测量体能', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!),
      home: Scaffold(
          body: SingleChildScrollView(child: TrainingLoadCard(state: base))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('训练负荷工程估算'), findsOneWidget);
    expect(find.textContaining('不代表实际训练量或已测得的体能'), findsOneWidget);
    expect(find.text('CTL 慢性体能'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
