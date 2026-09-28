import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/features/data_center/data_center_page.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/body_metric_display_service.dart';
import 'package:trainflow_ai/features/profile/profile_page.dart';

BodyMetric _metric(DateTime date,
        {String id = 'synthetic',
        double weight = 70,
        int hrv = 50,
        int fatigue = 0,
        Set<String>? fields,
        bool verified = true}) =>
    BodyMetric.fromJson({
      'id': id,
      'measuredAt': date.toIso8601String(),
      'weightKg': weight,
      'hrvMs': hrv,
      'fatigueLevel': fatigue,
      'source': 'manual',
      'sourceVerified': verified,
      if (fields != null) 'recordedFields': fields.toList()
    });

class _RecordedCanvas implements Canvas {
  final dots = <Offset>[];
  final paths = <Path>[];
  @override
  void drawCircle(Offset c, double radius, Paint paint) => dots.add(c);
  @override
  void drawPath(Path path, Paint paint) => paths.add(Path.from(path));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final now = DateTime(2026, 9, 19, 12);
  final service = BodyMetricDisplayService();
  for (final days in [7, 30, 90]) {
    test('$days 日窗口以当前自然日为准，含首日午夜但排除未来时刻', () {
      final start = DateTime(now.year, now.month, now.day - days + 1);
      final result = service.build(windowDays: days, now: now, metrics: [
        _metric(start),
        _metric(start.subtract(const Duration(seconds: 1))),
        _metric(now.add(const Duration(seconds: 1))),
      ]);
      expect(result.days, hasLength(days));
      expect(result.days.first, start);
      expect(result[BodyMetricDisplayField.weight].count, 1);
      expect(result[BodyMetricDisplayField.weight].values.first, 70);
      expect(result[BodyMetricDisplayField.weight].values.last, isNull);
    });
  }
  test('逐字段取当天最近有效值，较新缺失字段不覆盖较早观测', () {
    final records = [
      _metric(now.subtract(const Duration(hours: 1)), weight: 68, hrv: 40),
      _metric(now, weight: 72, hrv: 99, fields: {'weightKg'}),
      _metric(now.subtract(const Duration(days: 2)), weight: 70, hrv: 60),
    ];
    final before = records.map((m) => m.toJson()).toList();
    final result = service.build(metrics: records, now: now);
    expect(result[BodyMetricDisplayField.weight].average, 71);
    expect(result[BodyMetricDisplayField.hrv].average, 50);
    expect(result[BodyMetricDisplayField.hrv].latest!.hrvMs, 40);
    expect(result[BodyMetricDisplayField.weight].count, 2);
    expect(result[BodyMetricDisplayField.weight].values[5], isNull);
    expect(records.map((m) => m.toJson()).toList(), before);
    expect(
        service
            .build(
                metrics: records.reversed.toList(),
                now: now)[BodyMetricDisplayField.hrv]
            .values,
        result[BodyMetricDisplayField.hrv].values);
  });
  test('未知来源、零体重和继承值不入均值，疲劳零是有效值', () {
    final result = service.build(now: now, metrics: [
      _metric(now, verified: false),
      _metric(now.subtract(const Duration(days: 1)), weight: 0, hrv: 0),
      _metric(now.subtract(const Duration(days: 2)), fields: {}),
    ]);
    expect(result[BodyMetricDisplayField.weight].average, isNull);
    expect(result[BodyMetricDisplayField.weight].meanLabel, '无有效记录');
    expect(result[BodyMetricDisplayField.fatigue].count, 1);
    expect(result[BodyMetricDisplayField.fatigue].average, 0);
    expect(result[BodyMetricDisplayField.fatigue].evidenceLabel,
        contains('1/7 日'));
  });
  test('来源与最近日期来自每项有效观测，不使用整条最新记录来源', () {
    final earlier = _metric(now.subtract(const Duration(days: 1)));
    final result = service.build(now: now, metrics: [
      earlier,
      BodyMetric.fromJson({
        ..._metric(now, fields: {'weightKg'}).toJson(),
        'source': 'import_file'
      })
    ]);
    expect(result[BodyMetricDisplayField.hrv].evidenceLabel,
        contains('2026-09-18'));
    expect(result[BodyMetricDisplayField.hrv].evidenceLabel,
        isNot(contains('文件导入')));
    expect(
        result[BodyMetricDisplayField.weight].evidenceLabel, contains('文件导入'));
  });
  test('以本地日历排列跨月窗口，不用观测条数压缩空日', () {
    final result = service
        .build(now: DateTime(2026, 3, 10, 12), windowDays: 30, metrics: []);
    expect(result.days.first, DateTime(2026, 2, 9));
    expect(result.days.last, DateTime(2026, 3, 10));
    expect(result.days.map(bodyMetricDisplayDate).toSet(), hasLength(30));
    expect(result.coveredDays, 0);
  });

  testWidgets('画布按自然日定位且跨缺失区间断线，零疲劳绘点不补 HRV', (tester) async {
    final storage = InMemoryLocalStorageService();
    final today = DateTime.now();
    for (final days in [6, 5, 1, 0]) {
      PersistedBodyMetricRepository(storage).saveMetric(_metric(
          DateTime(today.year, today.month, today.day - days),
          id: 'day-$days',
          weight: 70 + days.toDouble(),
          fields: {'weightKg', if (days == 0) 'fatigueLevel'}));
    }
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DataCenterPage()))));
    await tester.pumpAndSettle();
    final painter = tester
        .widget<CustomPaint>(find.byKey(const ValueKey('body-trend-canvas')))
        .painter!;
    final canvas = _RecordedCanvas();
    painter.paint(canvas, const Size(600, 170));
    expect(canvas.dots.map((p) => p.dx), [0, 100, 500, 600, 600]);
    expect(canvas.paths, hasLength(2));
    final runs = canvas.paths.first.computeMetrics().toList();
    expect(runs, hasLength(2));
    for (final run in runs) {
      final start = run.getTangentForOffset(0)!.position;
      final end = run.getTangentForOffset(run.length)!.position;
      expect(end.dx - start.dx, closeTo(100, 0.01));
    }
    expect(canvas.dots.last.dy, 75);
    expect(tester.takeException(), isNull);
  });

  testWidgets('我的与身体摘要在窄屏大字使用同一字段均值和缺失口径', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = InMemoryLocalStorageService();
    PersistedBodyMetricRepository(storage).saveMetric(_metric(
        DateTime.now().subtract(const Duration(days: 1)),
        fields: {'weightKg'}));
    final before = storage.readJson('trainflow.body_metrics.v1');
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    for (final profile in [false, true]) {
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!),
              home: Scaffold(
                  body: profile
                      ? const ProfilePage()
                      : const DataCenterPage()))));
      await tester.pumpAndSettle();
      final card = find
          .byKey(ValueKey(profile ? 'profile-body-summary' : 'body-summary'));
      await tester.scrollUntilVisible(card, 400,
          scrollable: find.byType(Scrollable).first, maxScrolls: 30);
      await tester.pumpAndSettle();
      final texts = tester
          .widgetList<Text>(
              find.descendant(of: card, matching: find.byType(Text)))
          .map((w) => w.data ?? '')
          .join('\n');
      expect(texts, contains('70.0 kg'));
      expect('无有效记录'.allMatches(texts), hasLength(3));
      expect(texts, contains('1/7 日'));
      expect(texts, contains('0/7 日'));
      expect(texts, contains('不代表今日状态'));
      expect(tester.takeException(), isNull);
    }
    expect(storage.readJson('trainflow.body_metrics.v1'), before);
    expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
  });

  testWidgets('切换 7 至 30 至 90 日仅改变展示窗口，不写记录或计划', (tester) async {
    final storage = InMemoryLocalStorageService();
    PersistedBodyMetricRepository(storage).saveMetric(_metric(
        DateTime.now().subtract(const Duration(days: 10)),
        fields: {'weightKg'}));
    final before = storage.readJson('trainflow.body_metrics.v1');
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final plan = container.read(trainingMvpProvider).activePlan.toJson();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DataCenterPage()))));
    await tester.pumpAndSettle();
    expect(find.text('本窗口无有效观测，历史记录保留。'), findsOneWidget);
    for (final days in [30, 90]) {
      final button = find.widgetWithText(ChoiceChip, '$days 日');
      await tester.scrollUntilVisible(button, 400,
          scrollable: find.byType(Scrollable).first, maxScrolls: 30);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('$days 日趋势图表'), findsOneWidget);
      expect(find.text('本窗口无有效观测，历史记录保留。'), findsNothing);
      expect(find.textContaining('1/$days 日；最近有效记录'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    expect(storage.readJson('trainflow.body_metrics.v1'), before);
    expect(container.read(trainingMvpProvider).activePlan.toJson(), plan);
  });
  for (final oldOnly in [false, true]) {
    testWidgets('${oldOnly ? '仅过期记录' : '空记录'}不生成当前均值或趋势', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = InMemoryLocalStorageService();
      if (oldOnly) {
        PersistedBodyMetricRepository(storage).saveMetric(BodyMetric.fromJson({
          'id': 'synthetic-expired',
          'measuredAt': DateTime.now()
              .subtract(const Duration(days: 100))
              .toIso8601String(),
          'source': 'manual',
          'weightKg': 70,
          'recordedFields': ['weightKg'],
        }));
      }
      final before = storage.readJson('trainflow.body_metrics.v1');
      final container = ProviderContainer(
          overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
      addTearDown(container.dispose);
      final plan = container.read(trainingMvpProvider).activePlan.toJson();
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: DataCenterPage()))));
      await tester.pumpAndSettle();
      expect(find.text('0.0 kg'), findsNothing);
      expect(find.text('0 ms'), findsNothing);
      expect(find.text('今日身体状态'), findsNothing);
      expect(find.text('近 7 日身体记录'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('7 日趋势图表'), 500,
          scrollable: find.byType(Scrollable).first, maxScrolls: 30);
      await tester.pumpAndSettle();
      expect(find.text('本窗口无有效观测，历史记录保留。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(storage.readJson('trainflow.body_metrics.v1'), before);
      expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
      expect(container.read(trainingMvpProvider).activePlan.toJson(), plan);
    });
  }
}
