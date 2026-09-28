import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/data_center/data_center_page.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_export_controller.dart';
import 'package:trainflow_ai/services/body_metric_import_service.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

BodyMetric _metric({Map<String, dynamic> changes = const {}}) =>
    BodyMetric.fromJson({
      'id': 'synthetic-history',
      'measuredAt': '2026-01-01T12:00:00.000',
      'weightKg': 70.5,
      'bodyFatPercentage': 18.0,
      'restingHeartRate': 60,
      'hrvMs': 50,
      'sleepHours': 7.0,
      'fatigueLevel': 0,
      'sorenessLevel': 0,
      'moodLabel': '保存时标签',
      'source': 'manual',
      'note': '合成历史',
      ...changes,
    });

ProviderContainer _container(
    InMemoryLocalStorageService storage, BodyMetric metric) {
  PersistedBodyMetricRepository(storage).saveMetric(metric);
  final container = ProviderContainer(
      overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('完整旧记录 CSV 保留原表头、列顺序、单位精度及零疲劳酸痛', () {
    final container = _container(InMemoryLocalStorageService(), _metric());
    expect(
        container.read(trainingMvpProvider).bodyMetricCsvExport,
        'measured_at,weight_kg,body_fat_percentage,resting_heart_rate,hrv_ms,sleep_hours,fatigue_level,soreness_level,mood,source,note\n'
        '2026-01-01T12:00:00.000,70.5,18.0,60,50,7.0,0,0,保存时标签,manual,合成历史');
  });

  test('CSV 留空继承及缺失字段，重新导入也不能变成本次观测', () {
    final storage = InMemoryLocalStorageService();
    final container = _container(
        storage,
        _metric(changes: {
          'recordedFields': ['weightKg', 'fatigueLevel'],
        }));
    final state = container.read(trainingMvpProvider);
    final before = storage.readJson('trainflow.body_metrics.v1');
    final csv = state.bodyMetricCsvExport;
    expect(csv.split('\n').last.split(',').sublist(1, 8),
        ['70.5', '', '', '', '', '0', '']);
    final imported = BodyMetricImportService()
        .parseCsv(csv, historicalFallback: _metric())
        .metrics
        .single;
    expect(imported.recordedFields, {'weightKg', 'fatigueLevel'});
    expect(imported.hasValue('hrvMs'), isFalse);
    expect(storage.readJson('trainflow.body_metrics.v1'), before);
    expect(container.read(trainingMvpProvider).activePlan.toJson(),
        state.activePlan.toJson());
    expect(storage.readJson('trainflow.body_metric_exports.v1'), isNull);
  });

  for (final changes in [
    <String, dynamic>{'source': 'legacy_unknown'},
    <String, dynamic>{'sourceVerified': false},
  ]) {
    test('CSV 未确认来源不伪装手动测量：$changes', () {
      final container =
          _container(InMemoryLocalStorageService(), _metric(changes: changes));
      final csv = container.read(trainingMvpProvider).bodyMetricCsvExport;
      final cells = csv.split('\n').last.split(',');
      expect(cells.sublist(1, 8), List.filled(7, ''));
      expect(cells[9], 'unknown');
      expect(
          () => BodyMetricImportService()
              .parseCsv(csv, historicalFallback: _metric()),
          throwsFormatException);
    });
  }

  test('兼容零值、无效旧值不导出为观测，七个字段各自检查', () {
    final container = _container(
        InMemoryLocalStorageService(),
        _metric(changes: {
          'weightKg': 0,
          'bodyFatPercentage': -1,
          'restingHeartRate': 0,
          'hrvMs': -1,
          'sleepHours': 0,
          'fatigueLevel': 11,
          'sorenessLevel': -1,
        }));
    expect(
        container
            .read(trainingMvpProvider)
            .bodyMetricCsvExport
            .split('\n')
            .last
            .split(',')
            .sublist(1, 8),
        List.filled(7, ''));
  });

  test('JSON 保留历史值及字段来源元数据，CSV 保持备注转义', () {
    final original = _metric(changes: {
      'sourceVerified': false,
      'recordedFields': ['weightKg'],
      'note': '原始,备注\n含"引号"',
    });
    final storage = InMemoryLocalStorageService();
    final container = _container(storage, original);
    final state = container.read(trainingMvpProvider);
    final exported = jsonDecode(state.bodyMetricJsonExport) as List;
    expect(exported.single, original.toJson());
    final restored =
        BodyMetric.fromJson(exported.single as Map<String, dynamic>);
    expect(restored.hrvMs, 50);
    expect(restored.hasValue('hrvMs'), isFalse);
    expect(restored.sourceVerified, isFalse);
    expect(state.bodyMetricCsvExport, contains('"原始,备注\n含""引号"""'));
    expect(PersistedBodyMetricRepository(storage).listMetrics().single.toJson(),
        original.toJson());
  });

  testWidgets('实际 CSV 按钮预览留空字段，登记出口不改身体记录或计划', (tester) async {
    final storage = InMemoryLocalStorageService();
    final container = _container(
        storage,
        _metric(changes: {
          'recordedFields': ['weightKg', 'fatigueLevel'],
        }));
    final before = storage.readJson('trainflow.body_metrics.v1');
    final state = container.read(trainingMvpProvider);
    final csv = state.bodyMetricCsvExport;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DataCenterPage()))));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, '导出 CSV');
    await tester.scrollUntilVisible(button, 400,
        scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(container.read(bodyMetricExportTextProvider), csv);
    expect(find.text(csv), findsOneWidget);
    expect(container.read(bodyMetricExportControllerProvider).records,
        hasLength(1));
    expect(storage.readJson('trainflow.body_metrics.v1'), before);
    expect(container.read(trainingMvpProvider).activePlan.toJson(),
        state.activePlan.toJson());
    expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
    expect(tester.takeException(), isNull);
  });

  for (final unknown in [false, true]) {
    testWidgets('旧历史始终可读，逐字段显示且来源明确：未知=$unknown', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = InMemoryLocalStorageService();
      final container = _container(
          storage,
          _metric(changes: {
            'source': unknown ? 'legacy_unknown' : 'manual',
            'recordedFields': ['weightKg', 'fatigueLevel', 'sorenessLevel'],
          }));
      final before = storage.readJson('trainflow.body_metrics.v1');
      final plan = container.read(trainingMvpProvider).activePlan.toJson();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!),
          home: const Scaffold(body: DataCenterPage()),
        ),
      ));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('body-record-synthetic-history'));
      expect(card, findsOneWidget);
      await tester.scrollUntilVisible(card, 600,
          scrollable: find.byType(Scrollable).first, maxScrolls: 50);
      await tester.pumpAndSettle();
      final texts = tester
          .widgetList<Text>(
              find.descendant(of: card, matching: find.byType(Text)))
          .map((text) => text.data ?? '')
          .join('\n');
      expect(texts, contains('2026-01-01'));
      expect(texts, contains('酸痛'));
      expect('无有效记录'.allMatches(texts), hasLength(unknown ? 7 : 4));
      expect(texts, contains(unknown ? '来源未确认' : '手动录入'));
      expect(texts, contains('保存时标签'));
      if (unknown) {
        expect(texts, isNot(contains('手动录入')));
        expect(texts, isNot(contains('70.5 kg')));
      } else {
        expect(texts, contains('70.5 kg'));
        expect('0/10'.allMatches(texts), hasLength(2));
      }
      expect(tester.takeException(), isNull);
      expect(storage.readJson('trainflow.body_metrics.v1'), before);
      expect(container.read(trainingMvpProvider).activePlan.toJson(), plan);
    });
  }
}
