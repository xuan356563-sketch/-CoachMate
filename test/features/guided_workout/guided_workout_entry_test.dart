import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/pre_exercise_clearance.dart';
import 'package:trainflow_ai/features/guided_workout/data/guided_workout_catalog_loader.dart';
import 'package:trainflow_ai/features/guided_workout/domain/guided_workout_course.dart';
import 'package:trainflow_ai/features/guided_workout/presentation/guided_workout_pages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('训练计划入口展示三级跳绳课程', (WidgetTester tester) async {
    final GuidedWorkoutCatalog catalog =
        await GuidedWorkoutCatalogLoader().load();
    String? selectedId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GuidedWorkoutCourseSection(
              courses: catalog.courses,
              onSelected: (String id) => selectedId = id,
            ),
          ),
        ),
      ),
    );

    expect(find.text('跳绳跟练课程'), findsOneWidget);
    expect(find.text('20 分钟入门跳绳'), findsOneWidget);
    expect(find.text('38 分钟标准跳绳'), findsOneWidget);
    expect(find.text('45 分钟进阶跳绳'), findsOneWidget);

    await tester.tap(find.text('38 分钟标准跳绳'));
    expect(selectedId, 'jump-rope-standard-38');
  });

  test('筛查无效时阻止开始，有效时允许开始', () {
    final DateTime now = DateTime(2026, 7, 28);

    expect(
      guidedWorkoutStartBlocker(
        const PreExerciseClearance.notCompleted(),
        now,
      ),
      isNotNull,
    );
    expect(
      guidedWorkoutStartBlocker(
        PreExerciseClearance.recorded(
          status: PreExerciseClearanceStatus.selfCleared,
          currentInjuryOrRestriction: false,
          completedAt: now,
        ),
        now,
      ),
      isNull,
    );
  });
}
