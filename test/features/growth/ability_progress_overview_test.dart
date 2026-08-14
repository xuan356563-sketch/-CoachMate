import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/features/dashboard/today_training_page.dart';
import 'package:trainflow_ai/features/growth/ability_progress_overview.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('能力曲线只连接同算法和同口径的有效指标', () {
    final AbilityProgressSnapshot snapshot =
        const AbilityProgressSelector().build(<MetricAggregate>[
      _metric(
        id: 'hr-new',
        code: 'same_pace_heart_rate',
        date: DateTime(2026, 7, 14),
        value: 148,
        metadata: const <String, Object?>{'bandVersion': 'band-b'},
      ),
      _metric(
        id: 'hr-old-compatible',
        code: 'same_pace_heart_rate',
        date: DateTime(2026, 7, 7),
        value: 150,
        metadata: const <String, Object?>{'bandVersion': 'band-b'},
      ),
      _metric(
        id: 'hr-old-incompatible',
        code: 'same_pace_heart_rate',
        date: DateTime(2026, 6, 30),
        value: 155,
        metadata: const <String, Object?>{'bandVersion': 'band-a'},
      ),
      _metric(
        id: 'hr-invalidated',
        code: 'same_pace_heart_rate',
        date: DateTime(2026, 7, 21),
        value: 140,
        status: MetricStatus.invalidated,
        metadata: const <String, Object?>{'bandVersion': 'band-b'},
      ),
    ]);

    expect(
      snapshot.samePaceHeartRate.points
          .map((AbilityProgressPoint item) => item.value),
      <double>[150, 148],
    );
    expect(snapshot.samePaceHeartRate.summary, contains('下降 2.0 bpm'));
  });

  test('力量曲线不会跨动作连接', () {
    final AbilityProgressSnapshot snapshot =
        const AbilityProgressSelector().build(<MetricAggregate>[
      _metric(
        id: 'deadlift-new',
        code: 'strength_e1rm',
        date: DateTime(2026, 7, 14),
        value: 110,
        metadata: const <String, Object?>{
          'exerciseKey': 'deadlift',
          'exerciseName': '硬拉',
        },
      ),
      _metric(
        id: 'deadlift-old',
        code: 'strength_e1rm',
        date: DateTime(2026, 7, 7),
        value: 105,
        metadata: const <String, Object?>{
          'exerciseKey': 'deadlift',
          'exerciseName': '硬拉',
        },
      ),
      _metric(
        id: 'squat-old',
        code: 'strength_e1rm',
        date: DateTime(2026, 6, 30),
        value: 95,
        metadata: const <String, Object?>{
          'exerciseKey': 'squat',
          'exerciseName': '深蹲',
        },
      ),
    ]);

    expect(snapshot.strength.title, '力量主项 · 硬拉');
    expect(snapshot.strength.points, hasLength(2));
    expect(snapshot.strength.summary, contains('提升 5.0 kg'));
  });

  testWidgets('首页紧凑卡始终显示三项且空态不造0值', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AbilityProgressOverview(
            metrics: AsyncData<List<MetricAggregate>>(<MetricAggregate>[]),
            compact: true,
          ),
        ),
      ),
    );

    expect(find.text('能力进步总览'), findsOneWidget);
    expect(find.text('负荷进展（ACWR）'), findsOneWidget);
    expect(find.text('力量主项'), findsOneWidget);
    expect(find.text('同配速心率'), findsOneWidget);
    expect(find.textContaining('数据积累中'), findsNWidgets(3));
    expect(find.textContaining('0.0'), findsNothing);
  });

  testWidgets('393x852今日成长下滑后仍可看到三项能力摘要', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(
            InMemoryLocalStorageService(),
          ),
        ],
        child: const MaterialApp(home: TodayTrainingPage()),
      ),
    );
    await tester.pumpAndSettle();

    for (final String label in <String>[
      '负荷进展（ACWR）',
      '力量主项',
      '同配速心率',
    ]) {
      final Finder finder = find.text(label);
      await tester.scrollUntilVisible(
        finder,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(finder, findsOneWidget);
      expect(tester.getBottomRight(finder).dy, lessThan(852));
    }
  });
}

MetricAggregate _metric({
  required String id,
  required String code,
  required DateTime date,
  required double value,
  MetricStatus status = MetricStatus.ready,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return MetricAggregate(
    id: id,
    athleteProfileId: 'athlete-1',
    metricCode: code,
    period: MetricPeriod.week,
    periodStart: date,
    value: value,
    unit: code == 'same_pace_heart_rate'
        ? 'bpm'
        : code == 'strength_e1rm'
            ? 'kg'
            : 'ratio',
    sampleCount: 3,
    sampleDurationSeconds: 1800,
    coverage: 1,
    status: status,
    algorithmVersion: 'algorithm-v1',
    inputFingerprint: id,
    computedAt: date,
    metadata: metadata,
  );
}
