import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/core/theme/tdesign_theme.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/plan_adjustment_controller.dart';
import 'package:trainflow_ai/features/training_plan/workout_detail_page.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('详情页通过计划调整控制器保存并恢复训练日', (WidgetTester tester) async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    final WorkoutDay workout =
        container.read(trainingMvpProvider).plans.first.workoutDays.first;
    expect(
      container.read(planAdjustmentControllerProvider).adjustments,
      isEmpty,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: WorkoutDetailPage(
            planId: workout.planId,
            workoutDayId: workout.id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('训练是伙伴的主食'), findsOneWidget);
    expect(find.textContaining('完成度达到 50%'), findsOneWidget);

    await tester.tap(find.text('手动调整本次计划'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('plan-adjustment-minutes-field')),
      '20',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('plan-adjustment-reason-field')),
      '今天状态偏疲劳',
    );
    await tester.tap(find.text('保存调整'));
    await tester.pumpAndSettle();

    final TrainingMvpState adjusted = container.read(trainingMvpProvider);
    expect(container.read(planAdjustmentControllerProvider).adjustments,
        hasLength(1));
    expect(adjusted.findWorkoutDay(workout.id)?.estimatedMinutes, 20);
    expect(find.text('当前调整：20 分钟 · ${workout.intensity}'), findsOneWidget);
    expect(
      find.text(
          '已记录为本地学习信号：${workout.title} 调整为 20 分钟 · ${workout.intensity}。'),
      findsOneWidget,
    );

    await tester.tap(find.text('手动调整本次计划'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复原计划'));
    await tester.pumpAndSettle();

    final TrainingMvpState restored = container.read(trainingMvpProvider);
    expect(restored.findWorkoutDay(workout.id)?.estimatedMinutes,
        workout.estimatedMinutes);
    expect(find.textContaining('当前调整：'), findsNothing);
  });
}
