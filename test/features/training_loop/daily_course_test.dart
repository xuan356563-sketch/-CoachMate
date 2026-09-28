import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as timezone;
import 'package:trainflow_ai/services/system_training_notification_service.dart';
import 'package:trainflow_ai/features/daily_adjustment/application/daily_course_adjustment.dart';
import 'package:trainflow_ai/features/daily_adjustment/application/daily_adjustment_controller.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/plan_adjustment_controller.dart';
import 'package:trainflow_ai/data/repositories/plan_adjustment_repository.dart';
import 'package:trainflow_ai/data/repositories/training_schedule_repository.dart';
import 'package:trainflow_ai/data/models/training_schedule.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/services/weekly_report_service.dart';
import 'package:trainflow_ai/plugins/history/core_history.dart';
import '../resource_library/local_plan_test.dart' show LocalFixture;
import '../resource_library/assessment_test.dart' show FailStorage;

Future<LocalFixture> fixture({FailStorage? storage, TrainingNotificationScheduler? notifications}) async {
  final f = await LocalFixture.create(storage: storage, notificationScheduler: notifications);
  await f.controller.createLocalDraft('plan.strength.baseline');
  await f.controller.activateLocalDraft(f.draft!.id);
  final day = f.repo
      .getHistory()
      .activeVersion!
      .plan
      .workoutDays
      .firstWhere((d) => d.weekIndex == 3);
  TrainingScheduleRepository(f.storage).saveSchedule([
    ScheduledWorkout(
        id: 'test-slot',
        workoutDayId: day.id,
        scheduledDate: DateTime.now(),
        startMinute: 600,
        allocatedMinutes: day.estimatedMinutes,
        period: TrainingTimePeriod.morning,
        version: ScheduledWorkoutVersion.full)
  ]);
  f.container.read(trainingMvpProvider);
  await f.container
      .read(dailyAdjustmentControllerProvider.notifier)
      .setDailyAvailableMinutes(30);
  await Future<void>.delayed(Duration.zero);
  return f;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!dailyCourseApplyEnabled) {
    test('发行回滚阻止新调整并保留既有计划历史', () async {
      final f = await fixture(); addTearDown(f.close);
      final before = f.repo.getHistory().activeVersion!.toJson();
      expect(() => f.container.read(dailyCourseAdjustmentProvider).preview(), throwsStateError);
      expect(f.container.read(coreHistoryProvider).getPlanHistory().activeVersion!.toJson(), before);
      expect(f.container.read(planAdjustmentControllerProvider).adjustments, isEmpty);
    });
    return;
  }
  test('账号域变化后旧预览不能写入新账号', () async {
    final gateway = _NotificationGateway();
    final f = await fixture(notifications: TrainingNotificationScheduler(gateway)); addTearDown(f.close);
    final service = f.container.read(dailyCourseAdjustmentProvider);
    final preview = service.preview();
    await f.runtime.changeAccountScope(replaceScope: () => f.storage.clearBusinessData());
    await expectLater(service.confirm(preview), throwsStateError);
    expect(PersistedPlanAdjustmentRepository(f.storage).listAdjustments(), isEmpty);
    expect(gateway.cancelled, isTrue);
  });
  test('四项运动从本地草稿进入跟练，实际反馈在日志和周报一致', () async {
    for (final sport in [MainSport.marathon, MainSport.trailRunning, MainSport.strength, MainSport.hyrox]) {
      final f = await LocalFixture.create();
      addTearDown(f.close);
      final profiles = PersistedUserProfileRepository(f.storage);
      profiles.saveProfile(profiles.getProfile().copyWith(mainSports: [sport]));
      await f.controller.createLocalDraft('plan.${sport.jsonValue}.baseline');
      expect(f.draft!.auditSummary.blockingReasons, isEmpty, reason: sport.name);
      await f.controller.activateLocalDraft(f.draft!.id);
      final controller = f.container.read(trainingMvpProvider.notifier);
      final workout = f.container.read(trainingMvpProvider).activePlan.workoutDays.first;
      expect(controller.startWorkoutPlayer(workoutDayId: workout.id), isTrue);
      final state = f.container.read(trainingMvpProvider);
      expect(state.activeWorkoutPlayerWorkout.toJson(), workout.toJson());
      expect(state.workoutPlayerSteps, isNotEmpty);
      await controller.saveWorkoutSessionReview(actualDurationMinutes: 12,
        completionPercentage: 50, rpe: 4, averageHeartRate: 0, averagePaceSecondsPerKm: 0,
        plannedSetCount: 2, completedSetCount: 1, interruptionReason: '合成验收：时间不足',
        userNote: '合成验收手动反馈');
      final logs = f.container.read(coreHistoryProvider).listLogs().where((l) => l.isSessionRecord).toList();
      expect(logs, hasLength(1));
      expect(logs.single.workoutDayId, workout.id);
      expect(logs.single.actualDurationMinutes, 12);
      expect(logs.single.completionPercentage, 50);
      expect(logs.single.interruptionReason, '合成验收：时间不足');
      final report = WeeklyReportService().buildWeeklyReport(profile: state.profile, todayWorkout: workout,
        logs: logs, bodyMetrics: [], readinessScore: null, trainingStatusLabel: '无法评估',
        trainingStatusReason: '合成验收', recoveryCountdownLabel: '', recoveryAdvice: '', achievementSummaryLabel: '');
      expect(report.completionRate, closeTo(0.5 / state.profile.weeklyTrainingDays, 0.001));
      expect(report.recoverySummary, contains('无法评估'));
      await controller.stopWorkoutPlayer();
    }
  });
  test('预览不改计划，确认后计划、今日课程、历史一致且重复确认幂等', () async {
    final f = await fixture();
    addTearDown(f.close);
    final before = f.container.read(trainingMvpProvider).activePlan.toJson();
    final service = f.container.read(dailyCourseAdjustmentProvider);
    final preview = service.preview();
    expect(preview.candidate, isNotNull, reason: preview.reason);
    expect(f.container.read(trainingMvpProvider).activePlan.toJson(), before);
    await service.confirm(preview);
    final state = f.container.read(trainingMvpProvider);
    expect(state.todayWorkout.toJson(), preview.candidate!.toJson());
    expect(state.findWorkoutDay(preview.original.id)!.toJson(),
        preview.candidate!.toJson());
    expect(
        f.container
            .read(coreHistoryProvider)
            .listCourseAdjustments()
            .single
            .workoutSnapshot!
            .toJson(),
        preview.candidate!.toJson());
    await service.confirm(preview);
    expect(f.container.read(planAdjustmentControllerProvider).adjustments,
        hasLength(1));
    expect(
        PersistedPlanAdjustmentRepository(f.storage)
            .listAdjustments()
            .single
            .workoutSnapshot!
            .toJson(),
        preview.candidate!.toJson());
  });
  test('输入变化、执行锁和插件停用阻断旧预览', () async {
    final f = await fixture();
    addTearDown(f.close);
    final service = f.container.read(dailyCourseAdjustmentProvider);
    final preview = service.preview();
    await f.container
        .read(dailyAdjustmentControllerProvider.notifier)
        .setDailyAvailableMinutes(20);
    await Future<void>.delayed(Duration.zero);
    await expectLater(service.confirm(preview), throwsStateError);
    await f.container
        .read(dailyAdjustmentControllerProvider.notifier)
        .setDailyAvailableMinutes(30);
    await Future<void>.delayed(Duration.zero);
    final locked = service.preview();
    final unlock =
        f.runtime.registerDisableLock('feature.training_plan', () => '测试训练执行中');
    await expectLater(service.confirm(locked), throwsStateError);
    unlock();
    await f.runtime.disable('feature.daily_adjustment');
    await expectLater(service.confirm(locked), throwsStateError);
    expect(f.container.read(planAdjustmentControllerProvider).adjustments,
        isEmpty);
  });
  test('持久化失败恢复课程和文档，结果保留可重试', () async {
    final storage = FailStorage();
    final f = await fixture(storage: storage);
    addTearDown(f.close);
    final service = f.container.read(dailyCourseAdjustmentProvider);
    final preview = service.preview();
    final before = f.container.read(trainingMvpProvider).activePlan.toJson();
    storage.fail = true;
    await expectLater(service.confirm(preview), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(f.container.read(trainingMvpProvider).activePlan.toJson(), before);
    expect(
        PersistedPlanAdjustmentRepository(storage).listAdjustments(), isEmpty);
    await service.confirm(preview);
    expect(f.container.read(trainingMvpProvider).todayWorkout.toJson(),
        preview.candidate!.toJson());
  });
}

/// 仅替换宿主通知平台，仍验证切换时实际调用取消；不跳过插件清理。
class _NotificationGateway implements TrainingNotificationGateway {
  bool cancelled = false;
  @override
  Future<void> cancelTrainingNotifications() async { cancelled = true; }
  @override
  Future<timezone.Location> loadLocalLocation() async => timezone.UTC;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> schedule(TrainingNotificationRequest request) async {}
}
