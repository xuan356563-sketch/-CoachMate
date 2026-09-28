import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/features/daily_adjustment/application/daily_adjustment_controller.dart';
import 'package:trainflow_ai/features/daily_adjustment/daily_adjustment_page.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/readiness_evidence_service.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

import '../resource_library/local_plan_test.dart' show LocalFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 15, 12);
  Map<String, dynamic> record({Map<String, dynamic> changes = const {}}) => {
        'id': 'synthetic-readiness', 'measuredAt': now.toIso8601String(),
        'source': 'manual', 'sleepHours': 8.0, 'fatigueLevel': 2,
        'recordedFields': ['sleepHours', 'fatigueLevel', 'sorenessLevel'],
        ...changes,
      };
  ReadinessEvidence evaluate(List<BodyMetric> metrics) =>
      const ReadinessEvidenceService().evaluate(
        profile: InMemoryUserProfileRepository.defaultProfile,
        metrics: metrics, pain: null, now: now, confirmedAt: now,
      );

  test('字段清单不能把缺失或空疲劳变成零分，回读仍缺失', () {
    for (final nullValue in [true, false]) {
      final json = record(changes: {'fatigueLevel': null});
      if (!nullValue) json.remove('fatigueLevel');
      final metric = BodyMetric.fromJson(json);
      expect(metric.hasValue('fatigueLevel'), isFalse);
      expect(metric.hasValue('sorenessLevel'), isFalse);
      final restored = BodyMetric.fromJson(metric.toJson());
      expect(restored.hasValue('fatigueLevel'), isFalse);
      expect(evaluate([restored]).score, isNull);
      expect(evaluate([restored]).missing, contains('疲劳'));
    }
  });

  test('明确填写的零疲劳仍有效，非数字与分数型整数不能当观测', () {
    final zero = BodyMetric.fromJson(record(changes: {'fatigueLevel': 0}));
    expect(zero.hasValue('fatigueLevel'), isTrue);
    expect(evaluate([zero]).score, isNotNull);
    for (final invalid in ['0', false, 1.5]) {
      final metric = BodyMetric.fromJson(record(changes: {'fatigueLevel': invalid}));
      expect(metric.hasValue('fatigueLevel'), isFalse);
      expect(evaluate([metric]).score, isNull);
    }
  });

  test('仓储保留旧记录，读取不改写原文也不制造可用字段', () {
    final storage = InMemoryLocalStorageService();
    final document = {'schemaVersion': 1, 'metrics': [record(changes: {'fatigueLevel': null})], 'revisions': []};
    storage.saveJson('trainflow.body_metrics.v1', document);
    final restored = PersistedBodyMetricRepository(storage).listMetrics().single;
    expect(restored.sleepHours, 8);
    expect(evaluate([restored]).score, isNull);
    expect(storage.readJson('trainflow.body_metrics.v1'), document);
  });

  test('SharedPreferences 重启读取空值不产生疲劳观测，原始文档保留', () async {
    const key = 'trainflow.body_metrics.v1';
    final raw = jsonEncode({'schemaVersion': 1,
      'metrics': [record(changes: {'fatigueLevel': null})], 'revisions': []});
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final initial = await SharedPreferencesLocalStorageService.create();
    initial.saveRawJsonDocument(key, raw);
    await initial.flush();
    for (var attempt = 0; attempt < 2; attempt++) {
      final storage = await SharedPreferencesLocalStorageService.create();
      final saved = PersistedBodyMetricRepository(storage).listMetrics().single;
      expect(saved.sleepHours, 8);
      expect(saved.hasValue('fatigueLevel'), isFalse);
      expect(evaluate([saved]).score, isNull);
      expect(storage.readRawJsonDocument(key), raw);
    }
  });

  test('静息心率比较展示同一七日窗口和有效样本数量', () {
    BodyMetric sample(int days, int hr, {bool verified = true}) =>
        BodyMetric.fromJson(record(changes: {
          'measuredAt': now.subtract(Duration(days: days)).toIso8601String(),
          'restingHeartRate': hr, 'sourceVerified': verified,
          'recordedFields': ['sleepHours', 'fatigueLevel', 'restingHeartRate'],
        }));
    final result = evaluate([sample(0, 70), sample(1, 50), sample(8, 10),
      sample(-1, 10), sample(2, 10, verified: false)]);
    expect(result.explanation, contains('过去 7 天'));
    expect(result.explanation, contains('2 条有效记录'));
    expect(result.explanation, contains('60.0 次/分'));
    expect(result.score, evaluate([sample(0, 70)]).score! - 6);
  });

  testWidgets('确认与输入变化反映到调整页，缺失再降为无法评估且不改计划', (tester) async {
    final f = (await tester.runAsync(LocalFixture.create))!;
    addTearDown(f.close);
    final planBefore = f.container.read(trainingMvpProvider).activePlan.toJson();
    Future<void> load(Map<String, dynamic> changes) async {
      f.storage.saveJson('trainflow.body_metrics.v1', {
        'schemaVersion': 1, 'metrics': [record(changes: {
          'measuredAt': DateTime.now().toIso8601String(), ...changes})], 'revisions': []});
      // 模拟重新装载本机文档，仓储本身也缓存了上一次读取结果。
      f.container.invalidate(bodyMetricRepositoryProvider);
      f.container.invalidate(bodyMetricControllerProvider);
      f.container.read(bodyMetricControllerProvider);
      await Future<void>.delayed(Duration.zero);
    }
    await tester.runAsync(() => load({}));
    expect(f.container.read(trainingMvpProvider).readinessScore, isNull);
    await tester.runAsync(() => f.container.read(dailyAdjustmentControllerProvider.notifier).confirmTodayStatus());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final good = f.container.read(trainingMvpProvider).readinessScore;
    expect(good, isNotNull);
    await tester.pumpWidget(UncontrolledProviderScope(container: f.container,
        child: const MaterialApp(home: Scaffold(body: DailyAdjustmentPage()))));
    await tester.pumpAndSettle();
    expect(find.textContaining('工程估算，不代表临床测量'), findsOneWidget);
    expect(find.textContaining('睡眠 8.0 小时'), findsOneWidget);
    await tester.runAsync(() => load({'sleepHours': 5.0, 'fatigueLevel': 8}));
    await tester.pumpAndSettle();
    expect(f.container.read(trainingMvpProvider).readinessScore, good! - 16);
    expect(find.textContaining('睡眠 5.0 小时'), findsOneWidget);
    await tester.runAsync(() => load({'fatigueLevel': null}));
    await tester.pumpAndSettle();
    expect(f.container.read(trainingMvpProvider).readinessScore, isNull);
    expect(find.textContaining('未记录：疲劳'), findsOneWidget);
    await tester.runAsync(() => load({'source': 'unknown'}));
    await tester.pumpAndSettle();
    expect(f.container.read(trainingMvpProvider).readinessScore, isNull);
    expect(find.textContaining('未记录：睡眠、疲劳'), findsOneWidget);
    expect(f.container.read(trainingMvpProvider).activePlan.toJson(), planBefore);
  });
}
