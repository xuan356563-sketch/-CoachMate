import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/daily_activity_summary.dart';
import 'package:trainflow_ai/data/models/daily_check_in_record.dart';
import 'package:trainflow_ai/data/models/health_snapshot.dart';
import 'package:trainflow_ai/features/dashboard/widgets/today_health_overview.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 24, 10);

  DailyActivitySummary activity({
    required String localDate,
    int? steps,
    double? activeEnergyKcal,
  }) {
    return DailyActivitySummary(
      athleteProfileId: 'athlete-test',
      localDate: localDate,
      timeZoneName: 'Asia/Shanghai',
      timeZoneOffsetMinutes: 480,
      steps: steps,
      activeEnergyKcal: activeEnergyKcal,
      syncedAt: DateTime.utc(2026, 8, 24),
    );
  }

  TodayHealthOverviewData dataFrom(
    List<DailyActivitySummary> activities, {
    List<HealthSnapshot> snapshots = const <HealthSnapshot>[],
  }) {
    return TodayHealthOverviewData.fromSources(
      activitySummaries: activities,
      healthSnapshots: snapshots,
      latestBodyMetric: null,
      checkInStreak: const CheckInStreakState.empty(),
      activityStatusMessage: '已读取每日活动摘要。',
      now: now,
    );
  }

  test('今日活动只取当前自然日，历史数据只进入七日趋势', () {
    final TodayHealthOverviewData data = dataFrom(
      <DailyActivitySummary>[
        activity(localDate: '2026-08-23', steps: 7038),
        activity(localDate: '2026-08-24', steps: 0),
      ],
    );

    expect(data.latestActivity?.localDate, '2026-08-24');
    expect(data.latestActivity?.steps, 0);
    expect(
      data.weekValuesFor(DailyActivityField.steps, now),
      <double?>[null, null, null, null, null, 7038, 0],
    );
  });

  test('缺少今日摘要时不把历史活动伪装成今日数据', () {
    final TodayHealthOverviewData data = dataFrom(
      <DailyActivitySummary>[
        activity(localDate: '2026-08-23', steps: 7038),
      ],
      snapshots: <HealthSnapshot>[
        HealthSnapshot(
          id: 'snapshot',
          date: DateTime(2026, 8, 24),
          sleepHours: 0,
          restingHeartRate: 0,
          hrvMs: 0,
          weightKg: null,
          bodyFatPercentage: null,
          syncedAt: DateTime.utc(2026, 8, 24),
        ),
      ],
    );

    expect(data.latestActivity, isNull);
    // 活动的真实零值仍有效；无来源且无效的恢复值不能当成当日观测。
    expect(data.sleepHours, isNull);
    expect(data.restingHeartRate, isNull);
    expect(data.hrvMs, isNull);
  });

  testWidgets('320 宽度与两倍字号下健康概览改为单列并保留入口', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool openedActivitySettings = false;
    bool openedCheckIn = false;
    final TodayHealthOverviewData data = dataFrom(
      <DailyActivitySummary>[
        activity(localDate: '2026-08-24', steps: 4800),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: TodayHealthOverview(
                  data: data,
                  now: now,
                  onOpenActivitySettings: () => openedActivitySettings = true,
                  onOpenCheckIn: () => openedCheckIn = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final Rect stepsCard = tester.getRect(
      find.byKey(const ValueKey<String>('today-health-steps-card')),
    );
    final Rect energyCard = tester.getRect(
      find.byKey(const ValueKey<String>('today-health-energy-card')),
    );
    expect(energyCard.top, greaterThan(stepsCard.bottom));
    expect(stepsCard.right, lessThanOrEqualTo(320));

    final Finder settings =
        find.byKey(const ValueKey<String>('today-health-open-settings'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pump();
    expect(openedActivitySettings, isTrue);

    final Finder habitCard =
        find.byKey(const ValueKey<String>('today-habit-summary-card'));
    await tester.ensureVisible(habitCard);
    await tester.tap(habitCard);
    await tester.pump();
    expect(openedCheckIn, isTrue);
  });
}
