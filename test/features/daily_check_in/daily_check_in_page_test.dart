import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/daily_check_in/daily_check_in_page.dart';
import 'package:trainflow_ai/data/models/daily_check_in_record.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('每日签到偏累入口写入独立控制器并同步训练投影', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DailyCheckInPage()),
      ),
    );
    await tester.pump();

    final Finder tiredButton =
        find.widgetWithText(OutlinedButton, '今天偏累，建议轻松版');
    expect(tiredButton, findsOneWidget);
    await tester.scrollUntilVisible(
      tiredButton,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(tiredButton);
    await tester.pump();
    await tester.pump();

    final BodyMetricState bodyState =
        container.read(bodyMetricControllerProvider);
    final TrainingMvpState trainingState = container.read(trainingMvpProvider);
    expect(bodyState.latestMetric, isNull);
    expect(bodyState.dailyCheckInStatusMessage, contains('已完成今日主观签到'));
    expect(bodyState.checkInStreak.currentStreak, 1);
    expect(bodyState.checkInStreak.totalCheckInDays, 1);
    expect(trainingState.latestBodyMetric, isNull);
    expect(trainingState.dailyCheckInStatusMessage, contains('已完成今日主观签到'));
    expect(trainingState.dailyAdjustmentStatusMessage, contains('未生成身体指标'));
  });

  testWidgets('计划恢复需要确认且不生成训练或身体指标', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DailyCheckInPage()),
      ),
    );
    await tester.pump();

    final Finder plannedRestButton = find.text('按计划恢复');
    await tester.scrollUntilVisible(
      plannedRestButton,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(plannedRestButton);
    await tester.pumpAndSettle();

    expect(find.text('确认按计划恢复'), findsOneWidget);
    expect(find.textContaining('不会生成训练完成'), findsOneWidget);
    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    final BodyMetricState state = container.read(bodyMetricControllerProvider);
    expect(state.metrics, isEmpty);
    expect(state.dailyCheckInStatusMessage, contains('按计划恢复'));
    expect(
      container
          .read(dailyCheckInRepositoryProvider)
          .getSnapshot()
          .records
          .single
          .continuityKind,
      DailyContinuityKind.plannedRest,
    );
  });
}
