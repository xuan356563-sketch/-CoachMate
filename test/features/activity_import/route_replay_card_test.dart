import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/imported_workout.dart';
import 'package:trainflow_ai/features/activity_import/route_replay_card.dart';

void main() {
  testWidgets('离线路线回放支持播放进度和明确删除确认', (WidgetTester tester) async {
    bool deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RouteReplayCard(
              workout: ImportedWorkout(
                id: 'route-test',
                source: ImportedWorkoutSource.gpx,
                title: '测试路线',
                startedAt: DateTime(2026, 7, 20),
                distanceKm: 5,
                durationMinutes: 30,
                elevationGainMeters: 20,
                averageHeartRate: 140,
                trainingEffect: TrainingEffectLabel.aerobic,
                routeShape: const <RouteShapePoint>[
                  RouteShapePoint(
                    x: 0,
                    y: 0,
                    progress: 0,
                    segmentIndex: 0,
                  ),
                  RouteShapePoint(
                    x: 1,
                    y: 1,
                    progress: 1,
                    segmentIndex: 0,
                  ),
                ],
              ),
              onDeleteRoute: () => deleted = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('离线路线回放'), findsOneWidget);
    expect(find.textContaining('不保存原始经纬度'), findsOneWidget);
    await tester.tap(find.byTooltip('播放回放'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('暂停回放'), findsOneWidget);

    await tester.tap(find.text('删除路线'));
    await tester.pumpAndSettle();
    expect(find.text('删除本地路线数据？'), findsOneWidget);
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });
}
