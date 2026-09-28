import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/daily_check_in/daily_check_in_page.dart';
import 'package:trainflow_ai/services/daily_check_in_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  setUp(() => now = DateTime.now());
  Map<String, dynamic> record(int offset,
          {Map<String, dynamic> changes = const {}}) =>
      {
        'id': 'synthetic-$offset',
        'measuredAt': DateTime(now.year, now.month, now.day + offset, 7)
            .toIso8601String(),
        'source': 'manual',
        'weightKg': 70.0,
        'sleepHours': 7.0,
        'hrvMs': 50,
        'restingHeartRate': 60,
        'fatigueLevel': 0,
        ...changes,
      };
  (ProviderContainer, InMemoryLocalStorageService) setup(
      List<Map<String, dynamic>> records) {
    final storage = InMemoryLocalStorageService();
    storage.saveJson('trainflow.body_metrics.v1', {'metrics': records});
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    return (container, storage);
  }

  for (final scenario in [
    'today',
    'old',
    'future',
    'unknown',
    'partial',
    'invalid'
  ]) {
    test('不是有效昨日记录时入口与保存均阻止：$scenario', () async {
      final data = switch (scenario) {
        'today' => record(0),
        'old' => record(-2),
        'future' => record(1),
        'unknown' => record(-1, changes: {'source': 'unknown'}),
        'partial' => record(-1, changes: {
            'recordedFields': ['weightKg']
          }),
        _ => record(-1, changes: {'sleepHours': 0}),
      };
      final (container, storage) = setup([data]);
      final before = storage.readJson('trainflow.body_metrics.v1');
      final state = container.read(trainingMvpProvider);
      final plan = state.activePlan.toJson();
      expect(state.dailyCheckInSummary.canUseYesterday, isFalse);
      await container
          .read(bodyMetricControllerProvider.notifier)
          .confirmDailyCheckInSameAsYesterday();
      expect(storage.readJson('trainflow.body_metrics.v1'), before);
      expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
      expect(container.read(trainingMvpProvider).activePlan.toJson(), plan);
      expect(
          container
              .read(bodyMetricControllerProvider)
              .dailyCheckInStatusMessage,
          contains('昨日'));
    });
  }
  test('今日和未来记录不遮住昨日；保存明确沿用昨日的实际字段', () async {
    final (container, storage) = setup([
      record(1, changes: {'sleepHours': 12}),
      record(0, changes: {'sleepHours': 9}),
      record(-1),
    ]);
    final plan = container.read(trainingMvpProvider).activePlan.toJson();
    expect(
        container.read(trainingMvpProvider).dailyCheckInSummary.canUseYesterday,
        isTrue);
    await container
        .read(bodyMetricControllerProvider.notifier)
        .confirmDailyCheckInSameAsYesterday();
    final saved = container
        .read(bodyMetricControllerProvider)
        .metrics
        .singleWhere((item) => item.id.startsWith('daily-check-in-'));
    expect(saved.sleepHours, 7);
    expect(saved.fatigueLevel, 0);
    expect(saved.hasValue('bodyFatPercentage'), isFalse);
    expect(saved.hasValue('sorenessLevel'), isFalse);
    expect(saved.source, BodyMetricSource.manual);
    expect(saved.note, contains('昨日'));
    expect(storage.readJson('trainflow.daily_check_ins.v1'), isNotNull);
    expect(container.read(trainingMvpProvider).activePlan.toJson(), plan);
  });
  test('昨日最新记录缺失或未知时不退回昨日更早的完整记录', () {
    for (final change in [
      {'sleepHours': 0},
      {'source': 'unknown'}
    ]) {
      final metrics = [
        BodyMetric.fromJson(record(-1)),
        BodyMetric.fromJson(record(-1, changes: {
          ...change,
          'id': 'later',
          'measuredAt':
              DateTime(now.year, now.month, now.day - 1, 20).toIso8601String(),
        })),
      ];
      expect(DailyCheckInService.yesterdayMetric(metrics, now), isNull);
    }
  });

  test('本地日历跨月和夏令时边界不按过去 24 小时选择', () {
    for (final anchor in [
      DateTime(2026, 3, 9, 0, 30),
      DateTime(2026, 11, 2, 0, 30),
      DateTime(2026, 10, 1)
    ]) {
      final yesterday =
          DateTime(anchor.year, anchor.month, anchor.day - 1, 0, 10);
      final old = DateTime(anchor.year, anchor.month, anchor.day - 2, 23, 50);
      final target = BodyMetric.fromJson(record(-1,
          changes: {'measuredAt': yesterday.toUtc().toIso8601String()}));
      final invalid = BodyMetric.fromJson(
          record(-2, changes: {'measuredAt': old.toUtc().toIso8601String()}));
      expect(
          DailyCheckInService.yesterdayMetric([invalid, target], anchor.toUtc())
              ?.id,
          target.id);
      expect(DailyCheckInService.yesterdayMetric([invalid], anchor), isNull);
    }
  });

  test('来源内容或目标日期改变后旧确认被拒绝，两个文档均不写入', () async {
    final (container, storage) = setup([record(-1)]);
    final summary = container.read(trainingMvpProvider).dailyCheckInSummary;
    final metric = container.read(bodyMetricControllerProvider).metrics.single;
    final before = storage.readJson('trainflow.body_metrics.v1');
    final controller = container.read(bodyMetricControllerProvider.notifier);
    for (final token in [
      DailyCheckInService.yesterdayFingerprint(
          BodyMetric.fromJson(record(-1, changes: {'sleepHours': 9})), now),
      DailyCheckInService.yesterdayFingerprint(
          metric, DateTime(now.year, now.month, now.day - 1)),
    ]) {
      await expectLater(
          Future.sync(() => controller.confirmDailyCheckInSameAsYesterday(
              expectedFingerprint: token)),
          throwsStateError);
      expect(storage.readJson('trainflow.body_metrics.v1'), before);
      expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
    }
    await controller.confirmDailyCheckInSameAsYesterday(
        expectedFingerprint: summary.yesterdayFingerprint);
    expect(
        container
            .read(bodyMetricControllerProvider)
            .checkInStreak
            .totalCheckInDays,
        1);
    await controller.confirmDailyCheckInSameAsYesterday(
        expectedFingerprint: summary.yesterdayFingerprint);
    expect(
        container
            .read(bodyMetricControllerProvider)
            .checkInStreak
            .totalCheckInDays,
        1);
    expect(container.read(bodyMetricControllerProvider).metrics, hasLength(2));
  });

  for (final available in [false, true]) {
    testWidgets('实际签到页面显示昨日来源，入口可用状态和保存一致：$available', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (container, storage) = setup([record(available ? -1 : -2)]);
      final before = storage.readJson('trainflow.body_metrics.v1');
      final plan = container.read(trainingMvpProvider).activePlan.toJson();
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DailyCheckInPage())));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, '和昨天一样');
      await tester.scrollUntilVisible(button, 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final action = tester.widget<FilledButton>(button).onPressed;
      expect(action, available ? isNotNull : isNull);
      expect(storage.readJson('trainflow.body_metrics.v1'), before);
      if (available) {
        expect(find.textContaining('沿用昨日'), findsWidgets);
        expect(find.textContaining('体脂率 未记录'), findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(container.read(bodyMetricControllerProvider).metrics.first.note,
            contains('非重新测量'));
        expect(storage.readJson('trainflow.daily_check_ins.v1'), isNotNull);
      } else {
        expect(find.textContaining('请填写今天的状态'), findsOneWidget);
        expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
      }
      expect(container.read(trainingMvpProvider).activePlan.toJson(), plan);
      expect(tester.takeException(), isNull);
    });
  }
}
