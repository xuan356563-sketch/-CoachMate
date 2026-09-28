import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/user_insight.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/models/pain_log.dart';
import 'package:trainflow_ai/data/local/cloud_sync_projection_builder.dart';
import 'package:trainflow_ai/data/repositories/training_log_repository.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/daily_check_in/daily_check_in_page.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import '../../support/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late TrainingMvpState base;
  late DateTime now;
  setUp(() {
    container = ProviderContainer(overrides: [
      localStorageServiceProvider
          .overrideWithValue(InMemoryLocalStorageService()),
    ]);
    base = container.read(trainingMvpProvider).copyWith(
      bodyMetrics: [],
      logs: [],
      painLogs: [],
      profileCompleted: false,
    );
    now = DateTime.now();
  });
  tearDown(() => container.dispose());

  TrainingLog log({Map<String, dynamic> changes = const {}}) =>
      TrainingLog.fromJson({
        'id': 'synthetic-recovery',
        'workoutDayId': base.todayWorkout.id,
        'date': now.subtract(const Duration(minutes: 30)).toIso8601String(),
        'createdAt': now.toIso8601String(),
        'completed': true,
        'rpe': 8,
        'fatigueLevel': 8,
        'sleepQuality': 7,
        'logKind': 'sessionReview',
        ...changes,
      });
  BodyMetric metric({Map<String, dynamic> changes = const {}}) =>
      BodyMetric.fromJson({
        'id': 'synthetic-body',
        'measuredAt': now.toIso8601String(),
        'source': 'manual',
        'weightKg': 70,
        'fatigueLevel': 8,
        'sorenessLevel': 6,
        'sleepHours': 6,
        ...changes,
      });
  int baseHours(TrainingMvpState state) =>
      switch (state.todayWorkout.decisionType) {
        TrainingDecisionType.normal => 18,
        TrainingDecisionType.deload => 16,
        TrainingDecisionType.recovery => 10,
        TrainingDecisionType.technique => 12,
        TrainingDecisionType.rest => 6,
      };

  for (final changes in [
    <String, dynamic>{'source': 'unknown'},
    <String, dynamic>{'sourceVerified': false},
    <String, dynamic>{
      'recordedFields': ['weightKg']
    },
    <String, dynamic>{'fatigueLevel': 11, 'sorenessLevel': 11, 'sleepHours': 0},
  ]) {
    test('无效或继承身体字段不改变恢复估算：$changes', () {
      final state = base.copyWith(logs: [log()]);
      expect(
          state.copyWith(
              bodyMetrics: [metric(changes: changes)]).recommendedRecoveryHours,
          state.recommendedRecoveryHours);
    });
  }

  test('身体证据只使用当日非未来记录，字段独立计算', () {
    final state = base.copyWith(logs: [log()]);
    for (final time in [
      now.subtract(const Duration(days: 1)),
      now.add(const Duration(hours: 1))
    ]) {
      expect(
          state.copyWith(bodyMetrics: [
            metric(changes: {'measuredAt': time.toIso8601String()})
          ]).recommendedRecoveryHours,
          state.recommendedRecoveryHours);
    }
    for (final entry
        in {'fatigueLevel': 6, 'sorenessLevel': 4, 'sleepHours': 4}.entries) {
      expect(
          state.copyWith(bodyMetrics: [
            metric(changes: {
              'recordedFields': [entry.key]
            })
          ]).recommendedRecoveryHours,
          state.recommendedRecoveryHours + entry.value);
    }
    final zeros = metric(changes: {
      'fatigueLevel': 0,
      'sorenessLevel': 0,
      'recordedFields': ['fatigueLevel', 'sorenessLevel']
    });
    expect(state.copyWith(bodyMetrics: [zeros]).recommendedRecoveryHours,
        state.recommendedRecoveryHours);
  });

  test('没有会话证据不输出具体倒计时或恢复提醒', () {
    expect(base.recoveryCountdownLabel, contains('无法估算'));
    expect(
        base.trainingReminders.where((r) => r.id == 'recovery-check'), isEmpty);
    expect(base.predictionLogs.first.predictedValue, contains('无法评估'));
  });

  test('步骤、导入推算、未知来源、异常时间及缺失 RPE 不充当会话证据', () {
    for (final changes in [
      {'logKind': 'playerStep'},
      {'logKind': 'activityImport'},
      {'logKind': 'unknown'},
      {'logKind': null},
      {'recoveryEvidenceVerified': false},
      {'recoveryEvidenceVerified': 'false'},
      {'rpe': 0},
      {'rpe': 11},
      {'rpe': 6.8},
      {'date': now.add(const Duration(hours: 1)).toIso8601String()},
      {'createdAt': now.add(const Duration(hours: 1)).toIso8601String()},
      {'date': 'invalid'},
      {'createdAt': 'invalid'},
      {'completed': false},
    ]) {
      final state = base.copyWith(logs: [log(changes: changes)]);
      expect(state.recoveryCountdownLabel, contains('无法估算'),
          reason: '$changes');
      expect(state.trainingReminders.where((r) => r.id == 'recovery-check'),
          isEmpty,
          reason: '$changes');
      expect(state.predictionLogs.first.predictedValue, contains('无法评估'),
          reason: '$changes');
    }
  });

  test('补录按训练发生时间扣除经过小时，倒计时结束不能证明已恢复', () {
    final record = log(changes: {
      'date': now.subtract(const Duration(days: 3)).toIso8601String()
    });
    final state = base.copyWith(logs: [record]);
    expect(state.remainingRecoveryHours, 0);
    expect(state.recoveryCountdownLabel, '估算时段已结束');
    expect(state.recoveryAdvice, contains('不代表身体已恢复'));
    expect(state.predictionLogs.first.predictedAt, record.date);
    expect(state.predictionLogs.first.dueAt,
        record.date.add(Duration(hours: state.recommendedRecoveryHours)));
    expect(state.predictionLogs.first.status, PredictionStatus.pending);
  });

  test('按训练时间选择最近有效会话，迟到补录与列表顺序不覆盖它', () {
    final current = log();
    final older = log(changes: {
      'id': 'older',
      'rpe': 10,
      'date': now.subtract(const Duration(days: 3)).toIso8601String()
    });
    final step = log(changes: {'logKind': 'playerStep', 'rpe': 10});
    final expected = base.copyWith(logs: [current]);
    for (final records in [
      [older, step, current],
      [current, older, step]
    ]) {
      final state = base.copyWith(logs: records);
      expect(state.recommendedRecoveryHours, expected.recommendedRecoveryHours);
      expect(state.remainingRecoveryHours, expected.remainingRecoveryHours);
    }
  });

  test('有效会话和完整当日记录沿用原系数，部分训练也可记录实际反馈', () {
    final state = base.copyWith(logs: [log()], bodyMetrics: [metric()]);
    expect(state.recommendedRecoveryHours, baseHours(state) + 9 + 6 + 4 + 4);
    expect(state.recoveryCountdownLabel, contains('工程估算'));
    final partial = base.copyWith(logs: [
      log(changes: {'completed': false, 'actualDurationMinutes': 10})
    ]);
    expect(partial.recoveryCountdownLabel, contains('工程估算'));
    expect(state.activePlan.toJson(), base.activePlan.toJson());
  });

  test('来源不明的旧记录保留可读，保存重启后不能洗成可信会话', () {
    final storage = InMemoryLocalStorageService();
    final unknown = log(changes: {'logKind': 'other'});
    PersistedTrainingLogRepository(storage).saveLog(unknown);
    final restored = PersistedTrainingLogRepository(storage).listLogs().single;
    expect(restored.rpe, 8);
    expect(restored.date, unknown.date);
    expect(base.copyWith(logs: [restored]).recoveryCountdownLabel,
        contains('无法估算'));
  });

  testWidgets('签到页显示工程估算与无证据原因，窄屏大字可读', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!),
            home: const Scaffold(body: DailyCheckInPage()))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('恢复时间工程估算'), 200);
    await tester.pumpAndSettle();
    expect(find.text('恢复时间工程估算'), findsOneWidget);
    expect(find.textContaining('无法估算'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('证据说明包含时间、来源、实际值和缺失项，疼痛保护优先', () {
    final state = base.copyWith(logs: [
      log()
    ], bodyMetrics: [
      metric(changes: {
        'recordedFields': ['fatigueLevel'],
      })
    ]);
    expect(state.recoveryEvidenceSummary, contains('训练复盘 RPE 8'));
    expect(state.recoveryEvidenceSummary, contains('疲劳 8/10'));
    expect(state.recoveryEvidenceSummary, contains('缺失：酸痛、睡眠'));
    expect(state.recoveryEvidenceSummary, contains('未减免时长'));
    final protected = state.copyWith(painLogs: [
      PainLog(
          id: 'synthetic-pain',
          bodyPart: '膝',
          painLevel: 8,
          timing: PainTiming.ongoing,
          note: '合成保护测试',
          date: now,
          createdAt: now)
    ]);
    expect(protected.recoveryAdvice, contains('停止相关训练并就医'));
    expect(protected.morningReportAdvice, contains('疼痛红线'));
  });

  testWidgets('旧提醒路由仍进入签到页并能看到恢复估算', (tester) async {
    await tester.pumpWidget(TestHarness().buildApp(const TrainFlowApp()));
    router.go(AppRoutes.reminders);
    await tester.pumpAndSettle();
    addTearDown(() => router.go(AppRoutes.dashboard));
    expect(find.byType(DailyCheckInPage), findsOneWidget);
    await tester.scrollUntilVisible(find.text('恢复时间工程估算'), 200);
    await tester.pumpAndSettle();
    expect(find.text('恢复时间工程估算').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('恢复来源标记不增加云同步字段，读取估算不改业务文档', () {
    const key = 'trainflow.training_logs.v1';
    Map<String, Object?> payload(TrainingLog record) =>
        CloudSyncProjectionBuilder.build(
            changedKey: key,
            previousDocuments: {},
            currentDocuments: {
              'trainflow.generated_training_plan.v1': {
                'plan': base.activePlan.toJson()
              },
              key: {
                'logs': [record.toJson()]
              },
            }).single.payload;
    final valid = log();
    final unknown = log(changes: {'recoveryEvidenceVerified': false});
    expect(payload(valid), payload(unknown));
    expect(payload(unknown).keys, isNot(contains('recoveryEvidenceVerified')));
    final storage = container.read(localStorageServiceProvider);
    final before = storage.readJson(key);
    final state = base.copyWith(logs: [valid], bodyMetrics: [metric()]);
    expect(state.recoveryEvidenceSummary, isNotEmpty);
    expect(state.trainingReminders, isNotEmpty);
    expect(state.predictionLogs, isNotEmpty);
    expect(storage.readJson(key), before);
    expect(state.activePlan.toJson(), base.activePlan.toJson());
  });
}
