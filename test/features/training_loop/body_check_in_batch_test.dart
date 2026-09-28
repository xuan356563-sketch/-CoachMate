import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/daily_check_in_record.dart';
import 'package:trainflow_ai/features/data_center/data_center_page.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

const _bodyKey = 'trainflow.body_metrics.v1';
const _checkKey = 'trainflow.daily_check_ins.v1';
void _seedYesterday(InMemoryLocalStorageService storage) {
  final now = DateTime.now();
  storage.saveJson(_bodyKey, {'metrics': [{
    'id': 'synthetic-yesterday',
    'measuredAt': DateTime(now.year, now.month, now.day - 1, 7).toIso8601String(),
    'source': 'manual', 'weightKg': 70.0, 'restingHeartRate': 60,
    'hrvMs': 50, 'sleepHours': 7.0, 'fatigueLevel': 3,
    'recordedFields': ['weightKg', 'restingHeartRate', 'hrvMs', 'sleepHours', 'fatigueLevel'],
  }]});
}

Future<void> _seed(BodyMetricController controller) async {
  controller
      .recognizeSnapshotText('体重 70 体脂率 18 静息心率 60 HRV 50 睡眠 7 疲劳 3 酸痛 2');
  await controller.confirmPendingMetric();
}

Future<void> _manual(BodyMetricController controller) =>
    controller.saveManualMetric(
        weightKg: 71,
        restingHeartRate: 61,
        hrvMs: 51,
        sleepHours: 7.1,
        fatigueLevel: 3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('快录等待禁用保存，失败保留编辑值，重试后才发布身体与签到', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    await _seed(container.read(bodyMetricControllerProvider.notifier));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DataCenterPage()))));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider).first).onChanged!(71);
    await tester.pump();
    final button = find.widgetWithText(FilledButton, '保存身体数据');
    storage.gate = Completer<void>();
    storage.failFlushes = 1;
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(container.read(bodyMetricControllerProvider).latestMetric!.weightKg,
        70);
    storage.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider).first).value, 71);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(find.textContaining('已恢复原记录'), findsWidgets);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(container.read(bodyMetricControllerProvider).latestMetric!.weightKg,
        71);
    expect(
        container
            .read(bodyMetricControllerProvider)
            .checkInStreak
            .totalCheckInDays,
        1);
  });

  test('已存在的按计划恢复签到不被快录覆盖，昨日预填保留真实字段范围', () async {
    final storage = _Storage();
    _seedYesterday(storage);
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    await _seed(controller);
    await controller.recordContinuityDay(DailyContinuityKind.plannedRest);
    final check = storage.readJson(_checkKey);
    await _manual(controller);
    final fields = container
        .read(bodyMetricControllerProvider)
        .latestMetric!
        .recordedFields;
    expect(fields, hasLength(5));
    expect(storage.readJson(_checkKey), check);
    await controller.confirmDailyCheckInSameAsYesterday();
    expect(
        container
            .read(bodyMetricControllerProvider)
            .latestMetric!
            .recordedFields,
        fields);
    expect(storage.readJson(_checkKey), check);
  });

  test('签到插件停用时快录只写身体，身体插件停用时不能预填，重新开启可用', () async {
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    final storage = _Storage();
    _seedYesterday(storage);
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      pluginRuntimeProvider.overrideWith((ref) => runtime),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    await _seed(controller);
    await runtime.disable('feature.daily_check_in');
    await _manual(controller);
    expect(storage.readJson(_checkKey), isNull);
    await runtime.enable('feature.daily_check_in');
    await runtime.disable('feature.data_center');
    await expectLater(
        Future.sync(controller.confirmDailyCheckInSameAsYesterday),
        throwsStateError);
    expect(storage.readJson(_checkKey), isNull);
    await runtime.enable('feature.data_center');
    await controller.confirmDailyCheckInSameAsYesterday();
    expect(
        container
            .read(bodyMetricControllerProvider)
            .checkInStreak
            .totalCheckInDays,
        1);
  });

  test('第二仓储候选被占用时释放身体锁，迟到结果不覆盖重建控制器', () async {
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    await _seed(controller);
    final now = DateTime.now();
    final held = container
        .read(dailyCheckInRepositoryProvider)
        .prepareConfirmedRecord(
            localDate: now,
            confirmedAt: now,
            source: DailyCheckInSource.prefilled);
    try {
      await expectLater(_manual(controller), throwsStateError);
    } finally {
      held.release();
    }
    storage.gate = Completer<void>();
    final saving = _manual(controller);
    await Future<void>.delayed(Duration.zero);
    container.invalidate(bodyMetricControllerProvider);
    final rebuilt = container.read(bodyMetricControllerProvider);
    await expectLater(
        _manual(container.read(bodyMetricControllerProvider.notifier)),
        throwsStateError);
    final afterBlocked = container.read(bodyMetricControllerProvider);
    storage.gate!.complete();
    await saving;
    expect(container.read(bodyMetricControllerProvider), same(afterBlocked));
    expect(rebuilt.persistenceVersion, 0);
    expect(rebuilt.latestMetric!.weightKg, 70);
  });
  for (final sameYesterday in [false, true]) {
    for (final failure in ['body', 'check', 'flush']) {
      test('${sameYesterday ? '昨日预填' : '普通快录'} $failure 失败恢复两个文档和缓存，重试仅产生一次修订',
          () async {
        final storage = _Storage();
        if (sameYesterday) _seedYesterday(storage);
        final container = ProviderContainer(overrides: [
          localStorageServiceProvider.overrideWithValue(storage)
        ]);
        addTearDown(container.dispose);
        final controller =
            container.read(bodyMetricControllerProvider.notifier);
        await _seed(controller);
        final before = container.read(bodyMetricControllerProvider);
        final body = storage.readJson(_bodyKey);
        final check = storage.readJson(_checkKey);
        Future<void> save() => sameYesterday
            ? controller.confirmDailyCheckInSameAsYesterday()
            : _manual(controller);
        storage.failKey = failure == 'body'
            ? _bodyKey
            : failure == 'check'
                ? _checkKey
                : null;
        storage.failFlushes = failure == 'flush' ? 1 : 0;
        await expectLater(Future.sync(save), throwsStateError);
        expect(storage.readJson(_bodyKey), body);
        expect(storage.readJson(_checkKey), check);
        expect(
            container
                .read(bodyMetricRepositoryProvider)
                .listMetrics()
                .first
                .weightKg,
            70);
        expect(container.read(bodyMetricRepositoryProvider).listRevisions(),
            isEmpty);
        expect(
            container
                .read(dailyCheckInRepositoryProvider)
                .getSnapshot()
                .records,
            isEmpty);
        expect(container.read(bodyMetricRepositoryProvider).listMetrics(),
            hasLength(sameYesterday ? 2 : 1));
        final failed = container.read(bodyMetricControllerProvider);
        expect(failed.metrics, before.metrics);
        expect(failed.persistenceVersion, before.persistenceVersion);
        expect(failed.checkInStreak.totalCheckInDays, 0);
        expect(
            sameYesterday
                ? failed.dailyCheckInStatusMessage
                : failed.manualStatusMessage,
            contains('已恢复原记录'));
        await save();
        expect(container.read(bodyMetricControllerProvider).revisions,
            hasLength(1));
        expect(
            container
                .read(bodyMetricControllerProvider)
                .checkInStreak
                .totalCheckInDays,
            1);
        expect(container.read(bodyMetricControllerProvider).persistenceVersion,
            before.persistenceVersion + 1);
      });
    }
  }

  test('联合提交落盘前两仓储和训练事实不提前发布，所有相关入口阻止交错', () async {
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    final storage = _Storage();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      pluginRuntimeProvider.overrideWith((ref) => runtime)
    ]);
    addTearDown(container.dispose);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    await _seed(controller);
    final before = container.read(trainingMvpProvider);
    await Future<void>.delayed(Duration.zero);
    storage.gate = Completer<void>();
    final saving = _manual(controller);
    try {
      await Future<void>.delayed(Duration.zero);
      expect(
          container
              .read(bodyMetricRepositoryProvider)
              .listMetrics()
              .single
              .weightKg,
          70);
      expect(
          container.read(dailyCheckInRepositoryProvider).getSnapshot().records,
          isEmpty);
      await expectLater(controller.importCsv('date'), throwsStateError);
      await expectLater(controller.recordTiredDailyCheckIn(), throwsStateError);
      await expectLater(controller.confirmPendingMetric(), throwsStateError);
      await expectLater(controller.clear(), throwsStateError);
      await expectLater(
          runtime.disable('feature.daily_check_in'), throwsStateError);
      await expectLater(
          runtime.disable('feature.data_center'), throwsStateError);
      await expectLater(
          runtime.changeAccountScope(replaceScope: () {}), throwsStateError);
    } finally {
      storage.gate!.complete();
      await saving;
    }
    final after = container.read(trainingMvpProvider);
    expect(after.activePlan.toJson(), before.activePlan.toJson());
    expect(after.logs, before.logs);
  });

  test('恢复也失败时保留旧投影并阻止后续 CSV 和签到写入', () async {
    final storage = _Storage();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    await _seed(controller);
    storage.failFlushes = 2;
    await expectLater(_manual(controller), throwsStateError);
    expect(container.read(bodyMetricControllerProvider).manualStatusMessage,
        contains('磁盘状态无法确认'));
    await expectLater(controller.recordTiredDailyCheckIn(), throwsStateError);
    await expectLater(
        controller.importCsv('date,weight\n2026-09-15,71'), throwsStateError);
    expect(container.read(bodyMetricControllerProvider).metrics.single.weightKg,
        70);
  });
}

class _Storage extends InMemoryLocalStorageService {
  String? failKey;
  int failFlushes = 0;
  Completer<void>? gate;
  @override
  void saveJson(String key, Map<String, dynamic> value) {
    if (key == failKey) {
      failKey = null;
      throw StateError('合成联合写入失败');
    }
    super.saveJson(key, value);
  }

  @override
  Future<void> flush() async {
    await gate?.future;
    if (failFlushes > 0) {
      failFlushes--;
      throw StateError('合成联合落盘失败');
    }
  }
}
