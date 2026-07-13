import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/daily_check_in/daily_check_in_page.dart';
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
    await tester.tap(tiredButton);
    await tester.pump();
    await tester.pump();

    final BodyMetricState bodyState =
        container.read(bodyMetricControllerProvider);
    final TrainingMvpState trainingState = container.read(trainingMvpProvider);
    expect(bodyState.latestMetric?.note, '精简签到：今天偏累，建议轻松版');
    expect(bodyState.dailyCheckInStatusMessage, contains('已记录偏累'));
    expect(trainingState.latestBodyMetric?.note, '精简签到：今天偏累，建议轻松版');
    expect(trainingState.dailyCheckInStatusMessage, contains('已记录偏累'));
  });
}
