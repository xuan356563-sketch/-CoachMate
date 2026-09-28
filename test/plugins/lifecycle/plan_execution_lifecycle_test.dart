import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as timezone;
import 'package:trainflow_ai/plugins/application/feature_controller_binding.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/data/models/ai_artifact.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/pain_log.dart';
import 'package:trainflow_ai/data/models/pre_exercise_clearance.dart';
import 'package:trainflow_ai/data/repositories/ai_artifact_repository.dart';
import 'package:trainflow_ai/data/repositories/generated_training_plan_repository.dart';
import 'package:trainflow_ai/features/ai_center/application/ai_artifact_controller.dart';
import 'package:trainflow_ai/features/ai_center/data/ai_api.dart';
import 'package:trainflow_ai/features/ai_center/data/training_prescription_api_models.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/profile/application/training_schedule_controller.dart';
import 'package:trainflow_ai/features/reminders/application/reminder_settings_controller.dart';
import 'package:trainflow_ai/features/training_log/application/training_log_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/four_week_plan_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/plan_adjustment_controller.dart';
import 'package:trainflow_ai/features/training_plan/application/pre_exercise_clearance_controller.dart';
import 'package:trainflow_ai/features/workout_player/application/workout_player_assist_controller.dart';
import 'package:trainflow_ai/features/guided_workout/application/guided_workout_engine.dart';
import 'package:trainflow_ai/features/guided_workout/data/guided_workout_catalog_loader.dart';
import 'package:trainflow_ai/features/guided_workout/domain/guided_workout_course.dart';
import 'package:trainflow_ai/features/guided_workout/presentation/guided_workout_player_page.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';
import 'package:trainflow_ai/services/workout_platform_service.dart';

final _logServiceConsumer = Provider<TrainingLogController>((ref) =>
    readFeatureController(ref, 'feature.training_log', 'controller',
        () => ref.read(trainingLogControllerProvider.notifier)));

TrainingLog _log() => TrainingLog(
    id: '测试日志',
    workoutDayId: '测试训练日',
    date: DateTime(2026, 7, 14),
    createdAt: DateTime(2026, 7, 14),
    completed: true,
    rpe: 5,
    fatigueLevel: 5,
    sleepQuality: 7,
    painNote: null,
    userNote: null);

Future<PluginRuntime> _runtime() async {
  final runtime = PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
  await runtime.initialize();
  return runtime;
}

Future<void> _disableLogDependencies(PluginRuntime runtime) async {
  for (final id in [
    'feature.workout_player',
    'feature.guided_workout',
    'feature.activity_import'
  ]) {
    await runtime.disable(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实服务按需登记、消费原日志保存、停用撤销和同控制器重新绑定', () async {
    final runtime = await _runtime();
    final storage = InMemoryLocalStorageService();
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    expect(
        runtime
            .service('feature.training_log')!
            .read<TrainingLogController>('controller'),
        isNull);
    final controller = container.read(_logServiceConsumer);
    expect(await controller.save(_log()), hasLength(1));
    expect(
        runtime
            .service('feature.training_log')!
            .read<TrainingLogController>('controller'),
        same(controller));
    await _disableLogDependencies(runtime);
    await runtime.disable('feature.training_log');
    await expectLater(controller.save(_log()), throwsStateError);
    expect(container.read(trainingLogControllerProvider), hasLength(1));
    await controller.clear();
    expect(container.read(trainingLogControllerProvider), isEmpty);
    for (var index = 0; index < 2; index++) {
      await runtime.enable('feature.training_log');
      await container.pump();
      expect(
          runtime
              .service('feature.training_log')!
              .read<TrainingLogController>('controller'),
          same(controller));
      expect(await controller.save(_log()), hasLength(1));
      await runtime.disable('feature.training_log');
    }
    container.invalidate(trainingLogControllerProvider);
    expect(container.read(trainingLogControllerProvider), hasLength(1));
  });

  test('停用计划读取不新增fallback、镜像或排期，直接日程和调整写拒绝', () async {
    final runtime = await _runtime();
    await runtime.disable('feature.training_plan');
    final storage = InMemoryLocalStorageService();
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final repository = GeneratedTrainingPlanRepository(storage);
    final before = jsonEncode(
        [repository.getPlan()?.toJson(), repository.getHistory().toJson()]);
    final plan = container.read(fourWeekPlanControllerProvider);
    final schedule =
        container.read(trainingScheduleControllerProvider.notifier);
    final adjustment =
        container.read(planAdjustmentControllerProvider.notifier);
    expect(
        () => container
            .read(fourWeekPlanControllerProvider.notifier)
            .regenerate(),
        throwsStateError);
    await expectLater(
      schedule.addSlot(
          date: DateTime(2026, 9, 10), startMinute: 600, endMinute: 660),
      throwsStateError,
    );
    await expectLater(
      adjustment.restoreOriginalPlan(plan.activePlan.workoutDays.first),
      throwsStateError,
    );
    expect(
        jsonEncode(
            [repository.getPlan()?.toJson(), repository.getHistory().toJson()]),
        before);
    expect(container.read(trainingScheduleRepositoryProvider).listSchedule(),
        isEmpty);
  });

  test('激活等待筛查期间停用计划令结果失效且历史不变', () async {
    final runtime = await _runtime();
    final clearance = Completer<PreExerciseClearanceState>();
    final storage = InMemoryLocalStorageService();
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      preExerciseClearanceControllerProvider
          .overrideWith(() => _DeferredClearance(clearance.future)),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(fourWeekPlanControllerProvider.notifier);
    final pending = controller.activateDraft(artifactId: '不存在的草稿');
    final checked = expectLater(pending, throwsStateError);
    await runtime.disable('feature.training_plan');
    clearance.complete(const PreExerciseClearanceState(
        clearance: PreExerciseClearance.notCompleted(),
        isSaving: false,
        statusMessage: '测试'));
    await checked;
    expect(GeneratedTrainingPlanRepository(storage).getHistory().versions,
        isEmpty);
  });

  test('真实AI控制器收到已失效计划来源时不写迟到产物', () async {
    final runtime = await _runtime();
    final api = _DeferredApi();
    final storage = InMemoryLocalStorageService();
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      aiApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(aiArtifactControllerProvider.notifier);
    expect(
        runtime
            .service('feature.ai_center')!
            .read<AiArtifactController>('controller'),
        same(controller));
    final operation = runtime.beginOperation('feature.training_plan',
        dependencies: ['feature.ai_center']);
    final pending = controller.generateTrainingPrescriptionV2(_request,
        sourceOperation: operation);
    final checked = expectLater(pending, throwsStateError);
    await runtime.disable('feature.training_plan');
    api.result.complete(_artifact);
    await checked;
    expect(PersistedAiArtifactRepository(storage).listArtifacts(), isEmpty);
  });

  test('AI产物本地提交期间同时锁定计划和AI服务', () async {
    final runtime = await _runtime();
    final api = _DeferredApi();
    final storage = _BlockingFlushStorage();
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      aiApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final operation = runtime.beginOperation('feature.training_plan',
        dependencies: ['feature.ai_center']);
    final pending = container
        .read(aiArtifactControllerProvider.notifier)
        .generateTrainingPrescriptionV2(_request, sourceOperation: operation);
    api.result.complete(_artifact);
    await storage.started.future;
    expect(
        runtime.checkDisable('feature.training_plan').join(), contains('正在保存'));
    expect(runtime.checkDisable('feature.ai_center').join(), contains('正在保存'));
    storage.finish.complete();
    expect(await pending, _artifact);
  });

  test('AI共享来源在同一提交区内复用时等待嵌套写完成', () async {
    final runtime = await _runtime();
    final api = _DeferredApi();
    final storage = InMemoryLocalStorageService();
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      aiApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final operation = runtime.beginOperation(
      'feature.training_plan',
      dependencies: const <String>['feature.ai_center'],
    );
    api.result.complete(_artifact);

    await operation.commit(() async {
      final AiArtifact? artifact = await container
          .read(aiArtifactControllerProvider.notifier)
          .generateTrainingPrescriptionV2(
            _request,
            sourceOperation: operation,
          );
      expect(artifact, _artifact);
    });

    expect(
      PersistedAiArtifactRepository(storage)
          .listArtifacts()
          .map((AiArtifact artifact) => artifact.id),
      <String>[_artifact.id],
    );
    expect(runtime.checkDisable('feature.ai_center'), isEmpty);
    expect(runtime.checkDisable('feature.training_plan'), isEmpty);
  });

  test('提交区缺少AI来源时在远端与本地写前拒绝', () async {
    final runtime = await _runtime();
    final api = _CountingApi();
    final storage = _CountingFlushStorage();
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      aiApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final operation = runtime.beginOperation('feature.training_plan');
    expect(operation.containsSource('feature.ai_center'), isFalse);

    await operation.commit(() async {
      await expectLater(
        container
            .read(aiArtifactControllerProvider.notifier)
            .generateTrainingPrescriptionV2(
              _request,
              sourceOperation: operation,
            ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('未包含 AI 中心来源'),
          ),
        ),
      );
      expect(runtime.checkDisable('feature.ai_center'), isEmpty);
    });

    expect(api.calls, 0);
    expect(storage.flushCount, 0);
    expect(PersistedAiArtifactRepository(storage).listArtifacts(), isEmpty);
  });

  test('跟练日志真实落盘期间同时锁定跟练与日志来源', () async {
    final runtime = await _runtime();
    final storage = _BlockingFlushStorage();
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(_logServiceConsumer);
    final operation = runtime.beginOperation('feature.guided_workout');

    final pending = controller.save(_log(), sourceOperation: operation);
    await storage.started.future;

    expect(runtime.checkDisable('feature.guided_workout').join(),
        contains('正在保存'));
    expect(
        runtime.checkDisable('feature.training_log').join(), contains('正在保存'));
    await expectLater(runtime.changeAccountScope(), throwsStateError);
    storage.finish.complete();
    expect(await pending, hasLength(1));
  });

  test('MVP逐动作拒绝关闭功能，核心疼痛记录仍可写', () async {
    final runtime = await _runtime();
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider
          .overrideWithValue(InMemoryLocalStorageService()),
      workoutPlatformServiceProvider.overrideWithValue(_Platform()),
      trainingNotificationSchedulerProvider.overrideWithValue(
        TrainingNotificationScheduler(_NoopTrainingNotificationGateway()),
      ),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(trainingMvpProvider.notifier);
    final checks = <String, void Function()>{
      'feature.race_prep': () => controller.importRaceText('测试'),
      'feature.knowledge_library': () => controller.importKnowledgeText('测试'),
      'feature.motion_check': () => controller.analyzeMotionCheck('测试'),
      'feature.user_insights': controller.generateWeeklyUserInsightTask,
      'feature.workout_player': controller.startWorkoutPlayer,
      'support.rehab': () => controller.savePainLog(
          bodyPart: '膝盖', painLevel: 3, timing: PainTiming.afterTraining),
    };
    for (final entry in checks.entries) {
      await runtime.disable(entry.key);
      expect(entry.value, throwsStateError, reason: entry.key);
    }
    await runtime.disable('feature.activity_import');
    await expectLater(controller.importActivityText('测试'), throwsStateError);
    await runtime.enable('feature.motion_check');
    await runtime.disable('feature.ai_center');
    expect(
        () =>
            controller.applyAiMotionArtifact(artifact: _artifact, ruleId: '测试'),
        throwsStateError);
    expect(
        () => controller.applyAiTrainerArtifact(_artifact), throwsStateError);
    controller.recordSafetyPain(
        bodyPart: '膝盖', painLevel: 3, timing: PainTiming.afterTraining);
    expect(container.read(trainingMvpProvider).painLogs.first.painLevel, 3);
  });

  test('真实跟练未完成锁与强制清理释放计时、语音、常亮，不新增日志', () async {
    final runtime = await _runtime();
    final platform = _Platform();
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider
          .overrideWithValue(InMemoryLocalStorageService()),
      workoutPlatformServiceProvider.overrideWithValue(platform),
      trainingNotificationSchedulerProvider.overrideWithValue(
        TrainingNotificationScheduler(_NoopTrainingNotificationGateway()),
      ),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(trainingMvpProvider.notifier);
    expect(controller.startWorkoutPlayer(), isTrue);
    controller.startWorkoutPlayerCountdown();
    for (final id in [
      'feature.workout_player',
      'feature.training_log',
      'feature.training_plan'
    ]) {
      expect(runtime.checkDisable(id).join(), contains('训练尚未结束'));
    }
    final count = container.read(trainingLogControllerProvider).length;
    await runtime.changeAccountScope();
    expect(platform.stops, greaterThan(0));
    expect(platform.awake.last, isFalse);
    expect(
        container.read(trainingMvpProvider).workoutPlayerTimerRunning, isFalse);
    expect(container.read(trainingLogControllerProvider).length, count);
  });

  testWidgets('跳绳跟练登记真实engine，强制清理后解绑且不保存未完成日志', (tester) async {
    final runtime = await _runtime();
    final platform = _Platform();
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider
          .overrideWithValue(InMemoryLocalStorageService()),
      workoutPlatformServiceProvider.overrideWithValue(platform),
      preExerciseClearanceControllerProvider.overrideWith(_ReadyClearance.new),
      trainingNotificationSchedulerProvider.overrideWithValue(
        TrainingNotificationScheduler(_NoopTrainingNotificationGateway()),
      ),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
            home: GuidedWorkoutPlayerPage(courseId: 'jump-rope-beginner-20'))));
    await tester.pumpAndSettle();
    final service = runtime.service('feature.guided_workout')!;
    expect(service.read<GuidedWorkoutEngine>('engine'), isNotNull);
    expect(runtime.checkDisable('feature.guided_workout').join(),
        contains('尚未结束'));
    final count = container.read(trainingLogControllerProvider).length;
    await runtime.changeAccountScope();
    await tester.pump();
    expect(service.read<GuidedWorkoutEngine>('engine'), isNull);
    expect(platform.stops, greaterThan(0));
    expect(platform.awake.last, isFalse);
    expect(container.read(trainingLogControllerProvider).length, count);
  });

  testWidgets('跟练保存等待真实落盘成功后才退出并报告已保存', (tester) async {
    final runtime = await _runtime();
    final storage = _BlockingFlushStorage();
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      workoutPlatformServiceProvider.overrideWithValue(_Platform()),
      preExerciseClearanceControllerProvider.overrideWith(_ReadyClearance.new),
      guidedWorkoutCatalogProvider.overrideWith((ref) async => _testCatalog),
      trainingNotificationSchedulerProvider.overrideWithValue(
        TrainingNotificationScheduler(_NoopTrainingNotificationGateway()),
      ),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/guided'),
            child: const Text('打开跟练'),
          ),
        ),
      ),
      GoRoute(
        path: '/guided',
        builder: (context, state) => const GuidedWorkoutPlayerPage(
          courseId: 'jump-rope-beginner-20',
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('打开跟练'));
    final playerControl =
        find.byKey(const ValueKey<String>('guided-workout-pause-resume'));
    for (var attempt = 0;
        attempt < 20 && playerControl.evaluate().isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      playerControl,
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(
      runtime
          .service('feature.guided_workout')!
          .read<GuidedWorkoutEngine>('engine'),
      isNotNull,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('trainmate-back-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存部分记录'));
    await tester.pump();
    await storage.started.future;

    expect(find.byType(GuidedWorkoutPlayerPage), findsOneWidget);
    expect(container.read(trainingLogControllerProvider), isEmpty);
    expect(
      runtime
          .service('feature.training_log')!
          .read<TrainingLogController>('controller'),
      same(container.read(trainingLogControllerProvider.notifier)),
    );

    storage.finish.complete();
    await tester.pumpAndSettle();
    expect(find.byType(GuidedWorkoutPlayerPage), findsNothing);
    expect(container.read(trainingLogControllerProvider), hasLength(1));
  });
}

class _DeferredClearance extends PreExerciseClearanceController {
  _DeferredClearance(this.result);
  final Future<PreExerciseClearanceState> result;
  @override
  Future<PreExerciseClearanceState> build() => result;
}

class _ReadyClearance extends PreExerciseClearanceController {
  @override
  Future<PreExerciseClearanceState> build() async => PreExerciseClearanceState(
      clearance: PreExerciseClearance.recorded(
          status: PreExerciseClearanceStatus.selfCleared,
          currentInjuryOrRestriction: false,
          completedAt: DateTime.now()),
      isSaving: false,
      statusMessage: '测试筛查有效');
}

class _Platform extends WorkoutPlatformService {
  final awake = <bool>[];
  int stops = 0;
  @override
  Future<bool> speak(String text, {double rate = 1, String? voiceName}) async =>
      true;
  @override
  Future<void> stopSpeech() async {
    stops++;
  }

  @override
  Future<bool> setScreenAwake(bool enabled) async {
    awake.add(enabled);
    return true;
  }
}

class _NoopTrainingNotificationGateway implements TrainingNotificationGateway {
  @override
  Future<void> cancelTrainingNotifications() async {}

  @override
  Future<timezone.Location> loadLocalLocation() async =>
      throw UnsupportedError('测试不读取时区');

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(TrainingNotificationRequest request) async {}
}

class _DeferredApi implements AiApi {
  final result = Completer<AiArtifact>();
  @override
  Future<AiArtifact> generateTrainingPrescriptionV2(
          TrainingPrescriptionV2Request request) =>
      result.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingApi implements AiApi {
  int calls = 0;

  @override
  Future<AiArtifact> generateTrainingPrescriptionV2(
    TrainingPrescriptionV2Request request,
  ) async {
    calls += 1;
    return _artifact;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BlockingFlushStorage extends InMemoryLocalStorageService {
  final started = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<void> flush() async {
    if (!started.isCompleted) started.complete();
    await finish.future;
  }
}

class _CountingFlushStorage extends InMemoryLocalStorageService {
  int flushCount = 0;

  @override
  Future<void> flush() async {
    flushCount += 1;
  }
}

const _request = TrainingPrescriptionV2Request(
    clientContextDigest: '测试摘要',
    populationTemplateId: '测试模板',
    knowledgeSnapshotVersion: '测试版本',
    context: TrainingPrescriptionRequestContext(
        goal: 'general_fitness',
        secondarySport: null,
        raceType: null,
        daysUntilRace: null,
        primarySport: 'general_fitness',
        experienceLevel: 'beginner',
        biologicalSex: 'unknown',
        weeklyTrainingDays: 3,
        availableMinutes: 30,
        equipmentAccess: ['bodyweight']));
const _testCatalog = GuidedWorkoutCatalog(courses: [
  GuidedWorkoutCourse(
    id: 'jump-rope-beginner-20',
    title: '测试跟练',
    level: 'beginner',
    description: '用于验证真实保存生命周期。',
    expectedDurationSeconds: 60,
    phases: [
      GuidedWorkoutPhase(
        id: '测试阶段',
        name: '测试阶段',
        exercises: [
          GuidedWorkoutExercise(
            id: '测试动作',
            name: '测试动作',
            durationSeconds: 60,
            restSeconds: 0,
            repeat: 1,
            announce: '开始测试',
            cues: [],
          ),
        ],
      ),
    ],
    voice: GuidedWorkoutVoiceConfig(
      countdownLast: 0,
      preAnnounceOnRest: false,
      rate: 1,
      enabled: false,
      voiceName: null,
    ),
  ),
]);
final _artifact = AiArtifact.fromJson({
  'id': '迟到产物',
  'capability': 'trainer',
  'artifact_type': 'trainer_plan_v1',
  'schema_version': 1,
  'decision_status': 'pending',
  'context_digest': '测试摘要',
  'payload': <String, dynamic>{},
  'warnings': [],
  'provider': 'test',
  'model': 'test',
  'generated_at': '2026-07-14T00:00:00Z',
  'decided_at': null
});
