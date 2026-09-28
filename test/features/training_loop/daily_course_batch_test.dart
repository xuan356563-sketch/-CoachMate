import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/daily_adjustment.dart';
import 'package:trainflow_ai/data/repositories/plan_adjustment_repository.dart';
import 'package:trainflow_ai/data/repositories/training_schedule_repository.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/daily_adjustment/application/daily_adjustment_controller.dart';
import 'package:trainflow_ai/features/daily_adjustment/application/daily_course_adjustment.dart';
import 'package:trainflow_ai/features/daily_adjustment/daily_adjustment_page.dart';
import 'package:trainflow_ai/plugins/history/core_history.dart';
import 'package:trainflow_ai/features/training_plan/plan_list_page.dart';
import 'package:trainflow_ai/features/training_plan/application/four_week_plan_controller.dart';
import 'package:trainflow_ai/features/profile/application/training_schedule_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/plan_adjustment_controller.dart';

import 'daily_course_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无器械与时间不足同时出现时不把动作替换悄悄写入课程', () async {
    final f = await fixture();
    addTearDown(f.close);
    final before = f.container.read(trainingMvpProvider).activePlan.toJson();
    await f.container
        .read(dailyAdjustmentControllerProvider.notifier)
        .setDailyTrainingEnvironment(TrainingEnvironment.noEquipment);
    await Future<void>.delayed(Duration.zero);
    expect(f.container.read(trainingMvpProvider).noEquipmentConstraint, isTrue);
    final preview = f.container.read(dailyCourseAdjustmentProvider).preview();
    expect(preview.candidate, isNull,
        reason: '本流程仅允许已审核的缩短，不应保存未确认的器械替换');
    expect(preview.reason, contains('器械'));
    expect(f.container.read(trainingMvpProvider).activePlan.toJson(), before);
    expect(PersistedPlanAdjustmentRepository(f.storage).listAdjustments(), isEmpty);
  });

  testWidgets('页面展示完整差异，取消不写入，确认后跟练及历史保持一致', (tester) async {
    final f = (await tester.runAsync(fixture))!;
    addTearDown(f.close);
    final before = f.container.read(trainingMvpProvider).todayWorkout;
    final versionBefore = f.repo.getHistory().toJson();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: f.container,
      child: const MaterialApp(home: Scaffold(body: DailyAdjustmentPage())),
    ));
    await tester.pumpAndSettle();
    final previewButton = find.text('查看可执行课程差异');
    await tester.ensureVisible(previewButton);
    await tester.pumpAndSettle();
    await tester.tap(previewButton);
    await tester.pumpAndSettle();
    expect(find.text('确认课程调整'), findsOneWidget);
    expect(find.text('原主训练：${before.mainSets.join('；')}'), findsOneWidget);
    expect(find.text('原辅助训练：${before.accessoryWork.isEmpty ? '无' : before.accessoryWork.join('；')}'), findsOneWidget);
    expect(f.container.read(trainingMvpProvider).todayWorkout.toJson(), before.toJson());
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(PersistedPlanAdjustmentRepository(f.storage).listAdjustments(), isEmpty);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();
    // 场景初始化在真实异步区完成，提交后的仓储通知也需交还该事件循环。
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('课程调整已保存并应用到跟练，可在核心历史查看。'), findsOneWidget,
        reason: tester.widgetList<Text>(find.descendant(of: find.byType(SnackBar),
            matching: find.byType(Text))).map((text) => text.data).join('；'));
    final saved = f.container.read(coreHistoryProvider).listCourseAdjustments().single;
    final current = f.container.read(trainingMvpProvider).todayWorkout;
    expect(find.text('当前课程已应用确认调整：${before.estimatedMinutes} → 30 分钟。'), findsOneWidget);
    expect(current.toJson(), saved.workoutSnapshot!.toJson());
    expect(current.mainSets, [before.mainSets.first]);
    expect(current.accessoryWork, isEmpty);
    expect(current.intensity, before.intensity);
    expect(current.cooldownSteps, before.cooldownSteps);
    expect(f.repo.getHistory().toJson(), versionBefore);
    final controller = f.container.read(trainingMvpProvider.notifier);
    expect(controller.startWorkoutPlayer(workoutDayId: current.id), isTrue);
    expect(f.container.read(trainingMvpProvider).activeWorkoutPlayerWorkout.toJson(), current.toJson());
    expect(f.container.read(trainingMvpProvider).workoutPlayerSteps.fold<int>(
        0, (total, step) => total + step.estimatedSeconds), current.estimatedMinutes * 60,
        reason: '课程声明的总时长必须与实际五步倒计时一致');
    expect(current.cooldownSteps, contains('低强度整理 5 分钟'));
    expect(f.container.read(trainingMvpProvider).workoutPlayerSteps.last.estimatedSeconds,
        5 * 60, reason: '保留的冷身处方与倒计时必须一致');
    await controller.stopWorkoutPlayer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: f.container,
      child: const MaterialApp(home: Scaffold(body: PlanListPage())),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('10:00 · 30 分钟'), findsWidgets);
  });

  test('跨日旧预览不能确认，真实跟练执行中不能写入', () async {
    final f = await fixture();
    addTearDown(f.close);
    var now = DateTime(2026, 9, 15, 10);
    final scoped = ProviderContainer(parent: f.container, overrides: [
      dailyCourseClockProvider.overrideWithValue(() => now),
      dailyCourseAdjustmentProvider.overrideWith((ref) => DailyCourseAdjustment(ref)),
    ]);
    addTearDown(scoped.dispose);
    final service = scoped.read(dailyCourseAdjustmentProvider);
    final preview = service.preview();
    now = now.add(const Duration(days: 1));
    await expectLater(service.confirm(preview), throwsStateError);
    final fresh = service.preview();
    final controller = f.container.read(trainingMvpProvider.notifier);
    expect(controller.startWorkoutPlayer(workoutDayId: fresh.original.id), isTrue);
    await expectLater(service.confirm(fresh), throwsStateError);
    expect(PersistedPlanAdjustmentRepository(f.storage).listAdjustments(), isEmpty);
    await controller.stopWorkoutPlayer();
  });

  test('确认快照投影到日程目标，重读和停用后保留，新版本不继承旧快照', () async {
    final f = await fixture();
    addTearDown(f.close);
    final rawBefore = f.storage.readJson(TrainingScheduleRepository.scheduleStorageKey);
    final service = f.container.read(dailyCourseAdjustmentProvider);
    final preview = service.preview();
    await service.confirm(preview);
    expect(f.container.read(effectiveTrainingScheduleProvider).workouts.single.allocatedMinutes, 30);
    expect(f.container.read(effectiveTrainingScheduleProvider).workouts.single.targetMinutes, 30);
    f.container.invalidate(trainingScheduleControllerProvider);
    f.container.read(trainingScheduleControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(f.container.read(trainingMvpProvider).dailyAvailableMinutesOverride, 30,
        reason: '重读原排期不得覆盖用户已保存的今日可用时间');
    expect(f.storage.readJson(TrainingScheduleRepository.scheduleStorageKey), rawBefore,
        reason: '调整权威来源仍是原调整文档，不能另写一份排期状态');
    f.container.invalidate(trainingMvpProvider);
    expect(f.container.read(trainingMvpProvider).todayWorkout.toJson(), preview.candidate!.toJson());
    expect(f.container.read(effectiveTrainingScheduleProvider).workouts.single.allocatedMinutes, 30);
    await f.runtime.disable('feature.daily_adjustment');
    expect(f.container.read(effectiveTrainingScheduleProvider).workouts.single.allocatedMinutes, 30);
    expect(f.container.read(coreHistoryProvider).listCourseAdjustments(), hasLength(1));
    await f.controller.createLocalDraft('plan.strength.baseline');
    await f.controller.activateLocalDraft(f.draft!.id);
    expect(f.repo.getHistory().activeVersionId, isNot(preview.baseVersionId));
    expect(f.container.read(fourWeekPlanControllerProvider).activeVersionId,
        f.repo.getHistory().activeVersionId);
    await Future<void>.delayed(Duration.zero);
    expect(appliedDailyCourseFor(f.container.read(trainingMvpProvider), preview.original.id), isNull);
    expect(f.container.read(effectiveTrainingScheduleProvider).workouts.single.allocatedMinutes, preview.original.estimatedMinutes);
    expect(f.container.read(coreHistoryProvider).listCourseAdjustments(), hasLength(1));
  });

  test('十五及二十分钟不能容纳既有步骤时明确阻断且不改计划', () async {
    final f = await fixture();
    addTearDown(f.close);
    final before = f.container.read(trainingMvpProvider).activePlan.toJson();
    for (final minutes in [15, 20]) {
      await f.container.read(dailyAdjustmentControllerProvider.notifier)
          .setDailyAvailableMinutes(minutes);
      await Future<void>.delayed(Duration.zero);
      final preview = f.container.read(dailyCourseAdjustmentProvider).preview();
      expect(preview.candidate, isNull);
      expect(preview.reason, contains('跟练步骤'));
      await expectLater(f.container.read(dailyCourseAdjustmentProvider).confirm(preview), throwsStateError);
      expect(f.container.read(trainingMvpProvider).activePlan.toJson(), before);
    }
  });

  test('旧的二十分钟确认快照仍可读，但不能以不符的倒计时开始跟练', () async {
    final f = await fixture();
    addTearDown(f.close);
    final service = f.container.read(dailyCourseAdjustmentProvider);
    await service.confirm(service.preview());
    // 模拟升级前的本机记录，不使用新提交入口制造一个无效计划。
    final document = f.storage.readJson(PersistedPlanAdjustmentRepository.storageKey)!;
    final saved = (document['adjustments'] as List).single as Map<String, dynamic>;
    saved['adjustedEstimatedMinutes'] = 20;
    (saved['workoutSnapshot'] as Map<String, dynamic>)['estimatedMinutes'] = 20;
    f.storage.saveJson(PersistedPlanAdjustmentRepository.storageKey, document);
    f.container.invalidate(planAdjustmentRepositoryProvider);
    f.container.read(planAdjustmentControllerProvider);
    f.container.invalidate(trainingMvpProvider);
    final before = f.container.read(coreHistoryProvider).listCourseAdjustments().single.toJson();
    final controller = f.container.read(trainingMvpProvider.notifier);
    expect(controller.startWorkoutPlayer(), isFalse);
    expect(f.container.read(trainingMvpProvider).workoutPlayerStatusMessage, contains('时长无法容纳'));
    expect(f.container.read(coreHistoryProvider).listCourseAdjustments().single.toJson(), before);
  });
}
